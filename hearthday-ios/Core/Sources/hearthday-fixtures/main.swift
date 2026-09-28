// Emits golden scenarios as JSON so the browser companion prototype can prove it runs the same
// planning logic as the Swift core: `swift run hearthday-fixtures > ../prototype/fixtures.json`.
import Foundation
import HearthdayCore

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "UTC")!

let iso = ISO8601DateFormatter()
iso.timeZone = TimeZone(identifier: "UTC")!

func d(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

func stepsJSON(_ steps: [BakeStep]) -> [[String: Any]] {
    steps.map { ["id": $0.id, "start": iso.string(from: $0.start), "end": iso.string(from: $0.end), "attended": $0.attended] }
}

func planJSON(_ p: BakePlan) -> [String: Any] {
    [
        "proofMode": p.proofMode.rawValue,
        "inoculation": p.inoculationPercent,
        "feedRatio": p.feedRatio?.rawValue ?? NSNull(),
        "steps": stepsJSON(p.steps),
    ]
}

struct PlanScenario {
    var name: String
    var now: Date
    var readyBy: Date
    var tempC: Double
    var starterNeedsFeed = true
    var allowInoculation = true
    var allowFeed = true
    var proofModes: [ProofMode] = [.fridge, .room]
    var speedFactor = 1.0
    var uncertainty = 0.2
    var availability = Availability.typicalWeekdayWorker

    var request: PlanRequest {
        var model = FermentationModel()
        model.speedFactor = speedFactor
        model.uncertainty = uncertainty
        return PlanRequest(
            now: now,
            readyBy: readyBy,
            kitchenTempC: tempC,
            starterNeedsFeed: starterNeedsFeed,
            allowFeedRatioAdjustment: allowFeed,
            allowInoculationAdjustment: allowInoculation,
            proofModes: proofModes,
            availability: availability,
            model: model
        )
    }

    var inputJSON: [String: Any] {
        [
            "now": iso.string(from: now),
            "readyBy": iso.string(from: readyBy),
            "tempC": tempC,
            "starterNeedsFeed": starterNeedsFeed,
            "allowInoculationAdjustment": allowInoculation,
            "allowFeedRatioAdjustment": allowFeed,
            "proofModes": proofModes.map(\.rawValue),
            "speedFactor": speedFactor,
            "uncertainty": uncertainty,
            "blocks": availability.blocks.map {
                ["label": $0.label, "kind": $0.kind.rawValue, "weekdays": $0.weekdays.sorted(), "startMinute": $0.startMinute, "endMinute": $0.endMinute] as [String: Any]
            },
        ]
    }
}

let nightShift = Availability(blocks: [
    BusyBlock(label: "Sleep", kind: .sleep, weekdays: BusyBlock.everyDay, startMinute: 9 * 60, endMinute: 16 * 60),
    BusyBlock(label: "Shift", kind: .work, weekdays: [1, 2, 3, 4, 5], startMinute: 21 * 60, endMinute: 5 * 60 + 30),
])

let planScenarios: [PlanScenario] = [
    PlanScenario(name: "Friday morning → Saturday 10:00", now: d(9, 7, 15), readyBy: d(10, 10), tempC: 21),
    PlanScenario(name: "Weekend same-day room proof", now: d(10, 7), readyBy: d(10, 20), tempC: 23, starterNeedsFeed: false, allowInoculation: false, proofModes: [.room]),
    PlanScenario(name: "Active starter, Sunday lunch", now: d(10, 8), readyBy: d(11, 13), tempC: 20, starterNeedsFeed: false),
    PlanScenario(name: "Cool kitchen, calibrated fast dough", now: d(6, 18), readyBy: d(8, 19, 30), tempC: 18, speedFactor: 1.3, uncertainty: 0.12),
    PlanScenario(name: "Warm kitchen weekday evening loaf", now: d(5, 6, 30), readyBy: d(6, 19), tempC: 26),
    PlanScenario(name: "Night-shift worker", now: d(5, 17), readyBy: d(7, 18), tempC: 22, availability: nightShift),
    PlanScenario(name: "Too soon", now: d(5, 18), readyBy: d(5, 21), tempC: 21),
    PlanScenario(name: "Bake during work", now: d(5, 7), readyBy: d(7, 12), tempC: 21),
    PlanScenario(name: "Invalid: implausible temperature and past time", now: d(5, 7), readyBy: d(5, 6), tempC: 45),
]

var planOut: [[String: Any]] = []
for s in planScenarios {
    var expected: [String: Any]
    switch Planner.plan(s.request, calendar: calendar) {
    case let .feasible(primary, alternatives):
        expected = ["feasible": true, "primary": planJSON(primary), "alternatives": alternatives.map(planJSON)]
    case let .infeasible(info):
        expected = [
            "feasible": false,
            "reason": info.reason.rawValue,
            "blockingLabel": info.blockingLabel ?? NSNull(),
            "earliestFeasibleReadyAt": info.earliestFeasibleReadyAt.map { iso.string(from: $0) } ?? NSNull(),
        ]
    case let .invalid(problems):
        expected = ["feasible": false, "invalid": problems.map(\.code)]
    }
    planOut.append(["name": s.name, "input": s.inputJSON, "expected": expected])
}

struct CheckInScenario {
    var name: String
    var plan: PlanScenario
    var mixLateMinutes: Int
    var hoursAfterMix: Double
    var rise: Double
    var tempC: Double
}

let checkInScenarios: [CheckInScenario] = [
    CheckInScenario(name: "On track, warm evening", plan: planScenarios[4], mixLateMinutes: 0, hoursAfterMix: 2.5, rise: 21, tempC: 26),
    CheckInScenario(name: "Fast dough would peak overnight", plan: planScenarios[0], mixLateMinutes: 0, hoursAfterMix: 2, rise: 30, tempC: 22),
    CheckInScenario(name: "Slow overnight dough, late mix", plan: planScenarios[0], mixLateMinutes: 10, hoursAfterMix: 4, rise: 18, tempC: 20),
    CheckInScenario(name: "Warm evening dough racing ahead", plan: planScenarios[4], mixLateMinutes: 20, hoursAfterMix: 2, rise: 30, tempC: 27),
    CheckInScenario(name: "Ready now", plan: planScenarios[2], mixLateMinutes: 0, hoursAfterMix: 6, rise: 80, tempC: 21),
    CheckInScenario(name: "Very early reading", plan: planScenarios[2], mixLateMinutes: 0, hoursAfterMix: 0.25, rise: 15, tempC: 21),
]

var checkInOut: [[String: Any]] = []
for c in checkInScenarios {
    guard let plan = Planner.plan(c.plan.request, calendar: calendar).primary else { continue }
    var session = BakeSession(plan: plan, startedAt: plan.firstStepAt)
    for step in plan.steps where step.attended && step.end <= plan.mixAt.addingTimeInterval(1) {
        session.complete(step.id, at: step.end)
    }
    let mix = plan.step("mix")!
    session.complete("mix", at: mix.end.addingTimeInterval(TimeInterval(c.mixLateMinutes * 60)))
    let now = session.bulkClockStart.addingTimeInterval(c.hoursAfterMix * 3600)
    for step in session.plan.steps where step.kind == .fold && step.end <= now {
        session.complete(step.id, at: step.end)
    }
    let result = LiveReplanner.checkIn(
        session: session,
        now: now,
        risePercent: c.rise,
        tempC: c.tempC,
        availability: c.plan.availability,
        calendar: calendar,
        model: c.plan.request.model
    )
    var replanned = session
    if let first = result.options.first { replanned.apply(first) }
    let prefix = session.id.uuidString + "-"
    let remindersAfterFirstOption = Reminders.specs(for: replanned, now: now, availability: c.plan.availability, calendar: calendar).map {
        ["step": String($0.id.dropFirst(prefix.count)), "fireAt": iso.string(from: $0.fireAt)]
    }
    checkInOut.append([
        "name": c.name,
        "planScenario": c.plan.name,
        "mixLateMinutes": c.mixLateMinutes,
        "hoursAfterMix": c.hoursAfterMix,
        "rise": c.rise,
        "tempC": c.tempC,
        "expected": [
            "now": iso.string(from: now),
            "estimatedReadyAt": iso.string(from: result.estimatedReadyAt),
            "targetRisePercent": result.targetRisePercent,
            "summary": result.summary,
            "remindersAfterFirstOption": remindersAfterFirstOption,
            "options": result.options.map {
                [
                    "kind": $0.kind.rawValue,
                    "recommended": $0.recommended,
                    "bulkEndsAt": iso.string(from: $0.bulkEndsAt),
                    "conflictLabel": $0.conflictLabel ?? NSNull(),
                    "steps": stepsJSON($0.steps),
                ] as [String: Any]
            },
        ] as [String: Any],
    ])
}

// Wall-clock busy blocks across US daylight-saving changes (2026-03-08 spring forward, 2026-11-01 fall back).
var newYork = Calendar(identifier: .gregorian)
newYork.timeZone = TimeZone(identifier: "America/New_York")!
func ny(_ month: Int, _ day: Int, _ hour: Int) -> Date {
    newYork.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
}
let dstBlocks = Availability(blocks: [
    BusyBlock(label: "Sleep", kind: .sleep, weekdays: BusyBlock.everyDay, startMinute: 23 * 60, endMinute: 7 * 60),
    BusyBlock(label: "Early", kind: .other, weekdays: [1], startMinute: 2 * 60 + 30, endMinute: 4 * 60),
])
let dstWindows: [(String, Date, Date)] = [
    ("Spring forward", ny(3, 7, 12), ny(3, 8, 12)),
    ("Fall back", ny(10, 31, 12), ny(11, 1, 12)),
]
let dstOut: [[String: Any]] = dstWindows.map { name, from, to in
    [
        "name": name,
        "from": iso.string(from: from),
        "to": iso.string(from: to),
        "intervals": dstBlocks.intervals(from: from, to: to, calendar: newYork).map {
            ["label": $0.label, "start": iso.string(from: $0.start), "end": iso.string(from: $0.end)]
        },
    ]
}

let root: [String: Any] = [
    "note": "Generated by `swift run hearthday-fixtures`. Do not edit by hand.",
    "timeZone": "UTC",
    "planScenarios": planOut,
    "checkInScenarios": checkInOut,
    "dst": [
        "timeZone": "America/New_York",
        "blocks": dstBlocks.blocks.map {
            ["label": $0.label, "kind": $0.kind.rawValue, "weekdays": $0.weekdays.sorted(), "startMinute": $0.startMinute, "endMinute": $0.endMinute] as [String: Any]
        },
        "windows": dstOut,
    ] as [String: Any],
]
let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write("\n".data(using: .utf8)!)
