import SwiftUI
import HearthdayCore

struct PlanInput: Hashable {
    var readyBy: Date
    var formula: Formula
    var tempC: Double
    var starterNeedsFeed: Bool
}

/// The core question, front and centre: when do you want bread?
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var readyBy: Date?
    @State private var formulaID: UUID?
    @State private var tempC: Double?
    @State private var starterNeedsFeed: Bool?
    @State private var input: PlanInput?
    @State private var showingCustomTime = false

    private var settings: UserSettings { model.state.settings }
    private var readyTime: Date { readyBy ?? HomeView.defaultReadyTime(availability: settings.availability) }
    private var formula: Formula {
        model.state.formulas.first { $0.id == formulaID } ?? model.state.formulas.first ?? .countryLoaf
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                quickTimes
                details
                Button("Plan it") {
                    input = PlanInput(
                        readyBy: readyTime,
                        formula: formula,
                        tempC: tempC ?? settings.kitchenTempC,
                        starterNeedsFeed: starterNeedsFeed ?? settings.starterUsuallyNeedsFeed
                    )
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("home.plan")

                if let insight = model.state.calibrationInsight {
                    InsightCard(text: insight, applied: model.state.isPro)
                } else {
                    firstBakeHint
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your week").font(Typo.heading(.headline))
                    WeekRibbon(availability: settings.availability)
                }
                .card()
            }
            .padding()
        }
        .background(Palette.flour.ignoresSafeArea())
        .navigationTitle("Hearthday")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $input) { input in
            PlanResultView(input: input)
        }
        .sheet(isPresented: $showingCustomTime) {
            CustomTimeSheet(date: Binding(get: { readyTime }, set: { readyBy = $0 }))
                .presentationDetents([.medium])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("When do you want bread?")
                .font(Typo.display(.title))
                .foregroundStyle(Palette.rye)
            Text("Out of the oven by")
                .font(.subheadline)
                .foregroundStyle(Palette.ash)
            Button { showingCustomTime = true } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.dayTime(readyTime)).font(Typo.clock(.largeTitle)).foregroundStyle(Palette.crust)
                    Image(systemName: "pencil").foregroundStyle(Palette.ash).accessibilityHidden(true)
                }
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Ready by \(Fmt.dayTime(readyTime))")
            .accessibilityHint("Choose a different time")
        }
    }

    private var quickTimes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HomeView.suggestions(availability: settings.availability), id: \.self) { date in
                    let selected = abs(date.timeIntervalSince(readyTime)) < 60
                    Button { readyBy = date } label: {
                        Text(Fmt.dayTime(date))
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .foregroundStyle(selected ? .white : Palette.crust)
                            .background(selected ? Palette.crust : Palette.crust.opacity(0.1), in: Capsule())
                    }
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Button("Other…") { showingCustomTime = true }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Palette.hairline.opacity(0.6), in: Capsule())
                    .foregroundStyle(Palette.rye)
            }
        }
    }

    private var details: some View {
        VStack(spacing: 14) {
            if model.state.formulas.count > 1 {
                Picker("Formula", selection: Binding(get: { formula.id }, set: { formulaID = $0 })) {
                    ForEach(model.state.formulas) { Text($0.name).tag($0.id) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Text("Formula").foregroundStyle(Palette.ash)
                    Spacer()
                    Text(formula.name).foregroundStyle(Palette.rye)
                }
            }
            Divider()
            TemperatureStepper(
                celsius: Binding(get: { tempC ?? settings.kitchenTempC }, set: { tempC = $0 }),
                fahrenheit: settings.usesFahrenheit
            )
            Divider()
            Toggle("Starter needs a feed first", isOn: Binding(
                get: { starterNeedsFeed ?? settings.starterUsuallyNeedsFeed },
                set: { starterNeedsFeed = $0 }
            ))
        }
        .card()
    }

    private var firstBakeHint: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles").foregroundStyle(Palette.crust).accessibilityHidden(true)
            Text("After each bake, tell Hearthday whether the dough was ready at shaping. It learns how fast your kitchen really runs.")
                .font(.callout).foregroundStyle(Palette.ash)
        }
        .card()
    }

    static func defaultReadyTime(now: Date = .now, availability: Availability = .typicalWeekdayWorker) -> Date {
        suggestions(now: now, availability: availability).first ?? now.addingTimeInterval(86_400)
    }

    /// Everyday bread times over the next few days, keeping only those at least 14 h away whose oven
    /// slot is free, so a one-tap suggestion never starts with "that doesn't fit".
    static func suggestions(now: Date = .now, availability: Availability, calendar: Calendar = .current) -> [Date] {
        func at(_ dayOffset: Int, _ hour: Int) -> Date? {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) else { return nil }
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
        }
        let oven = TimeInterval((ProcessSettings().preheatMinutes + ProcessSettings().bakeMinutes) * 60)
        let timeline = availability.timeline(from: now, to: now.addingTimeInterval(5 * 86_400), calendar: calendar)
        let candidates = (1...4).flatMap { offset in [at(offset, 10), at(offset, 19), at(offset, 12)] }.compactMap { $0 }
        var seen = Set<Date>()
        let fitting = candidates
            .filter { $0.timeIntervalSince(now) > 14 * 3600 }
            .filter { timeline.isFree(start: $0.addingTimeInterval(-oven), duration: oven) }
            .filter { seen.insert(calendar.startOfDay(for: $0)).inserted }
        return Array(fitting.sorted().prefix(4))
    }
}

struct InsightCard: View {
    var text: String
    var applied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What your bakes say", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline).foregroundStyle(Palette.crust)
            Text(text).foregroundStyle(Palette.rye)
            Text(applied ? "Applied to your plans." : "Hearthday Pro applies this to your plans.")
                .font(.footnote).foregroundStyle(Palette.ash)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

private struct CustomTimeSheet: View {
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(
                "Ready by",
                selection: $date,
                in: Date().addingTimeInterval(3600)...Date().addingTimeInterval(7 * 86_400),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .padding()
            .navigationTitle("Out of the oven by")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
