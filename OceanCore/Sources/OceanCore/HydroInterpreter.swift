import Foundation

/// Deterministic perceptual translation from environmental measurements into
/// Slosh's water vocabulary. This is intentionally not a hydrodynamic model.
public struct HydroInterpreter: Sendable {
    public enum FreshnessThresholds {
        public static let live: TimeInterval = 15 * 60
        public static let recent: TimeInterval = 60 * 60
        /// Dynamic signals older than this remain evidence in `HydroState` but
        /// cannot affect perceptual forcing.
        public static let signalUsable: TimeInterval = recent
        public static let maxFutureClockSkew: TimeInterval = 5 * 60
    }

    public init() {}

    public func interpret(_ state: HydroState, referenceDate: Date) -> HydroExperience {
        let wave = normalized(
            state.waveHeight, unit: .meters, maximum: 5,
            stateObservedAt: state.observedAt, referenceDate: referenceDate
        )
        let current = normalized(
            state.currentSpeed, unit: .metersPerSecond, maximum: 2.5,
            stateObservedAt: state.observedAt, referenceDate: referenceDate
        )
        let wind = normalized(
            state.windSpeed, unit: .metersPerSecond, maximum: 25,
            stateObservedAt: state.observedAt, referenceDate: referenceDate
        )
        let period = waveRate(
            state.wavePeriod, stateObservedAt: state.observedAt, referenceDate: referenceDate
        )

        let level = normalizedMagnitude(
            state.waterLevel, unit: .meters, maximum: 3,
            stateObservedAt: state.observedAt, referenceDate: referenceDate
        )
        let temperature = normalizedDeviation(
            state.waterTemperature, unit: .celsius, center: 15, span: 20,
            stateObservedAt: state.observedAt, referenceDate: referenceDate
        )
        let pressure = normalizedDeviation(
            state.pressure, unit: .hectopascals, center: 1013.25, span: 45,
            stateObservedAt: state.observedAt, referenceDate: referenceDate
        )
        let salinity = normalizedDeviation(
            state.salinity, unit: .practicalSalinityUnits, center: 32, span: 20,
            stateObservedAt: state.observedAt, referenceDate: referenceDate
        )
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
            flowDirection: direction(
                state.currentDirection,
                stateObservedAt: state.observedAt,
                referenceDate: referenceDate
            ),
            flowStrength: currentValue,
            waveAmplitude: waveValue,
            waveRate: periodValue,
            foamPotential: foam,
            windDirection: direction(
                state.windDirection,
                stateObservedAt: state.observedAt,
                referenceDate: referenceDate
            ),
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

    private func normalized(
        _ measurement: HydroMeasurement?,
        unit: HydroUnit,
        maximum: Double,
        stateObservedAt: Date,
        referenceDate: Date
    ) -> Double? {
        guard isSignalUsable(
            measurement, expectedUnit: unit,
            stateObservedAt: stateObservedAt, referenceDate: referenceDate
        ) else { return nil }
        guard let measurement else { return nil }
        return clamp(measurement.value / maximum)
    }

    private func normalizedMagnitude(
        _ measurement: HydroMeasurement?, unit: HydroUnit, maximum: Double,
        stateObservedAt: Date, referenceDate: Date
    ) -> Double {
        guard isSignalUsable(
            measurement, expectedUnit: unit,
            stateObservedAt: stateObservedAt, referenceDate: referenceDate
        ), let measurement else { return 0 }
        return clamp(abs(measurement.value) / maximum)
    }

    private func normalizedDeviation(
        _ measurement: HydroMeasurement?, unit: HydroUnit, center: Double, span: Double,
        stateObservedAt: Date, referenceDate: Date
    ) -> Double {
        guard isSignalUsable(
            measurement, expectedUnit: unit,
            stateObservedAt: stateObservedAt, referenceDate: referenceDate
        ), let measurement else { return 0 }
        return clamp(abs(measurement.value - center) / span)
    }

    private func waveRate(
        _ measurement: HydroMeasurement?, stateObservedAt: Date, referenceDate: Date
    ) -> Double? {
        guard let measurement,
              isSignalUsable(
                measurement, expectedUnit: .seconds,
                stateObservedAt: stateObservedAt, referenceDate: referenceDate
              ),
              measurement.value > 0 else { return nil }
        // Short periods read as faster water. Twenty seconds and above settle at
        // zero; two seconds and below reach the normalized ceiling.
        return clamp((20 - measurement.value) / 18)
    }

    private func direction(
        _ measurement: HydroMeasurement?, stateObservedAt: Date, referenceDate: Date
    ) -> Double? {
        guard let measurement,
              isSignalUsable(
                measurement, expectedUnit: .degreesTrue,
                stateObservedAt: stateObservedAt, referenceDate: referenceDate
              ), let convention = measurement.directionConvention else { return nil }
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
            isStructurallyUsable(measurement, expectedUnit: unit)
        }
    }

    /// One authoritative dynamic-signal gate. Missing per-product timestamps use
    /// the snapshot summary; raw measurements are never removed or rewritten.
    public func isSignalUsable(
        _ measurement: HydroMeasurement?,
        expectedUnit: HydroUnit,
        stateObservedAt: Date,
        referenceDate: Date
    ) -> Bool {
        guard isStructurallyUsable(measurement, expectedUnit: expectedUnit),
              let measurement else { return false }
        return isSignalTimestampUsable(
            measurement,
            stateObservedAt: stateObservedAt,
            referenceDate: referenceDate
        )
    }

    /// The shared temporal portion of signal usability. Presentation uses this
    /// to distinguish stale evidence from a timely-but-suspect observation while
    /// the complete forcing gate remains `isSignalUsable`.
    public func isSignalTimestampUsable(
        _ measurement: HydroMeasurement,
        stateObservedAt: Date,
        referenceDate: Date
    ) -> Bool {
        let observedAt = measurement.observedAt ?? stateObservedAt
        guard observedAt <= referenceDate.addingTimeInterval(
            FreshnessThresholds.maxFutureClockSkew
        ) else { return false }
        return referenceDate.timeIntervalSince(observedAt)
            <= FreshnessThresholds.signalUsable
    }

    private func isStructurallyUsable(
        _ measurement: HydroMeasurement?, expectedUnit: HydroUnit
    ) -> Bool {
        guard let measurement,
              measurement.unit == expectedUnit,
              measurement.quality != .suspect,
              measurement.value.isFinite else { return false }
        if expectedUnit == .degreesTrue { return measurement.directionConvention != nil }
        return true
    }

    private func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
