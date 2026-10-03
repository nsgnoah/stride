import Foundation

/// The time of year, for seasonal app icons. Only the everyday icon exists right now;
/// a season is added with its own `AppIcon-<Name>` icon set, a case here, and its name in
/// `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` in project.yml.
enum Season: String, CaseIterable, Sendable {
    case standard

    static func current(on date: Date = .now, calendar: Calendar = .current) -> Season {
        .standard
    }

    /// The alternate app icon to show, or nil for the primary icon.
    var iconName: String? {
        switch self {
        case .standard: nil
        }
    }
}
