import Foundation

/// One frame of device motion, expressed in screen-space terms so the core
/// never has to import CoreMotion (and stays testable off-device).
///
/// Axes match CoreMotion's device frame: `x` points right across the screen,
/// `y` points up along the screen. Gravity is in g-units; rotation in rad/s.
public struct MotionSample: Sendable, Equatable {
    public var gravityX: Double
    public var gravityY: Double
    public var accelerationX: Double
    public var accelerationY: Double
    public var rotationZ: Double

    public init(
        gravityX: Double = 0,
        gravityY: Double = -1,
        accelerationX: Double = 0,
        accelerationY: Double = 0,
        rotationZ: Double = 0
    ) {
        self.gravityX = gravityX
        self.gravityY = gravityY
        self.accelerationX = accelerationX
        self.accelerationY = accelerationY
        self.rotationZ = rotationZ
    }

    /// A watch held upright, perfectly still.
    public static let level = MotionSample()
}
