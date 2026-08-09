import Foundation

/// Provider-independent state for one body of water at one observation time.
/// Missing measurements remain `nil`; zero is always a real measured value.
public struct HydroState: Sendable, Equatable {
    public var observedAt: Date
    public var retrievedAt: Date
    public var waterLevel: HydroMeasurement?
    public var waterTemperature: HydroMeasurement?
    public var currentSpeed: HydroMeasurement?
    public var currentDirection: HydroMeasurement?
    public var waveHeight: HydroMeasurement?
    public var wavePeriod: HydroMeasurement?
    public var windSpeed: HydroMeasurement?
    public var windDirection: HydroMeasurement?
    public var pressure: HydroMeasurement?
    public var salinity: HydroMeasurement?

    public init(
        observedAt: Date,
        retrievedAt: Date,
        waterLevel: HydroMeasurement? = nil,
        waterTemperature: HydroMeasurement? = nil,
        currentSpeed: HydroMeasurement? = nil,
        currentDirection: HydroMeasurement? = nil,
        waveHeight: HydroMeasurement? = nil,
        wavePeriod: HydroMeasurement? = nil,
        windSpeed: HydroMeasurement? = nil,
        windDirection: HydroMeasurement? = nil,
        pressure: HydroMeasurement? = nil,
        salinity: HydroMeasurement? = nil
    ) {
        self.observedAt = observedAt
        self.retrievedAt = retrievedAt
        self.waterLevel = waterLevel
        self.waterTemperature = waterTemperature
        self.currentSpeed = currentSpeed
        self.currentDirection = currentDirection
        self.waveHeight = waveHeight
        self.wavePeriod = wavePeriod
        self.windSpeed = windSpeed
        self.windDirection = windDirection
        self.pressure = pressure
        self.salinity = salinity
    }
}

public struct HydroMeasurement: Sendable, Equatable {
    public var value: Double
    public var unit: HydroUnit
    public var origin: HydroOrigin
    public var quality: HydroQuality
    public var sourceID: String
    /// Provider observation time when products in one state were not sampled
    /// simultaneously. `HydroState.observedAt` remains the conservative summary.
    public var observedAt: Date?
    /// Required for directional measurements. The interpreter converts both
    /// conventions to canonical direction-of-forcing-toward radians.
    public var directionConvention: HydroDirectionConvention?

    public init(
        value: Double,
        unit: HydroUnit,
        origin: HydroOrigin,
        quality: HydroQuality,
        sourceID: String,
        observedAt: Date? = nil,
        directionConvention: HydroDirectionConvention? = nil
    ) {
        self.value = value
        self.unit = unit
        self.origin = origin
        self.quality = quality
        self.sourceID = sourceID
        self.observedAt = observedAt
        self.directionConvention = directionConvention
    }
}

/// Whether a reported bearing names where a force travels or where it came from.
public enum HydroDirectionConvention: String, Sendable, Equatable {
    case toward
    case from
}

public enum HydroUnit: String, Sendable, Equatable {
    case meters
    case metersPerSecond
    case degreesTrue
    case seconds
    case celsius
    case hectopascals
    case practicalSalinityUnits
}

public enum HydroOrigin: String, Sendable, Equatable {
    case observed
    case forecast
    case predicted
    case derived
}

public enum HydroQuality: String, Sendable, Equatable {
    case good
    case suspect
    case unknown
}

public enum HydroFreshness: String, Sendable, Equatable {
    case live
    case recent
    case stale
    case unavailable
}
