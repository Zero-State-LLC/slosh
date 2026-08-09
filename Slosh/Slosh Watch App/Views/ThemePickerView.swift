import OceanCore
import OceanUI
import SpriteKit
import SwiftUI
import WatchKit

/// One page per ocean, each a live preview rather than a swatch — the whole
/// point is that the themes *move* differently, which a static colour chip
/// cannot show.
struct ThemePickerView: View {
    @Binding var selectedThemeID: String
    @Binding var selectedPlaceID: String
    @Binding var hapticsEnabled: Bool
    let realWaterLoadState: RealWaterLoadState
    @Environment(\.dismiss) private var dismiss

    @State private var page: String = ""

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                ForEach(OceanTheme.all) { theme in
                    ThemePage(
                        theme: theme,
                        isCurrent: selectedPlaceID.isEmpty && theme.id == selectedThemeID,
                        choose: {
                            selectedPlaceID = ""
                            selectedThemeID = theme.id
                            WKInterfaceDevice.current().play(.click)
                            dismiss()
                        }
                    )
                    .tag(theme.id)
                }

                ForEach(WaterBodies.all) { waterBody in
                    PlacePage(
                        waterBody: waterBody,
                        isCurrent: waterBody.id == selectedPlaceID,
                        loadState: realWaterLoadState,
                        choose: {
                            selectedPlaceID = waterBody.id
                            WKInterfaceDevice.current().play(.click)
                            dismiss()
                        }
                    )
                    .tag("place:\(waterBody.id)")
                }

                SettingsPage(hapticsEnabled: $hapticsEnabled)
                    .tag("settings")
            }
            .tabViewStyle(.verticalPage)
        }
        .onAppear {
            page = selectedPlaceID.isEmpty ? selectedThemeID : "place:\(selectedPlaceID)"
        }
    }
}

private struct PlacePage: View {
    let waterBody: WaterBody
    let isCurrent: Bool
    let loadState: RealWaterLoadState
    let choose: () -> Void

    private var supportedSignals: [HydroDisplaySignal] {
        HydroDisplaySignal.allCases.filter { signal in
            signal.capabilities.contains {
                waterBody.coverage[$0] == .supported
            }
        }
    }

    private var catalogSummary: String {
        let names = supportedSignals.map { $0.displayName.lowercased() }
        guard names.count > 2 else { return names.joined(separator: " + ") }
        return "\(names[0]) + \(names[1]) + \(names.count - 2) more"
    }

    private var activeState: RealWaterLoadState? {
        loadState.waterBodyID == waterBody.id ? loadState : nil
    }

    private var statusLine: String {
        guard let activeState else { return "Reviewed: \(catalogSummary)" }
        switch activeState {
        case .inactive: return "Reviewed: \(catalogSummary)"
        case .loading: return "Loading latest observations…"
        case let .loaded(status): return liveSummary(status)
        case let .preserved(status): return "Using last observation · \(ageSummary(status))"
        case .unavailable: return "Live data unavailable"
        }
    }

    private func liveSummary(_ status: PlaceHydroStatus) -> String {
        "\(HydroPresentationFormatter.freshness(status.freshness)) · \(ageSummary(status))"
    }

    private func ageSummary(_ status: PlaceHydroStatus) -> String {
        let observedAt = status.signals
            .flatMap { $0.effectiveObservedAtBySourceID.values }
            .min()
        guard let observedAt else { return "current time unavailable" }
        return HydroPresentationFormatter.age(observedAt: observedAt, referenceDate: Date())
            .replacingOccurrences(of: "Observed ", with: "")
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.03, green: 0.24, blue: 0.38),
                                     Color(red: 0.01, green: 0.08, blue: 0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: waterBody.kind == .lake ? "mountain.2.fill" : "water.waves")
                    .font(.system(size: 30))
                    .foregroundStyle(.cyan)
            }
            .frame(height: 74)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isCurrent ? .cyan : .clear, lineWidth: 2)
            }

            Text(waterBody.name).font(.headline)
            Text(waterBody.region)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(statusLine)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            NavigationLink {
                PlaceStatusView(waterBody: waterBody, loadState: loadState)
            } label: {
                Label("Status & sources", systemImage: "info.circle")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(waterBody.name), status and observation sources")

            Button(isCurrent ? "Current place" : "Wear this place", action: choose)
                .disabled(isCurrent)
                .buttonStyle(.bordered)
                .tint(.cyan)
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(waterBody.name), \(statusLine)")
    }
}

private struct PlaceStatusView: View {
    let waterBody: WaterBody
    let loadState: RealWaterLoadState

    private var status: PlaceHydroStatus {
        if loadState.waterBodyID == waterBody.id, let status = loadState.status {
            return status
        }
        return PlaceHydroStatusResolver().resolve(
            waterBody: waterBody,
            state: nil,
            referenceDate: Date()
        )
    }

    private var header: String {
        guard loadState.waterBodyID == waterBody.id else {
            return "Reviewed capability"
        }
        return switch loadState {
        case .loading: "Loading latest observations…"
        case .preserved: "Using last observation"
        case .unavailable: "Live data unavailable"
        case let .loaded(status): HydroPresentationFormatter.freshness(status.freshness)
        case .inactive: "Reviewed capability"
        }
    }

    var body: some View {
        List {
            Section {
                Text(header)
                    .foregroundStyle(loadState.waterBodyID == waterBody.id ? .primary : .secondary)
            } header: {
                Text(waterBody.name)
            }

            Section("Signals") {
                ForEach(status.displaySignals) { signal in
                    NavigationLink {
                        SignalProvenanceView(signal: signal, referenceDate: Date())
                    } label: {
                        SignalStatusRow(signal: signal)
                    }
                }
            }
        }
        .navigationTitle("Real Water")
    }
}

private struct SignalStatusRow: View {
    let signal: HydroDisplaySignalStatus

    private var detail: String {
        switch signal.observationAvailability {
        case .unavailable: "Unavailable"
        case .missing: "No current observation"
        case .stale: "Stale · not used"
        case .observed:
            signal.measurements.map(HydroPresentationFormatter.value).joined(separator: " · ")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(signal.signal.displayName)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(signal.signal.displayName), \(detail)")
    }
}

private struct SignalProvenanceView: View {
    let signal: HydroDisplaySignalStatus
    let referenceDate: Date

    var body: some View {
        List {
            if signal.measurements.isEmpty {
                Text(signal.observationAvailability == .unavailable
                     ? "No reviewed source is available for this Place."
                     : "The reviewed source returned no current observation.")
            } else {
                ForEach(Array(signal.measurements.enumerated()), id: \.offset) { _, measurement in
                    let source = HydroPresentationFormatter.source(measurement.sourceID)
                    let used = signal.usableMeasurementSourceIDs.contains(measurement.sourceID)
                    Section {
                        Text(HydroPresentationFormatter.value(measurement))
                            .font(.headline)
                        Text(signal.effectiveObservedAtBySourceID[measurement.sourceID].map {
                            HydroPresentationFormatter.age(observedAt: $0, referenceDate: referenceDate)
                        } ?? "Observation time unavailable")
                        Text("\(source.providerName) · \(source.sourceName)")
                        Text("Quality: \(HydroPresentationFormatter.quality(measurement.quality, used: used))")
                        Text("Origin: \(HydroPresentationFormatter.origin(measurement.origin))")
                        Text(source.canonicalSourceID)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text(signal.signal.displayName)
                    }
                }
            }
        }
        .navigationTitle(signal.signal.displayName)
    }
}

private struct ThemePage: View {
    let theme: OceanTheme
    let isCurrent: Bool
    let choose: () -> Void

    /// Each page runs its own small ocean, drifting slowly so the preview
    /// shows the swell moving without a wrist behind it.
    @State private var scene: WaterScene

    init(theme: OceanTheme, isCurrent: Bool, choose: @escaping () -> Void) {
        self.theme = theme
        self.isCurrent = isCurrent
        self.choose = choose

        let scene = WaterScene()
        scene.size = CGSize(width: Screen.width, height: 84)
        scene.scaleMode = .resizeFill
        scene.theme = theme
        scene.motionSource = DriftingMotion(startAngle: 0.8)
        _scene = State(initialValue: scene)
    }

    var body: some View {
        VStack(spacing: 6) {
            WaterSurfaceView(scene: scene)
                .frame(height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isCurrent ? Color(theme.light) : .clear, lineWidth: 2)
                }

            Text(theme.name)
                .font(.headline)
            Text(theme.blurb)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button(isCurrent ? "Current" : "Use this", action: choose)
                .disabled(isCurrent)
                .buttonStyle(.bordered)
                .tint(Color(theme.shallow))
        }
        .padding(.horizontal, 8)
    }
}

private struct SettingsPage: View {
    @Binding var hapticsEnabled: Bool

    var body: some View {
        Form {
            Toggle("Haptics", isOn: $hapticsEnabled)
            Section {
                Text("Turn the Digital Crown to change how lively the water is.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ThemePickerView(
        selectedThemeID: .constant(OceanTheme.calmOcean.id),
        selectedPlaceID: .constant(""),
        hapticsEnabled: .constant(true),
        realWaterLoadState: .inactive
    )
}
