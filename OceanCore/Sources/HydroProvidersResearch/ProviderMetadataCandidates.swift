import Foundation
import HydroProviders
import OceanCore

public struct ProviderMetadataCandidate: Sendable, Equatable, Codable {
    public let source: ObservationSourceCandidate
    public let evidence: [ResolutionEvidence]

    public init(source: ObservationSourceCandidate, evidence: [ResolutionEvidence]) {
        self.source = source
        self.evidence = evidence
    }
}

public enum ProviderMetadataCandidateError: Error, Sendable, Equatable {
    case invalidRequest
    case malformedResponse
}

public struct NOAACOOPSMetadataRequest: Sendable, Equatable {
    public let stationID: String

    public init(stationID: String) { self.stationID = stationID }

    public var url: URL? {
        URL(string: "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations/\(stationID).json")
    }
}

/// Research-only adapter. Station metadata identifies candidate observation
/// locations, but does not prove that a station represents the selected feature.
public enum NOAACOOPSMetadataCandidateAdapter {
    public static func decode(
        _ data: Data,
        selectedCoordinate: GeographicCoordinate,
        reviewedCapabilities: [String: Set<HydroCapability>] = [:]
    ) throws -> [ProviderMetadataCandidate] {
        guard selectedCoordinate.isValid else { throw ProviderMetadataCandidateError.malformedResponse }
        let response: NOAAStationsResponse
        do { response = try JSONDecoder().decode(NOAAStationsResponse.self, from: data) }
        catch { throw ProviderMetadataCandidateError.malformedResponse }

        return response.stations.compactMap { station in
            let coordinate = GeographicCoordinate(latitude: station.lat, longitude: station.lng)
            guard coordinate.isValid, !station.id.isEmpty, !station.name.isEmpty else { return nil }
            let capabilities = reviewedCapabilities[station.id] ?? []
            var evidence = [ResolutionEvidence(
                kind: .proximityOnly,
                source: "NOAA CO-OPS MDAPI",
                note: "Station is \(Int(distanceMeters(from: selectedCoordinate, to: coordinate).rounded())) m from the selected point; distance does not prove water-body identity."
            )]
            if !capabilities.isEmpty {
                evidence.append(.init(
                    kind: .productAvailable,
                    source: "Reviewed NOAA CO-OPS capability input",
                    note: "Capabilities were supplied by a separate reviewed product-availability step, not inferred from station metadata."
                ))
            }
            return ProviderMetadataCandidate(
                source: ObservationSourceCandidate(
                    namespace: NOAACOOPSProvider<URLSessionNOAATransport>.stationNamespace,
                    sourceID: station.id,
                    name: station.name,
                    coordinate: coordinate,
                    locationKind: station.tidal ? .estuary : nil,
                    capabilities: capabilities,
                    distanceMeters: distanceMeters(from: selectedCoordinate, to: coordinate)
                ),
                evidence: evidence
            )
        }.sorted(by: candidateOrder)
    }
}

public struct USGSMonitoringLocationsRequest: Sendable, Equatable {
    public let center: GeographicCoordinate
    public let radiusDegrees: Double
    public let limit: Int

    public init(center: GeographicCoordinate, radiusDegrees: Double = 0.25, limit: Int = 100) {
        self.center = center
        self.radiusDegrees = radiusDegrees
        self.limit = limit
    }

    public var url: URL? {
        guard center.isValid, radiusDegrees.isFinite, radiusDegrees > 0, (1 ... 10_000).contains(limit) else { return nil }
        var components = URLComponents(string: "https://api.waterdata.usgs.gov/ogcapi/v0/collections/monitoring-locations/items")
        components?.queryItems = [
            URLQueryItem(name: "f", value: "json"),
            URLQueryItem(name: "bbox", value: "\(center.longitude - radiusDegrees),\(center.latitude - radiusDegrees),\(center.longitude + radiusDegrees),\(center.latitude + radiusDegrees)"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return components?.url
    }
}

/// Research-only OGC adapter. Monitoring-location metadata supplies identity,
/// coordinates, site class, and HUC evidence. It deliberately claims no Hydro
/// capabilities because the collection does not prove product availability.
public enum USGSMonitoringLocationCandidateAdapter {
    public static func decode(
        _ data: Data,
        selectedCoordinate: GeographicCoordinate
    ) throws -> [ProviderMetadataCandidate] {
        guard selectedCoordinate.isValid else { throw ProviderMetadataCandidateError.malformedResponse }
        let response: USGSFeatureCollection
        do { response = try JSONDecoder().decode(USGSFeatureCollection.self, from: data) }
        catch { throw ProviderMetadataCandidateError.malformedResponse }

        return response.features.compactMap { feature in
            guard feature.geometry.type == "Point", feature.geometry.coordinates.count >= 2 else { return nil }
            let coordinate = GeographicCoordinate(
                latitude: feature.geometry.coordinates[1],
                longitude: feature.geometry.coordinates[0]
            )
            let properties = feature.properties
            guard coordinate.isValid,
                  !properties.monitoringLocationNumber.isEmpty,
                  !properties.monitoringLocationName.isEmpty else { return nil }
            let kind = waterBodyKind(siteTypeCode: properties.siteTypeCode, siteType: properties.siteType)
            var evidence = [ResolutionEvidence(
                kind: .proximityOnly,
                source: "USGS Water Data OGC monitoring-locations",
                note: "Monitoring location is \(Int(distanceMeters(from: selectedCoordinate, to: coordinate).rounded())) m from the selected point; distance does not prove water-body identity."
            )]
            if kind != nil {
                evidence.append(.init(
                    kind: .compatibleWaterBodyClass,
                    source: "USGS site_type",
                    note: "USGS classifies this location as \(properties.siteType); feature identity must still be resolved separately."
                ))
            }
            if let huc = properties.hydrologicUnitCode, !huc.isEmpty {
                evidence.append(.init(
                    kind: .hydrologicallyConnected,
                    source: "USGS hydrologic_unit_code",
                    note: "Reported HUC \(huc) is useful basin evidence but does not establish the same lake, river reach, bay, or estuary."
                ))
            }
            return ProviderMetadataCandidate(
                source: ObservationSourceCandidate(
                    namespace: USGSIVProvider<URLSessionUSGSTransport>.namespace,
                    sourceID: properties.monitoringLocationNumber,
                    name: properties.monitoringLocationName,
                    coordinate: coordinate,
                    locationKind: kind,
                    capabilities: [],
                    distanceMeters: distanceMeters(from: selectedCoordinate, to: coordinate)
                ),
                evidence: evidence
            )
        }.sorted(by: candidateOrder)
    }
}

private func candidateOrder(_ lhs: ProviderMetadataCandidate, _ rhs: ProviderMetadataCandidate) -> Bool {
    if lhs.source.distanceMeters != rhs.source.distanceMeters {
        return lhs.source.distanceMeters < rhs.source.distanceMeters
    }
    return lhs.source.sourceID < rhs.source.sourceID
}

private func distanceMeters(from lhs: GeographicCoordinate, to rhs: GeographicCoordinate) -> Double {
    let radius = 6_371_000.0
    let latitude1 = lhs.latitude * .pi / 180
    let latitude2 = rhs.latitude * .pi / 180
    let deltaLatitude = (rhs.latitude - lhs.latitude) * .pi / 180
    let deltaLongitude = (rhs.longitude - lhs.longitude) * .pi / 180
    let a = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
        + cos(latitude1) * cos(latitude2)
        * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
    return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
}

private func waterBodyKind(siteTypeCode: String, siteType: String) -> WaterBodyKind? {
    let value = "\(siteTypeCode) \(siteType)".lowercased()
    if value.contains("lake") || value.contains("reservoir") { return .lake }
    if value.contains("stream") || value.contains("river") || siteTypeCode == "ST" { return .river }
    if value.contains("estuary") { return .estuary }
    if value.contains("ocean") { return .ocean }
    return nil
}

private struct NOAAStationsResponse: Decodable {
    let stations: [Station]

    struct Station: Decodable {
        let tidal: Bool
        let id: String
        let name: String
        let lat: Double
        let lng: Double
    }
}

private struct USGSFeatureCollection: Decodable {
    let features: [Feature]

    struct Feature: Decodable {
        let properties: Properties
        let geometry: Geometry
    }

    struct Geometry: Decodable {
        let type: String
        let coordinates: [Double]
    }

    struct Properties: Decodable {
        let monitoringLocationNumber: String
        let monitoringLocationName: String
        let siteTypeCode: String
        let siteType: String
        let hydrologicUnitCode: String?

        enum CodingKeys: String, CodingKey {
            case monitoringLocationNumber = "monitoring_location_number"
            case monitoringLocationName = "monitoring_location_name"
            case siteTypeCode = "site_type_code"
            case siteType = "site_type"
            case hydrologicUnitCode = "hydrologic_unit_code"
        }
    }
}
