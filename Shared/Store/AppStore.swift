import Foundation
import Observation
import WidgetKit

/// Single source of truth on each device. Saved as JSON in the app's documents folder.
/// The phone owns the plan; the watch owns run records until they're synced over.
@Observable
@MainActor
final class AppStore {
    var profile: RunnerProfile?
    var plan: TrainingPlan?
    var activities: [ActivityRecord] = []
    /// Hour of the morning reminder on run days; nil when reminders are off.
    /// Set via `setReminderHour` so loading a snapshot never triggers a save.
    private(set) var reminderHour: Int?
    /// Phone only, not saved: when the watch last confirmed it holds the current plan.
    var watchConfirmedPlanAt: Date?
    /// She chose to skip the plan and just track runs. Cleared when a plan is built.
    private(set) var freeMode: Bool = false

    func setFreeMode(_ on: Bool) {
        freeMode = on
        save()
    }

    /// Stop following the plan but keep every logged run. The app drops into free-run mode.
    func dropPlan() {
        plan = nil
        freeMode = true
        save()
    }

    /// Watch side of a plan being removed on the phone: forget the plan, keep local runs.
    func clearPlan() {
        plan = nil
        save()
    }

    /// Spoken coaching on the watch (through connected headphones). On by default.
    private(set) var voiceCues: Bool = true

    func setVoiceCues(_ on: Bool) {
        voiceCues = on
        save()
    }

    func setReminderHour(_ hour: Int?) {
        reminderHour = hour
        save()
    }

    private let url: URL

    struct Snapshot: Codable {
        var profile: RunnerProfile?
        var plan: TrainingPlan?
        var activities: [ActivityRecord]
        var reminderHour: Int?
        var voiceCues: Bool?
        var freeMode: Bool?
    }

    /// Workout ids that no longer need a reminder.
    var settledWorkoutIDs: Set<UUID> {
        Set(activities.compactMap(\.plannedWorkoutID)).union(plan?.skipped ?? [])
    }

    /// Shared with the widget extension. Falls back to Documents when the group isn't available.
    static let appGroup = "group.co.nsgsolutions.stride"

    init(filename: String = "stride.json") {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) {
            let shared = group.appendingPathComponent(filename)
            // One-time move of data saved before the app group existed.
            if !fm.fileExists(atPath: shared.path), fm.fileExists(atPath: docs.path) {
                try? fm.copyItem(at: docs, to: shared)
            }
            url = shared
        } else {
            url = docs
        }
        load()
    }

    // MARK: - Mutations

    /// Builds (or rebuilds) the plan. A rebuild keeps the original start so week numbers
    /// and finished workouts line up, and re-applies her skips and moved days.
    /// `fresh` starts over from today (the next goal after a finished plan).
    func createPlan(from profile: RunnerProfile, fresh: Bool = false) {
        self.profile = profile
        let previous = fresh ? nil : plan
        var newPlan = PlanGenerator(runner: profile, startDate: previous?.startDate ?? .now).makePlan()
        freeMode = false
        if let previous {
            newPlan.skipped = previous.skipped
            for (id, date) in previous.moves { newPlan.move(workoutID: id, to: date) }
        }
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
        freeMode = false
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

    /// Runs from the last week that were neither done nor skipped. Nothing once the race
    /// has happened — there's no plan day left to make them up on.
    var missedRuns: [(day: PlannedDay, workout: Workout)] {
        guard let plan else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard plan.raceDate >= today else { return [] }
        guard let since = cal.date(byAdding: .day, value: -7, to: today) else { return [] }
        return plan.allDays
            .filter { $0.date >= since && $0.date < today }
            .flatMap { day in
                day.workouts
                    .filter { $0.type.isRun && !isCompleted($0) && !plan.isSkipped($0) }
                    .map { (day, $0) }
            }
    }

    /// Activities since Monday of this calendar week — used when there's no plan.
    var activitiesThisCalendarWeek: [ActivityRecord] {
        let start = PlanGenerator.startOfWeek(.now)
        return activities.filter { $0.date >= start }
    }

    // MARK: - Persistence

    func save() {
        let snap = Snapshot(profile: profile, plan: plan, activities: activities, reminderHour: reminderHour, voiceCues: voiceCues, freeMode: freeMode)
        do {
            let data = try JSONEncoder().encode(snap)
            try data.write(to: url, options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
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
        voiceCues = snap.voiceCues ?? true
        freeMode = snap.freeMode ?? false
    }
}
