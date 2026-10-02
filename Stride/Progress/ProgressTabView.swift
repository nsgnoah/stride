import SwiftUI
import Charts

struct ProgressTabView: View {
    @Environment(AppStore.self) private var store
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WeekCard()
                }

                if let plan = store.plan {
                    Section("Weekly miles — planned vs. run") {
                        MileageChart(plan: plan)
                            .frame(height: 220)
                            .padding(.vertical, 8)
                    }

                    if runs.count >= 2 {
                        Section("Easy-run pace over time") {
                            PaceChart(runs: runs, easyRange: plan.paces.easy)
                                .frame(height: 200)
                                .padding(.vertical, 8)
                        }
                    }

                }

                if store.plan == nil {
                    if runs.count >= 2 {
                        Section("Pace over time") {
                            PaceChart(runs: runs, easyRange: nil)
                                .frame(height: 200)
                                .padding(.vertical, 8)
                        }
                    }
                }

                Section {
                    if store.activities.isEmpty {
                        Text("Runs from the watch show up here.").foregroundStyle(.secondary)
                    }
                    ForEach(store.activities) { activity in
                        NavigationLink(value: activity) { ActivityRow(activity: activity) }
                    }
                    .onDelete { offsets in
                        for i in offsets { store.delete(store.activities[i]) }
                    }
                } header: {
                    Text("History")
                } footer: {
                    if let importMessage { Text(importMessage) }
                }

                if HealthImporter.isAvailable {
                    Section {
                        Button {
                            Task {
                                guard await HealthImporter.requestPermission() else { importMessage = "Health access is off for Stride."; return }
                                let n = await HealthImporter.importRuns(into: store)
                                importMessage = n == 0 ? "No new runs in Health." : "Imported \(n) run\(n == 1 ? "" : "s") from Health."
                            }
                        } label: {
                            Label("Import runs from Health", systemImage: "heart.text.square")
                        }
                    } footer: {
                        Text("Runs recorded with the Workout app or another tracker count toward the plan too.")
                    }
                }
            }
            .navigationTitle("Progress")
            .navigationDestination(for: ActivityRecord.self) { ActivityDetailView(activity: $0) }
            .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
        }
    }

    private var runs: [ActivityRecord] {
        store.activities.filter { $0.type.isRun && $0.meters > 400 }.sorted { $0.date < $1.date }
    }
}

/// This week at a glance: miles run against the plan, and what else got done.
struct WeekCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let week = store.thisWeek
        let acts = week.map { store.activities(in: $0) } ?? store.activitiesThisCalendarWeek
        let runs = acts.filter { $0.type.isRun }
        let miles = Units.miles(runs.reduce(0) { $0 + $1.meters })
        let planned = week.map { Units.miles($0.plannedMeters) }

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CardEyebrow(text: "This week")
                Spacer()
                if let week, let total = store.plan?.weeks.count {
                    Text("Week \(week.number) of \(total)").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.6))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(miles.formatted(.number.precision(.fractionLength(1))))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                Text(planned.map { "of \($0.formatted(.number.precision(.fractionLength(0...1)))) miles" } ?? "miles")
                    .font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
            }
            if let planned, planned > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule().fill(.stride).frame(width: max(8, geo.size.width * min(1, miles / planned)))
                            .opacity(miles > 0 ? 1 : 0)
                    }
                }
                .frame(height: 8)
            }
            HStack(spacing: 22) {
                CardStat("Runs", week.map { "\(runs.count) of \($0.runCount)" } ?? "\(runs.count)")
                CardStat("Time", Formatting.duration(acts.reduce(0) { $0 + $1.durationSeconds }))
                CardStat("Lifts", "\(acts.filter { $0.type == .strength }.count)")
                CardStat("Mobility", "\(acts.filter { $0.type == .mobility }.count)")
            }
        }
        .inkCard(glow: .ember)
    }
}

struct MileageChart: View {
    @Environment(AppStore.self) private var store
    let plan: TrainingPlan

    var body: some View {
        Chart {
            ForEach(plan.weeks) { week in
                BarMark(x: .value("Week", week.number), y: .value("Planned", Units.miles(week.plannedMeters)))
                    .foregroundStyle(Color(.tertiarySystemFill))
                let actual = store.activities(in: week).filter { $0.type.isRun }.reduce(0) { $0 + $1.meters }
                if actual > 0 {
                    BarMark(x: .value("Week", week.number), y: .value("Run", Units.miles(actual)))
                        .foregroundStyle(.tint)
                }
            }
            if let current = store.thisWeek {
                RuleMark(x: .value("Now", current.number))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
        }
        .chartXAxisLabel("Week")
        .chartYAxisLabel("mi")
    }
}

struct PaceChart: View {
    let runs: [ActivityRecord]
    let easyRange: PaceRange?

    var body: some View {
        Chart {
            if let easyRange {
                RectangleMark(yStart: .value("Fast", easyRange.fast / 60), yEnd: .value("Slow", easyRange.slow / 60))
                    .foregroundStyle(Color.jade.opacity(0.12))
            }
            ForEach(runs) { run in
                if let pace = run.averagePace {
                    LineMark(x: .value("Date", run.date), y: .value("Pace", pace / 60))
                        .foregroundStyle(.tint)
                    PointMark(x: .value("Date", run.date), y: .value("Pace", pace / 60))
                        .foregroundStyle(run.type.tint)
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false, reversed: true))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let m = value.as(Double.self) { Text(Pace(m * 60).formatted) }
                }
            }
        }
        .chartYAxisLabel("min/mi (faster ↑)")
    }
}

struct ActivityRow: View {
    let activity: ActivityRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.type.symbol).foregroundStyle(activity.type.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.type.name).font(.headline)
                Text(activity.date.formatted(.dateTime.weekday().month().day())).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if activity.meters > 0 {
                    Text(Formatting.miles(activity.meters, decimals: 2)).font(.headline)
                    if let pace = activity.averagePace { Text(pace.formattedPerMile).font(.caption).foregroundStyle(.secondary) }
                } else if activity.durationSeconds > 0 {
                    Text(Formatting.minutes(activity.durationSeconds)).font(.headline)
                } else {
                    Image(systemName: "checkmark").foregroundStyle(Color.jade)
                }
            }
        }
    }
}
