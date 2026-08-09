import Foundation

/// One unambiguous product selection shared by iPhone and Watch. The existing
/// Watch theme/place storage adapts to this without forcing a risky migration.
public enum SelectedWater: Sendable, Equatable, Codable {
    case experience(themeID: String)
    case place(waterBodyID: WaterBody.ID)

    private enum CodingKeys: String, CodingKey { case kind, id }
    private enum Kind: String, Codable { case experience, place }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let id = try values.decode(String.self, forKey: .id)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .experience: self = .experience(themeID: id)
        case .place: self = .place(waterBodyID: id)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .experience(themeID):
            try values.encode(Kind.experience, forKey: .kind)
            try values.encode(themeID, forKey: .id)
        case let .place(waterBodyID):
            try values.encode(Kind.place, forKey: .kind)
            try values.encode(waterBodyID, forKey: .id)
        }
    }

    public var canonicalID: String {
        switch self {
        case let .experience(themeID): "experience:\(themeID)"
        case let .place(waterBodyID): "place:\(waterBodyID)"
        }
    }

    public var isCatalogValid: Bool {
        switch self {
        case let .experience(themeID): OceanTheme.all.contains { $0.id == themeID }
        case let .place(waterBodyID): WaterBodies.body(id: waterBodyID) != nil
        }
    }
}

public enum WaterSelectionOrigin: String, Sendable, Codable, Equatable {
    case iphone
    case watch
}

/// Last deliberate selection wins. Origin is evidence, not a precedence tier.
public struct WaterSelectionEnvelope: Sendable, Codable, Equatable {
    public let selection: SelectedWater
    public let selectedAt: Date
    public let origin: WaterSelectionOrigin

    public init(selection: SelectedWater, selectedAt: Date, origin: WaterSelectionOrigin) {
        self.selection = selection
        self.selectedAt = selectedAt
        self.origin = origin
    }

    public func replacing(_ current: WaterSelectionEnvelope?) -> WaterSelectionEnvelope {
        guard let current else { return self }
        if selectedAt > current.selectedAt { return self }
        if selectedAt < current.selectedAt { return current }
        // Deterministic tie-breaker for clocks with coarse resolution. This is not
        // device priority; canonical identity only makes replay order irrelevant.
        return selection.canonicalID > current.selection.canonicalID ? self : current
    }
}

/// Domain-facing boundary. WatchConnectivity belongs in application targets.
public protocol WaterSelectionTransport: Sendable {
    func send(_ envelope: WaterSelectionEnvelope) async throws
}

/// Deterministic transport used by command-line tests and previews.
public final class RecordingWaterSelectionTransport: WaterSelectionTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [WaterSelectionEnvelope] = []

    public init() {}

    public func send(_ envelope: WaterSelectionEnvelope) async throws {
        lock.withLock { values.append(envelope) }
    }

    public var sent: [WaterSelectionEnvelope] {
        lock.withLock { values }
    }
}

public enum PlaceObservationLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded(PlaceHydroStatus)
    case preserved(PlaceHydroStatus)
    case unavailable
}

/// Keyed reducer for an information-rich multi-place surface. One completion can
/// never repaint a different Place's row or detail screen.
public struct PlaceObservationStore: Sendable, Equatable {
    public private(set) var states: [WaterBody.ID: PlaceObservationLoadState] = [:]

    public init() {}

    public func state(for waterBodyID: WaterBody.ID) -> PlaceObservationLoadState {
        states[waterBodyID] ?? .idle
    }

    public mutating func beginLoading(_ waterBodyID: WaterBody.ID) {
        states[waterBodyID] = .loading
    }

    public mutating func accept(
        _ state: PlaceObservationLoadState,
        for waterBodyID: WaterBody.ID
    ) {
        states[waterBodyID] = state
    }
}
