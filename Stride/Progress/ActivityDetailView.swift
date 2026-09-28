import SwiftUI
import Charts

/// One recorded run (or lift): the numbers, the mile splits, and what it was supposed to be.
struct ActivityDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let activity: ActivityRecord
    @State private var confirmDelete = false

    private var planned: Workout? {
        activity.plannedWorkoutID.flatMap { store.plan?.workout(id: $0) }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 20) {
                    if activity.meters > 0 { stat("Distance", Formatting.miles(activity.meters, decimals: 2)) }
                    stat("Time", Formatting.duration(activity.durationSeconds))
                    if let pace = activity.averagePace { stat("Avg pace", pace.formatted) }
                    if let hr = activity.averageHeartRate { stat("Avg HR", "\(Int(hr))") }
                }
                .padding(.vertical, 4)
            } header: {
                Text(activity.date.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
            }

            if let planned {
                Section("Planned") {
                    NavigationLink(value: planned) { WorkoutRow(workout: planned) }
                    if let target = planned.mainPace, let pace = activity.averagePace {
                        LabeledContent("Target", value: target.formatted)
                        LabeledContent("Result", value: verdict(pace: pace, target: target))
                    }
                }
            }

            if activity.splits.count >= 1 {
                Section("Splits") {
                    if activity.splits.count >= 2 {
                        SplitsChart(splits: activity.splits, target: planned?.mainPace)
                            .frame(height: 160)
                            .padding(.vertical, 8)
                    }
                    ForEach(activity.splits, id: \.mile) { split in
                        LabeledContent("Mile \(split.mile)", value: Formatting.duration(split.seconds))
                            .monospacedDigit()
                    }
                }
            }

            if !activity.notes.isEmpty {
                Section("Notes") { Text(activity.notes) }
            }

            Section {
                Button("Delete this activity", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(activity.type.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this activity?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(activity)
                dismiss()
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
    }

    private func verdict(pace: Pace, target: PaceRange) -> String {
        if target.contains(pace) { return "On target" }
        let diff = Int(abs(pace - target.midpoint))
        return pace < target.fast ? "\(diff) s/mi fast" : "\(diff) s/mi slow"
    }
}

struct SplitsChart: View {
    let splits: [ActivityRecord.Split]
    let target: PaceRange?

    /// Minutes-per-mile window that frames both the splits and the target, with headroom.
    private var yDomain: ClosedRange<Double> {
        var values = splits.map(\.seconds)
        if let target { values += [target.fast, target.slow] }
        let lo = (values.min() ?? 0) - 45
        let hi = (values.max() ?? 0) + 60
        return (lo / 60)...(hi / 60)
    }

    var body: some View {
        Chart {
            if let target {
                RectangleMark(yStart: .value("Fast", target.fast / 60), yEnd: .value("Slow", target.slow / 60))
                    .foregroundStyle(.green.opacity(0.12))
            }
            ForEach(splits, id: \.mile) { split in
                BarMark(x: .value("Mile", Double(split.mile)), yStart: .value("Floor", yDomain.lowerBound), yEnd: .value("Pace", split.seconds / 60), width: .fixed(28))
                    .foregroundStyle(color(for: split.seconds))
                    .cornerRadius(4)
                    .annotation(position: .top) {
                        Text(Pace(split.seconds).formatted).font(.caption2).foregroundStyle(.secondary)
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: 0.4...(Double(splits.count) + 0.6))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let m = value.as(Double.self) { Text(Pace(m * 60).formatted) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: splits.map { Double($0.mile) }) { value in
                AxisValueLabel {
                    if let m = value.as(Double.self) { Text("\(Int(m))") }
                }
            }
        }
    }

    private func color(for seconds: TimeInterval) -> Color {
        guard let target else { return .accentColor }
        if target.contains(seconds) { return .green }
        return seconds < target.fast ? .blue : .orange
    }
}
