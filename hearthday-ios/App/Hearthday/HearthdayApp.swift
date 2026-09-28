import SwiftUI

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
                .task {
                    store.onEntitlementChange = { isPro in model.setPro(isPro) }
                    await store.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refreshClock() }
                }
        }
    }
}
