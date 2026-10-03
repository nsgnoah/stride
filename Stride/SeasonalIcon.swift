import UIKit

/// Keeps the Home Screen icon in step with the season. iOS shows a small alert the
/// first time it changes each season; after that it's quiet. Also puts back the primary
/// icon on phones that switched to the retired Halloween one in build 12.
enum SeasonalIcon {
    @MainActor
    static func update(for date: Date = .now) {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons else { return }
        let wanted = Season.current(on: date).iconName
        guard app.alternateIconName != wanted else { return }
        app.setAlternateIconName(wanted) { error in
            if let error { print("Stride: icon change failed — \(error)") }
        }
    }
}
