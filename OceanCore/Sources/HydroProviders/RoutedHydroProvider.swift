import Foundation
import OceanCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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

        // Cancellation is not a provider outage. A throwing group rethrows it
        // so a cancelled child cannot be compactMapped away and merged into
        // last-known-good. Non-cancellation failures still return nil so one
        // route outage cannot erase a sibling's usable measurements.
        let results = try await withThrowingTaskGroup(of: (Int, HydroState?).self) { group in
            for (index, route) in matching {
                group.addTask {
                    do {
                        return (index, try await route.provider.fetch(waterBody))
                    } catch let error as URLError where error.code == .cancelled {
                        throw CancellationError()
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return (index, nil)
                    }
                }
            }
            var values: [(Int, HydroState?)] = []
            for try await value in group { values.append(value) }
            return values.sorted { $0.0 < $1.0 }
        }

        let states = results.compactMap(\.1)
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
