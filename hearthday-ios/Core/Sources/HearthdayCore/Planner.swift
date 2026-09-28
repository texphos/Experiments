import Foundation

/// Finds bake plans whose hands-on moments avoid the baker's busy blocks.
///
/// Levers, in the order a baker would reach for them: mix time, fridge vs room proof and fridge duration,
/// starter percentage, and feed ratio. The search is exhaustive over a 15-minute grid and fully deterministic:
/// the same request always yields the same plan.
public enum Planner {
    static let maxLeadHours = 72.0
    static let earliestSearchHours = 72

    public static func plan(_ request: PlanRequest, calendar: Calendar) -> PlanResult {
        let problems = request.problems
        guard problems.isEmpty else { return .invalid(problems) }
        var diagnostics = Diagnostics()
        let candidates = search(request, calendar: calendar, diagnostics: &diagnostics)
        if let primary = candidates.first {
            var alternatives: [BakePlan] = []
            var seen: Set<String> = [signature(primary)]
            for candidate in candidates.dropFirst() where alternatives.count < 2 {
                let s = signature(candidate)
                if !seen.contains(s) {
                    seen.insert(s)
                    alternatives.append(candidate)
                }
            }
            return .feasible(primary: primary, alternatives: alternatives)
        }
        return .infeasible(Infeasibility(
            reason: diagnostics.reason,
            blockingLabel: diagnostics.label,
            earliestFeasibleReadyAt: earliestFeasibleReadyTime(request, calendar: calendar)
        ))
    }

    public static func earliestFeasibleReadyTime(_ request: PlanRequest, calendar: Calendar) -> Date? {
        var r = request
        for hour in 1...earliestSearchHours {
            r.readyBy = request.readyBy.addingTimeInterval(TimeInterval(hour) * 3600)
            var scratch = Diagnostics()
            if let first = search(r, calendar: calendar, diagnostics: &scratch).first {
                return first.readyAt
            }
        }
        return nil
    }

    static func signature(_ plan: BakePlan) -> String {
        "\(plan.proofMode.rawValue)|\(Int(plan.inoculationPercent.rounded()))|\(plan.feedRatio?.rawValue ?? "-")"
    }

    static func inoculationOptions(_ r: PlanRequest) -> [Double] {
        var options = [r.formula.starterPercent]
        if r.allowInoculationAdjustment {
            for v in [10.0, 15.0, 20.0] where abs(v - r.formula.starterPercent) > 0.01 {
                options.append(v)
            }
        }
        return options
    }

    static func search(_ r: PlanRequest, calendar: Calendar, diagnostics: inout Diagnostics) -> [BakePlan] {
        let p = r.process
        let grid = TimeInterval(p.gridMinutes * 60)
        let timeline = r.availability.timeline(
            from: r.now.addingTimeInterval(-3600),
            to: r.readyBy.addingTimeInterval(3600),
            calendar: calendar
        )
        let ratios: [FeedRatio?] = r.starterNeedsFeed
            ? (r.allowFeedRatioAdjustment ? FeedRatio.allCases : [r.preferredFeedRatio])
            : [nil]

        var results: [(plan: BakePlan, order: Int)] = []
        var order = 0
        for mode in r.proofModes {
            if let busy = ovenSlotConflict(r, mode: mode, timeline: timeline) {
                diagnostics.note(.bakeConflict, busy.label)
                continue
            }
            for inoc in inoculationOptions(r) {
                for ratio in ratios {
                    order += 1
                    let ctx = Context(request: r, timeline: timeline, mode: mode, inoculation: inoc, ratio: ratio)
                    let earliestFromNow = ceilToGrid(r.now.addingTimeInterval(ctx.feedLead), grid)
                    let earliestFromHorizon = ceilToGrid(r.readyBy.addingTimeInterval(-maxLeadHours * 3600), grid)
                    let earliestMix = max(earliestFromNow, earliestFromHorizon)
                    let latestMix = r.readyBy.addingTimeInterval(-ctx.minimumSpanFromMix)
                    if earliestMix > latestMix {
                        diagnostics.note(.notEnoughTime, nil)
                        continue
                    }
                    var mix = earliestMix
                    while mix <= latestMix {
                        if let plan = evaluate(mix: mix, ctx: ctx, diagnostics: &diagnostics) {
                            results.append((plan, order))
                        }
                        mix = mix.addingTimeInterval(grid)
                    }
                }
            }
        }
        results.sort { a, b in
            if abs(a.plan.score - b.plan.score) > 1e-9 { return a.plan.score < b.plan.score }
            if a.plan.mixAt != b.plan.mixAt { return a.plan.mixAt < b.plan.mixAt }
            return a.order < b.order
        }
        return results.map(\.plan)
    }

    /// The oven window does not depend on the dough, so check it before searching.
    /// Returns the busy block when no allowed bake slot near `readyBy` is free.
    static func ovenSlotConflict(_ r: PlanRequest, mode: ProofMode, timeline: BusyTimeline) -> BusyInterval? {
        let p = r.process
        let attended = TimeInterval((p.preheatMinutes + p.bakeMinutes) * 60)
        switch mode {
        case .fridge:
            return timeline.conflict(start: r.readyBy.addingTimeInterval(-attended), duration: attended)
        case .room:
            let grid = TimeInterval(p.gridMinutes * 60)
            let latestEnd = r.readyBy
            var end = r.readyBy.addingTimeInterval(-TimeInterval(p.roomFinishSlackMinutes * 60))
            var first: BusyInterval?
            while end <= latestEnd {
                guard let c = timeline.conflict(start: end.addingTimeInterval(-attended), duration: attended) else { return nil }
                first = first ?? c
                end = end.addingTimeInterval(grid)
            }
            return first
        }
    }

    struct Context {
        let request: PlanRequest
        let timeline: BusyTimeline
        let mode: ProofMode
        let inoculation: Double
        let ratio: FeedRatio?

        var process: ProcessSettings { request.process }
        var model: FermentationModel { request.model }
        var u: Double { request.model.uncertainty }
        var grid: TimeInterval { TimeInterval(process.gridMinutes * 60) }

        var feedLead: TimeInterval {
            ratio.map { model.starterPeakHours(ratio: $0, tempC: request.kitchenTempC) * 3600 } ?? 0
        }
        var bulkHours: Double { model.bulkHours(tempC: request.kitchenTempC, inoculationPercent: inoculation) }
        var modelBulkHours: Double {
            var base = model
            base.speedFactor = 1
            return base.bulkHours(tempC: request.kitchenTempC, inoculationPercent: inoculation)
        }
        var proofHours: Double { model.roomProofHours(tempC: request.kitchenTempC) }
        var foldSpan: TimeInterval {
            process.foldCount > 0
                ? TimeInterval(process.foldCount * process.foldIntervalMinutes * 60 + process.foldMinutes * 60)
                : TimeInterval(process.mixMinutes * 60)
        }
        var shapeDuration: TimeInterval { TimeInterval(process.shapeMinutes * 60) }
        var bakeDuration: TimeInterval { TimeInterval(process.bakeMinutes * 60) }
        var preheatDuration: TimeInterval { TimeInterval(process.preheatMinutes * 60) }

        var minimumSpanFromMix: TimeInterval {
            let tail = mode == .fridge ? process.retardMinHours * 3600 : proofHours * 3600 * (1 - u)
            return max(bulkHours * 3600 * (1 - u), foldSpan) + shapeDuration + tail + bakeDuration
        }
    }

    struct Tail {
        var steps: [BakeStep]
        var penalty: Double
    }

    static func evaluate(mix: Date, ctx: Context, diagnostics: inout Diagnostics) -> BakePlan? {
        let r = ctx.request
        let p = ctx.process
        var steps: [BakeStep] = []

        if let ratio = ctx.ratio {
            let feedAt = floorToMinute(mix.addingTimeInterval(-ctx.feedLead))
            guard feedAt >= r.now else {
                diagnostics.note(.notEnoughTime, nil)
                return nil
            }
            if let c = ctx.timeline.conflict(start: feedAt, duration: TimeInterval(p.feedMinutes * 60)) {
                diagnostics.note(.feedConflict, c.label)
                return nil
            }
            let feed = StepFactory.feed(
                start: feedAt,
                minutes: p.feedMinutes,
                ratio: ratio,
                peakHours: ctx.model.starterPeakHours(ratio: ratio, tempC: r.kitchenTempC)
            )
            steps.append(feed)
            if feed.end < mix {
                steps.append(StepFactory.starterRise(start: feed.end, end: mix))
            }
        }

        if let c = ctx.timeline.conflict(start: mix, duration: TimeInterval(p.mixMinutes * 60)) {
            diagnostics.note(.mixConflict, c.label)
            return nil
        }
        steps.append(StepFactory.mix(start: mix, minutes: p.mixMinutes, inoculation: ctx.inoculation, formula: r.formula))

        if p.foldCount > 0 {
            for i in 1...p.foldCount {
                let start = mix.addingTimeInterval(TimeInterval(i * p.foldIntervalMinutes * 60))
                if let c = ctx.timeline.conflict(start: start, duration: TimeInterval(p.foldMinutes * 60)) {
                    diagnostics.note(.foldConflict, c.label)
                    return nil
                }
                steps.append(StepFactory.fold(number: i, count: p.foldCount, start: start, minutes: p.foldMinutes))
            }
        }

        let bulk = ctx.bulkHours * 3600
        let expected = mix.addingTimeInterval(bulk)
        let likelyStart = mix.addingTimeInterval(bulk * (1 - ctx.u))
        let likelyEnd = mix.addingTimeInterval(bulk * (1 + ctx.u))
        let lastFoldEnd = mix.addingTimeInterval(ctx.foldSpan)
        let targetRise = FermentationModel.targetRisePercent(tempC: r.kitchenTempC)

        var best: (score: Double, shapeAt: Date, tail: Tail)?
        var sawFreeShape = false
        var shapeAt = ceilToGrid(max(likelyStart, lastFoldEnd), ctx.grid)
        while shapeAt <= likelyEnd {
            if ctx.timeline.isFree(start: shapeAt, duration: ctx.shapeDuration) {
                sawFreeShape = true
                if let tail = buildTail(shapeAt: shapeAt, ctx: ctx, diagnostics: &diagnostics) {
                    let score = abs(shapeAt.timeIntervalSince(expected)) / 3600 + tail.penalty
                    if best == nil || score < best!.score - 1e-9 {
                        best = (score, shapeAt, tail)
                    }
                }
            }
            shapeAt = shapeAt.addingTimeInterval(ctx.grid)
        }

        if !sawFreeShape {
            let label = ctx.timeline.conflict(start: expected, duration: ctx.shapeDuration)?.label
                ?? ctx.timeline.conflict(start: likelyStart, duration: likelyEnd.timeIntervalSince(likelyStart))?.label
            diagnostics.note(.shapeConflict, label)
            return nil
        }
        guard let chosen = best else { return nil }

        steps.append(StepFactory.bulk(
            start: lastFoldEnd,
            end: chosen.shapeAt,
            lowHours: ctx.bulkHours * (1 - ctx.u),
            highHours: ctx.bulkHours * (1 + ctx.u),
            targetRise: targetRise
        ))
        steps.append(StepFactory.shape(
            start: chosen.shapeAt,
            minutes: p.shapeMinutes,
            likelyStart: likelyStart,
            likelyEnd: likelyEnd,
            targetRise: targetRise
        ))
        steps.append(contentsOf: chosen.tail.steps)

        let inocPenalty = abs(ctx.inoculation - r.formula.starterPercent) / 5 * 0.5
        let ratioPenalty = ctx.ratio.map { Double(abs($0.index - r.preferredFeedRatio.index)) * 0.25 } ?? 0

        return BakePlan(
            steps: sortSteps(steps),
            proofMode: ctx.mode,
            inoculationPercent: ctx.inoculation,
            feedRatio: ctx.ratio,
            kitchenTempC: r.kitchenTempC,
            formula: r.formula,
            expectedBulkHours: ctx.bulkHours,
            modelBulkHours: ctx.modelBulkHours,
            uncertainty: ctx.u,
            score: chosen.score + inocPenalty + ratioPenalty
        )
    }

    static func buildTail(shapeAt: Date, ctx: Context, diagnostics: inout Diagnostics) -> Tail? {
        let r = ctx.request
        let p = ctx.process
        let shapeEnd = shapeAt.addingTimeInterval(ctx.shapeDuration)

        switch ctx.mode {
        case .fridge:
            let bakeEnd = r.readyBy
            let bakeStart = bakeEnd.addingTimeInterval(-ctx.bakeDuration)
            let preheatStart = bakeStart.addingTimeInterval(-ctx.preheatDuration)
            if let c = ctx.timeline.conflict(start: preheatStart, duration: ctx.preheatDuration + ctx.bakeDuration) {
                diagnostics.note(.bakeConflict, c.label)
                return nil
            }
            let retardHours = bakeStart.timeIntervalSince(shapeEnd) / 3600
            guard retardHours >= p.retardMinHours, retardHours <= p.retardMaxHours else {
                diagnostics.note(.retardOutOfRange, nil)
                return nil
            }
            return Tail(
                steps: [
                    StepFactory.coldRetard(start: shapeEnd, end: bakeStart, process: p),
                    StepFactory.preheat(start: preheatStart, minutes: p.preheatMinutes),
                    StepFactory.bake(start: bakeStart, minutes: p.bakeMinutes),
                ],
                penalty: distanceOutside(retardHours, p.retardPreferredLowHours, p.retardPreferredHighHours) * 0.15
            )

        case .room:
            let proof = ctx.proofHours * 3600
            let expected = shapeEnd.addingTimeInterval(proof)
            let low = max(
                shapeEnd.addingTimeInterval(proof * (1 - ctx.u)),
                r.readyBy.addingTimeInterval(-TimeInterval(p.roomFinishSlackMinutes * 60) - ctx.bakeDuration)
            )
            let high = min(shapeEnd.addingTimeInterval(proof * (1 + ctx.u)), r.readyBy.addingTimeInterval(-ctx.bakeDuration))
            guard low <= high else { return nil }
            var best: (distance: Double, bakeStart: Date)?
            var conflictLabel: String?
            var bakeStart = ceilToGrid(low, ctx.grid)
            while bakeStart <= high {
                let preheatStart = bakeStart.addingTimeInterval(-ctx.preheatDuration)
                if let c = ctx.timeline.conflict(start: preheatStart, duration: ctx.preheatDuration + ctx.bakeDuration) {
                    conflictLabel = conflictLabel ?? c.label
                } else {
                    let d = abs(bakeStart.timeIntervalSince(expected)) / 3600
                    if best == nil || d < best!.distance - 1e-9 {
                        best = (d, bakeStart)
                    }
                }
                bakeStart = bakeStart.addingTimeInterval(ctx.grid)
            }
            guard let chosen = best else {
                if let conflictLabel { diagnostics.note(.bakeConflict, conflictLabel) }
                return nil
            }
            return Tail(
                steps: [
                    StepFactory.roomProof(
                        start: shapeEnd,
                        end: chosen.bakeStart,
                        lowHours: ctx.proofHours * (1 - ctx.u),
                        highHours: ctx.proofHours * (1 + ctx.u)
                    ),
                    StepFactory.preheat(start: chosen.bakeStart.addingTimeInterval(-ctx.preheatDuration), minutes: p.preheatMinutes),
                    StepFactory.bake(start: chosen.bakeStart, minutes: p.bakeMinutes),
                ],
                penalty: chosen.distance
            )
        }
    }

    struct Diagnostics {
        var reason: BlockReason = .notEnoughTime
        var labelCounts: [String: Int] = [:]

        mutating func note(_ r: BlockReason, _ label: String?) {
            if r.depth > reason.depth {
                reason = r
                labelCounts = [:]
            }
            if r == reason, let label {
                labelCounts[label, default: 0] += 1
            }
        }

        var label: String? {
            labelCounts.max { a, b in
                a.value != b.value ? a.value < b.value : a.key > b.key
            }?.key
        }
    }
}

// MARK: - Helpers shared with the live replanner

func ceilToGrid(_ date: Date, _ grid: TimeInterval) -> Date {
    Date(timeIntervalSince1970: (date.timeIntervalSince1970 / grid).rounded(.up) * grid)
}

func floorToMinute(_ date: Date) -> Date {
    Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
}

func distanceOutside(_ value: Double, _ low: Double, _ high: Double) -> Double {
    if value < low { return low - value }
    if value > high { return value - high }
    return 0
}

private let stepOrder: [StepKind] = [
    .feedStarter, .starterRise, .mix, .fold, .bulk, .fridgeDough, .coldBulk, .shape, .coldRetard, .roomProof, .preheat, .bake,
]

func sortSteps(_ steps: [BakeStep]) -> [BakeStep] {
    steps.sorted { a, b in
        if a.start != b.start { return a.start < b.start }
        return (stepOrder.firstIndex(of: a.kind) ?? 0) < (stepOrder.firstIndex(of: b.kind) ?? 0)
    }
}
