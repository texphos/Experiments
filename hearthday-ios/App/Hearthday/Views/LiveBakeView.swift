import SwiftUI
import UIKit
import HearthdayCore

/// The bake in progress: what's next, what the dough is doing, and a way to re-plan when it drifts.
struct LiveBakeView: View {
    @Environment(AppModel.self) private var model
    @State private var showingCheckIn = false
    @State private var showingFinish = false
    @State private var confirmingEnd = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let session = model.state.activeSession {
                content(session: session, now: context.date)
            }
        }
        .background(Palette.flour.ignoresSafeArea())
        .navigationTitle(model.state.activeSession?.plan.formula.name ?? "Bake")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Finish now and log it") { showingFinish = true }
                    Button("Abandon this bake", role: .destructive) { confirmingEnd = true }
                } label: {
                    Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("live.more")
            }
        }
        .confirmationDialog("Abandon this bake?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("Abandon bake", role: .destructive) { model.abandon() }
        } message: {
            Text("Reminders will be cancelled and nothing is added to your journal.")
        }
        .sheet(isPresented: $showingCheckIn) { CheckInView() }
        .sheet(isPresented: $showingFinish) { FinishBakeView() }
        .onAppear { model.refreshClock() }
    }

    @ViewBuilder
    private func content(session: BakeSession, now: Date) -> some View {
        let conflicts = session.upcomingConflicts(now: now, availability: model.state.settings.availability, calendar: model.calendar)
        let status = session.status(now: now)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.reminderPermission == .denied && status != .baked {
                    RemindersOffBanner()
                }

                if !conflicts.isEmpty && status != .stale {
                    ConflictBanner(conflicts: conflicts, canCheckIn: session.canCheckIn) { showingCheckIn = true }
                }

                switch status {
                case .baked:
                    StateMessage(systemImage: "birthday.cake", title: "Bread’s out", message: "Let it cool at least an hour before slicing. Then tell Hearthday how it went.")
                    Button("Log this bake") { showingFinish = true }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("live.logBake")
                case .stale:
                    StaleBakeCard(readyAt: session.plan.readyAt, onLog: { showingFinish = true }, onAbandon: { confirmingEnd = true })
                case .overdue(let step, let minutesLate):
                    NextStepCard(step: step, now: now, minutesLate: minutesLate, inBulk: session.isInBulk) { model.complete(step) }
                case .due(let step), .upcoming(let step):
                    NextStepCard(step: step, now: now, minutesLate: nil, inBulk: session.isInBulk) { model.complete(step) }
                }

                if session.completed["shape"] != nil && session.shapeReadiness == nil {
                    ShapeReadinessPrompt { model.setShapeReadiness($0) }
                }

                if let passive = session.passiveStep(at: now) {
                    PassiveCard(step: passive, now: now)
                }

                if let note = session.adjustmentNote, status != .baked {
                    Label(note, systemImage: "clock.arrow.circlepath")
                        .font(.subheadline).foregroundStyle(Palette.rye)
                        .card()
                        .accessibilityIdentifier("live.adjustment")
                }

                if session.canCheckIn {
                    Button {
                        showingCheckIn = true
                    } label: {
                        Label("Check the dough", systemImage: "gauge.with.dots.needle.50percent")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityHint("Enter how much it has risen to re-plan the rest of the bake")
                    .accessibilityIdentifier("live.checkin")
                }

                DayRibbonView(plan: session.plan, availability: model.state.settings.availability, now: now)
                    .card()

                StepList(plan: session.plan, session: session)

                if session.replanCount > 0 {
                    Text("Re-planned \(session.replanCount)× · originally \(Fmt.dayTime(session.originalReadyAt).lowercasedFirst)")
                        .font(.footnote).foregroundStyle(Palette.ash)
                }
            }
            .padding()
        }
    }
}

private struct NextStepCard: View {
    var step: BakeStep
    var now: Date
    var minutesLate: Int?
    var inBulk: Bool
    var onDone: () -> Void

    private var isDue: Bool { step.start <= now.addingTimeInterval(5 * 60) }

    private var heading: String {
        if let minutesLate {
            return "Was due \(Fmt.dayTime(step.start).lowercasedFirst) · \(DurationText.compact(minutes: minutesLate)) ago"
        }
        return isDue ? "Now" : "Next, in \(Fmt.countdown(to: step.start, from: now))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(minutesLate != nil ? Palette.warning : isDue ? Palette.ember : Palette.ash)
            if minutesLate != nil && step.kind == .shape && inBulk {
                Text("The dough may have gone past its best while you were away. Check it before shaping; if it’s very slack, shape gently and fridge it.")
                    .font(.footnote).foregroundStyle(Palette.rye)
            }
            Text(step.title).font(Typo.display(.title2)).foregroundStyle(Palette.rye)
            Text(step.detail).foregroundStyle(Palette.ash)
            if let lo = step.likelyStart, let hi = step.likelyEnd {
                Label("Likely ready \(Fmt.time(lo))–\(Fmt.time(hi)). Go by the dough, not the clock.", systemImage: "eye")
                    .font(.footnote).foregroundStyle(Palette.ash)
            }
            Text("\(Fmt.dayTime(step.start)) · \(DurationText.compact(minutes: Int(step.duration / 60)))")
                .font(Typo.clock(.headline)).foregroundStyle(Palette.crust)
            Button(isDue ? "Done" : "Done early", action: onDone)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityLabel("Mark \(step.title) done")
                .accessibilityIdentifier("step.done")
        }
        .card(padding: 20)
    }
}

private struct PassiveCard: View {
    var step: BakeStep
    var now: Date
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: step.kind == .coldRetard || step.kind == .coldBulk ? "snowflake" : "hourglass")
                .font(.title2).foregroundStyle(Palette.night).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title).font(.headline).foregroundStyle(Palette.rye)
                Text("Until about \(Fmt.dayTime(step.end)) · \(Fmt.countdown(to: step.end, from: now)) left")
                    .font(.subheadline).foregroundStyle(Palette.ash)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// Reopened long after the loaf should have come out: ask, don't guess.
private struct StaleBakeCard: View {
    var readyAt: Date
    var onLog: () -> Void
    var onAbandon: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            StateMessage(
                systemImage: "clock.badge.questionmark",
                title: "Did this bake finish?",
                message: "It was planned to come out \(Fmt.dayTime(readyAt).lowercasedFirst). Log how it went, or abandon it to plan a new one."
            )
            Button("Log this bake", action: onLog)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("live.logBake")
            Button("Abandon it", role: .destructive, action: onAbandon)
                .buttonStyle(SecondaryButtonStyle())
        }
        .card(padding: 20)
    }
}

/// Shown when iOS notification permission is off, so a bake never silently goes without reminders.
private struct RemindersOffBanner: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Reminders are off", systemImage: "bell.slash.fill")
                .font(.headline).foregroundStyle(Palette.warning)
            Text("Hearthday can’t alert you for the next step. Keep this screen handy, or turn notifications on.")
                .font(.subheadline).foregroundStyle(Palette.rye)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .card()
        .accessibilityIdentifier("live.remindersOff")
    }
}

private struct ConflictBanner: View {
    var conflicts: [StepConflict]
    var canCheckIn: Bool
    var onCheckIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Heads up", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(Palette.warning)
            ForEach(conflicts, id: \.step.id) { c in
                Text("\(c.step.title) at \(Fmt.dayTime(c.step.start).lowercasedFirst) now overlaps “\(c.busyLabel)”.")
                    .foregroundStyle(Palette.rye)
            }
            if canCheckIn {
                Button("Check the dough and re-plan", action: onCheckIn)
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .card()
    }
}

private struct ShapeReadinessPrompt: View {
    var onAnswer: (ShapeReadiness) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When you shaped, the dough felt…").font(.headline)
            HStack(spacing: 8) {
                answer("Under", "tortoise", .under)
                answer("Just right", "checkmark", .justRight)
                    .accessibilityIdentifier("readiness.justRight")
                answer("Over", "hare", .over)
            }
            Text("Only “just right” bakes without a fridge pause teach Hearthday your kitchen’s speed; the others are noted in your journal.")
                .font(.footnote).foregroundStyle(Palette.ash)
        }
        .card()
    }

    private func answer(_ title: String, _ icon: String, _ value: ShapeReadiness) -> some View {
        Button { onAnswer(value) } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).accessibilityHidden(true)
                Text(title).font(.footnote.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(Palette.crust)
            .background(Palette.crust.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

struct FinishBakeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var rating: Int?
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                if let session = model.state.activeSession, session.completed["shape"] != nil, session.shapeReadiness == nil {
                    Section("At shaping the dough was") {
                        Picker("Readiness", selection: Binding(
                            get: { model.state.activeSession?.shapeReadiness },
                            set: { if let v = $0 { model.setShapeReadiness(v) } }
                        )) {
                            Text("Not answered").tag(ShapeReadiness?.none)
                            Text("Under").tag(ShapeReadiness?.some(.under))
                            Text("Just right").tag(ShapeReadiness?.some(.justRight))
                            Text("Over").tag(ShapeReadiness?.some(.over))
                        }
                    }
                }
                Section("How was it?") {
                    HStack {
                        ForEach(1...5, id: \.self) { n in
                            Button { rating = rating == n ? nil : n } label: {
                                Image(systemName: (rating ?? 0) >= n ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundStyle(Palette.ember)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(n) star\(n == 1 ? "" : "s")")
                            .accessibilityAddTraits((rating ?? 0) == n ? .isSelected : [])
                        }
                    }
                }
                Section("Notes") {
                    TextField("Crumb, crust, what you’d change…", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Log this bake")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.finish(rating: rating, notes: notes)
                        dismiss()
                    }
                    .accessibilityIdentifier("finish.save")
                }
            }
        }
    }
}
