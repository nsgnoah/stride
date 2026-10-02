import AVFoundation

/// Joins the coach's recorded clips into one piece of audio for a cue.
enum VoiceClips {
    /// Every clip is recorded as mono AAC at this rate (see `Tools/render_voice.py`).
    static let sampleRate = 44_100.0

    /// Where the clips live in the app.
    static var bundled: URL? { Bundle.main.resourceURL?.appendingPathComponent("Voice") }

    /// The line as one WAV, clips joined with their pauses; nil unless every clip is there.
    static func recording(of line: VoiceLine, in folder: URL?) -> Data? {
        guard let folder, let clips = line.clips, !clips.isEmpty else { return nil }
        var samples = Data()
        for clip in clips {
            guard let pcm = pcm(at: folder.appendingPathComponent(clip.name + ".m4a")) else { return nil }
            samples.append(pcm)
            samples.append(Data(count: Int(sampleRate * clip.pause) * 2))
        }
        return wav(samples)
    }

    /// A clip decoded to 16-bit mono at `sampleRate`.
    private static func pcm(at url: URL) -> Data? {
        guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true),
              file.processingFormat.sampleRate == sampleRate, file.processingFormat.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.int16ChannelData else { return nil }
        return Data(bytes: channel[0], count: Int(buffer.frameLength) * 2)
    }

    private static func wav(_ samples: Data) -> Data {
        func le<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        let rate = UInt32(sampleRate)
        var data = Data("RIFF".utf8) + le(UInt32(36 + samples.count)) + Data("WAVEfmt ".utf8)
        data += le(UInt32(16)) + le(UInt16(1)) + le(UInt16(1)) + le(rate) + le(rate * 2) + le(UInt16(2)) + le(UInt16(16))
        data += Data("data".utf8) + le(UInt32(samples.count))
        return data + samples
    }
}
