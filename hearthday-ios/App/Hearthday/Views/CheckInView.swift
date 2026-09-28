import SwiftUI
import HearthdayCore

/// Ten-second check-in: how much has it risen? Hearthday re-plans the rest around your busy times.
struct CheckInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var rise: Double = 30
    @State private var tempC: Double = 21
    @State private var result: CheckInResult?
    @State private var checkedAt = Date()

    private var target: Double { FermentationModel.targetRisePercent(tempC: tempC) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .bottom, spacing: 20) {
                        RiseJar(rise: rise, target: target)
                            .frame(width: 96, height: 150)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(Int(rise))%")
                                .font(Typo.clock(.largeTitle)).foregroundStyle(Palette.rye)
                            Text("rise since mixing").foregroundStyle(Palette.ash)
                            Text("Aim ≈ \(Int(target))% at this temperature")
                                .font(.footnote).foregroundStyle(Palette.ash)
                        }
                    }
                    Slider(value: $rise, in: 0...150, step: 5) { Text("Rise") }
                        .accessibilityValue("\(Int(rise)) percent")
                        .accessibilityIdentifier("checkin.rise")
                    Text("Easiest in a straight-sided container: mark the level after mixing and compare. Rise targets are a guide from home-baker tables, not a rule; trust bubbles, jiggle and domed edges too.")
                        .font(.footnote).foregroundStyle(Palette.ash)

                    TemperatureStepper(celsius: $tempC, fahrenheit: model.state.settings.usesFahrenheit, label: "Dough temperature")
                        .card()

                    Button(result == nil ? "Re-plan from here" : "Update options") {
                        checkedAt = Date()
                        result = model.checkIn(risePercent: rise, tempC: tempC)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("checkin.replan")

                    if let result { options(result) }
                }
                .padding()
            }
            .background(Palette.flour.ignoresSafeArea())
            .navigationTitle("Check the dough")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear {
                tempC = model.state.activeSession?.checkIns.last?.tempC ?? model.state.activeSession?.plan.kitchenTempC ?? 21
            }
            .onChange(of: rise) { result = nil }
            .onChange(of: tempC) { result = nil }
        }
    }

    @ViewBuilder
    private func options(_ result: CheckInResult) -> some View {
        let checkIn = CheckIn(at: checkedAt, risePercent: rise, tempC: tempC)
        VStack(alignment: .leading, spacing: 12) {
            if !result.problems.isEmpty {
                StateMessage(
                    systemImage: "exclamationmark.circle",
                    title: "Check that reading",
                    message: result.summary,
                    tint: Palette.warning
                )
            } else {
                Text(result.summary).font(.headline).foregroundStyle(Palette.rye)
                    .accessibilityIdentifier("checkin.summary")
            }
            if result.options.isEmpty && result.problems.isEmpty {
                StateMessage(
                    systemImage: "questionmark.circle",
                    title: "No clean way to re-plan",
                    message: "Every option would put a hands-on step in your busy times. Keep an eye on the dough; fridging it is almost always the safest pause.",
                    tint: Palette.warning
                )
                Button("Log this check-in") {
                    model.logCheckInOnly(checkIn)
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            ForEach(result.options) { option in
                OptionCard(option: option) {
                    model.apply(option, checkIn: checkIn)
                    dismiss()
                }
            }
        }
    }
}

private struct OptionCard: View {
    var option: ReplanOption
    var choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(option.title).font(.headline).foregroundStyle(Palette.rye)
                    Spacer()
                    if option.recommended { Chip(text: "Suggested", systemImage: "star.fill") }
                }
                Text(option.detail).font(.subheadline).foregroundStyle(Palette.ash).multilineTextAlignment(.leading)
                HStack(spacing: 12) {
                    if let shape = option.shapeAt {
                        Label("Shape \(Fmt.dayTime(shape).lowercasedFirst)", systemImage: "circle.dashed")
                    }
                    Label("Bread \(Fmt.dayTime(option.readyAt).lowercasedFirst)", systemImage: "flame")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.crust)
                if let label = option.conflictLabel {
                    Label("Needs you during “\(label)”", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Palette.warning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(option.recommended ? Palette.crust : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Replaces the rest of the plan")
        .accessibilityIdentifier("option.\(option.kind.rawValue)")
    }
}

/// A straight-sided jar: the fill shows the rise, the dashed line the target.
struct RiseJar: View {
    var rise: Double
    var target: Double

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let base = h * 0.35
            let perPercent = (h - base - 8) / 150
            let fill = base + perPercent * rise
            let targetY = h - (base + perPercent * target)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.ash, lineWidth: 2)
                RoundedRectangle(cornerRadius: 11)
                    .fill(Palette.crumb.opacity(0.9))
                    .overlay(RoundedRectangle(cornerRadius: 11).fill(Palette.ember.opacity(0.18)))
                    .frame(height: fill)
                    .padding(3)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: targetY))
                    p.addLine(to: CGPoint(x: geo.size.width, y: targetY))
                }
                .stroke(Palette.crust, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h - base))
                    p.addLine(to: CGPoint(x: geo.size.width * 0.25, y: h - base))
                }
                .stroke(Palette.ash, lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.2), value: rise)
        }
        .accessibilityHidden(true)
    }
}
