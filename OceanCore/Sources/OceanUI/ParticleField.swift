import OceanCore
import SpriteKit

/// Loose particles over the water: spray thrown off breaking crests, or marine
/// snow sinking through deep water.
///
/// Deliberately not `SKEmitterNode`: without a texture an emitter draws squares,
/// and building a texture on watchOS means going through UIKit image rendering,
/// which is a dependency this does not need. A small pool of shape nodes is
/// predictable, capped, and costs nothing when it is idle.
final class ParticleField: SKNode {
    private struct Particle {
        var vx: CGFloat = 0
        var vy: CGFloat = 0
        var life: CGFloat = 0
        var maxLife: CGFloat = 1
        var peakAlpha: CGFloat = 0.9
    }

    private let kind: ParticleKind
    private let scale: Double
    private let capacity: Int
    private var nodes: [SKShapeNode] = []
    private var particles: [Particle] = []
    private var seed: UInt64 = 0x2545F491_4F6CDD1D
    private var sinceBurst: Double = 0
    private var sinceDrift: Double = 0

    init(kind: ParticleKind, color: RGBA, scale: Double) {
        self.kind = kind
        self.scale = scale
        // Snow is always falling, so it needs more bodies than spray, which
        // only exists in bursts.
        self.capacity = kind == .drift ? 52 : 26
        super.init()
        zPosition = 10

        let fill = SKColor(
            red: CGFloat(color.red), green: CGFloat(color.green),
            blue: CGFloat(color.blue), alpha: 1
        )
        for _ in 0..<capacity {
            let node = SKShapeNode(circleOfRadius: kind == .drift ? 1.5 : 1.6)
            node.fillColor = fill
            node.strokeColor = .clear
            node.alpha = 0
            node.isHidden = true
            addChild(node)
            nodes.append(node)
            particles.append(Particle())
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func random() -> CGFloat {
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        return CGFloat(seed % 10_000) / 10_000
    }

    func update(dt: Double, surge: Double, size: CGSize) {
        let step = CGFloat(dt)
        // Spray loses to the air quickly; snow is already at terminal velocity
        // and simply keeps going.
        let drag: CGFloat = kind == .spray ? 0.94 : 0.995

        for index in particles.indices where particles[index].life > 0 {
            particles[index].life -= step
            let node = nodes[index]
            if particles[index].life <= 0 {
                node.isHidden = true
                node.alpha = 0
                continue
            }
            particles[index].vx *= drag
            particles[index].vy *= drag
            node.position.x += particles[index].vx * step
            node.position.y += particles[index].vy * step

            let fraction = particles[index].life / particles[index].maxLife
            if kind == .drift {
                // Fade in and out at both ends, so snow does not pop into
                // existence in the middle of open water.
                let envelope = min(1, fraction * 4) * min(1, (1 - fraction) * 4 + 0.2)
                node.alpha = particles[index].peakAlpha * envelope
            } else {
                node.alpha = fraction * particles[index].peakAlpha
                node.setScale(0.55 + fraction * 0.75)
            }
        }

        guard size.width > 0 else { return }
        switch kind {
        case .none:
            break
        case .spray:
            sinceBurst += dt
            // Only a genuinely violent moment throws water into the air, and
            // only a few times a second however hard the wrist is shaken.
            guard surge > 0.55, sinceBurst > 0.16 else { return }
            sinceBurst = 0
            burst(surge: surge, size: size)
        case .drift:
            sinceDrift += dt
            guard sinceDrift > 0.10 / max(scale, 0.1) else { return }
            sinceDrift = 0
            snow(size: size)
        }
    }

    private func burst(surge: Double, size: CGSize) {
        let origin = CGPoint(
            x: random() * size.width,
            y: size.height * (0.2 + random() * 0.6)
        )
        let force = CGFloat(min(surge, 2.0)) * CGFloat(scale)
        let count = 4 + Int(random() * 4)

        var spawned = 0
        for index in particles.indices where particles[index].life <= 0 {
            guard spawned < count else { break }
            spawned += 1

            // Seen from above, spray does not arc — it bursts outward from the
            // break and slows.
            let angle = random() * .pi * 2
            let speed = (26 + random() * 74) * force
            particles[index] = Particle(
                vx: cos(angle) * speed,
                vy: sin(angle) * speed,
                life: 0.32 + random() * 0.34,
                maxLife: 0.66,
                peakAlpha: 0.9
            )
            let node = nodes[index]
            node.position = origin
            node.isHidden = false
        }
    }

    private func snow(size: CGSize) {
        guard let index = particles.indices.first(where: { particles[$0].life <= 0 })
        else { return }

        // Marine snow falls from the light into the dark, so it enters at the
        // top of the scene and sinks. Slower particles are drawn fainter, which
        // reads as distance.
        let speed = 6 + random() * 16
        let nearness = (speed - 6) / 16
        particles[index] = Particle(
            vx: (random() - 0.5) * 5,
            vy: -speed,
            life: CGFloat(size.height) / speed,
            maxLife: CGFloat(size.height) / speed,
            peakAlpha: 0.55 + nearness * 0.45
        )
        let node = nodes[index]
        node.position = CGPoint(x: random() * size.width, y: size.height + 4)
        node.isHidden = false
        node.setScale(0.5 + nearness * 0.8)
    }
}
