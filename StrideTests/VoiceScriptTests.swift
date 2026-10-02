import Testing
import Foundation
import AVFoundation
@testable import Stride

/// The coach's cues are stitched from recorded clips. These check that everything the
/// app can say has a clip in the list `Tools/render_voice.py` records.
struct VoiceScriptTests {
    static let recorded: Set<String> = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("StrideWatch/Voice/manifest.json")
        let manifest = try! JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        return Set(manifest.keys)
    }()

    /// Clips the line needs that aren't recorded; nil clips means it has an unrecorded part.
    static func missing(_ line: VoiceLine) -> [String] {
        guard let clips = line.clips else { return ["<unrecorded: \(line.text)>"] }
        return clips.map(\.name).filter { !recorded.contains($0) }
    }

    @Test func everyPlannedWorkoutCanBeSpoken() {
        for profile in PlanGeneratorTests.grid {
            let plan = PlanGeneratorTests.plan(profile)
            for workout in plan.allDays.flatMap(\.workouts) where workout.type.isRun {
                #expect(Self.missing(VoiceScript.start(workout)).isEmpty, "\(workout.title): \(Self.missing(VoiceScript.start(workout)))")
                for segment in workout.segments {
                    #expect(Self.missing(VoiceScript.segment(segment)).isEmpty, "\(workout.title) / \(segment.name): \(Self.missing(VoiceScript.segment(segment)))")
                }
            }
        }
    }

    @Test func everyPaceSplitAndFinishCanBeSpoken() {
        let target = PaceRange(fast: 698, slow: 753)
        for seconds in stride(from: 240, to: 1800, by: 1) {
            let pace = Double(seconds)
            #expect(Self.missing(VoiceScript.nudge(.slowDown, current: pace, target: target)).isEmpty, "\(seconds)")
            #expect(Self.missing(VoiceScript.nudge(.speedUp, current: 700, target: PaceRange(fast: pace, slow: pace + 30 < 1800 ? pace + 30 : pace))).isEmpty, "\(seconds)")
            #expect(Self.missing(VoiceScript.split(mile: 1 + seconds % 30, seconds: pace)).isEmpty, "\(seconds)")
        }
        for tenths in 1...309 {
            for seconds in [59.0, 600, 754, 3599, 3600, 3725, 14_400] {
                let line = VoiceScript.complete(meters: Units.meters(miles: Double(tenths) / 10), seconds: seconds)
                #expect(Self.missing(line).isEmpty, "\(tenths) tenths, \(seconds)s: \(Self.missing(line))")
            }
        }
        for line in [VoiceScript.onPace, VoiceScript.paused, VoiceScript.resuming] {
            #expect(Self.missing(line).isEmpty)
        }
    }

    @Test func freeRunSkipsTheSegmentName() {
        let free = Workout(type: .easy, title: "Free run", summary: "",
                           segments: [Segment(kind: .work, name: "Run", goal: .open, pace: PaceRange(fast: 698, slow: 753))], plannedMeters: 0)
        let line = VoiceScript.start(free)
        #expect(line.text == "Free run. Target 11 38 to 12 33.")
        #expect(line.clips?.map(\.name) == ["w_free", "target", "pm_11", "ps_38", "to", "pm_12", "ps_33"])
    }

    @Test func cuesReadTheWayARunnerWouldSayThem() {
        let nudge = VoiceScript.nudge(.slowDown, current: 655, target: PaceRange(fast: 698, slow: 753))
        #expect(nudge.text == "Slow down. You're at 10 55. Target 11 38 to 12 33.")
        #expect(VoiceScript.split(mile: 3, seconds: 545).text == "Mile 3. 9 oh 5.")
        #expect(VoiceScript.split(mile: 3, seconds: 480).text == "Mile 3. 8 flat.")
        #expect(VoiceScript.complete(meters: Units.meters(miles: 3.1), seconds: 2172).text == "Workout complete. 3.1 miles. 36 minutes, 12 seconds.")
        #expect(VoiceScript.complete(meters: Units.meters(miles: 13.1), seconds: 7500).text == "Workout complete. 13.1 miles. 2 hours, 5 minutes.")
        let rep = Segment(kind: .work, name: "Rep 2 of 6", goal: .distance(400), pace: nil)
        #expect(VoiceScript.segment(rep).text == "Rep 2 of 6. 400 meters.")
        #expect(VoiceScript.segment(Segment(kind: .recovery, name: "Recover", goal: .time(90), pace: nil)).text == "Recover. 90 seconds.")
    }

    @Test func aCueWithNoRecordingFallsBackWhole() {
        // A 35-minute mile has no clip: the whole line goes to the system voice.
        let slow = VoiceScript.split(mile: 2, seconds: 35 * 60)
        #expect(slow.clips == nil)
        #expect(slow.text == "Mile 2. 35 flat.")
        let odd = Segment(kind: .work, name: "Strides", goal: .time(60), pace: nil)
        #expect(VoiceScript.segment(odd).clips == nil)
    }

    // MARK: - Stitching

    /// Writes a short tone as mono AAC, the format the real clips are in.
    static func writeClip(_ name: String, seconds: Double, in folder: URL) throws {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: VoiceClips.sampleRate, AVNumberOfChannelsKey: 1]
        let file = try AVAudioFile(forWriting: folder.appendingPathComponent(name + ".m4a"), settings: settings)
        let frames = AVAudioFrameCount(VoiceClips.sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            buffer.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 440 / VoiceClips.sampleRate)) * 0.3
        }
        try file.write(from: buffer)
    }

    @Test func clipsAreJoinedIntoOnePlayableRecording() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let line = VoiceScript.split(mile: 3, seconds: 702) // mile_3, pm_11, ps_42

        // Nothing recorded yet: no audio, so the watch uses the system voice.
        #expect(VoiceClips.recording(of: line, in: folder) == nil)
        try Self.writeClip("mile_3", seconds: 0.6, in: folder)
        try Self.writeClip("pm_11", seconds: 0.4, in: folder)
        // Still one clip short.
        #expect(VoiceClips.recording(of: line, in: folder) == nil)
        try Self.writeClip("ps_42", seconds: 0.5, in: folder)

        let data = try #require(VoiceClips.recording(of: line, in: folder))
        let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
        // 1.5 s of clips plus the pauses between and after them (0.3 + 0.02 + 0.3).
        #expect(abs(player.duration - 2.12) < 0.15, "\(player.duration)")
        #expect(player.format.sampleRate == VoiceClips.sampleRate && player.format.channelCount == 1)
    }
}
