import AVFoundation

/// Short spoken cues through whatever headphones the watch is connected to (AirPods).
/// Music ducks while a cue plays and comes back afterwards. Nothing is spoken if no
/// audio route is available; the haptics still fire.
///
/// Cues are stitched from recorded clips in the app's `Voice` folder. A cue with any
/// clip missing is read by the system voice instead, whole, so a line never changes
/// voice halfway through.
@MainActor
final class VoiceCoach: NSObject, AVAudioPlayerDelegate {
    private let synth = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()
    private var queue: [VoiceLine] = []
    private var player: AVAudioPlayer?
    private var speaking = false

    override init() {
        super.init()
        synth.delegate = self
    }

    /// Cues queue up and play one after another.
    func speak(_ line: VoiceLine) {
        queue.append(line)
        if !speaking { next() }
    }

    func stop() {
        queue.removeAll()
        player?.stop()
        player = nil
        synth.stopSpeaking(at: .immediate)
        speaking = false
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func next() {
        guard !queue.isEmpty else {
            speaking = false
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        let line = queue.removeFirst()
        do {
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            queue.removeAll()
            speaking = false
            return
        }
        speaking = true

        if let data = VoiceClips.recording(of: line, in: VoiceClips.bundled), let player = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue) {
            player.delegate = self
            self.player = player
            if player.play() { return }
            self.player = nil
        }
        let utterance = AVSpeechUtterance(string: line.text)
        utterance.voice = Self.systemVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.postUtteranceDelay = 0.1
        synth.speak(utterance)
    }

    // MARK: - System voice

    /// For cues with no recording: an enhanced or premium English voice if one has been
    /// downloaded, otherwise the system default.
    private static let systemVoice: AVSpeechSynthesisVoice? = {
        let better = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" && $0.quality != .default }
        return better.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard self.player === player else { return }
        self.player = nil
        next()
    }
}

extension VoiceCoach: AVSpeechSynthesizerDelegate {
    // The synthesizer doesn't promise which thread it calls back on.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.next() }
    }
}
