import Foundation

public enum ProofMode: String, Codable, CaseIterable, Sendable {
    case fridge, room
}

public enum StepKind: String, Codable, Sendable {
    case feedStarter, starterRise, mix, fold, bulk, shape, coldRetard, roomProof, preheat, bake, coldBulk
    /// Hands-on: moving the dough into the fridge mid-bulk. Completing it marks the bake as chilled.
    case fridgeDough
}

public struct BakeStep: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var kind: StepKind
    public var start: Date
    public var end: Date
    /// True when the baker must be present (hands on dough or oven on).
    public var attended: Bool
    public var title: String
    public var detail: String
    /// For shaping: the window in which the dough is likely ready.
    public var likelyStart: Date?
    public var likelyEnd: Date?

    public init(
        id: String,
        kind: StepKind,
        start: Date,
        end: Date,
        attended: Bool,
        title: String,
        detail: String,
        likelyStart: Date? = nil,
        likelyEnd: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.attended = attended
        self.title = title
        self.detail = detail
        self.likelyStart = likelyStart
        self.likelyEnd = likelyEnd
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public struct ProcessSettings: Codable, Hashable, Sendable {
    public var feedMinutes = 5
    public var mixMinutes = 20
    public var foldCount = 4
    public var foldIntervalMinutes = 30
    public var foldMinutes = 5
    public var shapeMinutes = 20
    public var preheatMinutes = 45
    public var bakeMinutes = 45
    public var retardMinHours = 8.0
    public var retardMaxHours = 36.0
    public var retardPreferredLowHours = 12.0
    public var retardPreferredHighHours = 16.0
    /// How early a room-proofed loaf may finish before the requested time.
    public var roomFinishSlackMinutes = 60
    public var gridMinutes = 15

    public init() {}
}

public struct PlanRequest: Codable, Hashable, Sendable {
    public var now: Date
    public var readyBy: Date
    public var kitchenTempC: Double
    public var formula: Formula
    public var starterNeedsFeed: Bool
    public var preferredFeedRatio: FeedRatio
    public var allowFeedRatioAdjustment: Bool
    public var allowInoculationAdjustment: Bool
    public var proofModes: [ProofMode]
    public var availability: Availability
    public var model: FermentationModel
    public var process: ProcessSettings

    public init(
        now: Date,
        readyBy: Date,
        kitchenTempC: Double,
        formula: Formula = .countryLoaf,
        starterNeedsFeed: Bool = true,
        preferredFeedRatio: FeedRatio = .oneTwoTwo,
        allowFeedRatioAdjustment: Bool = true,
        allowInoculationAdjustment: Bool = true,
        proofModes: [ProofMode] = [.fridge, .room],
        availability: Availability = .typicalWeekdayWorker,
        model: FermentationModel = FermentationModel(),
        process: ProcessSettings = ProcessSettings()
    ) {
        self.now = now
        self.readyBy = readyBy
        self.kitchenTempC = kitchenTempC
        self.formula = formula
        self.starterNeedsFeed = starterNeedsFeed
        self.preferredFeedRatio = preferredFeedRatio
        self.allowFeedRatioAdjustment = allowFeedRatioAdjustment
        self.allowInoculationAdjustment = allowInoculationAdjustment
        self.proofModes = proofModes
        self.availability = availability
        self.model = model
        self.process = process
    }
}

public struct BakePlan: Codable, Hashable, Sendable {
    public var steps: [BakeStep]
    public var proofMode: ProofMode
    public var inoculationPercent: Double
    public var feedRatio: FeedRatio?
    public var kitchenTempC: Double
    public var formula: Formula
    /// Bulk hours the plan assumes (already includes personal calibration).
    public var expectedBulkHours: Double
    /// Bulk hours the uncalibrated model predicts, kept for calibration.
    public var modelBulkHours: Double
    public var uncertainty: Double
    public var score: Double

    public var mixAt: Date { steps.first { $0.kind == .mix }?.start ?? steps[0].start }
    public var readyAt: Date { steps.last?.end ?? mixAt }
    public var firstStepAt: Date { steps.first?.start ?? mixAt }
    public var attendedSteps: [BakeStep] { steps.filter(\.attended) }

    /// Hands-on minutes, counting preheat+bake as one attended block.
    public var handsOnMinutes: Int {
        Int((attendedSteps.reduce(0) { $0 + $1.duration } / 60).rounded())
    }

    public func step(_ id: String) -> BakeStep? { steps.first { $0.id == id } }

    /// Short human description of what the planner changed from the baker's usual formula.
    public var leverSummary: [String] {
        var items: [String] = []
        if abs(inoculationPercent - formula.starterPercent) > 0.01 {
            items.append("Starter \(Int(inoculationPercent.rounded()))% instead of \(Int(formula.starterPercent.rounded()))%")
        }
        if let feedRatio {
            items.append("Feed \(feedRatio.rawValue)")
        }
        switch proofMode {
        case .fridge: items.append("Cold proof overnight-style in the fridge")
        case .room: items.append("Same-day proof at room temperature")
        }
        return items
    }
}

public enum BlockReason: String, Codable, Sendable {
    case notEnoughTime, feedConflict, mixConflict, foldConflict, shapeConflict, retardOutOfRange, bakeConflict

    var depth: Int {
        switch self {
        case .notEnoughTime: return 0
        case .feedConflict: return 1
        case .mixConflict: return 2
        case .foldConflict: return 3
        case .shapeConflict: return 4
        case .retardOutOfRange: return 5
        case .bakeConflict: return 7
        }
    }
}

public struct Infeasibility: Codable, Hashable, Sendable {
    public var reason: BlockReason
    public var blockingLabel: String?
    public var earliestFeasibleReadyAt: Date?

    public var message: String {
        let who = blockingLabel.map { "“\($0)”" } ?? "your busy times"
        switch reason {
        case .notEnoughTime:
            return "There isn’t enough time left for a full bake before then."
        case .feedConflict:
            return "Every workable plan needs a starter feed during \(who)."
        case .mixConflict:
            return "Every workable plan needs you to mix during \(who)."
        case .foldConflict:
            return "Every workable plan puts a set of folds during \(who)."
        case .shapeConflict:
            return "The dough would most likely be ready to shape during \(who)."
        case .retardOutOfRange:
            return "The fridge proof would be too short or too long to hit that time."
        case .bakeConflict:
            return "Baking at that time would clash with \(who)."
        }
    }
}

public enum PlanResult: Hashable, Sendable {
    case feasible(primary: BakePlan, alternatives: [BakePlan])
    case infeasible(Infeasibility)
    case invalid([InputProblem])

    public var primary: BakePlan? {
        if case let .feasible(p, _) = self { return p }
        return nil
    }
}
