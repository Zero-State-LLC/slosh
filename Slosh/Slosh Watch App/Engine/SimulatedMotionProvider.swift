import Foundation
import OceanCore
import OceanUI

/// Stands in for the accelerometer where there isn't one.
///
/// The watch simulator has no motion sensors at all, so without this the
/// entire app is untestable outside a physical device. Dragging tilts the
/// world in the direction you drag; flicking stirs it.
final class SimulatedMotionProvider: MotionSource {
    private(set) var current: MotionSample = .level

    private var lastX: Double?
    private var lastY: Double?

    func start() {}

    func stop() {
        lastX = nil
        lastY = nil
        current = .level
    }

    /// - Parameters: drag position as a fraction of the screen, 0...1.
    func drag(toUnitX unitX: Double, unitY: Double) {
        guard unitX.isFinite, unitY.isFinite else { return }
        // Offset from the middle becomes the tilt direction, so dragging to a
        // corner pours the water that way.
        let tiltX = ((unitX - 0.5) * 2).clamped(to: -1...1)
        let tiltY = ((unitY - 0.5) * 2).clamped(to: -1...1)

        // Drag speed stands in for how hard the wrist moved.
        let dx = unitX - (lastX ?? unitX)
        let dy = unitY - (lastY ?? unitY)
        lastX = unitX
        lastY = unitY

        current = MotionSample(
            gravityX: tiltX,
            gravityY: -(1 - min(1, abs(tiltX))) - tiltY * 0.4,
            accelerationX: (dx * 45).clamped(to: -8...8),
            accelerationY: (-dy * 45).clamped(to: -8...8),
            rotationZ: (dx * 60).clamped(to: -14...14)
        )
    }

    func endDrag() {
        lastX = nil
        lastY = nil
        // Keep the tilt, drop the motion — the swell holds its new heading.
        current = MotionSample(
            gravityX: current.gravityX,
            gravityY: current.gravityY
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
