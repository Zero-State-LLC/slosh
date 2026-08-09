import Foundation

/// Current-observation state for one reviewed catalog capability. Catalog support
/// remains separate in `catalogAvailability`; a supported sensor can still be
/// missing or stale in the latest assembled snapshot.
public enum HydroSignalObservationAvailability: String, Sendable, Equatable {
    case observed
    case stale
    case missing
    case unavailable
}

public struct HydroSignalStatus: Identifiable, Sendable, Equatable {
    public var id: HydroCapability { capability }

    public let capability: HydroCapability
    public let catalogAvailability: HydroCoverageAvailability
    public let observationAvailability: HydroSignalObservationAvailability
    public let measurements: [HydroMeasurement]
    public let usableForForcing: Bool
    public let usableMeasurementSourceIDs: Set<String>
    public let effectiveObservedAtBySourceID: [String: Date]

    public init(
        capability: HydroCapability,
        catalogAvailability: HydroCoverageAvailability,
        observationAvailability: HydroSignalObservationAvailability,
        measurements: [HydroMeasurement],
        usableForForcing: Bool,
        usableMeasurementSourceIDs: Set<String> = [],
        effectiveObservedAtBySourceID: [String: Date] = [:]
    ) {
        self.capability = capability
        self.catalogAvailability = catalogAvailability
        self.observationAvailability = observationAvailability
        self.measurements = measurements
        self.usableForForcing = usableForForcing
        self.usableMeasurementSourceIDs = usableMeasurementSourceIDs
        self.effectiveObservedAtBySourceID = effectiveObservedAtBySourceID
    }
}

/// User-facing grouping. Wind and current retain their independent speed and
/// direction measurements while avoiding duplicate rows in compact UI.
public enum HydroDisplaySignal: String, CaseIterable, Identifiable, Sendable, Equatable {
    case waterLevel
    case temperature
    case wind
    case pressure
    case salinity
    case current

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .waterLevel: "Water level"
        case .temperature: "Temperature"
        case .wind: "Wind"
        case .pressure: "Pressure"
        case .salinity: "Salinity"
        case .current: "Current"
        }
    }

    public var capabilities: [HydroCapability] {
        switch self {
        case .waterLevel: [.waterLevel]
        case .temperature: [.waterTemperature]
        case .wind: [.wind]
        case .pressure: [.airPressure]
        case .salinity: [.salinity]
        case .current: [.currentSpeed, .currentDirection]
        }
    }
}

public struct HydroDisplaySignalStatus: Identifiable, Sendable, Equatable {
    public var id: HydroDisplaySignal { signal }

    public let signal: HydroDisplaySignal
    public let catalogAvailability: HydroCoverageAvailability
    public let observationAvailability: HydroSignalObservationAvailability
    public let measurements: [HydroMeasurement]
    public let usableForForcing: Bool
    public let usableMeasurementSourceIDs: Set<String>
    public let effectiveObservedAtBySourceID: [String: Date]
}

/// Provider-independent presentation snapshot for one canonical Place.
public struct PlaceHydroStatus: Sendable, Equatable {
    public let waterBodyID: WaterBody.ID
    public let freshness: HydroFreshness
    public let retrievedAt: Date?
    public let signals: [HydroSignalStatus]

    public init(
        waterBodyID: WaterBody.ID,
        freshness: HydroFreshness,
        retrievedAt: Date?,
        signals: [HydroSignalStatus]
    ) {
        self.waterBodyID = waterBodyID
        self.freshness = freshness
        self.retrievedAt = retrievedAt
        self.signals = signals
    }

    public func signal(_ capability: HydroCapability) -> HydroSignalStatus? {
        signals.first { $0.capability == capability }
    }

    public var displaySignals: [HydroDisplaySignalStatus] {
        HydroDisplaySignal.allCases.map { group in
            let members = group.capabilities.compactMap(signal)
            let catalogAvailability: HydroCoverageAvailability = members.contains {
                $0.catalogAvailability == .supported
            } ? .supported : .unavailable
            let observationAvailability: HydroSignalObservationAvailability
            if catalogAvailability == .unavailable {
                observationAvailability = .unavailable
            } else if members.contains(where: { $0.observationAvailability == .observed }) {
                observationAvailability = .observed
            } else if members.contains(where: { $0.observationAvailability == .stale }) {
                observationAvailability = .stale
            } else {
                observationAvailability = .missing
            }
            return HydroDisplaySignalStatus(
                signal: group,
                catalogAvailability: catalogAvailability,
                observationAvailability: observationAvailability,
                measurements: members.flatMap(\.measurements),
                usableForForcing: members.contains(where: \.usableForForcing),
                usableMeasurementSourceIDs: members.reduce(into: []) {
                    $0.formUnion($1.usableMeasurementSourceIDs)
                },
                effectiveObservedAtBySourceID: members.reduce(into: [:]) {
                    $0.merge($1.effectiveObservedAtBySourceID) { first, _ in first }
                }
            )
        }
    }
}

public struct PlaceHydroStatusResolver: Sendable {
    private let interpreter: HydroInterpreter

    public init(interpreter: HydroInterpreter = HydroInterpreter()) {
        self.interpreter = interpreter
    }

    public func resolve(
        waterBody: WaterBody,
        state: HydroState?,
        referenceDate: Date
    ) -> PlaceHydroStatus {
        PlaceHydroStatus(
            waterBodyID: waterBody.id,
            freshness: state.map {
                interpreter.freshness(of: $0, referenceDate: referenceDate)
            } ?? .unavailable,
            retrievedAt: state?.retrievedAt,
            signals: HydroCapability.allCases.map { capability in
                resolve(
                    capability: capability,
                    catalogAvailability: waterBody.coverage[capability] ?? .unavailable,
                    state: state,
                    referenceDate: referenceDate
                )
            }
        )
    }

    private func resolve(
        capability: HydroCapability,
        catalogAvailability: HydroCoverageAvailability,
        state: HydroState?,
        referenceDate: Date
    ) -> HydroSignalStatus {
        guard catalogAvailability == .supported else {
            return HydroSignalStatus(
                capability: capability,
                catalogAvailability: .unavailable,
                observationAvailability: .unavailable,
                measurements: [],
                usableForForcing: false
            )
        }
        guard let state else {
            return HydroSignalStatus(
                capability: capability,
                catalogAvailability: .supported,
                observationAvailability: .missing,
                measurements: [],
                usableForForcing: false
            )
        }

        let measurements = measurementPairs(for: capability, state: state)
        guard !measurements.isEmpty else {
            return HydroSignalStatus(
                capability: capability,
                catalogAvailability: .supported,
                observationAvailability: .missing,
                measurements: [],
                usableForForcing: false
            )
        }

        let usable = measurements.contains { measurement, unit in
            interpreter.isSignalUsable(
                measurement,
                expectedUnit: unit,
                stateObservedAt: state.observedAt,
                referenceDate: referenceDate
            )
        }
        let usableSourceIDs = Set(measurements.compactMap { measurement, unit in
            interpreter.isSignalUsable(
                measurement,
                expectedUnit: unit,
                stateObservedAt: state.observedAt,
                referenceDate: referenceDate
            ) ? measurement.sourceID : nil
        })
        let allTemporallyUnusable = measurements.allSatisfy { measurement, _ in
            !interpreter.isSignalTimestampUsable(
                measurement,
                stateObservedAt: state.observedAt,
                referenceDate: referenceDate
            )
        }
        return HydroSignalStatus(
            capability: capability,
            catalogAvailability: .supported,
            observationAvailability: allTemporallyUnusable ? .stale : .observed,
            measurements: measurements.map(\.0),
            usableForForcing: usable,
            usableMeasurementSourceIDs: usableSourceIDs,
            effectiveObservedAtBySourceID: Dictionary(
                uniqueKeysWithValues: measurements.map {
                    ($0.0.sourceID, $0.0.observedAt ?? state.observedAt)
                }
            )
        )
    }

    private func measurementPairs(
        for capability: HydroCapability,
        state: HydroState
    ) -> [(HydroMeasurement, HydroUnit)] {
        switch capability {
        case .waterLevel: pair(state.waterLevel, .meters)
        case .waterTemperature: pair(state.waterTemperature, .celsius)
        case .wind:
            pair(state.windSpeed, .metersPerSecond) + pair(state.windDirection, .degreesTrue)
        case .airPressure: pair(state.pressure, .hectopascals)
        case .salinity: pair(state.salinity, .practicalSalinityUnits)
        case .currentSpeed: pair(state.currentSpeed, .metersPerSecond)
        case .currentDirection: pair(state.currentDirection, .degreesTrue)
        }
    }

    private func pair(
        _ measurement: HydroMeasurement?,
        _ unit: HydroUnit
    ) -> [(HydroMeasurement, HydroUnit)] {
        measurement.map { [($0, unit)] } ?? []
    }
}

public enum RealWaterLoadDisposition: Sendable, Equatable {
    case updated
    case preserved
    case unavailable
}

public enum RealWaterLoadState: Sendable, Equatable {
    case inactive
    case loading(WaterBody.ID)
    case loaded(PlaceHydroStatus)
    case preserved(PlaceHydroStatus)
    case unavailable(WaterBody.ID)

    public var waterBodyID: WaterBody.ID? {
        switch self {
        case .inactive: nil
        case let .loading(id), let .unavailable(id): id
        case let .loaded(status), let .preserved(status): status.waterBodyID
        }
    }

    public var status: PlaceHydroStatus? {
        switch self {
        case let .loaded(status), let .preserved(status): status
        default: nil
        }
    }
}

/// Pure application-boundary reducer. Results are accepted only for the active
/// canonical Place ID, so a late completion cannot repaint a newer selection.
public struct RealWaterLoadReducer: Sendable, Equatable {
    public private(set) var state: RealWaterLoadState = .inactive
    private var requestGeneration: UInt64 = 0

    public init() {}

    @discardableResult
    public mutating func beginLoading(waterBodyID: WaterBody.ID) -> UInt64 {
        requestGeneration &+= 1
        state = .loading(waterBodyID)
        return requestGeneration
    }

    @discardableResult
    public mutating func accept(
        _ disposition: RealWaterLoadDisposition,
        status: PlaceHydroStatus?,
        waterBodyID: WaterBody.ID,
        requestGeneration: UInt64
    ) -> Bool {
        guard self.requestGeneration == requestGeneration,
              state.waterBodyID == waterBodyID else { return false }
        switch disposition {
        case .updated:
            guard let status, status.waterBodyID == waterBodyID else { return false }
            state = .loaded(status)
        case .preserved:
            guard let status, status.waterBodyID == waterBodyID else { return false }
            state = .preserved(status)
        case .unavailable:
            state = .unavailable(waterBodyID)
        }
        return true
    }

    public mutating func deactivate() {
        requestGeneration &+= 1
        state = .inactive
    }
}

public struct HydroSourcePresentation: Sendable, Equatable {
    public let providerName: String
    public let sourceName: String
    public let canonicalSourceID: String
}

public enum HydroPresentationFormatter {
    public static func source(_ sourceID: String) -> HydroSourcePresentation {
        let parts = sourceID.split(separator: ".").map(String.init)
        if parts.count >= 3, parts[0] == "noaa", parts[1] == "coops" {
            return HydroSourcePresentation(
                providerName: "NOAA CO-OPS",
                sourceName: "Station \(parts[2])",
                canonicalSourceID: sourceID
            )
        }
        if parts.count >= 3, parts[0] == "usgs", parts[1] == "nwis" {
            return HydroSourcePresentation(
                providerName: "USGS",
                sourceName: "Site \(parts[2])",
                canonicalSourceID: sourceID
            )
        }
        return HydroSourcePresentation(
            providerName: "Observation source",
            sourceName: sourceID,
            canonicalSourceID: sourceID
        )
    }

    public static func freshness(_ freshness: HydroFreshness) -> String {
        switch freshness {
        case .live: "Live"
        case .recent: "Recent"
        case .stale: "Stale"
        case .unavailable: "Unavailable"
        }
    }

    public static func age(observedAt: Date, referenceDate: Date) -> String {
        let seconds = max(0, referenceDate.timeIntervalSince(observedAt))
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "Observed just now" }
        if minutes < 60 { return "Observed \(minutes) min ago" }
        let hours = minutes / 60
        return "Observed \(hours) hr ago"
    }

    public static func quality(_ quality: HydroQuality, used: Bool) -> String {
        switch quality {
        case .good: "Good"
        case .unknown: "Provisional / Unknown"
        case .suspect: used ? "Suspect" : "Suspect · not used"
        }
    }

    public static func origin(_ origin: HydroOrigin) -> String {
        switch origin {
        case .observed: "Observed"
        case .forecast: "Forecast"
        case .predicted: "Predicted"
        case .derived: "Derived"
        }
    }

    public static func value(_ measurement: HydroMeasurement) -> String {
        let number = String(format: "%.1f", measurement.value)
        return switch measurement.unit {
        case .meters: "\(number) m"
        case .metersPerSecond: "\(number) m/s"
        case .degreesTrue: "\(number)°"
        case .seconds: "\(number) s"
        case .celsius: "\(number) °C"
        case .hectopascals: "\(number) hPa"
        case .practicalSalinityUnits: "\(number) PSU"
        }
    }
}
