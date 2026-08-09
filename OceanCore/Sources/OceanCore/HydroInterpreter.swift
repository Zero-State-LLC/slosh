import Foundation

/// Deterministic perceptual translation from environmental measurements into
/// Slosh's water vocabulary. This is intentionally not a hydrodynamic model.
public struct HydroInterpreter: Sendable {
    public enum FreshnessThresholds {
        public static let live: TimeInterval = 15 * 60
        public static let recent: TimeInterval = 60 * 60
        public static let maxFutureClockSkew: TimeInterval = 5 * 60
    }

    public init() {}

    public func interpret(_ state: HydroState, referenceDate: Date) -> HydroExperience {
        let wave = normalized(state.waveHeight, unit: .meters, maximum: 5)
        let current = normalized(state.currentSpeed, unit: .metersPerSecond, maximum: 2.5)
        let wind = normalized(state.windSpeed, unit: .metersPerSecond, maximum: 25)
        let period = waveRate(state.wavePeriod)

        let level = normalizedMagnitude(state.waterLevel, unit: .meters, maximum: 3)
        let temperature = normalizedDeviation(state.waterTemperature, unit: .celsius, center: 15, span: 20)
        let pressure = normalizedDeviation(state.pressure, unit: .hectopascals, center: 1013.25, span: 45)
        let salinity = normalizedDeviation(state.salinity, unit: .practicalSalinityUnits, center: 32, span: 20)
        let secondary = clamp((level + temperature + pressure + salinity) * 0.025)

        let waveValue = wave ?? 0
        let currentValue = current ?? 0
        let windValue = wind ?? 0
        let periodValue = period ?? 0
        let combinedWaveWind = waveValue * windValue

        let energy = clamp(0.08 + 0.55 * waveValue + 0.20 * currentValue + 0.14 * windValue + secondary)
        let chop = clamp(0.58 * waveValue + 0.32 * windValue + 0.10 * periodValue + secondary)
        let turbulence = clamp(0.62 * windValue + 0.23 * currentValue + 0.15 * waveValue + secondary)
        let foam = clamp(0.55 * combinedWaveWind + 0.30 * waveValue + 0.15 * windValue)

        let forcing = EnvironmentalForcing(
            energy: energy,
            chop: chop,
            turbulence: turbulence,
            flowDirection: direction(state.currentDirection),
            flowStrength: currentValue,
            waveAmplitude: waveValue,
            waveRate: periodValue,
            foamPotential: foam,
            windDirection: direction(state.windDirection),
            windStrength: windValue,
            freshness: freshness(of: state, referenceDate: referenceDate)
        )

        let modifiers = HydroThemeModifiers(
            choppiness: clamp(chop * 0.55),
            turbulence: clamp(turbulence * 0.60),
            crestSharpness: clamp(0.65 * combinedWaveWind + 0.20 * waveValue),
            foaminess: clamp(foam * 0.70),
            causticStrength: clamp(secondary * 0.35),
            glitter: clamp(0.12 * windValue + 0.08 * waveValue)
        )
        return HydroExperience(forcing: forcing, themeModifiers: modifiers)
    }

    public func freshness(of state: HydroState, referenceDate: Date) -> HydroFreshness {
        guard hasUsableMeasurement(state) else { return .unavailable }
        guard state.observedAt <= referenceDate.addingTimeInterval(
            FreshnessThresholds.maxFutureClockSkew
        ) else { return .unavailable }
        let age = max(0, referenceDate.timeIntervalSince(state.observedAt))
        if age <= FreshnessThresholds.live { return .live }
        if age <= FreshnessThresholds.recent { return .recent }
        return .stale
    }

    private func normalized(_ measurement: HydroMeasurement?, unit: HydroUnit, maximum: Double) -> Double? {
        guard isUsable(measurement, unit: unit) else { return nil }
        guard let measurement else { return nil }
        return clamp(measurement.value / maximum)
    }

    private func normalizedMagnitude(
        _ measurement: HydroMeasurement?, unit: HydroUnit, maximum: Double
    ) -> Double {
        guard isUsable(measurement, unit: unit), let measurement else { return 0 }
        return clamp(abs(measurement.value) / maximum)
    }

    private func normalizedDeviation(
        _ measurement: HydroMeasurement?, unit: HydroUnit, center: Double, span: Double
    ) -> Double {
        guard isUsable(measurement, unit: unit), let measurement else { return 0 }
        return clamp(abs(measurement.value - center) / span)
    }

    private func waveRate(_ measurement: HydroMeasurement?) -> Double? {
        guard let measurement,
              measurement.unit == .seconds,
              measurement.quality != .suspect,
              measurement.value.isFinite,
              measurement.value > 0 else { return nil }
        // Short periods read as faster water. Twenty seconds and above settle at
        // zero; two seconds and below reach the normalized ceiling.
        return clamp((20 - measurement.value) / 18)
    }

    private func direction(_ measurement: HydroMeasurement?) -> Double? {
        guard let measurement,
              measurement.unit == .degreesTrue,
              measurement.quality != .suspect,
              measurement.value.isFinite,
              let convention = measurement.directionConvention else { return nil }
        let towardDegrees = measurement.value + (convention == .from ? 180 : 0)
        let degrees = towardDegrees.truncatingRemainder(dividingBy: 360)
        let positive = degrees < 0 ? degrees + 360 : degrees
        return positive * .pi / 180
    }

    private func hasUsableMeasurement(_ state: HydroState) -> Bool {
        let expected: [(HydroMeasurement?, HydroUnit)] = [
            (state.waterLevel, .meters),
            (state.waterTemperature, .celsius),
            (state.currentSpeed, .metersPerSecond),
            (state.currentDirection, .degreesTrue),
            (state.waveHeight, .meters),
            (state.wavePeriod, .seconds),
            (state.windSpeed, .metersPerSecond),
            (state.windDirection, .degreesTrue),
            (state.pressure, .hectopascals),
            (state.salinity, .practicalSalinityUnits),
        ]
        return expected.contains { measurement, unit in
            isUsable(measurement, unit: unit)
        }
    }

    private func isUsable(_ measurement: HydroMeasurement?, unit: HydroUnit) -> Bool {
        guard let measurement,
              measurement.unit == unit,
              measurement.quality != .suspect,
              measurement.value.isFinite else { return false }
        if unit == .degreesTrue { return measurement.directionConvention != nil }
        return true
    }

    private func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
