import Foundation

/// The time of year, for the app icon and the widget's dressing. The runner and her
/// ribbon stay the same; only the colours and a prop or two change.
enum Season: String, CaseIterable, Sendable {
    case standard
    case halloween

    static func current(on date: Date = .now, calendar: Calendar = .current) -> Season {
        switch calendar.component(.month, from: date) {
        case 10: .halloween
        default: .standard
        }
    }

    /// The alternate app icon to show, or nil for the primary icon.
    var iconName: String? {
        switch self {
        case .standard: nil
        case .halloween: "AppIcon-Halloween"
        }
    }
}
