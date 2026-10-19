import Foundation

/// Her bests across every recorded run: the longest, the fastest mile, the quickest run at
/// each goal distance, and the biggest week. Worked out fresh from the activity list, so
/// deleting a run (or importing one from Health) is reflected straight away.
struct PersonalBests: Equatable, Sendable {
    struct Record: Equatable, Sendable {
        /// The run that set it; nil for the biggest week, which belongs to no single run.
        var activityID: UUID?
        /// When it was set; for the biggest week, that week's Monday.
        var date: Date
        /// Meters for distances, seconds per mile for paces, seconds for the fastest mile.
        var value: Double
    }

    var longestRun: Record?
    var fastestMile: Record?
    /// Best average pace over a run at least this long.
    var fastestPace: [GoalDistance: Record] = [:]
    var biggestWeek: Record?

    /// GPS often comes up a few meters short of the real distance, so a run within 2% of a
    /// goal distance counts toward it.
    static let distanceTolerance = 0.98
    /// Anything quicker than this is a GPS jump, not a mile.
    static let fastestBelievableMile: TimeInterval = 180

    var isEmpty: Bool { longestRun == nil }

    init(activities: [ActivityRecord], calendar: Calendar = .current) {
        // Oldest first, so on a tie the run that set the record first keeps it.
        let runs = activities
            .filter { $0.type.isRun && $0.meters > 0 }
            .sorted { $0.date < $1.date }

        var weeks: [Date: Double] = [:]
        for run in runs {
            if run.meters > (longestRun?.value ?? 0) {
                longestRun = Record(activityID: run.id, date: run.date, value: run.meters)
            }
            for split in run.splits where split.seconds >= Self.fastestBelievableMile {
                if split.seconds < (fastestMile?.value ?? .infinity) {
                    fastestMile = Record(activityID: run.id, date: run.date, value: split.seconds)
                }
            }
            if let pace = run.averagePace, run.durationSeconds > 0 {
                for goal in GoalDistance.allCases where run.meters >= goal.meters * Self.distanceTolerance {
                    if pace < (fastestPace[goal]?.value ?? .infinity) {
                        fastestPace[goal] = Record(activityID: run.id, date: run.date, value: pace)
                    }
                }
            }
            weeks[PlanGenerator.startOfWeek(run.date, calendar: calendar), default: 0] += run.meters
        }
        if let best = weeks.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }) {
            biggestWeek = Record(activityID: nil, date: best.key, value: best.value)
        }
    }

    /// The records a run holds, in the order the Progress tab lists them.
    func titles(for activityID: UUID) -> [String] {
        var out: [String] = []
        if longestRun?.activityID == activityID { out.append("Longest run") }
        if fastestMile?.activityID == activityID { out.append("Fastest mile") }
        for goal in GoalDistance.allCases where fastestPace[goal]?.activityID == activityID {
            out.append(Self.fastestTitle(goal))
        }
        return out
    }

    static func fastestTitle(_ goal: GoalDistance) -> String {
        "Fastest \(goal.name) or longer"
    }
}
