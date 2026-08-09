import Foundation
import OceanCore

public enum HydroRefreshOutcome: Sendable, Equatable {
    case updated(state: HydroState, experience: HydroExperience)
    case preserved(state: HydroState, experience: HydroExperience)
    case failed(message: String)
    case unavailable
}

/// In-memory refresh state for one canonical `WaterBody.id`.
private struct WaterBodyRefreshRecord: Sendable, Equatable {
    var lastAttemptAt: Date?
    var lastValidState: HydroState?
    /// Set only once cancellations start repeating. A single cancellation must
    /// still retry immediately — lowering and raising a wrist should not cost
    /// the user fresh data — but clearing the throttle unconditionally let a
    /// repeated cycle drive an unbounded request rate, measured at 50 provider
    /// fetches in 10 seconds.
    var retryNotBefore: Date?
    /// Reset by any success. Only consecutive cancellations back off.
    var consecutiveCancellations = 0

    init(
        lastAttemptAt: Date? = nil,
        lastValidState: HydroState? = nil,
        retryNotBefore: Date? = nil
    ) {
        self.lastAttemptAt = lastAttemptAt
        self.lastValidState = lastValidState
        self.retryNotBefore = retryNotBefore
    }
}

/// Application-facing refresh policy. Throttle and fallback state are isolated
/// by canonical water-body ID and never couple network cadence to render cadence.
public actor LiveHydroCoordinator {
    public static let minimumRefreshInterval: TimeInterval = 10 * 60
    /// Applied only from the *second* consecutive cancellation onward. The
    /// first still retries immediately, so the ordinary raise-lower-raise gets
    /// its data; a stuck cycle backs off instead of hammering the providers.
    public static let minimumRetryInterval: TimeInterval = 5

    private let provider: any HydroStateProvider
    private var records: [WaterBody.ID: WaterBodyRefreshRecord] = [:]
    /// One fetch per water body at a time. A second caller joins the running
    /// fetch rather than being turned away by the throttle it just armed.
    private var inFlight: [WaterBody.ID: Task<HydroState, Error>] = [:]

    public init(provider: any HydroStateProvider) {
        self.provider = provider
    }

    public func refresh(
        waterBody: WaterBody,
        referenceDate: Date
    ) async -> HydroRefreshOutcome {
        let waterBodyID = waterBody.id

        // Join a fetch already running for this body. Without this, the second
        // caller hits the throttle the first one armed a moment ago and is told
        // `.unavailable` on a cold cache — even though the fetch it was turned
        // away from is about to succeed.
        if let running = inFlight[waterBodyID] {
            return await outcome(
                of: running, for: waterBodyID, referenceDate: referenceDate, owned: false
            )
        }

        guard !isThrottled(waterBodyID, at: referenceDate) else {
            return preservedOrUnavailable(for: waterBodyID, referenceDate: referenceDate)
        }

        var record = records[waterBodyID] ?? WaterBodyRefreshRecord()
        record.lastAttemptAt = referenceDate
        record.retryNotBefore = nil
        records[waterBodyID] = record

        let task = Task { [provider] in try await provider.fetch(waterBody) }
        inFlight[waterBodyID] = task
        return await outcome(
            of: task, for: waterBodyID, referenceDate: referenceDate, owned: true
        )
    }

    /// - Parameter owned: whether this caller started the fetch. Only the
    ///   originator's cancellation cancels the underlying work, which keeps the
    ///   existing battery behaviour — backgrounding still stops the network —
    ///   while a joiner giving up leaves the fetch running for everyone else.
    private func outcome(
        of task: Task<HydroState, Error>,
        for waterBodyID: WaterBody.ID,
        referenceDate: Date,
        owned: Bool
    ) async -> HydroRefreshOutcome {
        let result: Result<HydroState, Error>
        if owned {
            result = await withTaskCancellationHandler {
                await task.result
            } onCancel: {
                task.cancel()
            }
            if inFlight[waterBodyID] == task { inFlight[waterBodyID] = nil }
        } else {
            result = await task.result
        }

        switch result {
        case let .success(state):
            var record = records[waterBodyID] ?? WaterBodyRefreshRecord()
            record.lastValidState = state
            record.consecutiveCancellations = 0
            record.retryNotBefore = nil
            records[waterBodyID] = record
            return .updated(
                state: state,
                experience: HydroInterpreter().interpret(state, referenceDate: referenceDate)
            )
        case let .failure(error):
            if owned, isCancellation(error) {
                // Backgrounding or reduced luminance cancelled the request. It
                // refreshed nothing, so release the ten-minute window.
                var record = records[waterBodyID] ?? WaterBodyRefreshRecord()
                if record.lastAttemptAt == referenceDate {
                    record.lastAttemptAt = nil
                    record.consecutiveCancellations += 1
                    // The first cancellation retries immediately; only a
                    // repeating cycle backs off.
                    record.retryNotBefore = record.consecutiveCancellations > 1
                        ? referenceDate.addingTimeInterval(Self.minimumRetryInterval)
                        : nil
                    records[waterBodyID] = record
                }
            }
            let preserved = preservedOrUnavailable(for: waterBodyID, referenceDate: referenceDate)
            return switch preserved {
            case .unavailable: .failed(message: failureMessage(for: error))
            default: preserved
            }
        }
    }

    private func isThrottled(_ waterBodyID: WaterBody.ID, at referenceDate: Date) -> Bool {
        guard let record = records[waterBodyID] else { return false }
        if let retryNotBefore = record.retryNotBefore, referenceDate < retryNotBefore {
            return true
        }
        guard let lastAttemptAt = record.lastAttemptAt else { return false }
        return referenceDate.timeIntervalSince(lastAttemptAt) < Self.minimumRefreshInterval
    }

    /// URLSession reports a cancelled task as `URLError(.cancelled)`; only
    /// `Task.sleep` and `Task.checkCancellation()` throw `CancellationError`.
    /// Both mean the caller stopped caring.
    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
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

    private func failureMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            return switch urlError.code {
            case .notConnectedToInternet: "No network"
            case .timedOut: "Request timed out"
            case .networkConnectionLost: "Network connection lost"
            case .cannotConnectToHost: "Cannot reach observation host"
            case .badServerResponse: "Bad server response"
            case .cannotParseResponse: "Could not parse response"
            default: "Live data unavailable"
            }
        }
        return "Live data unavailable"
    }
}
