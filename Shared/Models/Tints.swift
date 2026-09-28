import SwiftUI

extension WorkoutType {
    var tint: Color {
        switch self {
        case .easy, .shakeout: .green
        case .long: .blue
        case .tempo: .orange
        case .intervals: .red
        case .race: .purple
        case .strength: .indigo
        case .mobility: .teal
        case .rest: .secondary
        }
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
