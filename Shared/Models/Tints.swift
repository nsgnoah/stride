import SwiftUI

/// Stride's palette: the ember-to-gold of the icon's ribbon on deep ink, plus one colour
/// per kind of workout, chosen to sit together rather than taken from the system set.
extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    static let ember = Color(hex: 0xFF6A3D)
    static let gold = Color(hex: 0xFFC25A)
    static let jade = Color(hex: 0x2EBD8E)
    static let azure = Color(hex: 0x4F8DF7)
    static let amber = Color(hex: 0xF5A33B)
    static let ink = Color(hex: 0x171926)
    static let inkDeep = Color(hex: 0x0D0E16)
}

extension ShapeStyle where Self == LinearGradient {
    /// The ribbon: ember warming to gold.
    static var stride: LinearGradient {
        LinearGradient(colors: [.ember, .gold], startPoint: .bottomLeading, endPoint: .topTrailing)
    }
}

extension WorkoutType {
    var tint: Color {
        switch self {
        case .easy, .shakeout: .jade
        case .long: .azure
        case .tempo: .amber
        case .intervals: Color(hex: 0xF0564A)       // vermilion
        case .race: Color(hex: 0xA574F2)            // violet
        case .strength: Color(hex: 0x7C86E8)        // periwinkle
        case .mobility: Color(hex: 0x35B8C4)        // lagoon
        case .rest: .secondary
        }
    }
}

extension Segment.Kind {
    var tint: Color {
        switch self {
        case .warmup: .gold
        case .work: .ember
        case .recovery: .azure
        case .cooldown: Color(hex: 0x35B8C4)
        }
    }
}
