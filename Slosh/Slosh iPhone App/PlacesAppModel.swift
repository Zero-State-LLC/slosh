import Foundation
import HydroProviders
import Observation
import OceanCore
import WatchConnectivity

private struct OfflineHydroProvider: HydroStateProvider {
    func fetch(_ waterBody: WaterBody) async throws -> HydroState {
        throw URLError(.notConnectedToInternet)
    }
}

@MainActor
@Observable
final class PlacesAppModel {
    private static let selectionKey = "selectedWaterEnvelope"

    private let coordinator: LiveHydroCoordinator
    private let resolver = PlaceHydroStatusResolver()
    private let transport: any WaterSelectionTransport
    private let defaults: UserDefaults

    var observations = PlaceObservationStore()
    var experiences: [WaterBody.ID: HydroExperience] = [:]
    var selectedEnvelope: WaterSelectionEnvelope?

    init(
        defaults: UserDefaults = .standard,
        transport: any WaterSelectionTransport = WatchSelectionTransport.shared,
        forceOffline: Bool = UserDefaults.standard.bool(forKey: "placesOffline")
    ) {
        let provider: any HydroStateProvider = forceOffline
            ? OfflineHydroProvider()
            : RoutedHydroProvider.liveCurated()
        coordinator = LiveHydroCoordinator(provider: provider)
        self.transport = transport
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.selectionKey),
           let saved = try? JSONDecoder().decode(WaterSelectionEnvelope.self, from: data),
           saved.selection.isCatalogValid {
            selectedEnvelope = saved
        }
        #if DEBUG
        if let selectedPlaceID = defaults.string(forKey: "selectedPlace"),
           WaterBodies.body(id: selectedPlaceID) != nil {
            selectedEnvelope = WaterSelectionEnvelope(
                selection: .place(waterBodyID: selectedPlaceID),
                selectedAt: Date(timeIntervalSince1970: 1),
                origin: .iphone
            )
        }
        #endif
        WatchSelectionTransport.shared.onReceive = { [weak self] envelope in
            Task { @MainActor in self?.receive(envelope) }
        }
    }

    var selectedPlaceID: WaterBody.ID? {
        guard case let .place(waterBodyID) = selectedEnvelope?.selection else { return nil }
        return waterBodyID
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for waterBody in WaterBodies.all {
                group.addTask { [weak self] in await self?.refresh(waterBody) }
            }
        }
    }

    func refresh(_ waterBody: WaterBody) async {
        observations.beginLoading(waterBody.id)
        let referenceDate = Date()
        let outcome = await coordinator.refresh(waterBody: waterBody, referenceDate: referenceDate)
        switch outcome {
        case let .updated(state, experience):
            experiences[waterBody.id] = experience
            observations.accept(
                .loaded(resolver.resolve(
                    waterBody: waterBody,
                    state: state,
                    referenceDate: referenceDate
                )),
                for: waterBody.id
            )
        case let .preserved(state, experience):
            experiences[waterBody.id] = experience
            observations.accept(
                .preserved(resolver.resolve(
                    waterBody: waterBody,
                    state: state,
                    referenceDate: referenceDate
                )),
                for: waterBody.id
            )
        case .unavailable:
            observations.accept(.unavailable, for: waterBody.id)
        }
    }

    func choose(_ waterBody: WaterBody, at date: Date = Date()) {
        apply(
            WaterSelectionEnvelope(
                selection: .place(waterBodyID: waterBody.id),
                selectedAt: date,
                origin: .iphone
            ),
            send: true
        )
    }

    func state(for waterBody: WaterBody) -> PlaceObservationLoadState {
        observations.state(for: waterBody.id)
    }

    private func receive(_ envelope: WaterSelectionEnvelope) {
        apply(envelope, send: false)
    }

    private func apply(_ candidate: WaterSelectionEnvelope, send: Bool) {
        guard candidate.selection.isCatalogValid else { return }
        let resolved = candidate.replacing(selectedEnvelope)
        guard resolved != selectedEnvelope else { return }
        selectedEnvelope = resolved
        if let data = try? JSONEncoder().encode(resolved) {
            defaults.set(data, forKey: Self.selectionKey)
        }
        if send {
            Task { try? await transport.send(resolved) }
        }
    }
}

final class WatchSelectionTransport: NSObject, WaterSelectionTransport, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSelectionTransport()

    var onReceive: (@Sendable (WaterSelectionEnvelope) -> Void)?
    private let session: WCSession?

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func send(_ envelope: WaterSelectionEnvelope) async throws {
        guard let session else { return }
        let data = try JSONEncoder().encode(envelope)
        try session.updateApplicationContext(["selectedWater": data])
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["selectedWater"] as? Data,
              let envelope = try? JSONDecoder().decode(WaterSelectionEnvelope.self, from: data) else {
            return
        }
        onReceive?(envelope)
    }
}
