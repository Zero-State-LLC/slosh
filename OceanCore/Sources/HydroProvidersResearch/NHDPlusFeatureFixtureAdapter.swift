import Foundation
import OceanCore
import OceanCoreResearch

public struct NHDPlusFeatureFixtureAdapter: Sendable {
    public init() {}

    public func decode(_ data: Data) throws -> [AuthoritativeGeographicFeature] {
        let collection: FeatureCollection
        do { collection = try JSONDecoder().decode(FeatureCollection.self, from: data) }
        catch { throw ProviderMetadataCandidateError.malformedResponse }

        guard collection.type == "FeatureCollection" else { throw ProviderMetadataCandidateError.malformedResponse }
        return collection.features.compactMap { feature in
            guard feature.type == "Feature",
                  feature.geometry.type == "Polygon",
                  feature.geometry.coordinates.count == 1,
                  let ring = feature.geometry.coordinates.first,
                  ring.count >= 4,
                  !feature.properties.permanentIdentifier.isEmpty,
                  !feature.properties.gnisName.isEmpty,
                  let kind = FeatureKindMapping(nhdFType: feature.properties.fType)
            else { return nil }
            let polygon = ring.compactMap { pair -> GeographicCoordinate? in
                guard pair.count >= 2 else { return nil }
                return GeographicCoordinate(latitude: pair[1], longitude: pair[0])
            }
            guard polygon.count == ring.count, polygon.allSatisfy(\.isValid), polygon.first == polygon.last else { return nil }
            let representative = GeographicCoordinate(latitude: feature.properties.representativeLatitude, longitude: feature.properties.representativeLongitude)
            guard representative.isValid else { return nil }
            let lats = polygon.map(\.latitude)
            let lngs = polygon.map(\.longitude)
            return AuthoritativeGeographicFeature(
                identity: GeographicFeatureIdentity(
                    namespace: feature.properties.authorityNamespace,
                    featureID: feature.properties.permanentIdentifier,
                    name: feature.properties.gnisName,
                    kind: kind.waterBodyKind,
                    representativeCoordinate: representative
                ),
                featureKind: kind.geographicKind,
                hydrologicUnitID: feature.properties.hydrologicUnitCode,
                provenance: GeographicFeatureProvenance(
                    authorityName: feature.properties.authorityName,
                    datasetName: feature.properties.datasetName,
                    datasetVersion: feature.properties.datasetVersion,
                    collectionName: feature.properties.collectionName,
                    serviceReference: feature.properties.serviceReference,
                    geometryReference: feature.properties.geometryReference
                ),
                boundingBox: GeographicBoundingBox(
                    minimumLatitude: lats.min() ?? 0,
                    minimumLongitude: lngs.min() ?? 0,
                    maximumLatitude: lats.max() ?? 0,
                    maximumLongitude: lngs.max() ?? 0
                ),
                polygon: polygon
            )
        }.sorted {
            if $0.identity.namespace != $1.identity.namespace { return $0.identity.namespace < $1.identity.namespace }
            return $0.identity.featureID < $1.identity.featureID
        }
    }
}

private struct FeatureKindMapping {
    let geographicKind: GeographicFeatureKind
    let waterBodyKind: WaterBodyKind

    init?(nhdFType: Int) {
        switch nhdFType {
        case 390:
            self.geographicKind = .lakePond
            self.waterBodyKind = .lake
        case 445:
            self.geographicKind = .bay
            self.waterBodyKind = .bay
        case 436, 460:
            self.geographicKind = .riverStream
            self.waterBodyKind = .river
        default:
            return nil
        }
    }
}

private struct FeatureCollection: Decodable {
    let type: String
    let features: [Feature]

    struct Feature: Decodable {
        let type: String
        let properties: Properties
        let geometry: Geometry
    }

    struct Properties: Decodable {
        let authorityNamespace: String
        let authorityName: String
        let permanentIdentifier: String
        let gnisName: String
        let fType: Int
        let hydrologicUnitCode: String?
        let representativeLatitude: Double
        let representativeLongitude: Double
        let datasetName: String
        let datasetVersion: String
        let collectionName: String
        let serviceReference: String
        let geometryReference: String

        enum CodingKeys: String, CodingKey {
            case authorityNamespace = "authority_namespace"
            case authorityName = "authority_name"
            case permanentIdentifier = "permanent_identifier"
            case gnisName = "gnis_name"
            case fType = "f_type"
            case hydrologicUnitCode = "huc12"
            case representativeLatitude = "representative_latitude"
            case representativeLongitude = "representative_longitude"
            case datasetName = "dataset_name"
            case datasetVersion = "dataset_version"
            case collectionName = "collection_name"
            case serviceReference = "service_reference"
            case geometryReference = "geometry_reference"
        }
    }

    struct Geometry: Decodable {
        let type: String
        let coordinates: [[[Double]]]
    }
}
