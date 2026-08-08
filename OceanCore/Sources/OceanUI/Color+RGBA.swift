import OceanCore
import SwiftUI

extension Color {
    /// Bridges the core's platform-free colour into SwiftUI.
    public init(_ rgba: RGBA) {
        self.init(
            .sRGB,
            red: rgba.red,
            green: rgba.green,
            blue: rgba.blue,
            opacity: rgba.alpha
        )
    }
}
