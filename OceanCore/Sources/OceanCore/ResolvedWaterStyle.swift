import Foundation

/// A pure, bounded resolution of an immutable authored theme plus optional
/// Hydro modifiers.
public struct ResolvedWaterStyle: Sendable, Equatable {
    public let choppiness: Double
    public let turbulence: Double
    public let crestSharpness: Double
    public let foaminess: Double
    public let causticStrength: Double
    public let glitter: Double

    /// `nil` preserves every authored value exactly. This is the renderer's
    /// regression boundary for Experiences without Real Water styling.
    public init(base: OceanTheme, modifiers: HydroThemeModifiers?) {
        guard let modifiers else {
            self.init(
                choppiness: base.choppiness,
                turbulence: base.turbulence,
                crestSharpness: base.crestSharpness,
                foaminess: base.foaminess,
                causticStrength: base.causticStrength,
                glitter: base.glitter
            )
            return
        }
        self.init(base: base, modifiers: modifiers)
    }

    public init(base: OceanTheme, modifiers: HydroThemeModifiers) {
        self.init(
            choppiness: Self.clamp(
                base.choppiness + 0.60 * modifiers.choppiness, to: 0...2.5
            ),
            turbulence: Self.clamp(
                base.turbulence + 0.35 * modifiers.turbulence, to: 0...1
            ),
            crestSharpness: Self.clamp(
                base.crestSharpness + 0.25 * modifiers.crestSharpness, to: 0...1
            ),
            foaminess: Self.clamp(
                base.foaminess + 0.35 * modifiers.foaminess, to: 0...1
            ),
            causticStrength: Self.clamp(
                base.causticStrength + 0.25 * modifiers.causticStrength, to: 0...2
            ),
            glitter: Self.clamp(
                base.glitter + 0.50 * modifiers.glitter, to: 0...3.5
            )
        )
    }

    private init(
        choppiness: Double,
        turbulence: Double,
        crestSharpness: Double,
        foaminess: Double,
        causticStrength: Double,
        glitter: Double
    ) {
        self.choppiness = choppiness
        self.turbulence = turbulence
        self.crestSharpness = crestSharpness
        self.foaminess = foaminess
        self.causticStrength = causticStrength
        self.glitter = glitter
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
