import Foundation

/// What the runner tells us during setup. Everything the planner needs.
struct RunnerProfile: Codable, Hashable, Sendable {
    var goal: GoalDistance = .tenK
    var raceDate: Date = Calendar.current.date(byAdding: .weekOfYear, value: 10, to: .now)!
    var runDaysPerWeek: Int = 4
    /// Days she lifts. Runs avoid these where possible; they show up in the week view.
    var strengthDays: Set<Weekday> = []
    /// Preferred long run day.
    var longRunDay: Weekday = .saturday
    /// Current weekly mileage, miles. Sets the starting volume.
    var currentWeeklyMiles: Double = 10
    /// A recent effort used to estimate fitness.
    var recentRunMeters: Double = Units.meters(miles: 3)
    var recentRunSeconds: TimeInterval = 30 * 60

    var weeksUntilRace: Int {
        PlanGenerator.weekCount(from: .now, to: raceDate)
    }
}

/// Something that actually happened: a run recorded on the watch, or a lift she logged.
struct ActivityRecord: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var date: Date
    var type: WorkoutType
    var plannedWorkoutID: UUID?
    var durationSeconds: TimeInterval
    var meters: Double
    var averageHeartRate: Double?
    var splits: [Split] = []
    var notes: String = ""

    var averagePace: Pace? {
        guard meters > 0 else { return nil }
        return durationSeconds / Units.miles(meters)
    }

    struct Split: Codable, Hashable, Sendable {
        var mile: Int
        var seconds: TimeInterval
    }
}
