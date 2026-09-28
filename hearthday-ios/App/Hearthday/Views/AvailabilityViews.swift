import SwiftUI
import HearthdayCore

/// Seven rows, today first; hatched bars are busy time.
struct WeekRibbon: View {
    var availability: Availability
    var now: Date = .now
    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<7, id: \.self) { offset in
                let dayStart = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) ?? now
                let dayEnd = dayStart.addingTimeInterval(86_400)
                HStack(spacing: 8) {
                    Text(offset == 0 ? "Today" : dayStart.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.ash)
                        .frame(width: 44, alignment: .leading)
                    SpanBar(
                        start: dayStart,
                        end: dayEnd,
                        intervals: availability.intervals(from: dayStart, to: dayEnd, calendar: calendar),
                        steps: []
                    )
                    .frame(height: 14)
                }
            }
            HourAxis()
                .padding(.leading, 52)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your busy week")
        .accessibilityValue(summary)
    }

    private var summary: String {
        availability.blocks.map { "\($0.label), \(Fmt.weekdays($0.weekdays)), \(Fmt.clock(minuteOfDay: $0.startMinute)) to \(Fmt.clock(minuteOfDay: $0.endMinute))" }
            .joined(separator: ". ")
    }
}

private struct HourAxis: View {
    var body: some View {
        HStack {
            Text("12a"); Spacer(); Text("6a"); Spacer(); Text("12p"); Spacer(); Text("6p"); Spacer(); Text("12a")
        }
        .font(.caption2)
        .foregroundStyle(Palette.ash)
    }
}

/// A horizontal time span with hatched busy intervals and solid markers for hands-on steps.
struct SpanBar: View {
    var start: Date
    var end: Date
    var intervals: [BusyInterval]
    var steps: [BakeStep]
    var nowMarker: Date?

    var body: some View {
        GeometryReader { geo in
            let total = max(end.timeIntervalSince(start), 1)
            let x: (Date) -> CGFloat = { d in CGFloat(min(max(d.timeIntervalSince(start) / total, 0), 1)) * geo.size.width }
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.hairline.opacity(0.5))
                ForEach(Array(intervals.enumerated()), id: \.offset) { _, interval in
                    Hatching(color: Palette.busy(interval.kind))
                        .frame(width: max(x(interval.end) - x(interval.start), 0))
                        .offset(x: x(interval.start))
                }
                ForEach(steps) { step in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(step.kind == .bake || step.kind == .preheat ? Palette.ember : Palette.crust)
                        .frame(width: max(x(step.end) - x(step.start), 4))
                        .offset(x: x(step.start))
                }
                if let nowMarker, nowMarker > start, nowMarker < end {
                    Rectangle().fill(Palette.rye).frame(width: 2).offset(x: x(nowMarker) - 1)
                }
            }
            .clipShape(Capsule())
        }
    }
}

/// The plan at a glance: when your hands are needed against when you're busy.
struct DayRibbonView: View {
    var plan: BakePlan
    var availability: Availability
    var now: Date?
    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SpanBar(
                start: plan.firstStepAt,
                end: plan.readyAt,
                intervals: availability.intervals(from: plan.firstStepAt, to: plan.readyAt, calendar: calendar),
                steps: plan.attendedSteps,
                nowMarker: now
            )
            .frame(height: 22)
            HStack {
                Text(Fmt.dayTime(plan.firstStepAt))
                Spacer()
                Text(Fmt.dayTime(plan.readyAt))
            }
            .font(.caption2)
            .foregroundStyle(Palette.ash)
            HStack(spacing: 14) {
                LegendSwatch(label: "Hands on") { RoundedRectangle(cornerRadius: 2).fill(Palette.crust) }
                LegendSwatch(label: "Oven") { RoundedRectangle(cornerRadius: 2).fill(Palette.ember) }
                LegendSwatch(label: "Busy") { Hatching(color: Palette.night) }
            }
            .font(.caption2)
            .foregroundStyle(Palette.ash)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timeline from \(Fmt.dayTime(plan.firstStepAt)) to \(Fmt.dayTime(plan.readyAt))")
        .accessibilityValue("\(plan.attendedSteps.count) hands-on steps")
    }
}

private struct LegendSwatch<S: View>: View {
    var label: String
    @ViewBuilder var swatch: S
    var body: some View {
        HStack(spacing: 4) {
            swatch.frame(width: 14, height: 8).clipShape(RoundedRectangle(cornerRadius: 2))
            Text(label)
        }
    }
}

/// Editable list of busy blocks, used in onboarding and settings.
struct BusyBlockList: View {
    @Binding var availability: Availability
    @State private var editing: BusyBlock?

    var body: some View {
        VStack(spacing: 10) {
            if availability.blocks.isEmpty {
                StateMessage(
                    systemImage: "calendar.badge.plus",
                    title: "No busy times",
                    message: "Hearthday will happily schedule folds at 4 AM. Add when you sleep so it won’t."
                )
            }
            ForEach(availability.blocks) { block in
                Button { editing = block } label: {
                    HStack(spacing: 12) {
                        Hatching(color: Palette.busy(block.kind))
                            .frame(width: 10, height: 36)
                            .clipShape(Capsule())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(block.label).font(.headline).foregroundStyle(Palette.rye)
                            Text("\(Fmt.weekdays(block.weekdays)) · \(Fmt.clock(minuteOfDay: block.startMinute))–\(Fmt.clock(minuteOfDay: block.endMinute))")
                                .font(.subheadline).foregroundStyle(Palette.ash)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Palette.ash).accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .card(padding: 12)
                .accessibilityHint("Edit")
            }
            Button {
                editing = BusyBlock(label: "", kind: .other, weekdays: BusyBlock.weekdaysOnly, startMinute: 15 * 60, endMinute: 16 * 60)
            } label: {
                Label("Add busy time", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .sheet(item: $editing) { block in
            BusyBlockEditor(
                block: block,
                isNew: !availability.blocks.contains { $0.id == block.id },
                onSave: { saved in
                    if let i = availability.blocks.firstIndex(where: { $0.id == saved.id }) {
                        availability.blocks[i] = saved
                    } else {
                        availability.blocks.append(saved)
                    }
                },
                onDelete: { availability.blocks.removeAll { $0.id == block.id } }
            )
        }
    }
}

struct BusyBlockEditor: View {
    @State var block: BusyBlock
    var isNew: Bool
    var onSave: (BusyBlock) -> Void
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// A blank label is filled in on save, so it isn't a blocking problem here.
    private var problems: [InputProblem] { block.problems.filter { $0 != .busyLabelEmpty } }

    private var startBinding: Binding<Date> { minuteBinding(\.startMinute) }
    private var endBinding: Binding<Date> { minuteBinding(\.endMinute) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label (e.g. School run)", text: $block.label)
                    Picker("Kind", selection: $block.kind) {
                        Text("Sleep").tag(BusyBlock.Kind.sleep)
                        Text("Work").tag(BusyBlock.Kind.work)
                        Text("Other").tag(BusyBlock.Kind.other)
                    }
                }
                Section {
                    DatePicker("Starts", selection: startBinding, displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: endBinding, displayedComponents: .hourAndMinute)
                    if block.startMinute == block.endMinute {
                        Label(InputProblem.busyZeroLength.message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(Palette.warning)
                    } else if block.endMinute < block.startMinute {
                        Text("Ends the next day. Times follow your iPhone’s clock, including daylight-saving changes.")
                            .font(.footnote).foregroundStyle(Palette.ash)
                    }
                }
                Section("Starts on") {
                    WeekdayPicker(selection: $block.weekdays)
                    if block.weekdays.isEmpty {
                        Label(InputProblem.busyNoDays.message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(Palette.warning)
                    }
                }
                if !isNew {
                    Section {
                        Button("Delete busy time", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New busy time" : "Edit busy time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = block
                        if saved.label.trimmingCharacters(in: .whitespaces).isEmpty {
                            saved.label = saved.kind == .sleep ? "Sleep" : saved.kind == .work ? "Work" : "Busy"
                        }
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(!problems.isEmpty)
                }
            }
        }
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<BusyBlock, Int>) -> Binding<Date> {
        Binding(
            get: {
                let m = block[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
            },
            set: { block[keyPath: keyPath] = $0.minuteOfDay }
        )
    }
}

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    private let symbols = Calendar.current.veryShortWeekdaySymbols
    private let names = Calendar.current.weekdaySymbols

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(on ? .white : Palette.rye)
                        .background(on ? Palette.crust : Palette.hairline.opacity(0.6), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(names[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
