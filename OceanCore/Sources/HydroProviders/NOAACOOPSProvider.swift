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

    /// Shared rather than per-instance: `URLSession` retains itself until
    /// `invalidateAndCancel()`, so building one per transport leaked a session
    /// on every `RoutedHydroProvider.liveCurated()` call.
    private static let defaultSession = makeDefaultSession()

    public init(session: URLSession? = nil) {
        self.session = session ?? Self.defaultSession
    }

    public static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.allowsExpensiveNetworkAccess = false
        configuration.waitsForConnectivity = false
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

    public init(transport: Transport) {
        self.transport = transport
    }

    public func fetch(_ waterBody: WaterBody) async throws -> HydroState {
        let requests = requests(for: waterBody)
        let (samples, failures) = await withTaskGroup(
            of: Result<NOAAProductSample?, Error>.self,
            returning: ([NOAAProductSample], [Error]).self
        ) { group in
            for request in requests {
                group.addTask { [transport] in
                    if Task.isCancelled { return .failure(CancellationError()) }
                    do {
                        guard let url = request.url else { throw NOAAProviderError.invalidRequest }
                        let data = try await transport.data(from: url)
                        let sample = try NOAAHydroAdapter.decode(
                            data, product: request.product, stationID: request.stationID
                        )
                        return .success(sample.hasMeasurement ? sample : nil)
                    } catch let error as URLError where error.code == .cancelled {
                        return .failure(CancellationError())
                    } catch is CancellationError {
                        return .failure(CancellationError())
                    } catch {
                        // Partial product coverage is normal. Individual failures stay
                        // absent; only an entirely empty aggregate fails below.
                        return .failure(error)
                    }
                }
            }

            var samples: [NOAAProductSample] = []
            var failures: [Error] = []
            for await result in group {
                switch result {
                case let .success(sample):
                    if let sample { samples.append(sample) }
                case let .failure(error):
                    failures.append(error)
                }
            }
            return (samples, failures)
        }

        if failures.contains(where: Self.isCancellationFailure) {
            throw CancellationError()
        }
        if samples.isEmpty {
            if let terminalFailure = failures.first(where: Self.isTerminalFailure) {
                throw terminalFailure
            }
            throw NOAAProviderError.noUsableMeasurements
        }
        return try NOAAHydroAggregator.state(samples: samples, retrievedAt: Date())
    }

    private static func isTerminalFailure(_ error: Error) -> Bool {
        guard let providerError = error as? NOAAProviderError else { return false }
        if case .providerMessage = providerError { return true }
        return false
    }

    private static func isCancellationFailure(_ error: Error) -> Bool {
        error is CancellationError
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
