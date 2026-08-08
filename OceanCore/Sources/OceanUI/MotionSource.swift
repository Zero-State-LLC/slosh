import Foundation
import OceanCore

/// Where motion comes from. The watch app supplies a CoreMotion-backed
/// implementation; the simulator and previews supply scripted ones. Injecting
/// it keeps the scene identical everywhere.
public protocol MotionSource: AnyObject {
    var current: MotionSample { get }
    func start()
    func stop()
}

/// A still watch, for previews and the always-on frame.
public final class StillMotion: MotionSource {
    public var current: MotionSample

    public init(_ sample: MotionSample = .level) {
        current = sample
    }

    public func start() {}
    public func stop() {}
}

/// Slowly circles the gravity vector, so a preview shows the swell changing
/// direction without anyone having to move a wrist.
public final class DriftingMotion: MotionSource {
    private var angle: Double
    private let rate: Double

    public init(startAngle: Double = 0, rate: Double = 0.35) {
        self.angle = startAngle
        self.rate = rate
    }

    public var current: MotionSample {
        MotionSample(gravityX: sin(angle), gravityY: -cos(angle))
    }

    public func advance(dt: Double) {
        angle += rate * dt
    }

    public func start() {}
    public func stop() {}
}
