import SwiftUI
import HearthdayCore

/// Three short steps, all skippable with sensible defaults. The first plan is one tap away at the end.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0
    @State private var settings = UserSettings()

    var body: some View {
        VStack(spacing: 0) {
            ProgressDots(count: 3, current: page)
                .padding(.top, 12)

            TabView(selection: $page) {
                WelcomePage().tag(0)
                BusyTimesPage(availability: $settings.availability).tag(1)
                KitchenPage(settings: $settings).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            VStack(spacing: 10) {
                Button(page == 2 ? "Plan my first bake" : "Continue") {
                    if page < 2 { page += 1 } else { finish() }
                }
                .buttonStyle(PrimaryButtonStyle())

                if page > 0 {
                    Button("Back") { page -= 1 }
                        .frame(minHeight: 44)
                        .foregroundStyle(Palette.ash)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Palette.flour.ignoresSafeArea())
    }

    private func finish() {
        var s = settings
        s.hasCompletedOnboarding = true
        model.update { $0.settings = s }
    }
}

private struct ProgressDots: View {
    var count: Int
    var current: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Palette.crust : Palette.hairline)
                    .frame(width: i == current ? 22 : 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

private struct WelcomePage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LoafMark()
                    .frame(width: 88, height: 88)
                    .padding(.top, 32)
                Text("Sourdough that fits around your week.")
                    .font(Typo.display())
                    .foregroundStyle(Palette.rye)
                Text("Tell Hearthday when you’re asleep or at work. Pick when you want warm bread. It works backwards from there, and only asks for your hands when you’re free.")
                    .font(.body)
                    .foregroundStyle(Palette.ash)
                VStack(alignment: .leading, spacing: 14) {
                    Bullet(icon: "moon.zzz", text: "No folds at 3 AM, no shaping during a meeting.")
                    Bullet(icon: "gauge.with.dots.needle.33percent", text: "Dough running fast or slow? A 10-second check-in re-plans the rest.")
                    Bullet(icon: "lock", text: "No account. Your bakes stay on this iPhone.")
                }
                .padding(.top, 8)
                Text("Times are estimates. Dough is alive and kitchens vary; Hearthday shows a likely window and helps you adjust, but can’t promise the exact minute.")
                    .font(.footnote)
                    .foregroundStyle(Palette.ash)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)
        }
    }
}

private struct Bullet: View {
    var icon: String
    var text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Palette.crust)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text).foregroundStyle(Palette.rye)
        }
    }
}

private struct BusyTimesPage: View {
    @Binding var availability: Availability

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("When are you busy?")
                    .font(Typo.display(.title))
                    .padding(.top, 24)
                Text("Hearthday won’t schedule hands-on steps in these times. You can change them any time, and add school runs or gym.")
                    .foregroundStyle(Palette.ash)
                WeekRibbon(availability: availability)
                    .padding(.vertical, 4)
                BusyBlockList(availability: $availability)
            }
            .padding(.horizontal, 24)
        }
    }
}

private struct KitchenPage: View {
    @Binding var settings: UserSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your kitchen and starter")
                    .font(Typo.display(.title))
                    .padding(.top, 24)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Usual kitchen temperature").font(.headline)
                    TemperatureStepper(celsius: $settings.kitchenTempC, fahrenheit: settings.usesFahrenheit)
                    Toggle("Show °F", isOn: $settings.usesFahrenheit)
                    Text("Temperature is the biggest driver of timing. A rough guess is fine; you can adjust it per bake.")
                        .font(.footnote).foregroundStyle(Palette.ash)
                }
                .card()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Starter").font(.headline)
                    Picker("Starter", selection: $settings.starterUsuallyNeedsFeed) {
                        Text("Lives in the fridge").tag(true)
                        Text("Active on the counter").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Text(settings.starterUsuallyNeedsFeed
                         ? "Hearthday will schedule a feed and choose a feed ratio so it peaks when you can mix."
                         : "Hearthday will assume your starter is ready to use when you mix.")
                        .font(.footnote).foregroundStyle(Palette.ash)
                }
                .card()
            }
            .padding(.horizontal, 24)
        }
    }
}

/// The brand mark: a scored boule over a low sun, drawn in code so it scales with the design.
struct LoafMark: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let loaf = Path(ellipseIn: CGRect(x: w * 0.1, y: h * 0.28, width: w * 0.8, height: h * 0.56))
            ctx.fill(loaf, with: .color(Palette.crust))
            var score = Path()
            score.move(to: CGPoint(x: w * 0.32, y: h * 0.62))
            score.addQuadCurve(to: CGPoint(x: w * 0.68, y: h * 0.44), control: CGPoint(x: w * 0.44, y: h * 0.44))
            ctx.stroke(score, with: .color(Palette.flour), style: StrokeStyle(lineWidth: w * 0.05, lineCap: .round))
            ctx.fill(Path(CGRect(x: w * 0.04, y: h * 0.86, width: w * 0.92, height: h * 0.04)), with: .color(Palette.ember))
        }
        .accessibilityHidden(true)
    }
}

struct TemperatureStepper: View {
    @Binding var celsius: Double
    var fahrenheit: Bool

    var body: some View {
        Stepper(value: $celsius, in: 14...32, step: fahrenheit ? 5.0 / 9.0 : 0.5) {
            Text(Fmt.temperature(celsius, fahrenheit: fahrenheit))
                .font(Typo.clock(.title2))
                .foregroundStyle(Palette.rye)
        }
        .accessibilityLabel("Kitchen temperature")
        .accessibilityValue(Fmt.temperature(celsius, fahrenheit: fahrenheit))
    }
}
