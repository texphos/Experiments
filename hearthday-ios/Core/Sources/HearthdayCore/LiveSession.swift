import Foundation

public enum ShapeReadiness: String, Codable, CaseIterable, Sendable {
    case under, justRight, over
}

public struct CheckIn: Codable, Hashable, Sendable {
    public var at: Date
    public var risePercent: Double
    public var tempC: Double

    public init(at: Date, risePercent: Double, tempC: Double) {
        self.at = at
        self.risePercent = risePercent
        self.tempC = tempC
    }
}

public struct StepConflict: Hashable, Sendable {
    public var step: BakeStep
    public var busyLabel: String
}

/// A bake in progress. Steps are marked done by the baker; the plan can be replaced by a check-in option.
public struct BakeSession: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var plan: BakePlan
    public var originalReadyAt: Date
    public var startedAt: Date
    public var completed: [String: Date]
    public var checkIns: [CheckIn]
    public var shapeReadiness: ShapeReadiness?
    public var rating: Int?
    public var notes: String
    public var finishedAt: Date?
    public var replanCount: Int
    /// Set when a late or early mix/shape forced Hearthday to move the bake; shown until the next re-plan.
    public var adjustmentNote: String?

    public init(id: UUID = UUID(), plan: BakePlan, startedAt: Date) {
        self.id = id
        self.plan = plan
        self.originalReadyAt = plan.readyAt
        self.startedAt = startedAt
        self.completed = [:]
        self.checkIns = []
        self.shapeReadiness = nil
        self.rating = nil
        self.notes = ""
        self.finishedAt = nil
        self.replanCount = 0
    }

    public var nextAttendedStep: BakeStep? {
        plan.steps.first { $0.attended && completed[$0.id] == nil }
    }

    public func passiveStep(at now: Date) -> BakeStep? {
        plan.steps.first { !$0.attended && $0.start <= now && now < $0.end && completed[$0.id] == nil }
    }

    public func isDone(_ step: BakeStep) -> Bool { completed[step.id] != nil }

    /// Where the bake stands when the baker opens the app, including after it was closed for hours.
    public enum Status: Hashable, Sendable {
        case upcoming(BakeStep)
        case due(BakeStep)
        /// The next hands-on step started more than `graceMinutes` ago and hasn't been marked done.
        case overdue(BakeStep, minutesLate: Int)
        case baked
        /// The loaf should have been out long ago; ask the baker to log or abandon it rather than guess.
        case stale
    }

    public static let graceMinutes = 15
    public static let staleAfterHours = 12.0

    public func status(now: Date) -> Status {
        if isBaked { return .baked }
        if now.timeIntervalSince(plan.readyAt) > Self.staleAfterHours * 3600 { return .stale }
        guard let next = nextAttendedStep else { return .baked }
        let late = now.timeIntervalSince(next.start)
        if late > TimeInterval(Self.graceMinutes * 60) {
            return .overdue(next, minutesLate: Int(late / 60))
        }
        return late >= -5 * 60 ? .due(next) : .upcoming(next)
    }

    public var isBaked: Bool { completed["bake"] != nil }

    /// Bulk fermentation is timed from when mixing started.
    public var bulkClockStart: Date {
        guard let mix = plan.step("mix") else { return plan.firstStepAt }
        if let done = completed["mix"] {
            return done.addingTimeInterval(-mix.duration)
        }
        return mix.start
    }

    public var isInBulk: Bool {
        completed["mix"] != nil && completed["shape"] == nil
    }

    /// True once the dough has gone into the fridge mid-bulk. It stays true even if the plan is replaced later,
    /// because `completed` is never pruned. Bakes saved before the transfer step existed count as chilled as
    /// soon as their plan has a cold bulk.
    public var isChilled: Bool {
        if completed["fridge"] != nil { return true }
        return plan.step("fridge") == nil && plan.steps.contains { $0.kind == .coldBulk }
    }

    /// Rise check-ins compare against room-temperature targets, so they stop once the dough is chilled.
    public var canCheckIn: Bool { isInBulk && !isChilled }

    /// Mark a hands-on step done. Finishing the mix late or early slides the dough-driven steps with it; if that
    /// squeezes or stretches a cold proof beyond what's workable, the bake moves (see `keepColdProofWorkable`).
    public mutating func complete(
        _ stepID: String,
        at now: Date,
        availability: Availability? = nil,
        calendar: Calendar = .current,
        process: ProcessSettings = ProcessSettings()
    ) {
        guard let step = plan.step(stepID), completed[stepID] == nil else { return }
        completed[stepID] = now
        if stepID == "mix" {
            let delta = now.timeIntervalSince(step.end)
            if abs(delta) >= 60 { shiftDoughSteps(by: delta) }
        }
        if stepID == "shape" {
            let delta = now.timeIntervalSince(step.end)
            if abs(delta) >= 60 { shiftAfterShape(by: delta) }
        }
        if stepID == "mix" || stepID == "shape" {
            keepColdProofWorkable(reason: stepID == "mix" ? "Mixing" : "Shaping", availability: availability, calendar: calendar, process: process)
        }
        if stepID == "bake" { finishedAt = now }
    }

    /// Keeps a pending cold proof within the workable range. When it falls outside, the bake moves to the nearest
    /// grid time inside the range, preferring one where preheat and bake are free, and `adjustmentNote` says why.
    mutating func keepColdProofWorkable(reason: String, availability: Availability?, calendar: Calendar, process: ProcessSettings) {
        guard let retard = plan.step("cold-proof"), let bake = plan.step("bake"), let preheat = plan.step("preheat"),
              completed[retard.id] == nil, completed[bake.id] == nil, completed[preheat.id] == nil else { return }
        let low = retard.start.addingTimeInterval(process.retardMinHours * 3600)
        let high = retard.start.addingTimeInterval(process.retardMaxHours * 3600)
        let current = bake.start
        guard current < low || current > high else { return }

        let grid = TimeInterval(process.gridMinutes * 60)
        var candidates: [Date] = []
        var t = ceilToGrid(low, grid)
        while t <= high {
            candidates.append(t)
            t = t.addingTimeInterval(grid)
        }
        if candidates.isEmpty { candidates = [low] }
        candidates.sort {
            let a = abs($0.timeIntervalSince(current)), b = abs($1.timeIntervalSince(current))
            return a != b ? a < b : $0 < $1
        }
        let preheatDuration = preheat.duration
        let bakeDuration = bake.duration
        var chosen = candidates[0]
        if let availability {
            let timeline = availability.timeline(
                from: low.addingTimeInterval(-preheatDuration - 3600),
                to: high.addingTimeInterval(bakeDuration + 3600),
                calendar: calendar
            )
            if let free = candidates.first(where: {
                timeline.isFree(start: $0.addingTimeInterval(-preheatDuration), duration: preheatDuration + bakeDuration)
            }) {
                chosen = free
            }
        }

        plan.steps = sortSteps(plan.steps.map { step in
            switch step.id {
            case retard.id:
                return StepFactory.coldRetard(start: retard.start, end: chosen, process: process)
            case preheat.id:
                var s = step
                s.start = chosen.addingTimeInterval(-preheatDuration)
                s.end = chosen
                return s
            case bake.id:
                var s = step
                s.start = chosen
                s.end = chosen.addingTimeInterval(bakeDuration)
                return s
            default:
                return step
            }
        })
        adjustmentNote = current < low
            ? "\(reason) ran late, so the bake moved later to give the cold proof at least \(Int(process.retardMinHours)) h."
            : "\(reason) was early, so the bake moved earlier to keep the cold proof under \(Int(process.retardMaxHours)) h."
    }

    mutating func shiftDoughSteps(by delta: TimeInterval) {
        let doughKinds: Set<StepKind> = [.fold, .bulk, .shape]
        let followsShapeInRoom = plan.proofMode == .room
        plan.steps = sortSteps(plan.steps.map { step in
            var s = step
            if completed[s.id] != nil { return s }
            if doughKinds.contains(s.kind) || (followsShapeInRoom && [.roomProof, .preheat, .bake].contains(s.kind)) {
                s.start = s.start.addingTimeInterval(delta)
                s.end = s.end.addingTimeInterval(delta)
                s.likelyStart = s.likelyStart?.addingTimeInterval(delta)
                s.likelyEnd = s.likelyEnd?.addingTimeInterval(delta)
            } else if s.kind == .coldRetard {
                s.start = s.start.addingTimeInterval(delta)
            }
            return s
        })
    }

    mutating func shiftAfterShape(by delta: TimeInterval) {
        plan.steps = sortSteps(plan.steps.map { step in
            var s = step
            if completed[s.id] != nil { return s }
            switch s.kind {
            case .coldRetard:
                s.start = s.start.addingTimeInterval(delta)
            case .roomProof, .preheat, .bake:
                if plan.proofMode == .room {
                    s.start = s.start.addingTimeInterval(delta)
                    s.end = s.end.addingTimeInterval(delta)
                }
            default:
                break
            }
            return s
        })
    }

    /// Upcoming hands-on steps that now collide with a busy block (for a heads-up banner).
    public func upcomingConflicts(now: Date, availability: Availability, calendar: Calendar) -> [StepConflict] {
        let pending = plan.steps.filter { $0.attended && completed[$0.id] == nil && $0.end > now }
        guard let last = pending.map(\.end).max() else { return [] }
        let timeline = availability.timeline(from: now.addingTimeInterval(-3600), to: last, calendar: calendar)
        return pending.compactMap { step in
            timeline.conflict(start: step.start, duration: step.duration).map { StepConflict(step: step, busyLabel: $0.label) }
        }
    }

    /// Hours of bulk at room temperature: from mixing until shaping, or until the dough went into the fridge.
    public var actualBulkHours: Double? {
        guard let shapeDone = completed["shape"], let shape = plan.step("shape") else { return nil }
        var end = shapeDone.addingTimeInterval(-shape.duration)
        if let fridged = completed["fridge"] {
            end = fridged.addingTimeInterval(-TimeInterval(LiveReplanner.fridgeTransferMinutes * 60))
        } else if isChilled, let cold = plan.steps.first(where: { $0.kind == .coldBulk }) {
            end = cold.start
        }
        return max(0, end.timeIntervalSince(bulkClockStart) / 3600)
    }

    public var averageTempC: Double {
        guard !checkIns.isEmpty else { return plan.kitchenTempC }
        let temps = [plan.kitchenTempC] + checkIns.map(\.tempC)
        return temps.reduce(0, +) / Double(temps.count)
    }

    /// A calibration sample, only when the baker judged the dough "just right" at shaping and bulk ran
    /// entirely at room temperature. Chilled bulks are excluded outright: the model has no term for time in the
    /// fridge, and counting it as room time would teach Hearthday that the baker's dough is slow.
    public func calibrationSample(baseModel: FermentationModel = FermentationModel()) -> Calibration.Sample? {
        guard shapeReadiness == .justRight,
              !isChilled,
              completed["fridge"] == nil,
              !plan.steps.contains(where: { $0.kind == .coldBulk || $0.kind == .fridgeDough }),
              let actual = actualBulkHours,
              let date = completed["shape"] else { return nil }
        var model = baseModel
        model.speedFactor = 1
        let modelHours = model.bulkHours(tempC: averageTempC, inoculationPercent: plan.inoculationPercent)
        return Calibration.Sample(
            date: date,
            tempC: averageTempC,
            inoculationPercent: plan.inoculationPercent,
            modelHours: modelHours,
            actualHours: actual
        )
    }

    /// Accept a check-in option: keep what already happened, replace everything from the end of bulk on.
    /// Pending folds that would fall after the new end of bulk are dropped, and any earlier fridge option that
    /// hadn't been carried out is replaced. Ignored once the dough is chilled, when check-ins no longer apply.
    public mutating func apply(_ option: ReplanOption) {
        guard !isChilled else { return }
        var kept = plan.steps.filter { step in
            switch step.kind {
            case .feedStarter, .starterRise, .mix: return true
            case .fold: return completed[step.id] != nil || step.end <= option.bulkEndsAt
            default: return false
            }
        }
        if var bulk = plan.step("bulk") {
            let lastKeptEnd = kept.map(\.end).max() ?? bulk.start
            bulk.start = min(bulk.start, lastKeptEnd, option.bulkEndsAt)
            bulk.end = option.bulkEndsAt
            kept.append(bulk)
        }
        plan.steps = sortSteps(kept + option.steps)
        if option.steps.contains(where: { $0.kind == .coldRetard }) { plan.proofMode = .fridge }
        if option.steps.contains(where: { $0.kind == .roomProof }) { plan.proofMode = .room }
        replanCount += 1
        adjustmentNote = nil
    }
}

public struct ReplanOption: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case shapeNow, shapeWhenReady, stayUp, fridgeNow, waitLonger
    }

    public var kind: Kind
    public var title: String
    public var detail: String
    public var bulkEndsAt: Date
    public var steps: [BakeStep]
    public var conflictLabel: String?
    public var recommended: Bool

    public var id: String { kind.rawValue }
    public var shapeAt: Date? { steps.first { $0.kind == .shape }?.start }
    public var readyAt: Date { steps.last?.end ?? bulkEndsAt }
}

public struct CheckInResult: Hashable, Sendable {
    public var progress: Double
    public var targetRisePercent: Double
    public var estimatedReadyAt: Date
    public var summary: String
    public var options: [ReplanOption]
    public var problems: [InputProblem] = []
}

/// Re-plans the rest of a bake from a mid-bulk observation (volume rise in a straight-sided container
/// or aliquot jar). Progress toward the temperature-dependent target rise is extrapolated linearly;
/// fermentation usually accelerates, so this tends to overestimate the time remaining — the safer error
/// when the alternative is over-proofing while the baker is asleep.
public enum LiveReplanner {
    /// Before this, one reading says little about the dough's speed, so the summary says the estimate is rough.
    public static let earlyReadingMinutes = 45
    public static let fridgeTransferMinutes = 5

    public static func checkIn(
        session: BakeSession,
        now: Date,
        risePercent: Double,
        tempC: Double,
        availability: Availability,
        calendar: Calendar,
        model: FermentationModel,
        process: ProcessSettings = ProcessSettings()
    ) -> CheckInResult {
        var problems = CheckInValidation.problems(risePercent: risePercent, tempC: tempC)
        if session.isChilled {
            problems = [.doughIsChilled]
        } else if !session.isInBulk {
            problems = [.notInBulk]
        }
        guard problems.isEmpty else {
            return CheckInResult(
                progress: 0,
                targetRisePercent: 0,
                estimatedReadyAt: now,
                summary: problems.map(\.message).joined(separator: " "),
                options: [],
                problems: problems
            )
        }
        let target = FermentationModel.targetRisePercent(tempC: tempC)
        let elapsed = max(now.timeIntervalSince(session.bulkClockStart), 600)
        let progress = min(max(risePercent / target, 0.02), 2)
        let remaining: TimeInterval = progress >= 0.95 ? 0 : elapsed / progress - elapsed
        let readyAt = now.addingTimeInterval(remaining)
        let totalBulk = elapsed + remaining
        let tolerance = max(1800, 0.15 * totalBulk)
        let shapeDuration = TimeInterval(process.shapeMinutes * 60)
        let timeline = availability.timeline(
            from: now.addingTimeInterval(-3600),
            to: now.addingTimeInterval(TimeInterval((process.retardMaxHours + 60) * 3600)),
            calendar: calendar
        )
        let tailContext = TailContext(
            mode: session.plan.proofMode,
            originalReadyAt: session.originalReadyAt,
            tempC: tempC,
            model: model,
            process: process,
            timeline: timeline,
            likelyStart: readyAt.addingTimeInterval(-tolerance),
            likelyEnd: readyAt.addingTimeInterval(tolerance),
            targetRise: target
        )

        var options: [ReplanOption] = []
        let searchLimit = now.addingTimeInterval(48 * 3600)
        let freeShape = timeline.earliestFreeStart(atOrAfter: max(readyAt, now), duration: shapeDuration, limit: searchLimit)

        if let free = freeShape, free.timeIntervalSince(readyAt) <= tolerance {
            if let steps = tail(shapeAt: free, ctx: tailContext) {
                let isNow = remaining == 0 && free.timeIntervalSince(now) <= 300
                options.append(ReplanOption(
                    kind: isNow ? .shapeNow : .shapeWhenReady,
                    title: isNow ? "Shape now" : "Shape when it’s ready",
                    detail: isNow
                        ? "Your reading is at the target rise and you’re free. Confirm with a domed top and bubbles at the edges."
                        : "You’re free when the dough is likely ready. Reminders move to match.",
                    bulkEndsAt: free,
                    steps: steps,
                    conflictLabel: nil,
                    recommended: true
                ))
            }
        } else {
            let conflict = timeline.conflict(start: readyAt, duration: shapeDuration)
            let label = conflict?.label

            // The transfer is hands-on, so it has to happen while the baker is free: 10 minutes before the busy
            // block when that slot is free, otherwise right now (the baker is holding the phone).
            let transfer = TimeInterval(fridgeTransferMinutes * 60)
            let fridgeAt: Date = {
                guard let c = conflict, c.start > now else { return now }
                let before = max(now, c.start.addingTimeInterval(-600))
                if before.timeIntervalSince(now) < 300 || timeline.isFree(start: before, duration: transfer) { return before }
                return now
            }()
            let progressAtFridge = min(1, (elapsed + fridgeAt.timeIntervalSince(now)) / totalBulk)
            if let free = freeShape, progressAtFridge >= minimumColdBulkProgress, free > fridgeAt.addingTimeInterval(transfer) {
                if var rest = tail(shapeAt: free, ctx: tailContext) {
                    rest[0] = StepFactory.shapeCold(start: free, minutes: process.shapeMinutes)
                    let moveToFridge = StepFactory.fridgeDough(start: fridgeAt, minutes: fridgeTransferMinutes)
                    let coldBulk = StepFactory.coldBulk(start: moveToFridge.end, end: free)
                    let comfortable = progressAtFridge >= comfortableColdBulkProgress
                    let pctIn = Int((progressAtFridge * 100).rounded())
                    options.append(ReplanOption(
                        kind: .fridgeNow,
                        title: fridgeAt.timeIntervalSince(now) < 300 ? "Fridge the dough now" : "Fridge the dough before \(label ?? "then")",
                        detail: progressAtFridge >= 0.95
                            ? "It should be about ready by then. Chilling slows it right down so you can shape it cold when you’re free."
                            : comfortable
                            ? "It goes in about \(pctIn)% of the way through bulk and keeps fermenting slowly as it chills. Shape it cold when you’re free."
                            : "It would go in only about \(pctIn)% of the way through bulk. If it hasn’t risen much by morning, give it time at room temperature before shaping.",
                        bulkEndsAt: fridgeAt,
                        steps: [moveToFridge, coldBulk] + rest,
                        conflictLabel: nil,
                        recommended: comfortable
                    ))
                }
            }

            if let steps = tail(shapeAt: readyAt, ctx: tailContext) {
                options.append(ReplanOption(
                    kind: .stayUp,
                    title: label.map { "Shape during \($0)" } ?? "Shape on time",
                    detail: "Shapes at the likely-ready time, but you’d need to be around.",
                    bulkEndsAt: readyAt,
                    steps: steps,
                    conflictLabel: label,
                    recommended: !options.contains(where: \.recommended)
                ))
            }

            if let free = freeShape, free.timeIntervalSince(readyAt) <= 3 * tolerance, free > readyAt {
                let over = free.timeIntervalSince(readyAt) / 3600
                if let steps = tail(shapeAt: free, ctx: tailContext) {
                    options.append(ReplanOption(
                        kind: .waitLonger,
                        title: "Leave it out and shape later",
                        detail: "About \(DurationText.halfHours(over)) h past the likely-ready point. Can work in a cool kitchen; risks over-proofing when it’s warm.",
                        bulkEndsAt: free,
                        steps: steps,
                        conflictLabel: nil,
                        recommended: false
                    ))
                }
            }
        }

        let pct = Int((progress * 100).rounded())
        let sinceMix = max(0, Int((now.timeIntervalSince(session.bulkClockStart) / 60).rounded()))
        let summary: String
        if remaining == 0 {
            summary = "At \(Int(risePercent.rounded()))% rise your reading meets the target of about \(Int(target.rounded()))%. Go by the dough: a domed top and bubbles at the edges."
        } else if sinceMix < earlyReadingMinutes {
            summary = "Only \(DurationText.compact(minutes: sinceMix)) since mixing, so this is a very rough guess: a straight line says about \(DurationText.approximate(hours: remaining / 3600)). A reading after the first hour is much more reliable."
        } else {
            summary = "About \(pct)% of the way to a \(Int(target.rounded()))% rise. Likely ready in about \(DurationText.approximate(hours: remaining / 3600)). That’s a straight-line estimate from one reading, so check again if you can."
        }

        return CheckInResult(
            progress: progress,
            targetRisePercent: target,
            estimatedReadyAt: readyAt,
            summary: summary,
            options: options
        )
    }

    struct TailContext {
        var mode: ProofMode
        var originalReadyAt: Date
        var tempC: Double
        var model: FermentationModel
        var process: ProcessSettings
        var timeline: BusyTimeline
        var likelyStart: Date
        var likelyEnd: Date
        var targetRise: Double
    }

    /// Below this, a cold bulk is not offered at all; below the comfortable level it is offered with a caveat.
    static let minimumColdBulkProgress = 0.35
    static let comfortableColdBulkProgress = 0.5

    /// Shape → proof → preheat → bake. When a room proof would put baking in a busy block, fall back to a
    /// fridge proof, the most forgiving lever.
    static func tail(shapeAt: Date, ctx: TailContext) -> [BakeStep]? {
        if let steps = tailInMode(shapeAt: shapeAt, ctx: ctx) { return steps }
        guard ctx.mode == .room else { return nil }
        var fridge = ctx
        fridge.mode = .fridge
        return tailInMode(shapeAt: shapeAt, ctx: fridge)
    }

    /// Keeps the original finish time when possible.
    static func tailInMode(shapeAt: Date, ctx: TailContext) -> [BakeStep]? {
        let p = ctx.process
        let grid = TimeInterval(p.gridMinutes * 60)
        let shapeDuration = TimeInterval(p.shapeMinutes * 60)
        let bake = TimeInterval(p.bakeMinutes * 60)
        let preheat = TimeInterval(p.preheatMinutes * 60)
        let shapeEnd = shapeAt.addingTimeInterval(shapeDuration)
        let shape = StepFactory.shape(
            start: shapeAt,
            minutes: p.shapeMinutes,
            likelyStart: ctx.likelyStart,
            likelyEnd: ctx.likelyEnd,
            targetRise: ctx.targetRise
        )

        var bestStart: Date?
        var bestDistance = Double.infinity
        let low: Date
        let high: Date
        let target: Date
        switch ctx.mode {
        case .fridge:
            low = shapeEnd.addingTimeInterval(p.retardMinHours * 3600)
            high = shapeEnd.addingTimeInterval(p.retardMaxHours * 3600)
            target = ctx.originalReadyAt.addingTimeInterval(-bake)
        case .room:
            let proof = ctx.model.roomProofHours(tempC: ctx.tempC) * 3600
            low = shapeEnd.addingTimeInterval(proof * (1 - ctx.model.uncertainty))
            high = shapeEnd.addingTimeInterval(proof * (1 + ctx.model.uncertainty))
            target = shapeEnd.addingTimeInterval(proof)
        }

        var probe: [Date] = (ctx.mode == .fridge && target >= low && target <= high) ? [target] : []
        var t = ceilToGrid(low, grid)
        while t <= high {
            probe.append(t)
            t = t.addingTimeInterval(grid)
        }
        for start in probe where start >= low && start <= high {
            guard ctx.timeline.isFree(start: start.addingTimeInterval(-preheat), duration: preheat + bake) else { continue }
            let d = abs(start.timeIntervalSince(target))
            if d < bestDistance - 1e-6 {
                bestDistance = d
                bestStart = start
            }
        }
        guard let bakeStart = bestStart else { return nil }

        let middle: BakeStep
        switch ctx.mode {
        case .fridge:
            middle = StepFactory.coldRetard(start: shapeEnd, end: bakeStart, process: p)
        case .room:
            let hours = ctx.model.roomProofHours(tempC: ctx.tempC)
            middle = StepFactory.roomProof(
                start: shapeEnd,
                end: bakeStart,
                lowHours: hours * (1 - ctx.model.uncertainty),
                highHours: hours * (1 + ctx.model.uncertainty)
            )
        }
        return [
            shape,
            middle,
            StepFactory.preheat(start: bakeStart.addingTimeInterval(-preheat), minutes: p.preheatMinutes),
            StepFactory.bake(start: bakeStart, minutes: p.bakeMinutes),
        ]
    }
}
