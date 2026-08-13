import Foundation
import OceanCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum USGSIVError: Error, Sendable, Equatable {
    case invalidRequest
    case malformedResponse
    case noUsableMeasurements
    case httpStatus(Int)
}

public struct USGSIVRequest: Sendable, Equatable {
    public let siteID: String
    public let parameterCodes: [String]

    public init(siteID: String, parameterCodes: [String]) {
        self.siteID = siteID
        self.parameterCodes = parameterCodes
    }

    public var url: URL? {
        var components = URLComponents(string: "https://waterservices.usgs.gov/nwis/iv/")
        components?.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "sites", value: siteID),
            URLQueryItem(name: "parameterCd", value: parameterCodes.joined(separator: ",")),
            URLQueryItem(name: "siteStatus", value: "all"),
        ]
        return components?.url
    }
}

public protocol USGSDataTransport: Sendable {
    func data(from url: URL) async throws -> Data
}

public struct URLSessionUSGSTransport: USGSDataTransport, @unchecked Sendable {
    private let session: URLSession

    /// Shared rather than per-instance: `URLSession` retains itself until
    /// `invalidateAndCancel()`, so building one per transport leaks a session
    /// on every `RoutedHydroProvider.liveCurated()` call.
    private static let defaultSession = makeDefaultSession()

    public init(session: URLSession? = nil) {
        self.session = session ?? Self.defaultSession
    }

    /// Matches the NOAA transport deliberately. `URLSession.shared` carries a
    /// 60-second request timeout and a **seven-day** resource timeout, permits
    /// expensive network access, and caches to disk — so a stalled USGS request
    /// held the watch radio six times longer than the NOAA path allows, over
    /// links NOAA explicitly refuses, and a cached 200 could be mistaken for a
    /// fresh observation.
    public static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        #if !os(Linux)
        configuration.allowsExpensiveNetworkAccess = false
        configuration.waitsForConnectivity = false
        #endif
        return URLSession(configuration: configuration)
    }

    public func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse else {
            throw USGSIVError.malformedResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw USGSIVError.httpStatus(response.statusCode)
        }
        return data
    }
}

public struct USGSIVProvider<Transport: USGSDataTransport>: HydroStateProvider, Sendable {
    public static var namespace: String { "gov.usgs.nwis.iv" }
    public static var waterLevelParameter: String { "00065" }

    public let transport: Transport

    public init(transport: Transport) {
        self.transport = transport
    }

    public func requests(for waterBody: WaterBody) -> [USGSIVRequest] {
        waterBody.sourceBindings.compactMap { binding in
            guard binding.namespace == Self.namespace else { return nil }
            var parameters: [String] = []
            if binding.capabilities.contains(.waterLevel) {
                parameters.append(Self.waterLevelParameter)
            }
            guard !parameters.isEmpty else { return nil }
            return USGSIVRequest(siteID: binding.sourceID, parameterCodes: parameters)
        }
    }

    public func fetch(_ waterBody: WaterBody) async throws -> HydroState {
        // Concurrent, cancellation-aware, and tolerant of a single site
        // failing — mirroring the NOAA provider. Previously this was serial and
        // all-or-nothing: one 503 discarded every site that had already
        // succeeded, and a cancellation landing between two sites was invisible.
        let requests = requests(for: waterBody)
        let measurements = try await withThrowingTaskGroup(
            of: [USGSNormalizedMeasurement].self
        ) { group in
            for request in requests {
                try Task.checkCancellation()
                group.addTask { [transport] in
                    try Task.checkCancellation()
                    do {
                        guard let url = request.url else { throw USGSIVError.invalidRequest }
                        let data = try await transport.data(from: url)
                        return try USGSIVAdapter.decode(data, siteID: request.siteID)
                    } catch let error as URLError where error.code == .cancelled {
                        throw CancellationError()
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // Partial site coverage is normal. Individual failures
                        // stay absent; an entirely empty aggregate fails below.
                        return []
                    }
                }
            }

            var all: [USGSNormalizedMeasurement] = []
            for try await batch in group {
                all.append(contentsOf: batch)
            }
            return all
        }

        guard let observedAt = measurements.map(\.measurement.observedAt).compactMap({ $0 }).min()
        else { throw USGSIVError.noUsableMeasurements }

        var state = HydroState(observedAt: observedAt, retrievedAt: Date())
        for normalized in measurements {
            switch normalized.capability {
            case .waterLevel: state.waterLevel = state.waterLevel ?? normalized.measurement
            default: continue
            }
        }
        return state
    }
}

public typealias LiveUSGSIVProvider = USGSIVProvider<URLSessionUSGSTransport>

public struct USGSNormalizedMeasurement: Sendable, Equatable {
    public let capability: HydroCapability
    public let measurement: HydroMeasurement
}

public enum USGSIVAdapter {
    public static func decode(_ data: Data, siteID: String) throws -> [USGSNormalizedMeasurement] {
        let response: USGSTimeSeriesResponse
        do {
            response = try JSONDecoder().decode(USGSTimeSeriesResponse.self, from: data)
        } catch {
            throw USGSIVError.malformedResponse
        }

        return response.value.timeSeries.compactMap { series in
            guard series.variable.variableCode.first?.value == USGSIVProvider<URLSessionUSGSTransport>.waterLevelParameter,
                  series.variable.unit.unitCode.lowercased() == "ft",
                  let sample = series.values.first?.value.first,
                  let value = Double(sample.value), value.isFinite,
                  value != series.variable.noDataValue,
                  let observedAt = parseTimestamp(sample.dateTime)
            else { return nil }

            let quality = mapQuality(sample.qualifiers)
            return USGSNormalizedMeasurement(
                capability: .waterLevel,
                measurement: HydroMeasurement(
                    value: value * 0.3048,
                    unit: .meters,
                    origin: .observed,
                    quality: quality,
                    sourceID: "usgs.nwis.\(siteID).00065",
                    observedAt: observedAt
                )
            )
        }
    }

    public static func mapQuality(_ qualifiers: [String]) -> HydroQuality {
        if qualifiers.contains("A") { return .good }
        if qualifiers.allSatisfy({ $0 == "P" }) { return .unknown }
        return qualifiers.isEmpty ? .unknown : .suspect
    }

    public static func parseTimestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

private struct USGSTimeSeriesResponse: Decodable {
    let value: Value

    struct Value: Decodable {
        let timeSeries: [TimeSeries]
    }

    struct TimeSeries: Decodable {
        let variable: Variable
        let values: [Values]
    }

    struct Variable: Decodable {
        let variableCode: [Code]
        let unit: Unit
        let noDataValue: Double
    }

    struct Code: Decodable { let value: String }
    struct Unit: Decodable { let unitCode: String }
    struct Values: Decodable { let value: [Sample] }
    struct Sample: Decodable {
        let value: String
        let qualifiers: [String]
        let dateTime: String
    }
}
