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

    enum CodingKeys: String, CodingKey {
        case availability, kitchenTempC, usesFahrenheit, starterUsuallyNeedsFeed, preferredFeedRatio
        case allowInoculationAdjustment, allowFeedRatioAdjustment, hasCompletedOnboarding
    }

    /// Missing keys fall back to defaults so a file written by an older build still opens.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UserSettings()
        availability = try c.decodeIfPresent(Availability.self, forKey: .availability) ?? d.availability
        kitchenTempC = try c.decodeIfPresent(Double.self, forKey: .kitchenTempC) ?? d.kitchenTempC
        usesFahrenheit = try c.decodeIfPresent(Bool.self, forKey: .usesFahrenheit) ?? d.usesFahrenheit
        starterUsuallyNeedsFeed = try c.decodeIfPresent(Bool.self, forKey: .starterUsuallyNeedsFeed) ?? d.starterUsuallyNeedsFeed
        preferredFeedRatio = try c.decodeIfPresent(FeedRatio.self, forKey: .preferredFeedRatio) ?? d.preferredFeedRatio
        allowInoculationAdjustment = try c.decodeIfPresent(Bool.self, forKey: .allowInoculationAdjustment) ?? d.allowInoculationAdjustment
        allowFeedRatioAdjustment = try c.decodeIfPresent(Bool.self, forKey: .allowFeedRatioAdjustment) ?? d.allowFeedRatioAdjustment
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
    }
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
    public var schemaVersion = AppState.currentSchemaVersion

    public static let currentSchemaVersion = 1

    public init() {}

    enum CodingKeys: String, CodingKey {
        case settings, formulas, activeSession, history, calibration, isPro, schemaVersion
    }

    public struct NewerFileError: Error, Equatable {
        public var version: Int
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard version <= AppState.currentSchemaVersion else { throw NewerFileError(version: version) }
        let d = AppState()
        settings = try c.decodeIfPresent(UserSettings.self, forKey: .settings) ?? d.settings
        formulas = try c.decodeIfPresent([Formula].self, forKey: .formulas) ?? d.formulas
        activeSession = try c.decodeIfPresent(BakeSession.self, forKey: .activeSession)
        history = try c.decodeIfPresent([BakeRecord].self, forKey: .history) ?? d.history
        calibration = try c.decodeIfPresent(Calibration.self, forKey: .calibration) ?? d.calibration
        isPro = try c.decodeIfPresent(Bool.self, forKey: .isPro) ?? d.isPro
        schemaVersion = AppState.currentSchemaVersion
    }

    /// Brings values a hand-edited or damaged file could contain back inside what the planner accepts.
    /// Returns true when anything changed. Invalid busy blocks are kept (so the baker can fix them) but
    /// ignored by planning.
    @discardableResult
    public mutating func repair() -> Bool {
        let before = self
        settings.kitchenTempC = Self.clamp(settings.kitchenTempC, Limits.tempC, fallback: 21)
        for i in formulas.indices {
            var f = formulas[i]
            if f.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { f.name = "My loaf" }
            f.flourGrams = Self.clamp(f.flourGrams, Limits.flourGrams, fallback: 500)
            f.hydrationPercent = Self.clamp(f.hydrationPercent, Limits.hydrationPercent, fallback: 72)
            f.starterPercent = Self.clamp(f.starterPercent, Limits.starterPercent, fallback: 20)
            f.saltPercent = Self.clamp(f.saltPercent, Limits.saltPercent, fallback: 2)
            formulas[i] = f
        }
        if formulas.isEmpty { formulas = [.countryLoaf] }
        return before != self
    }

    static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

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

    /// Completing a step late can move the bake; it's kept out of the baker's busy times where possible.
    public mutating func completeStep(_ id: String, at now: Date, calendar: Calendar = .current) {
        activeSession?.complete(id, at: now, availability: settings.availability, calendar: calendar)
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
        var state = try Self.decoder.decode(AppState.self, from: data)
        state.repair()
        return state
    }

    public func save(_ state: AppState) throws {
        let data = try Self.encoder.encode(state)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    /// Moves an unreadable file aside so a fresh start never destroys the only copy.
    public func quarantineCorruptFile() throws -> URL {
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("hearthday-state-unreadable-\(Int(Date().timeIntervalSince1970)).json")
        try FileManager.default.moveItem(at: url, to: backup)
        return backup
    }

    /// Dates are written as seconds since 2001 at full precision, so a bake reloaded after the app is closed
    /// has bit-identical times (computed likely-ready windows carry sub-millisecond fractions that an
    /// ISO 8601 string would round). ISO 8601 strings are still accepted when reading.
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(date.timeIntervalSinceReferenceDate)
        }
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            if let seconds = try? c.decode(Double.self), seconds.isFinite {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            let text = try c.decode(String.self)
            guard let date = parseISO(text) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unreadable date \(text)")
            }
            return date
        }
        return d
    }()

    static func parseISO(_ text: String) -> Date? {
        guard text.hasSuffix("Z") else { return isoFormatter().date(from: text) }
        let body = text.dropLast()
        let parts = body.split(separator: ".", maxSplits: 1)
        guard let whole = isoFormatter().date(from: parts[0] + "Z") else { return nil }
        guard parts.count == 2 else { return whole }
        let digits = String(parts[1].prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        guard let ms = Int(digits) else { return nil }
        return Date(timeIntervalSince1970: whole.timeIntervalSince1970 + Double(ms) / 1000)
    }

    private static func isoFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }
}
