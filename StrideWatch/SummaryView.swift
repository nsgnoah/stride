import SwiftUI

struct SummaryView: View {
    @Environment(AppStore.self) private var store
    @Environment(WorkoutManager.self) private var manager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let run = manager.completed {
                    Text(manager.workout?.title ?? "Run").font(.headline)
                    row("Distance", Formatting.miles(run.meters, decimals: 2))
                    row("Time", Formatting.duration(run.durationSeconds))
                    row("Avg pace", run.averagePace?.formattedPerMile ?? "--")
                    if let hr = run.averageHeartRate { row("Avg HR", "\(Int(hr)) bpm") }
                    if !run.splits.isEmpty {
                        Divider()
                        ForEach(run.splits, id: \.mile) { split in
                            row("Mile \(split.mile)", Formatting.duration(split.seconds))
                        }
                    }
                    if let post = RoutineLibrary.routine(manager.workout?.postRoutineID) {
                        Divider()
                        Text("Cool down").font(.footnote).foregroundStyle(.secondary)
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
                        Text("Save").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
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
