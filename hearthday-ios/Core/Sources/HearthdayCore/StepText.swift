import Foundation

public enum DurationText {
    /// Rounds to the nearest half hour: 5.3 → "5½".
    public static func halfHours(_ hours: Double) -> String {
        let v = (hours * 2).rounded() / 2
        let whole = Int(v)
        let hasHalf = v - Double(whole) >= 0.5
        if whole == 0 && hasHalf { return "½" }
        return hasHalf ? "\(whole)½" : "\(whole)"
    }

    public static func hoursRange(_ low: Double, _ high: Double) -> String {
        let a = halfHours(low)
        let b = halfHours(high)
        return a == b ? "about \(a) h" : "\(a)–\(b) h"
    }

    /// "1 h 25 min", "40 min".
    /// A rough duration for estimates: nearest 5 minutes under an hour (never "0"), nearest half hour above.
    public static func approximate(hours: Double) -> String {
        if hours < 0.75 {
            return "\(max(5, Int((hours * 12).rounded()) * 5)) min"
        }
        return "\(halfHours(hours)) h"
    }

    public static func compact(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h) h" }
        return "\(h) h \(m) min"
    }
}

enum StepFactory {
    static func feed(start: Date, minutes: Int, ratio: FeedRatio, peakHours: Double) -> BakeStep {
        BakeStep(
            id: "feed",
            kind: .feedStarter,
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            attended: true,
            title: "Feed starter",
            detail: "Feed \(ratio.rawValue). It should peak in about \(DurationText.halfHours(peakHours)) h — ratios are a rule of thumb, so glance at it before mixing."
        )
    }

    static func starterRise(start: Date, end: Date) -> BakeStep {
        BakeStep(
            id: "starter-rise",
            kind: .starterRise,
            start: start,
            end: end,
            attended: false,
            title: "Starter rises",
            detail: "Nothing to do. Your starter is getting ready."
        )
    }

    static func mix(start: Date, minutes: Int, inoculation: Double, formula: Formula) -> BakeStep {
        let a = formula.amounts(starterPercent: inoculation)
        return BakeStep(
            id: "mix",
            kind: .mix,
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            attended: true,
            title: "Mix dough",
            detail: "\(Int(a.flour.rounded())) g flour, \(Int(a.water.rounded())) g water, \(Int(a.starter.rounded())) g starter, \(Int(a.salt.rounded())) g salt. Mark the level on your container."
        )
    }

    static func fold(number: Int, count: Int, start: Date, minutes: Int) -> BakeStep {
        BakeStep(
            id: "fold-\(number)",
            kind: .fold,
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            attended: true,
            title: "Fold \(number) of \(count)",
            detail: "One set of stretch-and-folds, about \(minutes) min."
        )
    }

    static func bulk(start: Date, end: Date, lowHours: Double, highHours: Double, targetRise: Double) -> BakeStep {
        BakeStep(
            id: "bulk",
            kind: .bulk,
            start: start,
            end: end,
            attended: false,
            title: "Bulk ferment",
            detail: "Likely \(DurationText.hoursRange(lowHours, highHours)) from mixing. Aim for about \(Int(targetRise.rounded()))% rise, a domed top and bubbles at the edges."
        )
    }

    static func shape(start: Date, minutes: Int, likelyStart: Date, likelyEnd: Date, targetRise: Double) -> BakeStep {
        BakeStep(
            id: "shape",
            kind: .shape,
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            attended: true,
            title: "Shape",
            detail: "Shape once the dough is up about \(Int(targetRise.rounded()))%. Check in first if it looks early or slow.",
            likelyStart: likelyStart,
            likelyEnd: likelyEnd
        )
    }

    /// Shaping after bulk finished in the fridge. There is no likely-ready window: the room-temperature model
    /// doesn't describe chilled dough, so the baker goes by look and feel.
    static func shapeCold(start: Date, minutes: Int) -> BakeStep {
        BakeStep(
            id: "shape",
            kind: .shape,
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            attended: true,
            title: "Shape",
            detail: "Shape it straight from the fridge. Look for a domed top and some bubbles; if it has barely risen, give it time at room temperature first."
        )
    }

    static func coldRetard(start: Date, end: Date, process: ProcessSettings) -> BakeStep {
        BakeStep(
            id: "cold-proof",
            kind: .coldRetard,
            start: start,
            end: end,
            attended: false,
            title: "Cold proof in fridge",
            detail: "\(DurationText.halfHours(end.timeIntervalSince(start) / 3600)) h planned. \(Int(process.retardPreferredLowHours))–\(Int(process.retardPreferredHighHours)) h is typical; \(Int(process.retardMinHours))–\(Int(process.retardMaxHours)) h is workable."
        )
    }

    static func roomProof(start: Date, end: Date, lowHours: Double, highHours: Double) -> BakeStep {
        BakeStep(
            id: "room-proof",
            kind: .roomProof,
            start: start,
            end: end,
            attended: false,
            title: "Proof at room temperature",
            detail: "Likely \(DurationText.hoursRange(lowHours, highHours)). Bake when a floured poke springs back slowly."
        )
    }

    static func fridgeDough(start: Date, minutes: Int) -> BakeStep {
        BakeStep(
            id: "fridge",
            kind: .fridgeDough,
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            attended: true,
            title: "Put the dough in the fridge",
            detail: "Cover it and move it to the fridge. Chilling slows bulk right down; you’ll shape it cold."
        )
    }

    static func coldBulk(start: Date, end: Date) -> BakeStep {
        BakeStep(
            id: "cold-bulk",
            kind: .coldBulk,
            start: start,
            end: end,
            attended: false,
            title: "Finish bulk in fridge",
            detail: "The dough keeps rising slowly while it chills. Shape it straight from the fridge."
        )
    }

    static func preheat(start: Date, minutes: Int) -> BakeStep {
        BakeStep(
            id: "preheat",
            kind: .preheat,
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            attended: true,
            title: "Preheat oven",
            detail: "Oven and pot, about \(minutes) min."
        )
    }

    static func bake(start: Date, minutes: Int) -> BakeStep {
        BakeStep(
            id: "bake",
            kind: .bake,
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            attended: true,
            title: "Bake",
            detail: "Score and bake, lid on for the first half, about \(minutes) min in total."
        )
    }
}
