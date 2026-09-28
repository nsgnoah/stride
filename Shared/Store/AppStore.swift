import Foundation
import Observation

/// Single source of truth on each device. Saved as JSON in the app's documents folder.
/// The phone owns the plan; the watch owns run records until they're synced over.
@Observable
@MainActor
final class AppStore {
    var profile: RunnerProfile?
    var plan: TrainingPlan?
    var activities: [ActivityRecord] = []
    /// Hour of the morning reminder on run days; nil when reminders are off.
    var reminderHour: Int? {
        didSet { save() }
    }

    private let url: URL

    struct Snapshot: Codable {
        var profile: RunnerProfile?
        var plan: TrainingPlan?
        var activities: [ActivityRecord]
        var reminderHour: Int?
    }

    /// Workout ids that no longer need a reminder.
    var settledWorkoutIDs: Set<UUID> {
        Set(activities.compactMap(\.plannedWorkoutID)).union(plan?.skipped ?? [])
    }

    init(filename: String = "stride.json") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = dir.appendingPathComponent(filename)
        load()
    }

    // MARK: - Mutations

    func createPlan(from profile: RunnerProfile) {
        self.profile = profile
        // Rebuilding keeps the original start so week numbers and finished workouts line up.
        let start = plan?.startDate ?? .now
        var newPlan = PlanGenerator(runner: profile, startDate: start).makePlan()
        newPlan.skipped = plan?.skipped ?? []
        plan = newPlan
        save()
    }

    func skip(_ workout: Workout) {
        plan?.skipped.insert(workout.id)
        save()
    }

    func unskip(_ workout: Workout) {
        plan?.skipped.remove(workout.id)
        save()
    }

    func move(_ workout: Workout, to date: Date) {
        plan?.move(workoutID: workout.id, to: date)
        save()
    }

    func replacePlan(_ plan: TrainingPlan) {
        self.plan = plan
        save()
    }

    func record(_ activity: ActivityRecord) {
        if let idx = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[idx] = activity
        } else {
            activities.append(activity)
        }
        activities.sort { $0.date > $1.date }
        save()
    }

    func delete(_ activity: ActivityRecord) {
        activities.removeAll { $0.id == activity.id }
        save()
    }

    func reset() {
        profile = nil
        plan = nil
        activities = []
        save()
    }

    // MARK: - Queries

    var today: PlannedDay? { plan?.day(on: .now) }
    var thisWeek: PlannedWeek? { plan?.week(containing: .now) }

    func isCompleted(_ workout: Workout) -> Bool {
        activities.contains { $0.plannedWorkoutID == workout.id }
    }

    func activity(for workout: Workout) -> ActivityRecord? {
        activities.first { $0.plannedWorkoutID == workout.id }
    }

    func activities(in week: PlannedWeek) -> [ActivityRecord] {
        let cal = Calendar.current
        guard let end = cal.date(byAdding: .day, value: 7, to: week.startDate) else { return [] }
        return activities.filter { $0.date >= week.startDate && $0.date < end }
    }

    /// The next run that hasn't been done yet, starting today.
    var nextRun: (day: PlannedDay, workout: Workout)? {
        guard let plan else { return nil }
        let start = Calendar.current.startOfDay(for: .now)
        for day in plan.allDays where day.date >= start {
            if let w = day.workouts.first(where: { $0.type.isRun && !isCompleted($0) && !plan.isSkipped($0) }) {
                return (day, w)
            }
        }
        return nil
    }

    /// Runs from the last week that were neither done nor skipped.
    var missedRuns: [(day: PlannedDay, workout: Workout)] {
        guard let plan else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let since = cal.date(byAdding: .day, value: -7, to: today) else { return [] }
        return plan.allDays
            .filter { $0.date >= since && $0.date < today }
            .flatMap { day in
                day.workouts
                    .filter { $0.type.isRun && !isCompleted($0) && !plan.isSkipped($0) }
                    .map { (day, $0) }
            }
    }

    // MARK: - Persistence

    func save() {
        let snap = Snapshot(profile: profile, plan: plan, activities: activities, reminderHour: reminderHour)
        do {
            let data = try JSONEncoder().encode(snap)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Stride: save failed — \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        profile = snap.profile
        plan = snap.plan
        activities = snap.activities
        reminderHour = snap.reminderHour
    }
}
