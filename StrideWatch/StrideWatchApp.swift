import SwiftUI

@main
struct StrideWatchApp: App {
    @State private var store = AppStore(filename: "stride-watch.json")
    @State private var manager = WorkoutManager()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
                .environment(manager)
                .task {
                    Connectivity.shared.store = store
                    Connectivity.shared.activate()
                    await manager.requestAuthorization()
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
