import Foundation
import CryptoKit
import WatchConnectivity

/// Phone ↔ watch bridge.
///
/// The plan reaches the watch three ways, because no single one is dependable:
/// - `applicationContext` whenever it changes. The system delivers this when it sees fit,
///   which can be many minutes later, so it's the safety net rather than the main route.
/// - A direct message the moment the watch app is reachable, acknowledged by the watch.
/// - The watch asks for the latest plan every time its app comes to the front, which
///   wakes the phone app if it has to.
///
/// Watch pushes each finished run via `transferUserInfo`, which queues until the phone
/// is reachable, so nothing is lost if the phone is at home.
final class Connectivity: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = Connectivity()

    private enum Key {
        /// Plan as plain JSON. Empty data means "no plan". Read by every build.
        static let plan = "plan"
        /// Plan as zlib-compressed JSON; a long plan is too big to send plain.
        static let planZ = "planZ"
        /// Identifies one version of the plan, so the watch can say which it has.
        static let stamp = "stamp"
        static let activity = "activity"
        static let request = "request"
        static let have = "have"
        static let ack = "ack"
        static let same = "same"
    }

    /// WatchConnectivity's reply closure isn't marked Sendable; it is safe to call from any thread.
    private struct Reply: @unchecked Sendable {
        let send: ([String: Any]) -> Void
    }

    private static let noPlanStamp = "none"
    private static let watchStampKey = "planStamp"

    /// Set by whichever app is running to receive incoming data on the main actor.
    @MainActor var store: AppStore?

    /// Phone: the last plan encoded, so its stamp stays the same until the plan changes.
    @MainActor private var encoded: (plan: TrainingPlan?, raw: Data, compressed: Data?, stamp: String)?
    /// Phone: the stamp the watch last confirmed it holds.
    @MainActor private var confirmedStamp: String?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Sending the plan (phone)

    @MainActor func send(plan: TrainingPlan?) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let current = encode(plan)
        do {
            var context = message(for: current)
            // Builds before plans were compressed only read the plain copy. Include it
            // while it fits, so a watch that hasn't updated yet still gets the plan.
            if current.compressed != nil, current.raw.count < 100_000 { context[Key.plan] = current.raw }
            try WCSession.default.updateApplicationContext(context)
        } catch {
            print("Stride: plan sync failed — \(error)")
        }
        pushIfReachable()
    }

    /// Delivers the plan right now if the watch app is in front and doesn't have it yet.
    @MainActor private func pushIfReachable() {
        guard let store, WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        let current = encode(store.plan)
        guard confirmedStamp != current.stamp else { return }
        let stamp = current.stamp
        // @Sendable: WatchConnectivity calls back on its own queue, not the main actor.
        WCSession.default.sendMessage(message(for: current), replyHandler: { @Sendable [weak self] reply in
            guard reply[Key.ack] as? String == stamp else { return }
            Task { @MainActor in self?.confirm(stamp) }
        }, errorHandler: nil)
    }

    @MainActor private func confirm(_ stamp: String) {
        confirmedStamp = stamp
        store?.watchConfirmedPlanAt = .now
    }

    @MainActor private func encode(_ plan: TrainingPlan?) -> (plan: TrainingPlan?, raw: Data, compressed: Data?, stamp: String) {
        if let encoded, encoded.plan == plan { return encoded }
        var result: (plan: TrainingPlan?, raw: Data, compressed: Data?, stamp: String) = (plan, Data(), nil, Self.noPlanStamp)
        if let plan, let raw = try? JSONEncoder().encode(plan) {
            let stamp = SHA256.hash(data: raw).prefix(8).map { String(format: "%02x", $0) }.joined()
            result = (plan, raw, try? (raw as NSData).compressed(using: .zlib) as Data, stamp)
        }
        if encoded?.stamp != result.stamp { store?.watchConfirmedPlanAt = nil }
        encoded = result
        return result
    }

    private func message(for encoded: (plan: TrainingPlan?, raw: Data, compressed: Data?, stamp: String)) -> [String: Any] {
        if let compressed = encoded.compressed {
            return [Key.planZ: compressed, Key.stamp: encoded.stamp]
        }
        return [Key.plan: encoded.raw, Key.stamp: encoded.stamp]
    }

    // MARK: - Receiving the plan (watch)

    /// Called whenever the watch app comes to the front: take whatever the system already
    /// delivered, then ask the phone directly in case that's stale.
    func refreshFromPhone() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let session = WCSession.default
        apply(session.receivedApplicationContext)
        guard session.isReachable else { return }
        let have = UserDefaults.standard.string(forKey: Self.watchStampKey) ?? ""
        session.sendMessage([Key.request: Key.plan, Key.have: have], replyHandler: { @Sendable [weak self] reply in
            self?.apply(reply)
        }, errorHandler: nil)
    }

    /// Applies a plan payload on the watch. Returns the stamp now held, if the payload had one.
    @discardableResult
    private func apply(_ payload: [String: Any]) -> String? {
        let plain = payload[Key.plan] as? Data
        let compressed = payload[Key.planZ] as? Data
        guard plain != nil || compressed != nil else { return nil }
        let stamp = payload[Key.stamp] as? String

        let data: Data?
        if let compressed {
            data = try? (compressed as NSData).decompressed(using: .zlib) as Data
        } else {
            data = plain
        }
        guard let data else { return nil }

        if data.isEmpty {
            UserDefaults.standard.set(stamp, forKey: Self.watchStampKey)
            Task { @MainActor in store?.clearPlan() }
            return stamp
        }
        // A plan we can't read is ignored, never treated as "no plan" — she keeps what she has.
        guard let plan = try? JSONDecoder().decode(TrainingPlan.self, from: data) else { return nil }
        let known = stamp != nil && stamp == UserDefaults.standard.string(forKey: Self.watchStampKey)
        UserDefaults.standard.set(stamp, forKey: Self.watchStampKey)
        Task { @MainActor in
            // Already holding this exact version: nothing to rewrite.
            if known, store?.plan != nil { return }
            store?.replacePlan(plan)
        }
        return stamp
    }

    // MARK: - Runs (watch → phone)

    func send(activity: ActivityRecord) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(activity) else { return }
        let payload = [Key.activity: data]
        let session = WCSession.default
        // Phone nearby and awake: deliver now so the checkmark appears while she's still
        // looking at it. Otherwise (or if that fails) queue it for whenever they reconnect.
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func receive(_ payload: [String: Any]) {
        if let data = payload[Key.activity] as? Data,
           let activity = try? JSONDecoder().decode(ActivityRecord.self, from: data) {
            Task { @MainActor in store?.record(activity) }
        }
        apply(payload)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        // Watch asking the phone for the newest plan.
        if message[Key.request] as? String == Key.plan {
            let have = message[Key.have] as? String
            let reply = Reply(send: replyHandler)
            Task { @MainActor in
                let current = encode(store?.plan)
                if have == current.stamp {
                    confirm(current.stamp)
                    reply.send([Key.same: true])
                } else {
                    reply.send(self.message(for: current))
                }
            }
            return
        }
        // Phone handing the watch a plan: confirm which version landed.
        if let data = message[Key.activity] as? Data,
           let activity = try? JSONDecoder().decode(ActivityRecord.self, from: data) {
            Task { @MainActor in store?.record(activity) }
        }
        replyHandler(apply(message).map { [Key.ack: $0] } ?? [:])
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error { print("Stride: WCSession activation error — \(error)") }
        #if os(iOS)
        // Re-push the plan on activation so a freshly paired watch gets it.
        Task { @MainActor in
            if let plan = store?.plan { send(plan: plan) }
        }
        #else
        refreshFromPhone()
        #endif
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        #if os(iOS)
        // The watch app just came to the front: hand it the plan if it's behind.
        Task { @MainActor in pushIfReachable() }
        #else
        if session.isReachable { refreshFromPhone() }
        #endif
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
