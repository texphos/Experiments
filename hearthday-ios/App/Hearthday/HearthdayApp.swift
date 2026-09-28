import SwiftUI
import UIKit

@main
struct HearthdayApp: App {
    @State private var model = AppModel.live()
    @State private var store = ProStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(store)
                .tint(Palette.crust)
                .preferredColorScheme(LaunchArgument.forcedColorScheme())
                .task {
                    store.onEntitlementChange = { isPro in model.setPro(isPro) }
                    await model.resume()
                    await store.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.resume() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                    Task { await model.resume() }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    Task { await model.resume() }
                }
        }
    }
}

extension LaunchArgument {
    /// Lets UI tests pin the appearance; ignored outside UI testing so real users always follow the system setting.
    static func forcedColorScheme(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> ColorScheme? {
        guard arguments.contains(uiTesting) else { return nil }
        if arguments.contains(darkAppearance) { return .dark }
        if arguments.contains(lightAppearance) { return .light }
        return nil
    }
}
