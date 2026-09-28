import Foundation
import HealthKit

/// Pulls running workouts she recorded with something other than Stride (the built-in
/// Workout app, a treadmill, another watch app) so they count toward the plan.
@MainActor
enum HealthImporter {
    private static let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static func requestPermission() async -> Bool {
        guard isAvailable else { return false }
        let read: Set<HKObjectType> = [HKObjectType.workoutType(), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.heartRate)]
        do {
            try await store.requestAuthorization(toShare: [], read: read)
            return true
        } catch {
            return false
        }
    }

    private static var importing = false

    /// Imports new running workouts since the plan started. Returns how many were added.
    @discardableResult
    static func importRuns(into appStore: AppStore) async -> Int {
        guard isAvailable, let plan = appStore.plan, let planStart = plan.startDate else { return 0 }
        // The permission sheet flips scenePhase, which can start a second import mid-flight.
        guard !importing else { return 0 }
        importing = true
        defer { importing = false }

        // Only look back as far as needed: a day before the newest import, or the plan start.
        let newestImport = appStore.activities.filter { $0.healthKitID != nil }.map(\.date).max()
        let start = newestImport.map { max(planStart, $0.addingTimeInterval(-86400)) } ?? planStart

        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: [])
        let running = HKQuery.predicateForWorkouts(with: .running)
        let combined = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, running])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let workouts: [HKWorkout] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: combined, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }

        var added = 0
        for w in workouts {
            // Stride's own watch recordings already arrive via WatchConnectivity.
            if w.sourceRevision.source.bundleIdentifier.hasPrefix("co.nsgsolutions.Stride") { continue }
            if appStore.activities.contains(where: { $0.healthKitID == w.uuid }) { continue }
            let meters = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
            guard w.duration > 60 else { continue }
            let hr = w.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))

            // Credit the first undone run planned for that day, if there is one.
            let planned = plan.day(on: w.startDate)?.workouts.first {
                $0.type.isRun && !appStore.isCompleted($0) && !plan.isSkipped($0)
            }
            let record = ActivityRecord(
                date: w.startDate,
                type: planned?.type ?? .easy,
                plannedWorkoutID: planned?.id,
                durationSeconds: w.duration,
                meters: meters,
                averageHeartRate: hr,
                notes: "Imported from \(w.sourceRevision.source.name)",
                healthKitID: w.uuid
            )
            appStore.record(record)
            added += 1
        }
        return added
    }
}
