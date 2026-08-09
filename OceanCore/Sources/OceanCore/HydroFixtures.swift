import Foundation

/// Synthetic, provider-independent fixtures for tests and previews only.
/// They are not observations of any geographic place.
public enum HydroFixtures {
    public static let referenceDate = Date(timeIntervalSince1970: 1_735_689_600)

    public static let calm = state(
        waveHeight: 0.25, wavePeriod: 8, currentSpeed: 0.15,
        currentDirection: 240, windSpeed: 3, windDirection: 270,
        waterLevel: 0.4, temperature: 15, pressure: 1015, salinity: 32
    )

    public static let active = state(
        waveHeight: 1.2, wavePeriod: 6.5, currentSpeed: 0.8,
        currentDirection: 225, windSpeed: 10, windDirection: 260,
        waterLevel: 1.0, temperature: 13, pressure: 1005, salinity: 30
    )

    public static let severe = state(
        waveHeight: 4.5, wavePeriod: 4.5, currentSpeed: 2.2,
        currentDirection: 200, windSpeed: 25, windDirection: 240,
        waterLevel: 2.4, temperature: 9, pressure: 975, salinity: 25
    )

    private static func measurement(
        _ value: Double,
        _ unit: HydroUnit,
        _ id: String,
        directionConvention: HydroDirectionConvention? = nil
    ) -> HydroMeasurement {
        HydroMeasurement(
            value: value,
            unit: unit,
            origin: .observed,
            quality: .good,
            sourceID: id,
            directionConvention: directionConvention
        )
    }

    private static func state(
        waveHeight: Double, wavePeriod: Double, currentSpeed: Double,
        currentDirection: Double, windSpeed: Double, windDirection: Double,
        waterLevel: Double, temperature: Double, pressure: Double, salinity: Double
    ) -> HydroState {
        HydroState(
            observedAt: referenceDate.addingTimeInterval(-5 * 60),
            retrievedAt: referenceDate,
            waterLevel: measurement(waterLevel, .meters, "fixture.water-level"),
            waterTemperature: measurement(temperature, .celsius, "fixture.temperature"),
            currentSpeed: measurement(currentSpeed, .metersPerSecond, "fixture.current-speed"),
            currentDirection: measurement(
                currentDirection, .degreesTrue, "fixture.current-direction",
                directionConvention: .toward
            ),
            waveHeight: measurement(waveHeight, .meters, "fixture.wave-height"),
            wavePeriod: measurement(wavePeriod, .seconds, "fixture.wave-period"),
            windSpeed: measurement(windSpeed, .metersPerSecond, "fixture.wind-speed"),
            windDirection: measurement(
                windDirection, .degreesTrue, "fixture.wind-direction",
                directionConvention: .from
            ),
            pressure: measurement(pressure, .hectopascals, "fixture.pressure"),
            salinity: measurement(salinity, .practicalSalinityUnits, "fixture.salinity")
        )
    }
}
