import Foundation
import OceanCore

public enum RoutedHydroProviderError: Error, Sendable, Equatable {
    case noMatchingProvider
    case noUsableMeasurements
}

public struct HydroProviderRoute: Sendable {
    public let namespaces: Set<String>
    public let provider: any HydroStateProvider

    public init(namespaces: Set<String>, provider: any HydroStateProvider) {
        self.namespaces = namespaces
        self.provider = provider
    }

    public func matches(_ waterBody: WaterBody) -> Bool {
        waterBody.sourceBindings.contains { namespaces.contains($0.namespace) }
    }
}

/// Application-boundary provider composition. Routes are selected from opaque
/// binding namespaces, fetched independently, then merged in declared route
/// order so one provider outage cannot erase usable observations from another.
public struct RoutedHydroProvider: HydroStateProvider, Sendable {
    public let routes: [HydroProviderRoute]

    public init(routes: [HydroProviderRoute]) {
        self.routes = routes
    }

    public func fetch(_ waterBody: WaterBody) async throws -> HydroState {
        let matching = routes.enumerated().filter { $0.element.matches(waterBody) }
        guard !matching.isEmpty else { throw RoutedHydroProviderError.noMatchingProvider }

        let results = await withTaskGroup(
            of: (Int, Result<HydroState, Error>).self,
            returning: [(Int, Result<HydroState, Error>)].self
        ) { group in
            for (index, route) in matching {
                group.addTask {
                    do {
                        return (index, .success(try await route.provider.fetch(waterBody)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var values: [(Int, Result<HydroState, Error>)] = []
            for await value in group { values.append(value) }
            return values.sorted { $0.0 < $1.0 }
        }

        // A route that reports cancellation counts even if this task was not
        // itself marked cancelled — a child cancelled by its own transport
        // would otherwise be merged in as an ordinary outage, and a partial
        // merge would be stored as the last known good state.
        if Task.isCancelled { throw CancellationError() }
        for (_, result) in results {
            if case let .failure(error) = result, isHydroCancellation(error) {
                throw CancellationError()
            }
        }
        let states = results.compactMap { try? $0.1.get() }
        guard !states.isEmpty else { throw RoutedHydroProviderError.noUsableMeasurements }
        return try HydroStateMerger.merge(states)
    }
}

public enum HydroStateMerger {
    /// Merges independently sourced snapshots without inventing values. Earlier
    /// route order wins only if two providers claim the same canonical signal.
    public static func merge(_ states: [HydroState]) throws -> HydroState {
        guard !states.isEmpty else { throw RoutedHydroProviderError.noUsableMeasurements }
        var merged = HydroState(
            observedAt: states.map(\.observedAt).min()!,
            retrievedAt: states.map(\.retrievedAt).max()!
        )
        for state in states {
            merged.waterLevel = merged.waterLevel ?? state.waterLevel
            merged.waterTemperature = merged.waterTemperature ?? state.waterTemperature
            merged.currentSpeed = merged.currentSpeed ?? state.currentSpeed
            merged.currentDirection = merged.currentDirection ?? state.currentDirection
            merged.waveHeight = merged.waveHeight ?? state.waveHeight
            merged.wavePeriod = merged.wavePeriod ?? state.wavePeriod
            merged.windSpeed = merged.windSpeed ?? state.windSpeed
            merged.windDirection = merged.windDirection ?? state.windDirection
            merged.pressure = merged.pressure ?? state.pressure
            merged.salinity = merged.salinity ?? state.salinity
        }
        return merged
    }
}

public extension RoutedHydroProvider {
    static func liveCurated() -> RoutedHydroProvider {
        RoutedHydroProvider(routes: [
            HydroProviderRoute(
                namespaces: [
                    NOAACOOPSProvider<URLSessionNOAATransport>.stationNamespace,
                    NOAACOOPSProvider<URLSessionNOAATransport>.currentStationNamespace,
                ],
                provider: LiveNOAACOOPSProvider()
            ),
            HydroProviderRoute(
                namespaces: [USGSIVProvider<URLSessionUSGSTransport>.namespace],
                provider: LiveUSGSIVProvider(transport: URLSessionUSGSTransport())
            ),
        ])
    }
}
