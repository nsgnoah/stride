import AVFoundation

/// Short spoken cues through whatever headphones the watch is connected to (AirPods).
/// Music ducks while a cue plays and comes back afterwards. Nothing is spoken if no
/// audio route is available; the haptics still fire.
///
/// Cues are stitched from recorded clips in the app's `Voice` folder. A cue with any
/// clip missing, or one the player can't start, is read by the system voice instead,
/// whole, so a line never changes voice halfway through.
///
/// Cues queue up and play one after another. Nothing is allowed to wedge the queue:
/// a cue that doesn't report finishing is timed out, and an audio interruption (a call,
/// Siri, another app taking the route) clears it.
@MainActor
final class VoiceCoach: NSObject, AVAudioPlayerDelegate {
    private let synth = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()
    private var queue: [VoiceLine] = []
    private var player: AVAudioPlayer?
    private var speaking = false
    /// Identifies the cue in flight, so a late timeout can't skip the one after it.
    private var cueID = 0

    override init() {
        super.init()
        synth.delegate = self
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.interrupted() }
        }
    }

    func speak(_ line: VoiceLine) {
        queue.append(line)
        if !speaking { next() }
    }

    func stop() {
        queue.removeAll()
        finishCurrent()
        speaking = false
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - The queue

    private func next() {
        guard !queue.isEmpty else {
            speaking = false
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        let line = queue.removeFirst()
        speaking = true
        cueID += 1
        let id = cueID

        var sessionError: String?
        do {
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            sessionError = error.localizedDescription
        }

        // Recorded clips first.
        if sessionError == nil, let data = VoiceClips.recording(of: line, in: VoiceClips.bundled) {
            if let player = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue) {
                player.delegate = self
                player.prepareToPlay()
                self.player = player
                if player.play() {
                    VoiceLog.note("▶︎ \(line.text)")
                    timeout(after: player.duration + 2, id: id)
                    return
                }
                self.player = nil
                VoiceLog.note("✗ clips wouldn't start: \(line.text)")
            } else {
                VoiceLog.note("✗ clips unreadable: \(line.text)")
            }
        } else if let sessionError {
            VoiceLog.note("✗ audio session: \(sessionError)")
        } else {
            VoiceLog.note("… no clips for: \(line.text)")
        }

        // The system voice, whatever happened above; it worked before clips existed.
        let utterance = AVSpeechUtterance(string: line.text)
        utterance.voice = Self.systemVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.postUtteranceDelay = 0.1
        synth.speak(utterance)
        VoiceLog.note("▶︎ system voice: \(line.text)")
        timeout(after: Double(line.text.count) * 0.09 + 3, id: id)
    }

    /// If the cue hasn't reported finishing by then, assume it never will and move on.
    private func timeout(after seconds: TimeInterval, id: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.speaking, self.cueID == id else { return }
            VoiceLog.note("⚠︎ cue never finished; moving on")
            self.finishCurrent()
            self.next()
        }
    }

    private func finishCurrent() {
        player?.stop()
        player = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    private func interrupted() {
        guard speaking else { return }
        VoiceLog.note("⚠︎ audio interrupted; \(queue.count) cue(s) dropped")
        queue.removeAll()
        finishCurrent()
        speaking = false
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
        if !flag { VoiceLog.note("✗ playback ended early") }
        next()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard self.player === player else { return }
        VoiceLog.note("✗ decode error: \(error?.localizedDescription ?? "unknown")")
        self.player = nil
        next()
    }
}

extension VoiceCoach: AVSpeechSynthesizerDelegate {
    // The synthesizer doesn't promise which thread it calls back on.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.speaking, self.player == nil else { return }
            self.next()
        }
    }
}
