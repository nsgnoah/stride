import SwiftUI

@main
struct StrideApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task {
                    Connectivity.shared.store = store
                    Connectivity.shared.activate()
                }
                .onChange(of: store.plan) { _, plan in
                    Connectivity.shared.send(plan: plan)
                }
        }
    }
}
