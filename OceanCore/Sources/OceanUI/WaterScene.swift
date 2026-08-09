import OceanCore
import SpriteKit
import SwiftUI

/// Hosts the water shader and feeds it uniforms once per frame.
public final class WaterScene: SKScene {
    public struct DiagnosticSnapshot: Sendable {
        public let frameRate: FrameRateMonitor.Snapshot
        public let gravityX: Double
        public let gravityY: Double
        public let inPlaneMagnitude: Double
        public let heading: Double
        public let flowX: Double
        public let flowY: Double
    }

    private var surface = SKSpriteNode()
    private var driver = SurfaceDriver()
    private var particles: ParticleField?
    private var lastUpdate: TimeInterval?
    private var frameRateMonitor = FrameRateMonitor()
    private var lastDiagnosticReportTime: TimeInterval = -.infinity

    /// Validation-only consumers may install this callback. Normal production
    /// rendering pays only one nil check and never logs or changes physics.
    public var onDiagnostics: ((DiagnosticSnapshot) -> Void)?

    public var theme: OceanTheme = .calmOcean {
        didSet {
            driver.configure(for: theme)
            applyTheme()
        }
    }

    /// Where motion comes from. Swapped for a scripted source in previews.
    public var motionSource: MotionSource = StillMotion()

    public var energy: Double = 1.0 {
        didSet { driver.energy = energy }
    }

    /// Normalized persistent input only. HydroState and provider DTOs stay out
    /// of the renderer boundary.
    public var environmentalForcing: EnvironmentalForcing? {
        didSet { driver.environmentalForcing = environmentalForcing }
    }

    /// Already-normalized visual influence. WaterScene resolves it against the
    /// immutable authored theme and never sees HydroState or provider data.
    public var hydroThemeModifiers: HydroThemeModifiers? {
        didSet { applyResolvedStyle() }
    }

    /// Set false when the app backgrounds or the screen dims — the scene keeps
    /// existing but stops costing anything.
    public var isRunning = true

    /// Loose particles are expensive and pointless on a small preview tile.
    public var allowsParticles = true

    private var uniforms: [String: SKUniform] = [:]

    // MARK: - Setup

    /// Built here rather than in `sceneDidLoad`, which fires while the scene
    /// still has zero size — a sprite sized from it would be invisible.
    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard size.width > 0, size.height > 0 else { return }
        if surface.parent == nil { build() }
        surface.size = size
        surface.position = CGPoint(x: size.width / 2, y: size.height / 2)
        driver.aspect = Double(size.height / max(size.width, 1))
        uniforms["u_size"]?.vectorFloat2Value = vector_float2(
            Float(size.width), Float(size.height)
        )
    }

    private func build() {
        backgroundColor = .black
        scaleMode = .resizeFill

        // Uniforms have to be created with the right shape, or SpriteKit binds
        // a float where the shader expects a vector and the draw is garbage.
        uniforms["u_now"] = SKUniform(name: "u_now", float: 0)
        uniforms["u_size"] = SKUniform(name: "u_size", vectorFloat2: vector_float2(1, 1))
        uniforms["u_flowCenter"] = SKUniform(
            name: "u_flowCenter", vectorFloat4: vector_float4(0, 1, 0.5, 0.6)
        )
        for name in ["u_state", "u_wave", "u_layers", "u_optics"] {
            uniforms[name] = SKUniform(name: name, vectorFloat4: vector_float4(0, 0, 0, 0))
        }
        for name in ["u_deep", "u_shallow", "u_light", "u_foam", "u_skyA", "u_skyB"] {
            uniforms[name] = SKUniform(name: name, vectorFloat3: vector_float3(0, 0, 0))
        }
        // Birth time far in the past, so an unused slot is simply a ripple that
        // finished long ago rather than one perpetually at age zero.
        for name in ["u_r0", "u_r1", "u_r2", "u_r3", "u_r4", "u_r5"] {
            uniforms[name] = SKUniform(name: name, vectorFloat4: vector_float4(0, 0, -999, 0))
        }

        let shader = SKShader(source: WaterShader.source)
        shader.uniforms = WaterShader.uniformNames.compactMap { uniforms[$0] }

        surface = SKSpriteNode(color: .white, size: size)
        surface.shader = shader
        addChild(surface)

        applyTheme()
    }

    private func applyTheme() {
        uniforms["u_deep"]?.vectorFloat3Value = theme.deep.simd
        uniforms["u_shallow"]?.vectorFloat3Value = theme.shallow.simd
        uniforms["u_light"]?.vectorFloat3Value = theme.light.simd
        uniforms["u_foam"]?.vectorFloat3Value = theme.foamColor.simd
        uniforms["u_skyA"]?.vectorFloat3Value = theme.skyColorA.simd
        uniforms["u_skyB"]?.vectorFloat3Value = theme.skyColorB.simd

        uniforms["u_layers"]?.vectorFloat4Value = vector_float4(
            Float(theme.bedDetail), Float(theme.shadows),
            Float(theme.shafts), Float(theme.skyGlow)
        )
        applyResolvedStyle()

        particles?.removeFromParent()
        particles = nil
        if allowsParticles, theme.particles != .none {
            let field = ParticleField(
                kind: theme.particles,
                color: theme.particles == .drift ? theme.light : theme.foamColor,
                scale: theme.particleScale
            )
            addChild(field)
            particles = field
        }
    }

    /// Style changes only touch the two existing packed uniforms. The scene,
    /// shader, surface node, and particle field remain intact.
    private func applyResolvedStyle() {
        let style = ResolvedWaterStyle(base: theme, modifiers: hydroThemeModifiers)
        uniforms["u_wave"]?.vectorFloat4Value = vector_float4(
            Float(style.choppiness), Float(style.turbulence),
            Float(style.crestSharpness), Float(style.glitter)
        )
        uniforms["u_optics"]?.vectorFloat4Value = vector_float4(
            Float(style.causticStrength), Float(theme.causticTimeScale),
            Float(style.foaminess), Float(theme.glowResponse)
        )
    }

    // MARK: - Frame

    public override func update(_ currentTime: TimeInterval) {
        defer { lastUpdate = currentTime }
        guard isRunning else { return }
        guard let last = lastUpdate else { return }
        // Cap the step so returning from the background doesn't lurch.
        let dt = min(max(currentTime - last, 0), 1.0 / 20.0)
        guard dt > 0 else { return }

        if let driftingMotion = motionSource as? DriftingMotion {
            driftingMotion.advance(dt: dt)
        }

        driver.advance(dt: dt, motion: motionSource.current)

        if onDiagnostics != nil,
           let frameRate = frameRateMonitor.recordFrame(at: currentTime),
           currentTime - lastDiagnosticReportTime >= FrameRateMonitor.Thresholds.reportingInterval {
            let motion = motionSource.current
            lastDiagnosticReportTime = currentTime
            onDiagnostics?(DiagnosticSnapshot(
                frameRate: frameRate,
                gravityX: motion.gravityX,
                gravityY: motion.gravityY,
                inPlaneMagnitude: hypot(motion.gravityX, motion.gravityY),
                heading: driver.heading,
                flowX: driver.flowX,
                flowY: driver.flowY
            ))
        }

        uniforms["u_now"]?.floatValue = Float(driver.time)
        uniforms["u_flowCenter"]?.vectorFloat4Value = vector_float4(
            Float(driver.flowX), Float(driver.flowY),
            Float(driver.centerX), Float(driver.centerY)
        )
        uniforms["u_state"]?.vectorFloat4Value = vector_float4(
            Float(driver.resolvedEnergy), Float(driver.surge), Float(driver.flash), 0
        )

        for (index, name) in ["u_r0", "u_r1", "u_r2", "u_r3", "u_r4", "u_r5"].enumerated() {
            let r = driver.ripples[index]
            uniforms[name]?.vectorFloat4Value = vector_float4(
                Float(r.x), Float(r.y), Float(r.birth), Float(r.strength)
            )
        }

        particles?.update(dt: dt, surge: driver.surge, size: size)
    }

    // MARK: - Input

    /// - Parameter point: a location in the scene's own coordinates.
    public func tap(at point: CGPoint) {
        guard size.width > 0 else { return }
        let x = Double(point.x / size.width)
        // Scene coordinates put the origin at the bottom; the shader's space
        // runs downward from the top.
        let y = Double((size.height - point.y) / size.width)
        driver.ripple(atX: x, y: y, strength: 1.0)
    }

    public func resume() {
        lastUpdate = nil
        frameRateMonitor.resetBoundary()
        isRunning = true
    }

    public func calm() {
        driver.reset()
    }
}

extension RGBA {
    var simd: vector_float3 {
        vector_float3(Float(red), Float(green), Float(blue))
    }
}
