import Foundation

/// An expanding circular wave, spawned by a tap, a jolt, or a raindrop.
public struct Ripple: Sendable, Equatable {
    /// Centre in shader space: x is 0…1 across the screen, y is 0…aspect down it.
    public var x: Double
    public var y: Double
    /// When it was born, on the driver's own clock.
    public var birth: Double
    public var strength: Double

    public static let none = Ripple(x: 0, y: 0, birth: -999, strength: 0)
}

/// Drives the water shader from device motion.
///
/// The wave field itself lives in the fragment shader — this decides *where*
/// the waves roll, *how hard*, where the deep part of the bowl sits, and when a
/// ripple or a lightning strike happens. Keeping that here rather than in the
/// scene means it is plain Swift and can be tested.
public struct SurfaceDriver: Sendable {
    public enum EnvironmentalBlendThresholds {
        /// Below this in-plane gravity, the watch is treated as flat.
        public static let gravityDeadZone = 0.12
        /// At and above this magnitude, wrist direction has full authority.
        public static let fullWristAuthority = 0.75
    }

    /// Direction the swell travels, as an angle.
    ///
    /// Stored as an angle rather than a vector on purpose: interpolating a
    /// vector and renormalising it every step cancels the interpolation, and a
    /// 180° reversal collapses through zero length. An angle sweeps around.
    public private(set) var heading: Double = 0

    /// Unit vector the swell travels along.
    public var flowX: Double { sin(heading) }
    public var flowY: Double { cos(heading) }

    /// Where the deep part of the bowl sits, in shader space. Tilting moves it,
    /// so the water visibly pools toward the low side rather than only changing
    /// which way the waves march.
    public private(set) var centerX: Double = 0.5
    public private(set) var centerY: Double = 0.6

    /// Extra amplitude and disorder from recent movement, decaying back to
    /// zero. This is what makes the water visibly react to a shake rather than
    /// only to tilt.
    public private(set) var surge: Double = 0

    /// Lightning brightness, 0…1, spiking on a strike and falling away fast.
    public private(set) var flash: Double = 0

    /// Crown-controlled liveliness, 0.3…2.
    public var energy: Double = 1.0

    /// Persistent, normalized influence from a Hydro interpretation. `nil`
    /// preserves the original authored-mode driver behavior exactly.
    public var environmentalForcing: EnvironmentalForcing?

    /// Environmental forcing is an additive baseline, never a replacement for
    /// crown energy: E = crown + 0.65e + 0.15t + 0.10c + 0.10w, capped at 3.
    public var resolvedEnergy: Double {
        guard let forcing = usableEnvironmentalForcing else { return energy }
        let crown = energy.isFinite ? max(0, energy) : 1
        let baseline = 0.65 * forcing.energy
            + 0.15 * forcing.turbulence
            + 0.10 * forcing.flowStrength
            + 0.10 * forcing.windStrength
        return min(crown + baseline, 3)
    }

    /// Total current activity including shake-driven transient surge.
    public var resolvedActivity: Double {
        let value = resolvedEnergy + surge
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 6)
    }

    /// How hard this mode answers movement. Breaking surf is violent; rain
    /// barely notices.
    public var motionGain: Double = 1.0

    /// Drops per second falling with no input at all.
    public var rainRate: Double = 0

    /// Average seconds between lightning strikes. Zero for no storm.
    public var lightningInterval: Double = 0

    /// When false the swell ignores gravity and wanders of its own accord.
    public var followsGravity: Bool = true

    public private(set) var time: Double = 0

    /// Six slots is what the shader can afford; the oldest is recycled.
    public private(set) var ripples: [Ripple] = Array(repeating: .none, count: 6)
    private var nextSlot = 0

    /// How quickly the flow direction chases gravity. Low-passed so tilting
    /// feels like water finding its level rather than a compass needle.
    public var flowSmoothing: Double = 0.9

    public var aspect: Double = 1.2

    private var lastEdgeRipple: Double = -1
    private var rainAccumulator: Double = 0
    private var nextStrike: Double = -1
    /// Self-contained so a rain shower or a storm is reproducible in tests.
    private var seed: UInt64 = 0x9E37_79B9_7F4A_7C15

    public init() {}

    private mutating func random() -> Double {
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        return Double(seed % 100_000) / 100_000
    }

    // MARK: - Motion

    public mutating func advance(dt: Double, motion: MotionSample) {
        guard dt > 0, dt.isFinite else { return }
        time += dt

        if followsGravity {
            let gx = motion.gravityX
            let gy = motion.gravityY
            let magnitude = (gx * gx + gy * gy).squareRoot()
            let wristDirection = magnitude > EnvironmentalBlendThresholds.gravityDeadZone
                && magnitude.isFinite
                ? atan2(gx / magnitude, -gy / magnitude)
                : nil

            if let ambient = usableEnvironmentalForcing?.flowDirection {
                // Flat means ambient authority. As tilt grows, the target moves
                // along the shortest angular path until the wrist owns it.
                let wristWeight = wristAuthority(forGravityMagnitude: magnitude)
                let target = wristDirection.map {
                    angle(from: ambient, toward: $0, fraction: wristWeight)
                } ?? ambient
                turnHeading(toward: target, dt: dt)
            } else if let wristDirection {
                // Original behavior when no environmental direction is present.
                turnHeading(toward: wristDirection, dt: dt)
            }
        } else {
            // No down to find, so the swell simply wanders. Two incommensurate
            // rates, or the wander is a visible loop.
            heading += (0.21 * sin(time * 0.13) + 0.11 * sin(time * 0.37)) * dt
        }

        updateCenter(dt: dt)

        // Shaking the wrist stirs the surface.
        let shake = abs(motion.accelerationX) + abs(motion.accelerationY)
            + abs(motion.rotationZ) * 0.16
        let excitement = max(0, shake - 0.18) * motionGain
        surge += excitement * dt * 3.4
        surge *= pow(0.28, dt)
        surge = min(surge, 3.0)

        // A hard jolt throws a wave in from the edge it came from.
        if excitement > 0.9 {
            let nx = motion.accelerationX
            let ny = motion.accelerationY
            let n = (nx * nx + ny * ny).squareRoot()
            if n > 0.01 {
                spawnEdgeRipple(
                    directionX: -nx / n,
                    directionY: ny / n,
                    strength: min(1.4, excitement * 0.5)
                )
            }
        }

        rain(dt: dt)
        lightning(dt: dt)
    }

    /// The bowl's centre follows gravity in the ordinary modes and drifts on
    /// its own where there is none.
    private mutating func updateCenter(dt: Double) {
        let base = (x: 0.5, y: aspect * 0.5)
        let target: (x: Double, y: Double)
        if followsGravity {
            target = (base.x + flowX * 0.13, base.y + flowY * 0.13)
        } else {
            target = (
                base.x + 0.17 * sin(time * 0.19),
                base.y + 0.17 * cos(time * 0.11)
            )
        }
        // Slower than the heading: a sloshing centre of mass looks like a bug.
        let blend = (1.4 * dt).clamped(to: 0...1)
        centerX += (target.x - centerX) * blend
        centerY += (target.y - centerY) * blend
    }

    /// Drops land at a steady average rate, at random points. Fractional drops
    /// carry over so a slow rate still produces evenly spaced drops rather than
    /// none at all.
    private mutating func rain(dt: Double) {
        guard rainRate > 0 else { return }
        rainAccumulator += rainRate * dt
        while rainAccumulator >= 1 {
            rainAccumulator -= 1
            ripple(
                atX: random(),
                y: random() * aspect,
                strength: 0.35 + random() * 0.5
            )
        }
    }

    /// Strikes at random intervals around the mode's average, then decays fast.
    /// Real lightning is not periodic, and a metronome would be maddening on
    /// something meant to be watched for minutes.
    private mutating func lightning(dt: Double) {
        guard lightningInterval > 0 else {
            flash = 0
            return
        }
        if nextStrike < 0 {
            nextStrike = time + lightningInterval * (0.4 + random())
        }
        if time >= nextStrike {
            nextStrike = time + lightningInterval * (0.4 + random() * 1.2)
            // Occasionally a strike lands on top of the tail of the last one,
            // which is what gives real lightning its flicker.
            flash = min(1.0, flash + 0.75 + random() * 0.25)
        }
        // Hard decay. A slow fade reads as someone turning a lamp up, not as
        // lightning; a real strike is gone inside a few tenths of a second.
        flash *= pow(0.0015, dt)
        if flash < 0.002 { flash = 0 }
    }

    // MARK: - Ripples

    public mutating func ripple(atX x: Double, y: Double, strength: Double = 1.0) {
        guard x.isFinite, y.isFinite, strength > 0 else { return }
        ripples[nextSlot] = Ripple(
            x: x, y: y, birth: time, strength: strength * resolvedEnergy
        )
        nextSlot = (nextSlot + 1) % ripples.count
    }

    /// Born just off the edge the motion came from, so the wave washes across
    /// the whole screen rather than blooming out of the middle.
    private mutating func spawnEdgeRipple(
        directionX: Double, directionY: Double, strength: Double
    ) {
        // Rate-limit: without this a sustained shake spawns a ripple every
        // frame and they smear into noise.
        guard time - lastEdgeRipple > 0.35 else { return }
        lastEdgeRipple = time
        ripple(
            atX: 0.5 + directionX * 0.62,
            y: aspect * (0.5 + directionY * 0.62),
            strength: strength
        )
    }

    public mutating func reset() {
        surge = 0
        flash = 0
        nextStrike = -1
        ripples = Array(repeating: .none, count: ripples.count)
        nextSlot = 0
        rainAccumulator = 0
    }

    /// Applies everything a mode declares about behaviour.
    public mutating func configure(for theme: OceanTheme) {
        motionGain = theme.motionGain
        rainRate = theme.rainRate
        lightningInterval = theme.lightningInterval
        followsGravity = theme.followsGravity
    }

    private var usableEnvironmentalForcing: EnvironmentalForcing? {
        guard let environmentalForcing,
              environmentalForcing.freshness != .unavailable else { return nil }
        return environmentalForcing
    }

    private func wristAuthority(forGravityMagnitude magnitude: Double) -> Double {
        guard magnitude.isFinite else { return 0 }
        let span = EnvironmentalBlendThresholds.fullWristAuthority
            - EnvironmentalBlendThresholds.gravityDeadZone
        return ((magnitude - EnvironmentalBlendThresholds.gravityDeadZone) / span)
            .clamped(to: 0...1)
    }

    private func angle(from start: Double, toward end: Double, fraction: Double) -> Double {
        start + shortestAngularDelta(from: start, to: end) * fraction.clamped(to: 0...1)
    }

    private func shortestAngularDelta(from start: Double, to end: Double) -> Double {
        var delta = (end - start).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return delta
    }

    private mutating func turnHeading(toward target: Double, dt: Double) {
        heading += shortestAngularDelta(from: heading, to: target)
            * (flowSmoothing * dt).clamped(to: 0...1)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
