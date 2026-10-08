import Foundation

/// A short diary of what the coach tried to say and what happened, kept on the watch so
/// a quiet run can be explained afterwards from the Voice log screen.
@MainActor
enum VoiceLog {
    private static let key = "voiceLog"
    private static let limit = 60

    static var entries: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func note(_ text: String) {
        let stamp = Date.now.formatted(.dateTime.hour().minute().second())
        var all = entries
        all.append("\(stamp)  \(text)")
        if all.count > limit { all.removeFirst(all.count - limit) }
        UserDefaults.standard.set(all, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
