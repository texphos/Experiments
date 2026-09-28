import SwiftUI
import HearthdayCore

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var showingPro = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    CalibrationCard(calibration: model.state.calibration, insight: model.state.calibrationInsight, isPro: model.state.isPro)

                    if model.state.history.isEmpty {
                        StateMessage(
                            systemImage: "book.closed",
                            title: "Your journal is empty",
                            message: "Finished bakes land here with how close the plan came, how the dough felt at shaping, and your notes."
                        )
                        .card()
                    } else {
                        ForEach(model.state.visibleHistory) { BakeRow(record: $0, fahrenheit: model.state.settings.usesFahrenheit) }
                        if model.state.hiddenHistoryCount > 0 {
                            Button {
                                showingPro = true
                            } label: {
                                Text("\(model.state.hiddenHistoryCount) older \(model.state.hiddenHistoryCount == 1 ? "bake is" : "bakes are") kept safely on this iPhone. Pro shows your full journal.")
                                    .font(.footnote)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(minHeight: 44)
                        }
                    }
                }
                .padding()
            }
            .background(Palette.flour.ignoresSafeArea())
            .navigationTitle("Journal")
            .sheet(isPresented: $showingPro) { ProView() }
        }
    }
}

private struct CalibrationCard: View {
    var calibration: Calibration
    var insight: String?
    var isPro: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your kitchen’s speed").font(Typo.heading(.headline))
            HStack(spacing: 6) {
                ForEach(0..<Calibration.samplesNeededToNarrow, id: \.self) { i in
                    Capsule()
                        .fill(i < calibration.samples.count ? Palette.crust : Palette.hairline)
                        .frame(height: 8)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("\(min(calibration.samples.count, Calibration.samplesNeededToNarrow)) of \(Calibration.samplesNeededToNarrow) calibration bakes")
            Text(insight ?? "Log a bake where the dough felt “just right” at shaping and Hearthday starts learning how your starter, flour and kitchen compare to the textbook.")
                .font(.callout).foregroundStyle(insight == nil ? Palette.ash : Palette.rye)
            if insight != nil && !isPro {
                Text("Plans use the textbook model until Pro is on. What’s learned is never locked away.")
                    .font(.footnote).foregroundStyle(Palette.ash)
            }
        }
        .card()
    }
}

private struct BakeRow: View {
    var record: BakeRecord
    var fahrenheit: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.formulaName).font(.headline).foregroundStyle(Palette.rye)
                Spacer()
                Text(record.finishedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline).foregroundStyle(Palette.ash)
            }
            HStack(spacing: 6) {
                if record.planHeld {
                    Chip(text: "Plan held", systemImage: "checkmark.seal", tint: Palette.sage)
                } else if record.replanCount > 0 {
                    Chip(text: "Re-planned \(record.replanCount)×", systemImage: "arrow.triangle.branch", tint: Palette.plum)
                }
                if let r = record.shapeReadiness {
                    Chip(text: label(r), tint: r == .justRight ? Palette.sage : Palette.warning)
                }
                if let rating = record.rating {
                    Chip(text: String(repeating: "★", count: rating), tint: Palette.ember)
                        .accessibilityLabel("\(rating) stars")
                }
            }
            Text("\(record.proofMode == .fridge ? "Fridge proof" : "Room proof") · \(Int(record.inoculationPercent))% starter · \(Fmt.temperature(record.tempC, fahrenheit: fahrenheit))\(record.actualBulkHours.map { " · bulk \(DurationText.halfHours($0)) h" } ?? "")")
                .font(.footnote).foregroundStyle(Palette.ash)
            if !record.notes.isEmpty {
                Text(record.notes).font(.callout).foregroundStyle(Palette.rye)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func label(_ r: ShapeReadiness) -> String {
        switch r {
        case .under: return "Under at shaping"
        case .justRight: return "Just right"
        case .over: return "Over at shaping"
        }
    }
}
