import Foundation
import WatchKit

enum SettingsKey {
    static let themeID = "themeID"
    static let energy = "energy"
    static let hapticsEnabled = "hapticsEnabled"
    static let placeID = "placeID"
}

/// Crown range for the energy multiplier.
enum EnergyRange {
    static let minimum = 0.3
    static let maximum = 2.0
    static let step = 0.05
    static let `default` = 1.0
}

enum Screen {
    /// The physics is solved across the real screen width, so a wave that
    /// crosses the tank crosses the display.
    ///
    /// Deliberately not isolated to the main actor: views build their preview
    /// oceans from inside `init`, where hopping actors is not an option.
    static var width: Double {
        Double(WKInterfaceDevice.current().screenBounds.width)
    }
}
