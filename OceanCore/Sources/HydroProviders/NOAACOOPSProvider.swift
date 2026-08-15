import Foundation
import OceanCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum NOAAHydroAggregator {
    /// The oldest valid product timestamp is the conservative snapshot summary;
    /// using the newest would make older included evidence appear fresher.
    public static func state(
        samples: [NOAAProductSample],
        retrievedAt: Date
    ) throws -> HydroState {
        let usable = samples.filter(\.hasMeasurement)
        guard let observedAt = usable.map(\.observedAt).min() else {
            throw NOAAProviderError.noUsableMeasurements
        }

        var state = HydroState(observedAt: observedAt, retrievedAt: retrievedAt)
        for sample in usable {
            state.waterLevel = state.waterLevel ?? sample.waterLevel
            state.waterTemperature = state.waterTemperature ?? sample.waterTemperature
            state.currentSpeed = state.currentSpeed ?? sample.currentSpeed
            state.currentDirection = state.currentDirection ?? sample.currentDirection
            state.windSpeed = state.windSpeed ?? sample.windSpeed
            state.windDirection = state.windDirection ?? sample.windDirection
            state.pressure = state.pressure ?? sample.pressure
            state.salinity = state.salinity ?? sample.salinity
        }
        return state
    }
}

public protocol HydroStateProvider: Sendable {
    func fetch(_ waterBody: WaterBody) async throws -> HydroState
}

public protocol NOAADataTransport: Sendable {
    func data(from url: URL) async throws -> Data
}

public struct URLSessionNOAATransport: NOAADataTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        self.session = session ?? Self.makeDefaultSession()
    }

    public static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // FoundationNetworking on Linux does not expose these Apple-only flags.
        #if !os(Linux)
        configuration.allowsExpensiveNetworkAccess = false
        configuration.waitsForConnectivity = false
        #endif
        return URLSession(configuration: configuration)
    }

    public func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse else {
            throw NOAAProviderError.malformedResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw NOAAProviderError.httpStatus(response.statusCode)
        }
        return data
    }
}

public struct NOAACOOPSProvider<Transport: NOAADataTransport>: HydroStateProvider, Sendable {
    public static var stationNamespace: String { "gov.noaa.coops.station" }
    public static var currentStationNamespace: String { "gov.noaa.coops.current-station" }

    public let transport: Transport
    public let reportProductFailure: @Sendable (NOAAProduct, String, Error) -> Void

    public init(
        transport: Transport,
        reportProductFailure: @escaping @Sendable (NOAAProduct, String, Error) -> Void = {
            product, stationID, error in
            let line = "NOAA product \(product.rawValue) station \(stationID) failed: \(error)\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
    ) {
        self.transport = transport
        self.reportProductFailure = reportProductFailure
    }

    public func fetch(_ waterBody: WaterBody) async throws -> HydroState {
        let requests = requests(for: waterBody)
        let outcome = try await withThrowingTaskGroup(of: NOAAProductTaskResult.self) { group in
            for request in requests {
                try Task.checkCancellation()
                group.addTask { [transport] in
                    try Task.checkCancellation()
                    do {
                        guard let url = request.url else { throw NOAAProviderError.invalidRequest }
                        let data = try await transport.data(from: url)
                        let sample = try NOAAHydroAdapter.decode(
                            data, product: request.product, stationID: request.stationID
                        )
                        return .sample(sample.hasMeasurement ? sample : nil)
                    } catch let error as URLError where error.code == .cancelled {
                        throw CancellationError()
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch let error as NOAAProviderError where error == .noUsableMeasurements {
                        // Empty payloads are ordinary absence, not a typed provider failure.
                        return .sample(nil)
                    } catch let error as NOAAProviderError {
                        return .failed(
                            NOAAProductFailure(
                                product: request.product,
                                stationID: request.stationID,
                                providerError: error
                            )
                        )
                    } catch {
                        return .failed(
                            NOAAProductFailure(
                                product: request.product,
                                stationID: request.stationID,
                                message: String(describing: error)
                            )
                        )
                    }
                }
            }

            var samples: [NOAAProductSample] = []
            var failures: [NOAAProductFailure] = []
            for try await result in group {
                switch result {
                case let .sample(sample):
                    if let sample { samples.append(sample) }
                case let .failed(failure):
                    failures.append(failure)
                }
            }
            return (samples, failures)
        }

        let (samples, failures) = outcome
        for failure in failures {
            reportProductFailure(failure.product, failure.stationID, failure.error)
        }
        if samples.isEmpty, let firstFailure = failures.first {
            throw firstFailure.error
        }
        return try NOAAHydroAggregator.state(samples: samples, retrievedAt: Date())
    }

    public func requests(for waterBody: WaterBody) -> [NOAARequest] {
        var result: [NOAARequest] = []
        for binding in waterBody.sourceBindings {
            switch binding.namespace {
            case Self.stationNamespace:
                let stationID = binding.sourceID
                let capabilities = binding.capabilities
                if capabilities.contains(.waterLevel) {
                    result.append(NOAARequest(stationID: stationID, product: .waterLevel))
                }
                if capabilities.contains(.waterTemperature) {
                    result.append(NOAARequest(stationID: stationID, product: .waterTemperature))
                }
                if capabilities.contains(.wind) {
                    result.append(NOAARequest(stationID: stationID, product: .wind))
                }
                if capabilities.contains(.airPressure) {
                    result.append(NOAARequest(stationID: stationID, product: .airPressure))
                }
                if capabilities.contains(.salinity) {
                    result.append(NOAARequest(stationID: stationID, product: .salinity))
                }
            case Self.currentStationNamespace:
                guard binding.capabilities.contains(.currentSpeed)
                        || binding.capabilities.contains(.currentDirection) else { continue }
                let bin = binding.parameters["bin"].flatMap(Int.init)
                result.append(NOAARequest(stationID: binding.sourceID, product: .currents, bin: bin))
            default:
                continue
            }
        }
        return result
    }
}

public typealias LiveNOAACOOPSProvider = NOAACOOPSProvider<URLSessionNOAATransport>

public extension NOAACOOPSProvider where Transport == URLSessionNOAATransport {
    init() {
        self.init(transport: URLSessionNOAATransport())
    }
}

/// Typed NOAA product failures that must not be mistaken for ordinary missing coverage.
private enum NOAAProductTaskResult: Sendable {
    case sample(NOAAProductSample?)
    case failed(NOAAProductFailure)
}

private struct NOAAProductFailure: Sendable {
    let product: NOAAProduct
    let stationID: String
    let providerError: NOAAProviderError?
    let message: String

    init(product: NOAAProduct, stationID: String, providerError: NOAAProviderError) {
        self.product = product
        self.stationID = stationID
        self.providerError = providerError
        self.message = providerError.description
    }

    init(product: NOAAProduct, stationID: String, message: String) {
        self.product = product
        self.stationID = stationID
        self.providerError = nil
        self.message = message
    }

    var error: Error {
        providerError ?? NOAAReportedProductError(
            product: product, stationID: stationID, message: message
        )
    }
}

private struct NOAAReportedProductError: Error, Sendable, CustomStringConvertible {
    let product: NOAAProduct
    let stationID: String
    let message: String

    var description: String {
        "NOAA product \(product.rawValue) station \(stationID) failed: \(message)"
    }
}
