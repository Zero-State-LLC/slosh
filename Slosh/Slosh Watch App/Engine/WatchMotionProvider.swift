import CoreMotion
import OceanCore
import OceanUI
import WatchKit

/// Feeds the ocean from the watch's motion sensors.
///
/// Device motion needs no permission prompt — that is only required for the
/// activity and pedometer APIs — so the app can start reading gravity the
/// moment it appears.
final class WatchMotionProvider: MotionSource {
    private let manager = CMMotionManager()
    private(set) var current: MotionSample = .level
    private var running = false

    /// 40 Hz. The simulation runs at 60, and interpolating a slightly stale
    /// gravity reading is invisible — but the extra sensor duty cycle is not,
    /// on a battery this size.
    private let updateInterval = 1.0 / 40.0

    /// Worn crown-left, the whole screen is rotated 180°, so the in-plane axes
    /// point the opposite way. Without this the water runs uphill for anyone
    /// who wears their watch the other way round.
    private var axisSign: Double {
        WKInterfaceDevice.current().crownOrientation == .left ? -1 : 1
    }

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard !running, manager.isDeviceMotionAvailable else { return }
        running = true
        manager.deviceMotionUpdateInterval = updateInterval
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let sign = self.axisSign
            self.current = MotionSample(
                gravityX: motion.gravity.x * sign,
                gravityY: motion.gravity.y * sign,
                accelerationX: motion.userAcceleration.x * sign,
                accelerationY: motion.userAcceleration.y * sign,
                // A 180° turn about the screen normal leaves z-rotation alone.
                rotationZ: motion.rotationRate.z
            )
        }
    }

    func stop() {
        guard running else { return }
        running = false
        manager.stopDeviceMotionUpdates()
        current = .level
    }
}
