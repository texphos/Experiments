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
            for block in blocks where block.weekdays.contains(weekday) {
                guard let blockStart = calendar.date(
                    bySettingHour: block.startMinute / 60,
                    minute: block.startMinute % 60,
                    second: 0,
                    of: day
                ) else { continue }
                let blockEnd = blockStart.addingTimeInterval(TimeInterval(block.durationMinutes * 60))
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
