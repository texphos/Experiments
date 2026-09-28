import Foundation

/// A recurring stretch of time when the baker cannot do hands-on work (asleep, at work, school run…).
public struct BusyBlock: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case sleep, work, other
    }

    public var id: UUID
    public var label: String
    public var kind: Kind
    /// Calendar weekdays (1 = Sunday … 7 = Saturday) on which the block *starts*.
    public var weekdays: Set<Int>
    /// Minutes after local midnight.
    public var startMinute: Int
    /// Minutes after local midnight. A value at or before `startMinute` means the block ends the next day.
    public var endMinute: Int

    public init(
        id: UUID = UUID(),
        label: String,
        kind: Kind,
        weekdays: Set<Int>,
        startMinute: Int,
        endMinute: Int
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.weekdays = weekdays
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    public var durationMinutes: Int {
        endMinute > startMinute ? endMinute - startMinute : 1440 - startMinute + endMinute
    }

    public static let everyDay: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    public static let weekdaysOnly: Set<Int> = [2, 3, 4, 5, 6]
}

/// One concrete occurrence of a `BusyBlock`.
public struct BusyInterval: Hashable, Sendable {
    public var label: String
    public var kind: BusyBlock.Kind
    public var start: Date
    public var end: Date

    func overlaps(_ start: Date, _ end: Date) -> Bool {
        self.start < end && start < self.end
    }
}

public struct Availability: Codable, Hashable, Sendable {
    public var blocks: [BusyBlock]

    public init(blocks: [BusyBlock]) {
        self.blocks = blocks
    }

    /// Sleep 23:00–07:00 daily, work 08:30–17:30 on weekdays.
    public static let typicalWeekdayWorker = Availability(blocks: [
        BusyBlock(label: "Sleep", kind: .sleep, weekdays: BusyBlock.everyDay, startMinute: 23 * 60, endMinute: 7 * 60),
        BusyBlock(label: "Work", kind: .work, weekdays: BusyBlock.weekdaysOnly, startMinute: 8 * 60 + 30, endMinute: 17 * 60 + 30),
    ])

    /// All concrete busy intervals that touch `[start, end]`, sorted by start.
    public func intervals(from start: Date, to end: Date, calendar: Calendar) -> [BusyInterval] {
        guard end >= start else { return [] }
        var result: [BusyInterval] = []
        let firstDay = calendar.startOfDay(for: start).addingTimeInterval(-86_400 * 1.5)
        var day = calendar.startOfDay(for: firstDay)
        let lastDay = calendar.startOfDay(for: end)
        while day <= lastDay {
            let weekday = calendar.component(.weekday, from: day)
            for block in blocks where block.weekdays.contains(weekday) && block.isValid {
                guard let blockStart = Self.wallClock(block.startMinute, on: day, calendar: calendar),
                      let endDay = block.endMinute > block.startMinute
                        ? day
                        : calendar.date(byAdding: .day, value: 1, to: day),
                      let blockEnd = Self.wallClock(block.endMinute, on: endDay, calendar: calendar),
                      blockEnd > blockStart
                else { continue }
                let interval = BusyInterval(label: block.label, kind: block.kind, start: blockStart, end: blockEnd)
                if interval.overlaps(start, end) {
                    result.append(interval)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result.sorted { ($0.start, $0.label) < ($1.start, $1.label) }
    }

    /// A local wall-clock time on `day`. Busy blocks are wall-clock commitments, so across a DST change a
    /// 23:00–07:00 night is 7 or 9 real hours, never "start + 8 h". A time skipped by spring-forward
    /// moves forward by the gap (02:30 → 03:30), which is also what JavaScript's `Date` does.
    /// A time repeated by fall-back resolves to its first occurrence. Implemented explicitly because
    /// Foundation's matching policies behave differently on Apple platforms and Linux.
    static func wallClock(_ minute: Int, on day: Date, calendar: Calendar) -> Date? {
        let ymd = calendar.dateComponents([.year, .month, .day], from: day)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let naive = utc.date(from: DateComponents(
            year: ymd.year, month: ymd.month, day: ymd.day, hour: minute / 60, minute: minute % 60
        )) else { return nil }
        let zone = calendar.timeZone
        let offsetBefore = TimeInterval(zone.secondsFromGMT(for: naive.addingTimeInterval(-86_400)))
        let offsetAfter = TimeInterval(zone.secondsFromGMT(for: naive.addingTimeInterval(86_400)))
        let candidates = [offsetBefore, offsetAfter]
            .map { naive.addingTimeInterval(-$0) }
            .filter { zone.secondsFromGMT(for: $0) == Int(naive.timeIntervalSince($0)) }
        return candidates.min() ?? naive.addingTimeInterval(-offsetBefore)
    }

    public func timeline(from start: Date, to end: Date, calendar: Calendar) -> BusyTimeline {
        BusyTimeline(intervals: intervals(from: start, to: end, calendar: calendar))
    }
}

/// Precomputed busy intervals for a planning horizon, so the planner can test thousands of candidates cheaply.
public struct BusyTimeline: Sendable {
    public let intervals: [BusyInterval]

    public init(intervals: [BusyInterval]) {
        self.intervals = intervals
    }

    public func conflict(start: Date, duration: TimeInterval) -> BusyInterval? {
        let end = start.addingTimeInterval(duration)
        return intervals.first { $0.overlaps(start, end) }
    }

    public func isFree(start: Date, duration: TimeInterval) -> Bool {
        conflict(start: start, duration: duration) == nil
    }

    /// Earliest start at or after `date` where `duration` fits without touching a busy interval.
    public func earliestFreeStart(atOrAfter date: Date, duration: TimeInterval, limit: Date) -> Date? {
        var t = date
        while t <= limit {
            if let c = conflict(start: t, duration: duration) {
                t = c.end
            } else {
                return t
            }
        }
        return nil
    }
}
