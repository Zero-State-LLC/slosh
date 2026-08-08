import Foundation

/// A colour, kept free of SwiftUI so the whole catalogue lives in the
/// portable core.
public struct RGBA: Sendable, Equatable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `RGBA(0x1B3B6F)` — easier to eyeball against a palette than triples.
    public init(_ hex: UInt32, alpha: Double = 1) {
        self.red = Double((hex >> 16) & 0xFF) / 255
        self.green = Double((hex >> 8) & 0xFF) / 255
        self.blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    public func opacity(_ value: Double) -> RGBA {
        RGBA(red, green, blue, alpha * value)
    }
}

/// Which of the watch's canned haptics a mode uses.
public enum HapticKind: String, Sendable, CaseIterable {
    case click
    case directionUp
    case notification
    case start
    case stop
}

/// What the particle pool does, if anything.
public enum ParticleKind: String, Sendable, Equatable {
    case none
    /// Droplets thrown outward from a breaking crest.
    case spray
    /// Marine snow sinking slowly through dark water.
    case drift
}

/// One body of water, looking straight down into it.
///
/// These are *modes*, not colour schemes: the behaviour fields change how the
/// water moves and how it answers you, so switching from Calm ocean to Breaking
/// surf is a different substance, not a different palette.
///
/// Every field defaults to "off", so a new mode only declares what makes it
/// different. The expensive features are gated behind uniform branches in the
/// shader — uniform, so the branch is coherent across the whole draw and costs
/// nothing in the modes that leave them off.
public struct OceanTheme: Identifiable, Sendable, Equatable {
    public var id: String
    public var name: String
    /// Short line shown under the name in the picker.
    public var blurb: String

    // MARK: Palette

    /// Colour at the deepest point, out at the rim.
    public var deep: RGBA
    /// Colour of the shallows in the middle.
    public var shallow: RGBA
    /// Sun and caustic colour.
    public var light: RGBA
    /// Whitecaps and spray.
    public var foamColor: RGBA

    // MARK: Surface

    /// Weight of the short, high-frequency waves.
    public var choppiness: Double
    /// Specular strength. Overcast water barely glitters; a lagoon at noon does.
    public var glitter: Double
    /// How much the wave field is stirred out of straight lines.
    public var turbulence: Double
    /// 0 rolls as smooth sine swell; 1 peaks the crests and broadens the
    /// troughs, which is the shape water takes just before it breaks.
    public var crestSharpness: Double
    /// Brightness of the caustic web.
    public var causticStrength: Double
    /// Rate the caustic web evolves. **Zero freezes it**, which turns the same
    /// cell network from moving light into a static fracture pattern — that one
    /// number is the whole of Under ice.
    public var causticTimeScale: Double

    // MARK: The world under the surface

    /// Sand ripples and pebbles on the bed, seen through the refraction.
    public var bedDetail: Double
    /// Slow dark shapes moving below, visible only as silhouette.
    public var shadows: Double
    /// Shafts of light coming down from above.
    public var shafts: Double

    // MARK: The world above it

    /// Strength of coloured curtains reflected in the surface.
    public var skyGlow: Double
    public var skyColorA: RGBA
    public var skyColorB: RGBA
    /// Average seconds between lightning strikes. Zero for no storm.
    public var lightningInterval: Double

    // MARK: Response

    /// How hard movement stirs this water.
    public var motionGain: Double
    /// Whitecap coverage where the surface gets steep. 0 is glassy.
    public var foaminess: Double
    public var particles: ParticleKind
    /// Particle density for whichever kind is in use.
    public var particleScale: Double
    /// Ripples spawned per second with no input at all — rain on the surface.
    public var rainRate: Double
    /// Light emitted by disturbance rather than reflected. Bioluminescence.
    public var glowResponse: Double
    /// When false the swell ignores gravity entirely and drifts of its own
    /// accord, which is the whole idea of Zero gravity.
    public var followsGravity: Bool

    public var haptic: HapticKind?

    public init(
        id: String,
        name: String,
        blurb: String,
        deep: RGBA,
        shallow: RGBA,
        light: RGBA,
        foamColor: RGBA = RGBA(0xFFFFFF),
        choppiness: Double,
        glitter: Double,
        turbulence: Double = 0,
        crestSharpness: Double = 0,
        causticStrength: Double = 1,
        causticTimeScale: Double = 1,
        bedDetail: Double = 0,
        shadows: Double = 0,
        shafts: Double = 0,
        skyGlow: Double = 0,
        skyColorA: RGBA = RGBA(0x4CFFB0),
        skyColorB: RGBA = RGBA(0x9A6BFF),
        lightningInterval: Double = 0,
        motionGain: Double = 1,
        foaminess: Double = 0,
        particles: ParticleKind = .none,
        particleScale: Double = 1,
        rainRate: Double = 0,
        glowResponse: Double = 0,
        followsGravity: Bool = true,
        haptic: HapticKind? = .click
    ) {
        self.id = id
        self.name = name
        self.blurb = blurb
        self.deep = deep
        self.shallow = shallow
        self.light = light
        self.foamColor = foamColor
        self.choppiness = choppiness
        self.glitter = glitter
        self.turbulence = turbulence
        self.crestSharpness = crestSharpness
        self.causticStrength = causticStrength
        self.causticTimeScale = causticTimeScale
        self.bedDetail = bedDetail
        self.shadows = shadows
        self.shafts = shafts
        self.skyGlow = skyGlow
        self.skyColorA = skyColorA
        self.skyColorB = skyColorB
        self.lightningInterval = lightningInterval
        self.motionGain = motionGain
        self.foaminess = foaminess
        self.particles = particles
        self.particleScale = particleScale
        self.rainRate = rainRate
        self.glowResponse = glowResponse
        self.followsGravity = followsGravity
        self.haptic = haptic
    }
}

extension OceanTheme {
    // MARK: - Restful

    /// Still, deep, orderly. The one to fall asleep to.
    public static let calmOcean = OceanTheme(
        id: "calm",
        name: "Calm ocean",
        blurb: "Deep and slow",
        deep: RGBA(0x03142E),
        shallow: RGBA(0x1E6FA8),
        light: RGBA(0xBFE4FF),
        choppiness: 0.65,
        glitter: 1.5,
        turbulence: 0.05,
        motionGain: 0.8,
        haptic: .click
    )

    /// Nothing but falling drops. The only mode that keeps moving when you do
    /// not, which makes it the most restful of the set.
    public static let rainShower = OceanTheme(
        id: "rain",
        name: "Rain shower",
        blurb: "Endless quiet drops",
        deep: RGBA(0x0A1620),
        shallow: RGBA(0x35606F),
        light: RGBA(0xCFE9F2),
        choppiness: 0.35,
        glitter: 1.2,
        causticStrength: 0.7,
        motionGain: 0.55,
        rainRate: 4.2,
        haptic: .click
    )

    /// Clear water a hand deep, with the bottom plainly visible.
    public static let tidePool = OceanTheme(
        id: "tidepool",
        name: "Tide pool",
        blurb: "Shallow over sand",
        deep: RGBA(0x1B3A44),
        shallow: RGBA(0x6FC5C0),
        light: RGBA(0xFFF3D0),
        choppiness: 0.5,
        glitter: 1.3,
        turbulence: 0.08,
        causticStrength: 1.4,
        bedDetail: 1.0,
        motionGain: 0.9,
        rainRate: 0.35,
        haptic: .click
    )

    /// Rain's calm, plus something alive underneath.
    public static let koiPond = OceanTheme(
        id: "koi",
        name: "Koi pond",
        blurb: "Something moves below",
        deep: RGBA(0x0B2018),
        shallow: RGBA(0x2F6E52),
        light: RGBA(0xE8F7CF),
        choppiness: 0.3,
        glitter: 1.0,
        causticStrength: 0.85,
        bedDetail: 0.35,
        shadows: 1.0,
        motionGain: 0.6,
        rainRate: 1.1,
        haptic: .click
    )

    // MARK: - Still and strange

    /// The caustic web frozen. The same cell network that reads as moving light
    /// reads as fracture the moment it stops moving.
    public static let underIce = OceanTheme(
        id: "ice",
        name: "Under ice",
        blurb: "Frozen and cracked",
        deep: RGBA(0x0A1C2E),
        shallow: RGBA(0x8FB8CE),
        light: RGBA(0xF2FBFF),
        choppiness: 0.22,
        glitter: 2.6,
        causticStrength: 1.7,
        causticTimeScale: 0.0,
        motionGain: 0.25,
        haptic: .stop
    )

    /// Still black water with the sky in it.
    public static let aurora = OceanTheme(
        id: "aurora",
        name: "Aurora",
        blurb: "The sky, reflected",
        deep: RGBA(0x01050C),
        shallow: RGBA(0x0A1B2C),
        light: RGBA(0x9FE8FF),
        choppiness: 0.4,
        glitter: 1.1,
        causticStrength: 0.22,
        skyGlow: 1.0,
        skyColorA: RGBA(0x3DFFAE),
        skyColorB: RGBA(0x8E5CFF),
        motionGain: 0.8,
        haptic: .directionUp
    )

    /// Dark water that lights up where it is disturbed.
    public static let midnightGlow = OceanTheme(
        id: "midnight",
        name: "Midnight glow",
        blurb: "Lights up when stirred",
        deep: RGBA(0x01020A),
        shallow: RGBA(0x152A63),
        light: RGBA(0x5BF5DF),
        choppiness: 0.6,
        glitter: 2.3,
        turbulence: 0.18,
        causticStrength: 0.5,
        motionGain: 1.4,
        glowResponse: 1.0,
        haptic: .directionUp
    )

    /// Looking down into deep water, with the light failing and snow falling
    /// through it.
    public static let deepDrift = OceanTheme(
        id: "deep",
        name: "Deep drift",
        blurb: "Snow falling in the dark",
        deep: RGBA(0x000306),
        shallow: RGBA(0x0B2C3E),
        light: RGBA(0xAEDCEA),
        choppiness: 0.3,
        glitter: 0.8,
        // Almost no caustic web: at this depth there is no bed for light to
        // focus on, and leaving it in competed with the shafts for attention.
        causticStrength: 0.12,
        shafts: 1.0,
        motionGain: 0.5,
        particles: .drift,
        particleScale: 1.0,
        haptic: .click
    )

    /// Water that does not know which way is down.
    public static let zeroGravity = OceanTheme(
        id: "zerog",
        name: "Zero gravity",
        blurb: "No up, no down",
        deep: RGBA(0x040A1E),
        shallow: RGBA(0x2E5BA8),
        light: RGBA(0xD6ECFF),
        choppiness: 0.55,
        glitter: 1.8,
        turbulence: 0.30,
        causticStrength: 0.9,
        motionGain: 1.2,
        glowResponse: 0.25,
        followsGravity: false,
        haptic: .directionUp
    )

    // MARK: - Violent

    /// Crests peak and break, whitecaps tear across the surface, spray comes
    /// off the top, and a hard flick throws the whole body of water sideways.
    public static let breakingSurf = OceanTheme(
        id: "surf",
        name: "Breaking surf",
        blurb: "Crashing and wild",
        deep: RGBA(0x04181C),
        shallow: RGBA(0x2E7E86),
        light: RGBA(0xDDF3F0),
        foamColor: RGBA(0xF2FFFB),
        choppiness: 2.1,
        glitter: 1.1,
        turbulence: 1.0,
        crestSharpness: 0.95,
        causticStrength: 0.28,
        motionGain: 2.6,
        foaminess: 1.0,
        particles: .spray,
        particleScale: 1.0,
        haptic: .notification
    )

    /// Breaking surf with the lights off, and lightning that shows you what the
    /// water was doing all along.
    public static let stormAtNight = OceanTheme(
        id: "nightstorm",
        name: "Storm at night",
        blurb: "Lightning on black water",
        deep: RGBA(0x01040A),
        shallow: RGBA(0x0E2733),
        light: RGBA(0x9FC6D6),
        foamColor: RGBA(0xD8E8EE),
        choppiness: 2.0,
        glitter: 0.6,
        turbulence: 0.95,
        crestSharpness: 0.9,
        causticStrength: 0.12,
        lightningInterval: 5.5,
        motionGain: 2.4,
        foaminess: 0.95,
        particles: .spray,
        particleScale: 0.8,
        haptic: .notification
    )

    public static let stormSwell = OceanTheme(
        id: "storm",
        name: "Storm swell",
        blurb: "Grey and heaving",
        deep: RGBA(0x060F12),
        shallow: RGBA(0x2A5E5C),
        light: RGBA(0xC8DAD6),
        foamColor: RGBA(0xE8F1EE),
        choppiness: 1.75,
        glitter: 0.75,
        turbulence: 0.55,
        crestSharpness: 0.5,
        causticStrength: 0.55,
        motionGain: 1.5,
        foaminess: 0.45,
        particles: .spray,
        particleScale: 0.5,
        haptic: .notification
    )

    // MARK: - Bright and other

    public static let tropicalLagoon = OceanTheme(
        id: "lagoon",
        name: "Tropical lagoon",
        blurb: "Bright and shallow",
        deep: RGBA(0x044F52),
        shallow: RGBA(0x3FD4B4),
        light: RGBA(0xFFF6D2),
        choppiness: 0.85,
        glitter: 1.9,
        turbulence: 0.12,
        causticStrength: 1.25,
        bedDetail: 0.4,
        motionGain: 1.0,
        foaminess: 0.08,
        haptic: .click
    )

    /// Not water at all, which is the point — the same machinery, a different
    /// substance. Thick, slow, and lit from underneath.
    public static let moltenCore = OceanTheme(
        id: "molten",
        name: "Molten",
        blurb: "Slow and glowing",
        deep: RGBA(0x160402),
        shallow: RGBA(0x8E2405),
        light: RGBA(0xFFD46A),
        foamColor: RGBA(0xFFE9A8),
        choppiness: 0.5,
        glitter: 0.9,
        turbulence: 0.35,
        crestSharpness: 0.25,
        causticStrength: 1.5,
        motionGain: 0.7,
        glowResponse: 0.7,
        haptic: .stop
    )

    public static let mercury = OceanTheme(
        id: "mercury",
        name: "Mercury",
        blurb: "Heavy and metallic",
        deep: RGBA(0x101114),
        shallow: RGBA(0x9BA3AC),
        light: RGBA(0xFFFFFF),
        choppiness: 1.3,
        glitter: 3.0,
        turbulence: 0.2,
        crestSharpness: 0.15,
        causticStrength: 0.6,
        motionGain: 1.1,
        haptic: .stop
    )

    /// Ordered restful first, so the picker opens on the modes most people want
    /// and the violent ones are a deliberate scroll away.
    public static let all: [OceanTheme] = [
        .calmOcean, .rainShower, .tidePool, .koiPond,
        .underIce, .aurora, .midnightGlow, .deepDrift, .zeroGravity,
        .tropicalLagoon, .moltenCore, .mercury,
        .stormSwell, .breakingSurf, .stormAtNight,
    ]

    public static func theme(id: String) -> OceanTheme {
        all.first(where: { $0.id == id }) ?? .calmOcean
    }
}
