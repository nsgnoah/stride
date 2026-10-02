import Foundation

/// One spoken cue, built from short parts. Each part names the recorded clips that say
/// it and carries the same words as text, so the watch can fall back to the system
/// voice when a clip isn't bundled.
///
/// Clip names here must match `Tools/render_voice.py`, which records them. The tests
/// sweep every cue the app can produce and check each clip is in the manifest.
struct VoiceLine: Equatable {
    struct Part: Equatable {
        /// Clip names, played back to back.
        var clips: [String]
        /// The same words for the system voice.
        var text: String
        /// Silence after the part, in seconds.
        var pause: TimeInterval = 0.3

        /// A part with no recording: forces the whole line onto the system voice.
        static func unrecorded(_ text: String) -> Part { Part(clips: [], text: text) }
    }

    var parts: [Part]

    var text: String { parts.map(\.text).joined(separator: " ") }

    /// Every clip in order, or nil if any part has no recording.
    var clips: [(name: String, pause: TimeInterval)]? {
        var out: [(String, TimeInterval)] = []
        for part in parts {
            guard !part.clips.isEmpty else { return nil }
            for (i, clip) in part.clips.enumerated() {
                out.append((clip, i == part.clips.count - 1 ? part.pause : 0.02))
            }
        }
        return out
    }
}

/// What the coach says, and when.
enum VoiceScript {
    enum Nudge { case speedUp, slowDown }

    // MARK: - Lines

    static func start(_ workout: Workout) -> VoiceLine {
        var parts = [title(of: workout)]
        if let first = workout.segments.first {
            // A free run is one open-ended segment; its name adds nothing.
            let isFreeRun = workout.segments.count == 1 && first.goal == .open
            parts += isFreeRun ? target(first.pace) : segment(first).parts
        }
        return VoiceLine(parts: parts)
    }

    static func segment(_ segment: Segment) -> VoiceLine {
        var parts = [name(of: segment)]
        switch segment.goal {
        case .time(let t): parts += duration(t)
        case .distance(let m): parts += distance(m)
        case .open: break
        }
        return VoiceLine(parts: parts + target(segment.pace))
    }

    static func nudge(_ nudge: Nudge, current: Pace, target range: PaceRange) -> VoiceLine {
        let lead = nudge == .speedUp
            ? VoiceLine.Part(clips: ["speed_up"], text: "Speed up!")
            : VoiceLine.Part(clips: ["slow_down"], text: "Slow down.")
        return VoiceLine(parts: [lead, pace(current, clip: "at", text: "You're at %@.")] + target(range))
    }

    static let onPace = VoiceLine(parts: [.init(clips: ["on_pace"], text: "Nice, on pace!")])
    static let paused = VoiceLine(parts: [.init(clips: ["paused"], text: "Paused.")])
    static let resuming = VoiceLine(parts: [.init(clips: ["resuming"], text: "Resuming. Let's go!")])

    static func split(mile: Int, seconds: TimeInterval) -> VoiceLine {
        let marker = (1...30).contains(mile)
            ? VoiceLine.Part(clips: ["mile_\(mile)"], text: "Mile \(mile).")
            : .unrecorded("Mile \(mile).")
        return VoiceLine(parts: [marker] + duration(seconds, exact: true))
    }

    static func complete(meters: Double, seconds: TimeInterval) -> VoiceLine {
        let done = VoiceLine.Part(clips: ["complete"], text: "Workout complete! Great job.")
        return VoiceLine(parts: [done] + distance(meters) + duration(seconds, exact: true))
    }

    // MARK: - Pieces

    private static func title(of workout: Workout) -> VoiceLine.Part {
        if workout.segments.count == 1, workout.segments[0].goal == .open, workout.type != .race {
            return .init(clips: ["w_free"], text: "Free run.")
        }
        switch workout.type {
        case .easy: return .init(clips: ["w_easy"], text: "Easy run.")
        // One run a week is titled "Run 3 mi": nothing for it to be long relative to.
        case .long: return workout.title.hasPrefix("Long")
            ? .init(clips: ["w_long"], text: "Long run.")
            : .init(clips: ["w_run"], text: "Today's run.")
        case .tempo: return .init(clips: ["w_tempo"], text: "Tempo run.")
        case .intervals: return .init(clips: ["w_intervals"], text: "Intervals.")
        case .shakeout: return .init(clips: ["w_shakeout"], text: "Shakeout run.")
        case .race: return .init(clips: ["w_race"], text: "Race day!")
        case .strength, .mobility, .rest: return .unrecorded("Starting \(workout.title).")
        }
    }

    private static let segmentNames: [String: String] = [
        "Walk & drills": "seg_walk_drills",
        "Easy run": "w_easy",
        "Long run": "w_long",
        "Run": "seg_run",
        "Walk": "seg_walk",
        "Warm-up jog": "seg_warmup_jog",
        "Cool-down jog": "seg_cooldown_jog",
        "Tempo": "seg_tempo",
        "Recover": "seg_recover",
        "Easy jog": "seg_easy_jog",
        "5K": "g_5k",
        "10K": "g_10k",
        "Half Marathon": "g_half",
        "Marathon": "g_marathon",
    ]

    private static func name(of segment: Segment) -> VoiceLine.Part {
        let spoken = segment.name.replacingOccurrences(of: "&", with: "and") + "."
        if let clip = segmentNames[segment.name] {
            return .init(clips: [clip], text: spoken)
        }
        // "Rep 3 of 8"
        let words = segment.name.split(separator: " ")
        if words.count == 4, words[0] == "Rep", words[2] == "of",
           let i = Int(words[1]), let n = Int(words[3]), (3...8).contains(n), (1...n).contains(i) {
            return .init(clips: ["rep_\(i)_\(n)"], text: spoken)
        }
        return .unrecorded(spoken)
    }

    private static func target(_ range: PaceRange?) -> [VoiceLine.Part] {
        guard let range else { return [] }
        return [
            pace(range.fast, clip: "tg", text: "Target %@", pause: 0.06),
            pace(range.slow, clip: "to", text: "to %@."),
        ]
    }

    /// "11:05" → "11 oh 5", "9:40" → "9 40", "8:00" → "8 flat". The system voice reads
    /// those as a runner would say them.
    static func spoken(_ pace: Pace) -> String {
        let total = Int(pace.rounded())
        let m = total / 60, s = total % 60
        if s == 0 { return "\(m) flat" }
        return s < 10 ? "\(m) oh \(s)" : "\(m) \(s)"
    }

    /// Paces are spoken to the nearest five seconds — GPS pace isn't steadier than that —
    /// and each is recorded as a whole phrase ("You're at eleven ten.") so nothing is
    /// spliced mid-breath. Recorded from 4:00 to 19:55 a mile.
    private static func pace(_ pace: Pace, clip: String, text: String, pause: TimeInterval = 0.3) -> VoiceLine.Part {
        guard pace.isFinite, pace > 0, pace < 3600 else { return .unrecorded(String(format: text, "an unknown pace")) }
        let seconds = Int((pace / 5).rounded()) * 5
        let words = String(format: text, spoken(Double(seconds)))
        guard (240...1195).contains(seconds) else { return .unrecorded(words) }
        return .init(clips: ["\(clip)_\(seconds)"], text: words, pause: pause)
    }

    private static func distance(_ meters: Double) -> [VoiceLine.Part] {
        // Track distances are said in meters.
        let whole = Int(meters.rounded())
        if [200, 400, 600, 800, 1000, 1200, 1600].contains(whole), abs(meters - Double(whole)) < 0.5 {
            return [.init(clips: ["m_\(whole)"], text: "\(whole) meters.")]
        }
        let tenths = Int((Units.miles(meters) * 10).rounded())
        let n = tenths / 10, t = tenths % 10
        let text = t == 0 ? "\(n) \(n == 1 ? "mile" : "miles")." : "\(n).\(t) miles."
        switch tenths {
        case ..<1: return []
        // Every tenth up to 30.9 miles is its own clip.
        case 1...309: return [.init(clips: ["mi_\(tenths)"], text: text)]
        default: return [.unrecorded(text)]
        }
    }

    /// `exact` keeps the seconds (a finish time); otherwise a goal like "8 minutes".
    private static func duration(_ seconds: TimeInterval, exact: Bool = false) -> [VoiceLine.Part] {
        let total = Int(seconds.rounded())
        if total == 90, !exact { return [.init(clips: ["sec_90"], text: "90 seconds.")] }
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        var parts: [VoiceLine.Part] = []
        if h > 0 {
            let text = "\(h) \(h == 1 ? "hour" : "hours"),"
            parts.append((1...6).contains(h) ? .init(clips: ["hr_\(h)"], text: text, pause: 0.1) : .unrecorded(text))
        }
        if m > 0 {
            // "Eleven minutes," leading into the seconds is recorded separately from "Eleven minutes."
            let leadsOn = h == 0 && s > 0
            parts.append(.init(clips: [leadsOn ? "minc_\(m)" : "min_\(m)"], text: "\(m) \(m == 1 ? "minute" : "minutes")\(leadsOn ? "," : ".")", pause: leadsOn ? 0.08 : 0.3))
        }
        // Past an hour, seconds are noise.
        if h == 0, s > 0 {
            parts.append(.init(clips: ["sec_\(s)"], text: "\(s) \(s == 1 ? "second" : "seconds")."))
        }
        return parts
    }
}
