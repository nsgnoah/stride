import SwiftUI

struct SummaryView: View {
    @Environment(AppStore.self) private var store
    @Environment(WorkoutManager.self) private var manager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let run = manager.completed {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: manager.workout?.title ?? "Run", symbol: "checkmark.circle.fill", color: .jade)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Units.miles(run.meters).formatted(.number.precision(.fractionLength(2))))
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                            Text("miles").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 14) {
                            WatchStat("Time", Formatting.duration(run.durationSeconds))
                            WatchStat("Pace", run.averagePace?.formatted ?? "--")
                            if let hr = run.averageHeartRate { WatchStat("Bpm", "\(Int(hr))") }
                        }
                    }
                    .inkCard(glow: .jade)

                    if !run.splits.isEmpty {
                        Eyebrow(text: "Splits")
                        ForEach(run.splits, id: \.mile) { split in
                            row("Mile \(split.mile)", Formatting.duration(split.seconds))
                        }
                    }
                    if let post = RoutineLibrary.routine(manager.workout?.postRoutineID) {
                        Eyebrow(text: "Cool down", color: .init(hex: 0x35B8C4))
                        ForEach(post.exercises) { ex in
                            HStack {
                                Text(ex.name).font(.footnote)
                                Spacer()
                                Text(ex.dose).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        store.record(run)
                        Connectivity.shared.send(activity: run)
                        manager.discard()
                    } label: {
                        Text("Save").fontWeight(.semibold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.ember)
                    Button("Discard", role: .destructive) { manager.discard() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Done")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.footnote)
    }
}
