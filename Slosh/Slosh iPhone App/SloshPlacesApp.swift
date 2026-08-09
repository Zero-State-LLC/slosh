import Foundation
import OceanCore
import SwiftUI

@main
struct SloshPlacesApp: App {
    var body: some Scene {
        WindowGroup {
            PlacesBrowserView()
        }
    }
}

struct PlacesBrowserView: View {
    @State private var model = PlacesAppModel()
    @State private var searchText = ""
    @State private var path: [WaterBody.ID] = {
        #if DEBUG
        guard let id = UserDefaults.standard.string(forKey: "openPlace"),
              WaterBodies.body(id: id) != nil else { return [] }
        return [id]
        #else
        return []
        #endif
    }()

    private var filteredPlaces: [WaterBody] {
        guard !searchText.isEmpty else { return WaterBodies.all }
        return WaterBodies.all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.region.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List(filteredPlaces) { waterBody in
                NavigationLink(value: waterBody.id) {
                    PlaceRow(
                        waterBody: waterBody,
                        state: model.state(for: waterBody),
                        isSelected: model.selectedPlaceID == waterBody.id
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Places")
            .navigationDestination(for: WaterBody.ID.self) { id in
                if let waterBody = WaterBodies.body(id: id) {
                    PlaceDetailView(waterBody: waterBody, model: model)
                }
            }
            .searchable(text: $searchText, prompt: "Search Places")
            .refreshable { await model.refreshAll() }
            .task { await model.refreshAll() }
        }
    }
}

private struct PlaceRow: View {
    let waterBody: WaterBody
    let state: PlaceObservationLoadState
    let isSelected: Bool

    private var supportedSignals: [HydroDisplaySignal] {
        HydroDisplaySignal.allCases.filter { signal in
            signal.capabilities.contains { waterBody.coverage[$0] == .supported }
        }
    }

    private var statusText: String {
        switch state {
        case .idle: "Catalog ready"
        case .loading: "Loading observations…"
        case let .loaded(status): HydroPresentationFormatter.freshness(status.freshness)
        case .preserved: "Using last observation"
        case .unavailable: "Live data unavailable"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(waterBody.name).font(.headline)
                    Text(waterBody.region).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Label("Selected", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.blue)
                        .accessibilityLabel("Selected on Watch")
                }
            }
            HStack {
                Label(waterBody.kind.displayName, systemImage: "water.waves")
                Spacer()
                Text(statusText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(supportedSignals.map(\.displayName).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(waterBody.name), \(waterBody.region), \(statusText), reviewed coverage \(supportedSignals.map(\.displayName).joined(separator: ", "))")
    }
}

struct PlaceDetailView: View {
    let waterBody: WaterBody
    let model: PlacesAppModel

    private var state: PlaceObservationLoadState { model.state(for: waterBody) }
    private var status: PlaceHydroStatus? {
        switch state {
        case let .loaded(value), let .preserved(value): value
        default: nil
        }
    }

    var body: some View {
        List {
            Section("Place") {
                LabeledContent("Region", value: waterBody.region)
                LabeledContent("Type", value: waterBody.kind.displayName)
                LabeledContent(
                    "Coordinates",
                    value: String(format: "%.4f, %.4f", waterBody.latitude, waterBody.longitude)
                )
            }

            Section("Current state") {
                CurrentStateView(state: state, status: status)
                Button(model.selectedPlaceID == waterBody.id ? "Selected for Watch" : "Wear this water") {
                    model.choose(waterBody)
                }
                .disabled(model.selectedPlaceID == waterBody.id)
                .accessibilityHint("Sends this canonical Place selection to the paired Watch when available")
            }

            Section("Measurements") {
                ForEach(HydroDisplaySignal.allCases) { signal in
                    SignalDetailRow(
                        signal: signal,
                        status: status?.displaySignals.first { $0.signal == signal },
                        waterBody: waterBody
                    )
                }
            }

            Section("Technical provenance") {
                ForEach(waterBody.sourceBindings, id: \.sourceID) { binding in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(binding.namespace).font(.caption).foregroundStyle(.secondary)
                        Text(binding.sourceID).font(.body.monospaced())
                        Text(binding.capabilities.map(\.displayName).sorted().joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(waterBody.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh(waterBody) }
        .task { await model.refresh(waterBody) }
    }
}

private struct CurrentStateView: View {
    let state: PlaceObservationLoadState
    let status: PlaceHydroStatus?

    var body: some View {
        switch state {
        case .idle:
            Label("Catalog available offline", systemImage: "checkmark.circle")
        case .loading:
            HStack { ProgressView(); Text("Loading observations…") }
        case .loaded:
            Label(summary, systemImage: "dot.radiowaves.left.and.right")
        case .preserved:
            Label("Using last observation · \(summary)", systemImage: "clock.arrow.circlepath")
        case .unavailable:
            Label("Live data unavailable", systemImage: "wifi.slash")
        }
    }

    private var summary: String {
        guard let status else { return "Unavailable" }
        let dates = status.signals.flatMap { $0.effectiveObservedAtBySourceID.values }
        let age = dates.min().map {
            HydroPresentationFormatter.age(observedAt: $0, referenceDate: Date())
        } ?? "Observation time unavailable"
        return "\(HydroPresentationFormatter.freshness(status.freshness)) · \(age)"
    }
}

private struct SignalDetailRow: View {
    let signal: HydroDisplaySignal
    let status: HydroDisplaySignalStatus?
    let waterBody: WaterBody

    var body: some View {
        DisclosureGroup {
            if let status, !status.measurements.isEmpty {
                ForEach(Array(status.measurements.enumerated()), id: \.offset) { _, measurement in
                    MeasurementProvenanceView(measurement: measurement, status: status)
                }
            } else {
                Text(detailText).foregroundStyle(.secondary)
            }
        } label: {
            HStack {
                Text(signal.displayName)
                Spacer()
                Text(summaryText).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(signal.displayName), \(summaryText)")
    }

    private var summaryText: String {
        guard let status else {
            return signal.capabilities.contains { waterBody.coverage[$0] == .supported }
                ? "Not loaded" : "Unsupported"
        }
        switch status.observationAvailability {
        case .observed:
            return status.measurements.first.map(HydroPresentationFormatter.value) ?? "Observed"
        case .stale: return "Stale"
        case .missing: return "Missing"
        case .unavailable: return "Unsupported"
        }
    }

    private var detailText: String {
        switch status?.observationAvailability {
        case .missing: "A reviewed source exists, but the latest state has no measurement."
        case .stale: "The latest measurement is retained as evidence but is too old to drive water."
        case .unavailable: "No reviewed source currently supports this signal."
        case .observed: "Observation details unavailable."
        case nil: "Current observations have not loaded."
        }
    }
}

private struct MeasurementProvenanceView: View {
    let measurement: HydroMeasurement
    let status: HydroDisplaySignalStatus

    var body: some View {
        let source = HydroPresentationFormatter.source(measurement.sourceID)
        let used = status.usableMeasurementSourceIDs.contains(measurement.sourceID)
        VStack(alignment: .leading, spacing: 4) {
            Text(HydroPresentationFormatter.value(measurement)).font(.headline)
            Text("\(source.providerName) · \(source.sourceName)")
            if let observedAt = status.effectiveObservedAtBySourceID[measurement.sourceID] {
                Text(HydroPresentationFormatter.age(observedAt: observedAt, referenceDate: Date()))
            }
            Text("\(HydroPresentationFormatter.quality(measurement.quality, used: used)) · \(HydroPresentationFormatter.origin(measurement.origin))")
            Text(source.canonicalSourceID).font(.caption.monospaced()).textSelection(.enabled)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

private extension WaterBodyKind {
    var displayName: String { rawValue.capitalized }
}

private extension HydroCapability {
    var displayName: String {
        switch self {
        case .waterLevel: "Water level"
        case .waterTemperature: "Temperature"
        case .wind: "Wind"
        case .airPressure: "Pressure"
        case .salinity: "Salinity"
        case .currentSpeed: "Current speed"
        case .currentDirection: "Current direction"
        }
    }
}
