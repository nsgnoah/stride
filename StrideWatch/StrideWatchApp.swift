import SwiftUI

@main
struct StrideWatchApp: App {
    @State private var store: AppStore
    @State private var manager = WorkoutManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = AppStore(filename: "stride-watch.json")
        _store = State(initialValue: store)
        Connectivity.shared.store = store
        Connectivity.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
                .environment(manager)
                .task {
                    await manager.requestAuthorization()
                }
                .onChange(of: scenePhase) { _, phase in
                    // Every time she raises the app, make sure it has the phone's latest plan.
                    if phase == .active { Connectivity.shared.refreshFromPhone() }
                }
        }
    }
}

struct WatchRootView: View {
    @Environment(WorkoutManager.self) private var manager

    var body: some View {
        switch manager.phase {
        case .idle: WatchHomeView()
        case .running, .paused: ActiveWorkoutView()
        case .finished: SummaryView()
        }
    }
}
