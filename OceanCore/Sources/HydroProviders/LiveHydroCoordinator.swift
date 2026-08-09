import Foundation
import OceanCore

public enum HydroRefreshOutcome: Sendable, Equatable {
    case updated(state: HydroState, experience: HydroExperience)
    case preserved(state: HydroState, experience: HydroExperience)
    case unavailable
}

/// In-memory refresh state for one canonical `WaterBody.id`.
private struct WaterBodyRefreshRecord: Sendable, Equatable {
    var lastAttemptAt: Date?
    var lastValidState: HydroState?

    init(lastAttemptAt: Date? = nil, lastValidState: HydroState? = nil) {
        self.lastAttemptAt = lastAttemptAt
        self.lastValidState = lastValidState
    }
}

/// Application-facing refresh policy. Throttle and fallback state are isolated
/// by canonical water-body ID and never couple network cadence to render cadence.
public actor LiveHydroCoordinator {
    public static let minimumRefreshInterval: TimeInterval = 10 * 60

    private let provider: any HydroStateProvider
    private var records: [WaterBody.ID: WaterBodyRefreshRecord] = [:]

    public init(provider: any HydroStateProvider) {
        self.provider = provider
    }

    public func refresh(
        waterBody: WaterBody,
        referenceDate: Date
    ) async -> HydroRefreshOutcome {
        let waterBodyID = waterBody.id
        var record = records[waterBodyID] ?? WaterBodyRefreshRecord()
        if let lastAttemptAt = record.lastAttemptAt,
           referenceDate.timeIntervalSince(lastAttemptAt) < Self.minimumRefreshInterval {
            return preservedOrUnavailable(for: waterBodyID, referenceDate: referenceDate)
        }
        record.lastAttemptAt = referenceDate
        records[waterBodyID] = record

        do {
            let state = try await provider.fetch(waterBody)
            record = records[waterBodyID] ?? WaterBodyRefreshRecord()
            record.lastValidState = state
            records[waterBodyID] = record
            return .updated(
                state: state,
                experience: HydroInterpreter().interpret(state, referenceDate: referenceDate)
            )
        } catch let error as URLError where error.code == .cancelled {
            // Backgrounding or reduced luminance cancels the in-flight request.
            // A canceled request did not refresh anything and must not suppress
            // the next foreground activation for the normal ten-minute window.
            record = records[waterBodyID] ?? WaterBodyRefreshRecord()
            if record.lastAttemptAt == referenceDate {
                record.lastAttemptAt = nil
                records[waterBodyID] = record
            }
            return preservedOrUnavailable(for: waterBodyID, referenceDate: referenceDate)
        } catch is CancellationError {
            // Backgrounding or reduced luminance cancels the in-flight request.
            // A canceled request did not refresh anything and must not suppress
            // the next foreground activation for the normal ten-minute window.
            record = records[waterBodyID] ?? WaterBodyRefreshRecord()
            if record.lastAttemptAt == referenceDate {
                record.lastAttemptAt = nil
                records[waterBodyID] = record
            }
            return preservedOrUnavailable(for: waterBodyID, referenceDate: referenceDate)
        } catch {
            return preservedOrUnavailable(for: waterBodyID, referenceDate: referenceDate)
        }
    }

    public func cachedState(for waterBodyID: WaterBody.ID) -> HydroState? {
        records[waterBodyID]?.lastValidState
    }

    public func cachedState(for waterBody: WaterBody) -> HydroState? {
        cachedState(for: waterBody.id)
    }

    private func preservedOrUnavailable(
        for waterBodyID: WaterBody.ID,
        referenceDate: Date
    ) -> HydroRefreshOutcome {
        guard let state = records[waterBodyID]?.lastValidState else { return .unavailable }
        return .preserved(
            state: state,
            experience: HydroInterpreter().interpret(state, referenceDate: referenceDate)
        )
    }
}
