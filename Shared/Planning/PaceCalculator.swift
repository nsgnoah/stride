import Foundation

/// Turns one recent effort into a full set of training paces.
///
/// Uses the Riegel formula to predict race times at other distances, then anchors
/// training zones off those predictions the way most coaches do:
///   - threshold/tempo ≈ pace you could hold for about an hour
///   - intervals ≈ 3K–5K effort
///   - easy ≈ 60–90 s/mi slower than threshold
enum PaceCalculator {
    /// Riegel: T2 = T1 × (D2 / D1)^1.06
    static func predictedTime(forMeters target: Double, fromMeters d1: Double, seconds t1: TimeInterval) -> TimeInterval {
        guard d1 > 0, t1 > 0 else { return 0 }
        return t1 * pow(target / d1, 1.06)
    }

    static func predictedPace(forMeters target: Double, fromMeters d1: Double, seconds t1: TimeInterval) -> Pace {
        predictedTime(forMeters: target, fromMeters: d1, seconds: t1) / Units.miles(target)
    }

    static func profile(for runner: RunnerProfile) -> PaceProfile {
        let d1 = runner.recentRunMeters
        let t1 = runner.recentRunSeconds

        let racePace = predictedPace(forMeters: runner.goal.meters, fromMeters: d1, seconds: t1)
        // ~1 hour race effort is a solid threshold anchor for recreational runners.
        let thresholdPace = predictedPace(forMeters: Units.meters(miles: 10), fromMeters: d1, seconds: t1) * 0.99
        let intervalPace = predictedPace(forMeters: 3000, fromMeters: d1, seconds: t1)

        let easyCenter = thresholdPace + 80
        return PaceProfile(
            easy: PaceRange(fast: easyCenter - 20, slow: easyCenter + 35),
            long: PaceRange(fast: easyCenter - 10, slow: easyCenter + 40),
            tempo: PaceRange(center: thresholdPace, tolerance: 10),
            interval: PaceRange(center: intervalPace, tolerance: 8),
            race: PaceRange(fast: racePace - 8, slow: racePace + 8)
        )
    }
}
