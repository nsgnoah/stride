import AVFoundation

/// Short spoken cues through whatever headphones the watch is connected to (AirPods).
/// Music ducks while a cue plays and comes back afterwards. Nothing is spoken if no
/// audio route is available; the haptics still fire.
final class VoiceCoach: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()
    private var pending = 0

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String) {
        do {
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.postUtteranceDelay = 0.1
        pending += 1
        synth.speak(utterance)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        pending = 0
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Phrasing

    /// "11:05" → "eleven oh five", "9:40" → "nine forty".
    static func spoken(_ pace: Pace) -> String {
        let total = Int(pace.rounded())
        let m = total / 60, s = total % 60
        if s == 0 { return "\(m) flat" }
        return s < 10 ? "\(m) oh \(s)" : "\(m) \(s)"
    }

    static func spoken(_ range: PaceRange) -> String {
        "\(spoken(range.fast)) to \(spoken(range.slow))"
    }

    static func spokenDistance(_ meters: Double) -> String {
        let miles = Units.miles(meters)
        if miles < 0.95 { return String(format: "%.1f miles", miles) }
        let rounded = (miles * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded)) \(Int(rounded) == 1 ? "mile" : "miles")" : String(format: "%.1f miles", rounded)
    }

    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hour\(h == 1 ? "" : "s")") }
        if m > 0 { parts.append("\(m) minute\(m == 1 ? "" : "s")") }
        if h == 0, s > 0 { parts.append("\(s) second\(s == 1 ? "" : "s")") }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        release()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        release()
    }

    private func release() {
        pending = max(0, pending - 1)
        if pending == 0 {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
