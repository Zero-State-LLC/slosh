import Foundation

/// Normalized environmental influence, independent of renderer and UI.
public struct EnvironmentalForcing: Sendable, Equatable {
    public private(set) var energy: Double
    public private(set) var chop: Double
    public private(set) var turbulence: Double
    public private(set) var flowDirection: Double?
    public private(set) var flowStrength: Double
    public private(set) var waveAmplitude: Double
    public private(set) var waveRate: Double
    public private(set) var foamPotential: Double
    public private(set) var windDirection: Double?
    public private(set) var windStrength: Double
    public private(set) var freshness: HydroFreshness

    public init(
        energy: Double,
        chop: Double,
        turbulence: Double,
        flowDirection: Double?,
        flowStrength: Double,
        waveAmplitude: Double,
        waveRate: Double,
        foamPotential: Double,
        windDirection: Double?,
        windStrength: Double,
        freshness: HydroFreshness
    ) {
        self.energy = Self.normalized(energy)
        self.chop = Self.normalized(chop)
        self.turbulence = Self.normalized(turbulence)
        self.flowDirection = Self.finiteDirection(flowDirection)
        self.flowStrength = Self.normalized(flowStrength)
        self.waveAmplitude = Self.normalized(waveAmplitude)
        self.waveRate = Self.normalized(waveRate)
        self.foamPotential = Self.normalized(foamPotential)
        self.windDirection = Self.finiteDirection(windDirection)
        self.windStrength = Self.normalized(windStrength)
        self.freshness = freshness
    }

    private static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func finiteDirection(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }
}

/// Additive influences expressed only in vocabulary the existing renderer owns.
public struct HydroThemeModifiers: Sendable, Equatable {
    public private(set) var choppiness: Double
    public private(set) var turbulence: Double
    public private(set) var crestSharpness: Double
    public private(set) var foaminess: Double
    public private(set) var causticStrength: Double
    public private(set) var glitter: Double

    public init(
        choppiness: Double,
        turbulence: Double,
        crestSharpness: Double,
        foaminess: Double,
        causticStrength: Double,
        glitter: Double
    ) {
        self.choppiness = Self.normalized(choppiness)
        self.turbulence = Self.normalized(turbulence)
        self.crestSharpness = Self.normalized(crestSharpness)
        self.foaminess = Self.normalized(foaminess)
        self.causticStrength = Self.normalized(causticStrength)
        self.glitter = Self.normalized(glitter)
    }

    private static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

public struct HydroExperience: Sendable, Equatable {
    public var forcing: EnvironmentalForcing
    public var themeModifiers: HydroThemeModifiers

    public init(forcing: EnvironmentalForcing, themeModifiers: HydroThemeModifiers) {
        self.forcing = forcing
        self.themeModifiers = themeModifiers
    }
}
