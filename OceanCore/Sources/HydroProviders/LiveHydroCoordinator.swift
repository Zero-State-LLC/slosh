import Foundation
import OceanCore

public enum HydroRefreshOutcome: Sendable, Equatable {
    case updated(state: HydroState, experience: HydroExperience)
    case preserved(state: HydroState, experience: HydroExperience)
    case unavailable
}

/// Application-facing refresh policy. It owns only an in-memory last-known valid
/// state and never couples network cadence to simulation or render cadence.
public actor LiveHydroCoordinator {
    public static let minimumRefreshInterval: TimeInterval = 10 * 60

    private let provider: any HydroStateProvider
    private var lastAttemptAt: Date?
    private var lastValidState: HydroState?

    public init(provider: any HydroStateProvider) {
        self.provider = provider
    }

    public func refresh(
        waterBody: WaterBody,
        referenceDate: Date
    ) async -> HydroRefreshOutcome {
        if let lastAttemptAt,
           referenceDate.timeIntervalSince(lastAttemptAt) < Self.minimumRefreshInterval {
            return preservedOrUnavailable(referenceDate: referenceDate)
        }
        lastAttemptAt = referenceDate

        do {
            let state = try await provider.fetch(waterBody)
            lastValidState = state
            return .updated(
                state: state,
                experience: HydroInterpreter().interpret(state, referenceDate: referenceDate)
            )
        } catch where isCancellation(error) {
            // Backgrounding or reduced luminance cancels the in-flight request.
            // A canceled request did not refresh anything and must not suppress
            // the next foreground activation for the normal ten-minute window.
            if lastAttemptAt == referenceDate { lastAttemptAt = nil }
            return preservedOrUnavailable(referenceDate: referenceDate)
        } catch {
            return preservedOrUnavailable(referenceDate: referenceDate)
        }
    }

    public func cachedState() -> HydroState? {
        lastValidState
    }

    private func preservedOrUnavailable(referenceDate: Date) -> HydroRefreshOutcome {
        guard let state = lastValidState else { return .unavailable }
        return .preserved(
            state: state,
            experience: HydroInterpreter().interpret(state, referenceDate: referenceDate)
        )
    }
}
