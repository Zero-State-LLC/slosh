import Foundation

public enum GeographicFeatureKind: String, Sendable, Equatable, Codable {
    case lakePond
    case reservoir
    case riverStream
    case estuary
    case bay
    case coastline
}

public struct GeographicBoundingBox: Sendable, Equatable, Codable {
    public let minimumLatitude: Double
    public let minimumLongitude: Double
    public let maximumLatitude: Double
    public let maximumLongitude: Double

    public init(minimumLatitude: Double, minimumLongitude: Double, maximumLatitude: Double, maximumLongitude: Double) {
        self.minimumLatitude = minimumLatitude
        self.minimumLongitude = minimumLongitude
        self.maximumLatitude = maximumLatitude
        self.maximumLongitude = maximumLongitude
    }

    public func contains(_ coordinate: GeographicCoordinate) -> Bool {
        coordinate.isValid
            && minimumLatitude <= maximumLatitude
            && minimumLongitude <= maximumLongitude
            && (minimumLatitude ... maximumLatitude).contains(coordinate.latitude)
            && (minimumLongitude ... maximumLongitude).contains(coordinate.longitude)
    }
}

public struct GeographicFeatureProvenance: Sendable, Equatable, Codable {
    public let authorityName: String
    public let datasetName: String
    public let datasetVersion: String
    public let collectionName: String
    public let serviceReference: String
    public let geometryReference: String

    public init(
        authorityName: String,
        datasetName: String,
        datasetVersion: String,
        collectionName: String,
        serviceReference: String,
        geometryReference: String
    ) {
        self.authorityName = authorityName
        self.datasetName = datasetName
        self.datasetVersion = datasetVersion
        self.collectionName = collectionName
        self.serviceReference = serviceReference
        self.geometryReference = geometryReference
    }
}

public struct AuthoritativeGeographicFeature: Sendable, Equatable, Codable {
    public let identity: GeographicFeatureIdentity
    public let featureKind: GeographicFeatureKind
    public let hydrologicUnitID: String?
    public let provenance: GeographicFeatureProvenance
    public let boundingBox: GeographicBoundingBox
    public let polygon: [GeographicCoordinate]

    public init(
        identity: GeographicFeatureIdentity,
        featureKind: GeographicFeatureKind,
        hydrologicUnitID: String?,
        provenance: GeographicFeatureProvenance,
        boundingBox: GeographicBoundingBox,
        polygon: [GeographicCoordinate]
    ) {
        self.identity = identity
        self.featureKind = featureKind
        self.hydrologicUnitID = hydrologicUnitID
        self.provenance = provenance
        self.boundingBox = boundingBox
        self.polygon = polygon
    }

    /// Boundary semantics are conservative and deterministic: a point exactly on
    /// the authoritative polygon boundary counts as contained for candidate
    /// generation. Malformed polygons fail closed.
    public func contains(_ coordinate: GeographicCoordinate) -> Bool {
        guard boundingBox.contains(coordinate), isValidSingleRingPolygon else { return false }
        var inside = false
        var previous = polygon.count - 1
        for current in polygon.indices {
            let a = polygon[current]
            let b = polygon[previous]
            if point(coordinate, isOnSegmentFrom: a, to: b) { return true }
            let crosses = ((a.longitude > coordinate.longitude) != (b.longitude > coordinate.longitude))
                && (coordinate.latitude < (b.latitude - a.latitude) * (coordinate.longitude - a.longitude) / (b.longitude - a.longitude) + a.latitude)
            if crosses { inside.toggle() }
            previous = current
        }
        return inside
    }

    private var isValidSingleRingPolygon: Bool {
        polygon.count >= 4
            && polygon.allSatisfy(\.isValid)
            && polygon.first == polygon.last
    }

    private func point(_ point: GeographicCoordinate, isOnSegmentFrom a: GeographicCoordinate, to b: GeographicCoordinate) -> Bool {
        let cross = (point.longitude - a.longitude) * (b.latitude - a.latitude) - (point.latitude - a.latitude) * (b.longitude - a.longitude)
        guard abs(cross) <= 1e-12 else { return false }
        return point.latitude >= min(a.latitude, b.latitude) - 1e-12
            && point.latitude <= max(a.latitude, b.latitude) + 1e-12
            && point.longitude >= min(a.longitude, b.longitude) - 1e-12
            && point.longitude <= max(a.longitude, b.longitude) + 1e-12
    }
}

public enum AuthoritativeFeatureResolution: Sendable, Equatable, Codable {
    case resolved(AuthoritativeGeographicFeature)
    case ambiguous([AuthoritativeGeographicFeature])
    case unsupportedRegion(String)
}

public protocol AuthoritativeGeographicFeatureResolver: Sendable {
    func resolveFeature(containing coordinate: GeographicCoordinate) async -> AuthoritativeFeatureResolution
}

public struct DeterministicFeatureIndexResolver: AuthoritativeGeographicFeatureResolver {
    public let features: [AuthoritativeGeographicFeature]

    public init(features: [AuthoritativeGeographicFeature]) {
        self.features = features.sorted {
            if $0.identity.namespace != $1.identity.namespace { return $0.identity.namespace < $1.identity.namespace }
            return $0.identity.featureID < $1.identity.featureID
        }
    }

    public func resolveFeature(containing coordinate: GeographicCoordinate) async -> AuthoritativeFeatureResolution {
        guard coordinate.isValid else { return .unsupportedRegion("Invalid coordinate") }
        let matches = features.filter { $0.contains(coordinate) }
        if matches.count == 1, let match = matches.first { return .resolved(match) }
        if matches.isEmpty { return .unsupportedRegion("No bounded authoritative inland feature contains the coordinate") }
        return .ambiguous(matches)
    }
}

public struct AuthoritativeResolutionComposer: Sendable {
    public init() {}

    public func compose(
        featureResolution: AuthoritativeFeatureResolution,
        providerCandidates: [ObservationSourceCandidate],
        providerEvidence: [ResolutionEvidence]
    ) -> WaterBodyResolutionCandidate {
        let sources = providerCandidates.sorted { lhs, rhs in
            if lhs.distanceMeters != rhs.distanceMeters { return lhs.distanceMeters < rhs.distanceMeters }
            return lhs.sourceID < rhs.sourceID
        }
        switch featureResolution {
        case let .resolved(feature):
            var evidence = [
                ResolutionEvidence(
                    kind: .selectedPointContainedByFeature,
                    source: feature.provenance.datasetName,
                    note: "Selected coordinate is contained by authoritative feature \(feature.identity.namespace):\(feature.identity.featureID)."
                ),
                ResolutionEvidence(
                    kind: .geometryDatasetVersion,
                    source: feature.provenance.datasetName,
                    note: "Dataset version \(feature.provenance.datasetVersion), collection \(feature.provenance.collectionName), geometry \(feature.provenance.geometryReference)."
                ),
                ResolutionEvidence(
                    kind: .authoritativeFeatureClass,
                    source: feature.provenance.authorityName,
                    note: "Authoritative feature class is \(feature.featureKind.rawValue); product water kind is \(feature.identity.kind.rawValue)."
                ),
                ResolutionEvidence(
                    kind: .compatibleWaterBodyClass,
                    source: feature.provenance.authorityName,
                    note: "Authoritative feature class maps conservatively to product water kind \(feature.identity.kind.rawValue)."
                )
            ]
            if !feature.identity.name.isEmpty {
                evidence.append(.init(kind: .authoritativeFeatureName, source: feature.provenance.authorityName, note: "Feature name is \(feature.identity.name)."))
            }
            if let huc = feature.hydrologicUnitID, !huc.isEmpty {
                evidence.append(.init(kind: .authoritativeHydrologicID, source: feature.provenance.authorityName, note: "Hydrologic unit identifier \(huc)."))
            }
            evidence.append(contentsOf: providerEvidence)
            return WaterBodyResolutionCandidate(feature: feature.identity, observationSources: sources, evidence: evidence)
        case let .ambiguous(features):
            return WaterBodyResolutionCandidate(
                feature: nil,
                observationSources: sources,
                evidence: providerEvidence + [.init(
                    kind: .conflictingFeature,
                    source: "Authoritative feature index",
                    note: "Selected point matched multiple authoritative features: \(features.map { $0.identity.featureID }.joined(separator: ", "))."
                )]
            )
        case let .unsupportedRegion(reason):
            return WaterBodyResolutionCandidate(
                feature: nil,
                observationSources: sources,
                evidence: providerEvidence + [.init(kind: .unsupportedRegion, source: "Authoritative feature index", note: reason)]
            )
        }
    }
}
