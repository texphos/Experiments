import SwiftUI
import HearthdayCore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.state.settings.hasCompletedOnboarding {
                TabView {
                    BakeTab()
                        .tabItem { Label("Bake", systemImage: "flame") }
                    HistoryView()
                        .tabItem { Label("Journal", systemImage: "book.closed") }
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                }
            } else {
                OnboardingView()
            }
        }
        .background(Palette.flour.ignoresSafeArea())
        .overlay(alignment: .top) { ProblemBanner() }
    }
}

/// The Bake tab switches between planning and the bake in progress; there is only ever one active bake.
struct BakeTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            if model.state.activeSession != nil {
                LiveBakeView()
            } else {
                HomeView()
            }
        }
        // Starting or ending a bake replaces the whole stack, so the plan screen that was pushed to start it
        // doesn't stay on top of the live bake.
        .id(model.state.activeSession != nil)
    }
}

/// Storage problems are surfaced, never swallowed.
private struct ProblemBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let message = model.loadProblem ?? model.saveProblem {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.warning)
                    .accessibilityHidden(true)
                Text(message).font(.footnote).foregroundStyle(Palette.rye)
                Spacer(minLength: 0)
                if !model.isHoldingUnreadableFile {
                    Button {
                        model.loadProblem = nil
                        model.saveProblem = nil
                    } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Dismiss")
                }
            }
            .padding(.leading, 14)
            .padding(.vertical, model.isHoldingUnreadableFile ? 12 : 0)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal)
            .accessibilityElement(children: .contain)
        }
    }
}
