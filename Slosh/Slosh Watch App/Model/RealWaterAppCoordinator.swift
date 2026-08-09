import Foundation
import HydroProviders
import OceanCore
import OSLog

private struct UnavailableHydroProvider: HydroStateProvider {
    func fetch(_ waterBody: WaterBody) async throws -> HydroState {
        throw RoutedHydroProviderError.noUsableMeasurements
    }
}

/// Bridges the provider/application layer into the already-proven renderer
/// inputs. The authored ocean is running before this object starts any request.
@MainActor
final class RealWaterAppCoordinator {
    private static let logger = Logger(
        subsystem: "com.example.Slosh.watchkitapp",
        category: "RealWater"
    )
    private let coordinator: LiveHydroCoordinator
    private var task: Task<Void, Never>?

    init(forceFailure: Bool = false) {
        if forceFailure {
            coordinator = LiveHydroCoordinator(provider: UnavailableHydroProvider())
        } else {
            coordinator = LiveHydroCoordinator(provider: RoutedHydroProvider.liveCurated())
        }
    }

    func activate(waterBody: WaterBody?, model: OceanModel) {
        guard let waterBody else { return }
        task?.cancel()
        task = Task {
            let outcome = await coordinator.refresh(
                waterBody: waterBody,
                referenceDate: Date()
            )
            guard !Task.isCancelled else { return }
            switch outcome {
            case let .updated(state, experience):
                model.apply(hydroExperience: experience)
                printLiveSummary(state: state, experience: experience, disposition: "updated")
            case let .preserved(state, experience):
                model.apply(hydroExperience: experience)
                printLiveSummary(state: state, experience: experience, disposition: "preserved")
            case .unavailable:
                // No prior observation means there is nothing environmental to
                // apply. The authored Calm ocean has kept rendering throughout.
                Self.logger.notice("RW3A real-water unavailable; authored ocean preserved")
            }
        }
    }

    func deactivate() {
        task?.cancel()
        task = nil
    }

    private func printLiveSummary(
        state: HydroState,
        experience: HydroExperience,
        disposition: String
    ) {
        let fields = [
            state.waterLevel.map { "waterLevel=\($0.value)m" },
            state.waterTemperature.map { "waterTemperature=\($0.value)C" },
            state.currentSpeed.map { "currentSpeed=\($0.value)m/s" },
            state.currentDirection.map { "currentDirection=\($0.value)deg" },
            state.windSpeed.map { "windSpeed=\($0.value)m/s" },
            state.windDirection.map { "windDirection=\($0.value)deg" },
            state.pressure.map { "pressure=\($0.value)hPa" },
            state.salinity.map { "salinity=\($0.value)PSU" },
        ].compactMap { $0 }.joined(separator: ",")
        let message = "RW3A real-water \(disposition) observedAt=\(state.observedAt) "
            + "fields=[\(fields)] freshness=\(experience.forcing.freshness.rawValue) "
            + "forcing=\(experience.forcing) modifiers=\(experience.themeModifiers)"
        Self.logger.notice("\(message, privacy: .public)")
    }
}
