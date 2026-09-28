import SwiftUI

/// Two pages: the coaching screen (default) and controls. Swipe left for controls.
struct ActiveWorkoutView: View {
    @Environment(WorkoutManager.self) private var manager
    @State private var page = 1

    var body: some View {
        TabView(selection: $page) {
            ControlsView().tag(0)
            CoachingView().tag(1)
        }
        .tabViewStyle(.verticalPage)
        .navigationBarBackButtonHidden()
    }
}

struct CoachingView: View {
    @Environment(WorkoutManager.self) private var manager

    var body: some View {
        VStack(spacing: 6) {
            // Segment header
            HStack {
                Text(manager.segment?.name ?? "Run")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(manager.segment?.kind.tint ?? .primary)
                    .lineLimit(1)
                Spacer()
                Text(manager.segmentRemainingText)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 10) // clear the page-indicator dots
            }

            if let progress = manager.segmentProgress {
                ProgressView(value: progress)
                    .tint(manager.segment?.kind.tint ?? .accentColor)
            }

            Spacer(minLength: 0)

            // The big number: current pace, colored by whether she's on target.
            Text(manager.currentPace?.formatted ?? "--:--")
                .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(paceColor)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)

            if let target = manager.segment?.pace {
                VStack(spacing: 1) {
                    Text(coachingText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(paceColor)
                    Text(target.formatted)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("no target · \(Formatting.miles(manager.distance, decimals: 2))")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                metric(Formatting.duration(manager.elapsed), "time")
                Spacer()
                metric(Formatting.miles(manager.distance, decimals: 2), "dist")
                Spacer()
                metric(manager.heartRate.map { "\(Int($0))" } ?? "--", "bpm")
            }
        }
        .padding(.horizontal, 6)
        .overlay(alignment: .top) {
            if manager.phase == .paused {
                Text("PAUSED").font(.caption2.bold()).padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.yellow, in: Capsule()).foregroundStyle(.black)
                    .offset(y: -18)
            }
        }
    }

    private var paceColor: Color {
        switch manager.coaching {
        case .speedUp: .orange
        case .slowDown: .blue
        case .onPace: .green
        case .none: .primary
        }
    }

    private var coachingText: String {
        switch manager.coaching {
        case .speedUp: "▲ Speed up"
        case .slowDown: "▼ Slow down"
        case .onPace: "✓ On pace"
        case .none: "Target"
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.footnote.monospacedDigit().weight(.medium))
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

struct ControlsView: View {
    @Environment(WorkoutManager.self) private var manager

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                controlButton(manager.phase == .paused ? "play.fill" : "pause.fill",
                              manager.phase == .paused ? "Resume" : "Pause", .yellow) {
                    manager.togglePause()
                }
                controlButton("xmark", "End", .red) { manager.end() }
            }
            controlButton("forward.end.fill", manager.nextSegment.map { "Next: \($0.name)" } ?? "Finish", .blue) {
                manager.advanceSegment()
            }
        }
        .padding(.horizontal, 6)
    }

    private func controlButton(_ symbol: String, _ label: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(label).font(.caption2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }
}

extension Segment.Kind {
    var tint: Color {
        switch self {
        case .warmup: .yellow
        case .work: .orange
        case .recovery: .blue
        case .cooldown: .teal
        }
    }
}
