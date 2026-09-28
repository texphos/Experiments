import SwiftUI
import HearthdayCore

struct PlanResultView: View {
    @Environment(AppModel.self) private var model
    @State var input: PlanInput
    @State private var result: PlanResult?
    @State private var selected = 0

    var body: some View {
        ScrollView {
            Group {
                switch result {
                case nil:
                    ProgressView("Finding a plan that fits…")
                        .frame(maxWidth: .infinity, minHeight: 300)
                case .infeasible(let why)?:
                    InfeasibleView(infeasibility: why) { earliest in
                        input.readyBy = earliest
                    }
                case .feasible(let primary, let alternatives)?:
                    let plans = [primary] + alternatives
                    let plan = plans[min(selected, plans.count - 1)]
                    VStack(alignment: .leading, spacing: 18) {
                        if plans.count > 1 {
                            Picker("Plan", selection: $selected) {
                                ForEach(plans.indices, id: \.self) { i in
                                    Text(i == 0 ? "Best fit" : "Option \(i + 1)").tag(i)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        PlanSummary(plan: plan, fahrenheit: model.state.settings.usesFahrenheit)
                        DayRibbonView(plan: plan, availability: model.state.settings.availability)
                            .card()
                        StepList(plan: plan, session: nil)
                        EstimateNote(plan: plan)
                        Button("Start this bake") { model.start(plan) }
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(.bottom)
                    }
                }
            }
            .padding()
        }
        .background(Palette.flour.ignoresSafeArea())
        .navigationTitle("Your plan")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: input) {
            result = nil
            selected = 0
            result = await model.plan(
                readyBy: input.readyBy,
                formula: input.formula,
                tempC: input.tempC,
                starterNeedsFeed: input.starterNeedsFeed
            )
        }
    }
}

private struct PlanSummary: View {
    var plan: BakePlan
    var fahrenheit: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start \(Fmt.dayTime(plan.firstStepAt).lowercasedFirst)")
                .font(Typo.display(.title2))
                .foregroundStyle(Palette.rye)
            Text("Bread out \(Fmt.dayTime(plan.readyAt).lowercasedFirst) · about \(DurationText.compact(minutes: plan.handsOnMinutes)) hands-on")
                .foregroundStyle(Palette.ash)
            FlowChips(items: plan.leverSummary)
            let a = plan.formula.amounts(starterPercent: plan.inoculationPercent)
            Text("\(Int(a.flour)) g flour · \(Int(a.water.rounded())) g water · \(Int(a.starter.rounded())) g starter · \(String(format: "%.0f", a.salt)) g salt")
                .font(.footnote)
                .foregroundStyle(Palette.ash)
        }
    }
}

struct FlowChips: View {
    var items: [String]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { ForEach(items, id: \.self) { Chip(text: $0) } }
            VStack(alignment: .leading, spacing: 6) { ForEach(items, id: \.self) { Chip(text: $0) } }
        }
    }
}

/// Every step in order; hands-on steps are emphasised, passive ones show their likely window.
struct StepList: View {
    var plan: BakePlan
    var session: BakeSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(plan.steps) { step in
                let done = session?.isDone(step) ?? false
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Image(systemName: done ? "checkmark.circle.fill" : icon(step.kind))
                            .foregroundStyle(done ? Palette.sage : step.attended ? Palette.crust : Palette.ash)
                            .frame(width: 28, height: 28)
                        Rectangle().fill(Palette.hairline).frame(width: 1).frame(maxHeight: .infinity)
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(step.title)
                                .font(step.attended ? .headline : .subheadline)
                                .foregroundStyle(done ? Palette.ash : Palette.rye)
                                .strikethrough(done)
                            Spacer()
                            Text(Fmt.dayTime(step.start)).font(.subheadline.monospacedDigit()).foregroundStyle(Palette.ash)
                        }
                        Text(step.detail).font(.footnote).foregroundStyle(Palette.ash)
                        if !step.attended {
                            Text("Passive · \(DurationText.compact(minutes: Int(step.duration / 60)))")
                                .font(.caption).foregroundStyle(Palette.ash)
                        }
                    }
                    .padding(.bottom, 16)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(step.title), \(Fmt.dayTime(step.start))\(done ? ", done" : "")\(step.attended ? ", hands-on" : ", passive")")
            }
        }
        .card()
    }

    private func icon(_ kind: StepKind) -> String {
        switch kind {
        case .feedStarter: return "drop"
        case .starterRise: return "hourglass"
        case .mix: return "hands.sparkles"
        case .fold: return "arrow.triangle.2.circlepath"
        case .bulk: return "clock"
        case .shape: return "circle.dashed"
        case .coldRetard, .coldBulk: return "snowflake"
        case .roomProof: return "hourglass.bottomhalf.filled"
        case .preheat: return "thermometer.sun"
        case .bake: return "flame"
        }
    }
}

private struct EstimateNote: View {
    var plan: BakePlan
    var body: some View {
        Label {
            Text("Bulk is estimated at \(DurationText.halfHours(plan.expectedBulkHours)) h, give or take \(Int((plan.uncertainty * 100).rounded()))%. Flour, starter strength and a warm afternoon all shift it. A quick check-in during bulk re-plans the rest if it drifts.")
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.footnote)
        .foregroundStyle(Palette.ash)
    }
}

private struct InfeasibleView: View {
    var infeasibility: Infeasibility
    var tryEarliest: (Date) -> Void

    var body: some View {
        VStack(spacing: 16) {
            StateMessage(
                systemImage: "calendar.badge.exclamationmark",
                title: "That time doesn’t fit your week",
                message: infeasibility.message,
                tint: Palette.warning
            )
            if let earliest = infeasibility.earliestFeasibleReadyAt {
                Button("Earliest that fits: \(Fmt.dayTime(earliest))") { tryEarliest(earliest) }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Text("No workable plan in the next three days. Try freeing up a busy time in Settings.")
                    .font(.callout).foregroundStyle(Palette.ash).multilineTextAlignment(.center)
            }
            Text("Hearthday never schedules hands-on steps during your busy times. It will say no rather than hand you an alarm at 3 AM.")
                .font(.footnote).foregroundStyle(Palette.ash).multilineTextAlignment(.center)
        }
        .card(padding: 20)
    }
}

extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        let head = String(first)
        return ["Today", "Tonight", "Tomorrow"].contains(where: hasPrefix) ? head.lowercased() + dropFirst() : self
    }
}
