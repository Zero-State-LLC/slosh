import Foundation

/// Provider-independent annotation content for the curated product catalog.
/// Coordinates describe a canonical WaterBody, never an underlying sensor.
public struct CuratedPlaceMapAnnotation: Identifiable, Sendable, Equatable {
    public let id: WaterBody.ID
    public let name: String
    public let region: String
    public let latitude: Double
    public let longitude: Double
    public let coverageSummary: String
    public let statusText: String
    public let isCurrent: Bool

    public init(
        waterBody: WaterBody,
        state: PlaceObservationLoadState,
        isCurrent: Bool
    ) {
        id = waterBody.id
        name = waterBody.name
        region = waterBody.region
        latitude = waterBody.latitude
        longitude = waterBody.longitude
        coverageSummary = HydroDisplaySignal.allCases
            .filter { signal in
                signal.capabilities.contains { waterBody.coverage[$0] == .supported }
            }
            .map(\.displayName)
            .joined(separator: " · ")
        statusText = Self.statusText(for: state)
        self.isCurrent = isCurrent
    }

    private static func statusText(for state: PlaceObservationLoadState) -> String {
        switch state {
        case .idle: "Reviewed coverage"
        case .loading: "Loading"
        case let .loaded(status): HydroPresentationFormatter.freshness(status.freshness)
        case let .preserved(status): "Preserved · \(HydroPresentationFormatter.freshness(status.freshness))"
        case .unavailable: "Unavailable"
        }
    }
}

public struct CuratedPlacesMapSnapshot: Sendable, Equatable {
    public let annotations: [CuratedPlaceMapAnnotation]

    public init(
        waterBodies: [WaterBody] = WaterBodies.all,
        observations: PlaceObservationStore,
        selectedPlaceID: WaterBody.ID?
    ) {
        annotations = waterBodies.map { waterBody in
            CuratedPlaceMapAnnotation(
                waterBody: waterBody,
                state: observations.state(for: waterBody.id),
                isCurrent: selectedPlaceID == waterBody.id
            )
        }
    }
}

/// Browsing and wearing are deliberately separate. Inspecting a pin has no
/// persistence or transport side effect; only an explicit wear action changes
/// the canonical selected Place.
public struct CuratedPlaceBrowsingState: Sendable, Equatable {
    public private(set) var inspectedPlaceID: WaterBody.ID?
    public private(set) var selectedPlaceID: WaterBody.ID?

    public init(
        inspectedPlaceID: WaterBody.ID? = nil,
        selectedPlaceID: WaterBody.ID? = nil
    ) {
        self.inspectedPlaceID = inspectedPlaceID
        self.selectedPlaceID = selectedPlaceID
    }

    public mutating func inspect(_ waterBodyID: WaterBody.ID) {
        inspectedPlaceID = waterBodyID
    }

    public mutating func wearInspectedPlace() {
        selectedPlaceID = inspectedPlaceID
    }
}
