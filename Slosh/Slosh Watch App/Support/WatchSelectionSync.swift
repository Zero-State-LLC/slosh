import Foundation
import OceanCore
import WatchConnectivity

/// Additive adapter around the Watch's proven theme/place AppStorage keys. The
/// shared domain remains free of WatchConnectivity, and incoming stale messages
/// cannot overwrite a newer deliberate selection.
final class WatchSelectionSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSelectionSync()

    private static let envelopeKey = "selectedWaterEnvelope"
    private let session: WCSession?
    private var suppressNextCanonicalID: String?

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func recordLocal(_ selection: SelectedWater, at date: Date = Date()) {
        guard selection.isCatalogValid else { return }
        if suppressNextCanonicalID == selection.canonicalID {
            suppressNextCanonicalID = nil
            return
        }
        let envelope = WaterSelectionEnvelope(
            selection: selection,
            selectedAt: date,
            origin: .watch
        )
        persist(envelope)
        send(envelope)
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["selectedWater"] as? Data,
              let incoming = try? JSONDecoder().decode(WaterSelectionEnvelope.self, from: data),
              incoming.selection.isCatalogValid else { return }
        DispatchQueue.main.async { [weak self] in self?.apply(incoming) }
    }

    private func apply(_ incoming: WaterSelectionEnvelope) {
        let resolved = incoming.replacing(savedEnvelope)
        guard resolved == incoming, resolved != savedEnvelope else { return }
        suppressNextCanonicalID = incoming.selection.canonicalID
        persist(incoming)
        switch incoming.selection {
        case let .experience(themeID):
            UserDefaults.standard.set("", forKey: SettingsKey.placeID)
            UserDefaults.standard.set(themeID, forKey: SettingsKey.themeID)
        case let .place(waterBodyID):
            UserDefaults.standard.set(waterBodyID, forKey: SettingsKey.placeID)
        }
    }

    private var savedEnvelope: WaterSelectionEnvelope? {
        guard let data = UserDefaults.standard.data(forKey: Self.envelopeKey) else { return nil }
        return try? JSONDecoder().decode(WaterSelectionEnvelope.self, from: data)
    }

    private func persist(_ envelope: WaterSelectionEnvelope) {
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        UserDefaults.standard.set(data, forKey: Self.envelopeKey)
    }

    private func send(_ envelope: WaterSelectionEnvelope) {
        guard let session, let data = try? JSONEncoder().encode(envelope) else { return }
        try? session.updateApplicationContext(["selectedWater": data])
    }
}
