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
                    Task { await Reminders.reschedule(plan: plan, hour: store.reminderHour, skippedOrDone: store.settledWorkoutIDs) }
                }
                .onChange(of: store.activities) { _, _ in
                    // A run done early in the day shouldn't still ping her at 7 tomorrow… or today.
                    Task { await Reminders.reschedule(plan: store.plan, hour: store.reminderHour, skippedOrDone: store.settledWorkoutIDs) }
                }
        }
    }
}
