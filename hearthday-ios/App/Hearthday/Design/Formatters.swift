import Foundation
import HearthdayCore

enum Fmt {
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Tonight 8:15 PM", "Tomorrow 7:00 AM", "Sat 10:00 AM".
    static func dayTime(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        "\(day(date, now: now, calendar: calendar)) \(time(date))"
    }

    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return calendar.component(.hour, from: date) >= 17 ? "Tonight" : "Today"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    static func countdown(to date: Date, from now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        return DurationText.compact(minutes: minutes)
    }

    static func temperature(_ celsius: Double, fahrenheit: Bool) -> String {
        fahrenheit
            ? "\(Int((celsius * 9 / 5 + 32).rounded())) °F"
            : String(format: "%.1f °C", celsius).replacingOccurrences(of: ".0 °C", with: " °C")
    }

    static func weekdays(_ days: Set<Int>) -> String {
        if days == BusyBlock.everyDay { return "Every day" }
        if days == BusyBlock.weekdaysOnly { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return days.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
    }

    static func clock(minuteOfDay: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: .now) ?? .now
        return time(date)
    }
}

extension Date {
    var minuteOfDay: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: self)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
