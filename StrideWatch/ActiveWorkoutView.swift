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
                if let split = manager.lastSplit, Date.now < manager.splitBannerUntil {
                    Eyebrow(text: "Mile \(split.mile) · \(Formatting.duration(split.seconds))", color: .gold)
                        .transition(.opacity)
                } else {
                    Eyebrow(text: manager.segment?.name ?? "Run", color: manager.segment?.kind.tint ?? .ember)
                }
                Spacer()
                Text(manager.segmentRemainingText)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 10) // clear the page-indicator dots
            }

            if let progress = manager.segmentProgress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule().fill(.stride).frame(width: max(5, geo.size.width * min(1, max(0, progress))))
                    }
                }
                .frame(height: 5)
            }

            Spacer(minLength: 0)

            // The big number: current pace, colored by whether she's on target.
            Text(manager.currentPace?.formatted ?? "--:--")
                .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(paceColor)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)

            if let target = manager.segment?.pace {
                VStack(spacing: 3) {
                    Label(coachingText, systemImage: coachingSymbol)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(glowColor.opacity(0.22), in: Capsule())
                        .foregroundStyle(manager.coaching == .none ? Color.secondary : paceColor)
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
                WatchStat("Time", Formatting.duration(manager.elapsed))
                Spacer()
                WatchStat("Dist", Formatting.miles(manager.distance, decimals: 2))
                Spacer()
                WatchStat("Bpm", manager.heartRate.map { "\(Int($0))" } ?? "--")
            }
        }
        .padding(.horizontal, 6)
        // The glow says the same thing as the number: on pace, too fast, too slow.
        .glow(glowColor)
        .animation(.easeInOut(duration: 0.6), value: manager.coaching)
        .overlay(alignment: .top) {
            if manager.phase == .paused {
                Text(manager.autoPaused ? "AUTO-PAUSED" : "PAUSED").font(.caption2.bold()).padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.gold, in: Capsule()).foregroundStyle(.black)
                    .offset(y: -18)
            }
        }
    }

    private var paceColor: Color {
        switch manager.coaching {
        case .speedUp: .amber
        case .slowDown: .azure
        case .onPace: .jade
        case .none: .primary
        }
    }

    private var glowColor: Color {
        manager.coaching == .none ? (manager.segment?.kind.tint ?? .ember) : paceColor
    }

    private var coachingText: String {
        switch manager.coaching {
        case .speedUp: "Speed up"
        case .slowDown: "Slow down"
        case .onPace: "On pace"
        case .none: "Target"
        }
    }

    private var coachingSymbol: String {
        switch manager.coaching {
        case .speedUp: "arrow.up"
        case .slowDown: "arrow.down"
        case .onPace: "checkmark"
        case .none: "scope"
        }
    }
}

struct ControlsView: View {
    @Environment(WorkoutManager.self) private var manager

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                controlButton(manager.phase == .paused ? "play.fill" : "pause.fill",
                              manager.phase == .paused ? "Resume" : "Pause", .gold) {
                    manager.togglePause()
                }
                controlButton("xmark", "End", .red) { manager.end() }
            }
            controlButton("forward.end.fill", manager.nextSegment.map { "Next: \($0.name)" } ?? "Finish", .azure) {
                manager.advanceSegment()
            }
        }
        .padding(.horizontal, 6)
        .glow(.ember)
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

