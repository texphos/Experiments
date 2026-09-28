import Foundation
@testable import HearthdayCore

enum TestClock {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 2026-10-05 is a Monday.
    static func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }
}

extension BakePlan {
    func attendedConflicts(_ availability: Availability, calendar: Calendar = TestClock.calendar) -> [String] {
        let timeline = availability.timeline(
            from: firstStepAt.addingTimeInterval(-3600),
            to: readyAt.addingTimeInterval(3600),
            calendar: calendar
        )
        return attendedSteps.compactMap { step in
            timeline.conflict(start: step.start, duration: step.duration).map { "\(step.id) in \($0.label)" }
        }
    }
}

/// A hand-built fridge plan, so live-session tests don't depend on which plan the search prefers.
func makeFridgePlan(mixAt mix: Date, readyAt: Date, tempC: Double = 21, inoculation: Double = 20) -> BakePlan {
    let process = ProcessSettings()
    let model = FermentationModel()
    let bulk = model.bulkHours(tempC: tempC, inoculationPercent: inoculation)
    var steps: [BakeStep] = [StepFactory.mix(start: mix, minutes: process.mixMinutes, inoculation: inoculation, formula: .countryLoaf)]
    for i in 1...process.foldCount {
        steps.append(StepFactory.fold(
            number: i,
            count: process.foldCount,
            start: mix.addingTimeInterval(TimeInterval(i * process.foldIntervalMinutes * 60)),
            minutes: process.foldMinutes
        ))
    }
    let lastFoldEnd = mix.addingTimeInterval(TimeInterval(process.foldCount * process.foldIntervalMinutes * 60 + process.foldMinutes * 60))
    let shapeAt = mix.addingTimeInterval(bulk * 3600)
    steps.append(StepFactory.bulk(start: lastFoldEnd, end: shapeAt, lowHours: bulk * 0.8, highHours: bulk * 1.2, targetRise: 75))
    steps.append(StepFactory.shape(
        start: shapeAt,
        minutes: process.shapeMinutes,
        likelyStart: mix.addingTimeInterval(bulk * 3600 * 0.8),
        likelyEnd: mix.addingTimeInterval(bulk * 3600 * 1.2),
        targetRise: 75
    ))
    let bakeStart = readyAt.addingTimeInterval(-TimeInterval(process.bakeMinutes * 60))
    steps.append(StepFactory.coldRetard(start: shapeAt.addingTimeInterval(TimeInterval(process.shapeMinutes * 60)), end: bakeStart, process: process))
    steps.append(StepFactory.preheat(start: bakeStart.addingTimeInterval(-TimeInterval(process.preheatMinutes * 60)), minutes: process.preheatMinutes))
    steps.append(StepFactory.bake(start: bakeStart, minutes: process.bakeMinutes))
    return BakePlan(
        steps: sortSteps(steps),
        proofMode: .fridge,
        inoculationPercent: inoculation,
        feedRatio: nil,
        kitchenTempC: tempC,
        formula: .countryLoaf,
        expectedBulkHours: bulk,
        modelBulkHours: bulk,
        uncertainty: 0.2,
        score: 0
    )
}
