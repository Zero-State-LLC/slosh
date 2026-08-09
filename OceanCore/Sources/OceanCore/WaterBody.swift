import Foundation

public struct WaterBody: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let region: String
    public let latitude: Double
    public let longitude: Double
    public let kind: WaterBodyKind
    public let sourceBindings: [HydroSourceBinding]

    public init(
        id: String,
        name: String,
        region: String,
        latitude: Double,
        longitude: Double,
        kind: WaterBodyKind,
        sourceBindings: [HydroSourceBinding]
    ) {
        self.id = id
        self.name = name
        self.region = region
        self.latitude = latitude
        self.longitude = longitude
        self.kind = kind
        self.sourceBindings = sourceBindings
    }

    public var capabilities: Set<HydroCapability> {
        sourceBindings.reduce(into: []) { result, binding in
            result.formUnion(binding.capabilities)
        }
    }
}

public enum WaterBodyKind: String, Sendable, Equatable {
    case bay
    case ocean
    case sound
    case lake
    case river
    case estuary
    case gulf
}

public enum HydroCapability: String, Sendable, Equatable, Hashable, CaseIterable {
    case waterLevel
    case waterTemperature
    case wind
    case airPressure
    case salinity
    case currentSpeed
    case currentDirection
}

/// An opaque binding from a product place to an external observation source.
/// OceanCore does not interpret the namespace, source identifier, or parameters;
/// provider targets own that resolution and may ignore bindings they do not own.
public struct HydroSourceBinding: Sendable, Equatable {
    public let namespace: String
    public let sourceID: String
    public let capabilities: Set<HydroCapability>
    public let parameters: [String: String]

    public init(
        namespace: String,
        sourceID: String,
        capabilities: Set<HydroCapability>,
        parameters: [String: String] = [:]
    ) {
        self.namespace = namespace
        self.sourceID = sourceID
        self.capabilities = capabilities
        self.parameters = parameters
    }
}

public enum WaterBodies {
    /// The first curated Real Water place. Capabilities reflect active NOAA
    /// observations reviewed for RW2B, not every sensor ever installed nearby.
    public static let sanFranciscoBay = WaterBody(
        id: "san-francisco-bay",
        name: "San Francisco Bay",
        region: "California, USA",
        latitude: 37.806305,
        longitude: -122.46589,
        kind: .bay,
        sourceBindings: [
            HydroSourceBinding(
                namespace: "gov.noaa.coops.station",
                sourceID: "9414290",
                capabilities: [.waterLevel, .wind, .airPressure]
            ),
            HydroSourceBinding(
                namespace: "gov.noaa.coops.current-station",
                sourceID: "s09010",
                capabilities: [.currentSpeed, .currentDirection],
                parameters: ["bin": "2"]
            ),
        ]
    )

    public static let all: [WaterBody] = [sanFranciscoBay]

    public static func body(id: String) -> WaterBody? {
        all.first { $0.id == id }
    }
}
