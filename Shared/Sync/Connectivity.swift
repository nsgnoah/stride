import Foundation
import WatchConnectivity

/// Phone ↔ watch bridge.
///
/// - Phone pushes the whole plan via `applicationContext` whenever it changes; the
///   watch always has the latest even if it wasn't running.
/// - Watch pushes each finished run via `transferUserInfo`, which queues until the phone
///   is reachable, so nothing is lost if the phone is at home.
final class Connectivity: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = Connectivity()

    private enum Key {
        static let plan = "plan"
        static let activity = "activity"
    }

    /// Set by whichever app is running to receive incoming data on the main actor.
    @MainActor var store: AppStore?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Sending

    func send(plan: TrainingPlan?) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        do {
            let data = try plan.map { try JSONEncoder().encode($0) } ?? Data()
            try WCSession.default.updateApplicationContext([Key.plan: data])
        } catch {
            print("Stride: plan sync failed — \(error)")
        }
    }

    func send(activity: ActivityRecord) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(activity) else { return }
        WCSession.default.transferUserInfo([Key.activity: data])
    }

    // MARK: - Receiving

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[Key.plan] as? Data else { return }
        let plan = data.isEmpty ? nil : try? JSONDecoder().decode(TrainingPlan.self, from: data)
        Task { @MainActor in
            if let plan { store?.replacePlan(plan) } else { store?.reset() }
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[Key.activity] as? Data,
              let activity = try? JSONDecoder().decode(ActivityRecord.self, from: data) else { return }
        Task { @MainActor in store?.record(activity) }
    }

    // MARK: - WCSessionDelegate boilerplate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error { print("Stride: WCSession activation error — \(error)") }
        #if os(iOS)
        // Re-push the plan on activation so a freshly paired watch gets it.
        Task { @MainActor in
            if let plan = store?.plan { send(plan: plan) }
        }
        #else
        // Pull whatever the phone last sent.
        let context = session.receivedApplicationContext
        if !context.isEmpty { self.session(session, didReceiveApplicationContext: context) }
        #endif
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
