import Foundation

/// Distances in this app are stored in meters; the UI shows miles.
enum Units {
    static let metersPerMile = 1609.344

    static func miles(_ meters: Double) -> Double { meters / metersPerMile }
    static func meters(miles: Double) -> Double { miles * metersPerMile }
}

/// Pace is seconds per mile.
typealias Pace = Double

extension Pace {
    /// "8:45" style formatting.
    var formatted: String {
        guard isFinite, self > 0 else { return "--:--" }
        let total = Int(rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var formattedPerMile: String { formatted + " /mi" }
}

/// A target pace window, in seconds per mile. `fast` is the smaller number.
struct PaceRange: Codable, Hashable, Sendable {
    var fast: Pace
    var slow: Pace

    init(fast: Pace, slow: Pace) {
        self.fast = min(fast, slow)
        self.slow = max(fast, slow)
    }

    init(center: Pace, tolerance: Double) {
        self.init(fast: center - tolerance, slow: center + tolerance)
    }

    var midpoint: Pace { (fast + slow) / 2 }

    func contains(_ pace: Pace) -> Bool { pace >= fast && pace <= slow }

    var formatted: String { "\(fast.formatted)–\(slow.formatted) /mi" }
}

enum Formatting {
    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func minutes(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        return "\(m) min"
    }

    static func miles(_ meters: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f mi", Units.miles(meters))
    }
}
