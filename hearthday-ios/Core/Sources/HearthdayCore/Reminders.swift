import Foundation

public struct ReminderSpec: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var fireAt: Date
    public var title: String
    public var body: String
}

public enum Reminders {
    /// Local notifications for the rest of a bake: one per pending hands-on step, plus an early
    /// "check your dough" nudge when the likely-ready window opens well before the planned shape time.
    ///
    /// The nudge is optional, so it is dropped when it would land in a busy block (it must never wake the
    /// baker) or while the dough is chilling in the fridge, where an early check means nothing.
    public static func specs(
        for session: BakeSession,
        now: Date,
        availability: Availability? = nil,
        calendar: Calendar = .current
    ) -> [ReminderSpec] {
        var specs: [ReminderSpec] = []
        let chilling = session.plan.steps.contains { $0.kind == .coldBulk }
        for step in session.plan.steps where step.attended && session.completed[step.id] == nil && step.start > now {
            specs.append(ReminderSpec(id: "\(session.id.uuidString)-\(step.id)", fireAt: step.start, title: step.title, body: step.detail))
            if step.kind == .shape, !chilling, let early = step.likelyStart, early > now, step.start.timeIntervalSince(early) >= 20 * 60 {
                if let availability {
                    let timeline = availability.timeline(from: early.addingTimeInterval(-3600), to: early.addingTimeInterval(3600), calendar: calendar)
                    if !timeline.isFree(start: early, duration: 60) { continue }
                }
                specs.append(ReminderSpec(
                    id: "\(session.id.uuidString)-check",
                    fireAt: early,
                    title: "Check your dough",
                    body: "It could be ready early. Compare the rise with your mark and do a quick check-in."
                ))
            }
        }
        return specs.sorted { $0.fireAt < $1.fireAt }
    }
}
