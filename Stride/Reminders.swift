import Foundation
import UserNotifications

/// A morning nudge on run days: "Today: Easy 3 mi · 11:38–12:33 /mi". Local only.
enum Reminders {
    private static let prefix = "stride.run."

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default: return false
        }
    }

    /// Replaces all pending run reminders with the next two weeks of the plan.
    static func reschedule(plan: TrainingPlan?, hour: Int?, skippedOrDone: Set<UUID>) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard let plan, let hour else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let horizon = cal.date(byAdding: .day, value: 14, to: today) else { return }

        for day in plan.allDays where day.date >= today && day.date < horizon {
            guard let run = day.workouts.first(where: { $0.type.isRun && !skippedOrDone.contains($0.id) }) else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: day.date)
            comps.hour = hour
            comps.minute = 0
            guard let fireDate = cal.date(from: comps), fireDate > .now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Today: \(run.title)"
            var lines: [String] = []
            if let pace = run.mainPace { lines.append(pace.formatted) }
            if let pre = RoutineLibrary.routine(run.preRoutineID) { lines.append("Start with \(pre.title.lowercased()).") }
            content.body = lines.joined(separator: " · ")
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: prefix + run.id.uuidString, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
