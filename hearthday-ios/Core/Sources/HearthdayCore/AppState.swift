import Foundation

public struct UserSettings: Codable, Hashable, Sendable {
    public var availability: Availability = .typicalWeekdayWorker
    public var kitchenTempC: Double = 21
    public var usesFahrenheit = false
    public var starterUsuallyNeedsFeed = true
    public var preferredFeedRatio: FeedRatio = .oneTwoTwo
    public var allowInoculationAdjustment = true
    public var allowFeedRatioAdjustment = true
    public var hasCompletedOnboarding = false

    public init() {}
}

/// What we keep about a finished bake. Everything stays on device.
public struct BakeRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var finishedAt: Date
    public var formulaName: String
    public var proofMode: ProofMode
    public var inoculationPercent: Double
    public var tempC: Double
    public var originalReadyAt: Date
    public var actualReadyAt: Date
    public var replanCount: Int
    public var checkInCount: Int
    public var shapeReadiness: ShapeReadiness?
    public var rating: Int?
    public var notes: String
    public var modelBulkHours: Double
    public var actualBulkHours: Double?

    /// The plan "held" when the loaf came out within 30 minutes of the original time without a re-plan.
    public var planHeld: Bool {
        replanCount == 0 && abs(actualReadyAt.timeIntervalSince(originalReadyAt)) <= 30 * 60
    }
}

/// The whole persisted app state. The SwiftUI layer is a thin shell around these mutations.
public struct AppState: Codable, Hashable, Sendable {
    public static let freeFormulaLimit = 2
    public static let freeHistoryLimit = 5

    public var settings = UserSettings()
    public var formulas: [Formula] = [.countryLoaf]
    public var activeSession: BakeSession?
    public var history: [BakeRecord] = []
    public var calibration = Calibration()
    /// Cached entitlement for offline launches; StoreKit remains the source of truth.
    public var isPro = false

    public init() {}

    /// Personal calibration is applied to plans for Pro; everyone sees what it has learned.
    public var planningModel: FermentationModel {
        isPro ? FermentationModel().applying(calibration) : FermentationModel()
    }

    public var canAddFormula: Bool { isPro || formulas.count < AppState.freeFormulaLimit }

    public var visibleHistory: [BakeRecord] {
        let sorted = history.sorted { $0.finishedAt > $1.finishedAt }
        return isPro ? sorted : Array(sorted.prefix(AppState.freeHistoryLimit))
    }

    public var hiddenHistoryCount: Int { history.count - visibleHistory.count }

    public func request(
        readyBy: Date,
        now: Date,
        formula: Formula,
        tempC: Double? = nil,
        starterNeedsFeed: Bool? = nil
    ) -> PlanRequest {
        PlanRequest(
            now: now,
            readyBy: readyBy,
            kitchenTempC: tempC ?? settings.kitchenTempC,
            formula: formula,
            starterNeedsFeed: starterNeedsFeed ?? settings.starterUsuallyNeedsFeed,
            preferredFeedRatio: settings.preferredFeedRatio,
            allowFeedRatioAdjustment: settings.allowFeedRatioAdjustment,
            allowInoculationAdjustment: settings.allowInoculationAdjustment,
            availability: settings.availability,
            model: planningModel
        )
    }

    public mutating func start(_ plan: BakePlan, now: Date) {
        activeSession = BakeSession(plan: plan, startedAt: now)
    }

    public mutating func completeStep(_ id: String, at now: Date) {
        activeSession?.complete(id, at: now)
    }

    public mutating func setShapeReadiness(_ readiness: ShapeReadiness) {
        activeSession?.shapeReadiness = readiness
    }

    public mutating func recordCheckIn(_ checkIn: CheckIn) {
        activeSession?.checkIns.append(checkIn)
    }

    public mutating func apply(_ option: ReplanOption) {
        activeSession?.apply(option)
    }

    /// Ends the active bake, learns from it when the baker judged shaping "just right", and files it in history.
    @discardableResult
    public mutating func finishActiveBake(rating: Int?, notes: String, at now: Date) -> BakeRecord? {
        guard var session = activeSession else { return nil }
        if session.completed["bake"] == nil { session.complete("bake", at: now) }
        session.rating = rating
        session.notes = notes
        if let sample = session.calibrationSample() {
            calibration.record(sample)
        }
        let record = BakeRecord(
            id: session.id,
            finishedAt: session.finishedAt ?? now,
            formulaName: session.plan.formula.name,
            proofMode: session.plan.proofMode,
            inoculationPercent: session.plan.inoculationPercent,
            tempC: session.averageTempC,
            originalReadyAt: session.originalReadyAt,
            actualReadyAt: session.finishedAt ?? now,
            replanCount: session.replanCount,
            checkInCount: session.checkIns.count,
            shapeReadiness: session.shapeReadiness,
            rating: rating,
            notes: notes,
            modelBulkHours: session.plan.modelBulkHours,
            actualBulkHours: session.actualBulkHours
        )
        history.append(record)
        activeSession = nil
        return record
    }

    public mutating func abandonActiveBake() {
        activeSession = nil
    }

    /// Plain-language summary of what calibration has learned, or nil before there is anything honest to say.
    public var calibrationInsight: String? {
        let n = calibration.samples.count
        guard n > 0 else { return nil }
        let pct = Int(((calibration.speedFactor - 1) * 100).rounded())
        let bakes = n == 1 ? "1 bake" : "\(n) bakes"
        let direction: String
        if abs(pct) < 5 {
            direction = "right in line with the textbook"
        } else if pct > 0 {
            direction = "about \(pct)% faster than the textbook"
        } else {
            direction = "about \(-pct)% slower than the textbook"
        }
        if calibration.isPersonalized {
            return "Across \(bakes), your dough has run \(direction). Likely windows are now ±\(Int((calibration.uncertainty * 100).rounded()))%."
        }
        let more = Calibration.samplesNeededToNarrow - n
        return "After \(bakes), your dough looks \(direction). \(more) more “just right” \(more == 1 ? "bake" : "bakes") before windows adjust."
    }
}

/// Atomic JSON persistence in the app's Application Support directory.
public struct JSONFileStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func defaultLocation(fileManager: FileManager = .default) throws -> JSONFileStore {
        let dir = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return JSONFileStore(url: dir.appendingPathComponent("hearthday-state.json"))
    }

    /// Missing file → fresh state. Unreadable file → throws, so the caller can keep a backup instead of silently wiping.
    public func load() throws -> AppState {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppState() }
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(AppState.self, from: data)
    }

    public func save(_ state: AppState) throws {
        let data = try Self.encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    /// Moves an unreadable file aside so a fresh start never destroys the only copy.
    public func quarantineCorruptFile() throws -> URL {
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("hearthday-state-unreadable-\(Int(Date().timeIntervalSince1970)).json")
        try FileManager.default.moveItem(at: url, to: backup)
        return backup
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
