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
    @Environment(\.dismiss) private var dismiss

    @State private var page: String = ""

    var body: some View {
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
        .onAppear {
            page = selectedPlaceID.isEmpty ? selectedThemeID : "place:\(selectedPlaceID)"
        }
    }
}

private struct PlacePage: View {
    let waterBody: WaterBody
    let isCurrent: Bool
    let choose: () -> Void

    private var observed: String {
        HydroCapability.allCases
            .filter { waterBody.coverage[$0] == .observed }
            .map(\.displayName)
            .joined(separator: " · ")
    }

    private var unavailableCount: Int {
        HydroCapability.allCases.filter { waterBody.coverage[$0] == .unavailable }.count
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
            Text("Live: \(observed)")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text("\(unavailableCount) unavailable")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button(isCurrent ? "Current place" : "Wear this place", action: choose)
                .disabled(isCurrent)
                .buttonStyle(.bordered)
                .tint(.cyan)
        }
        .padding(.horizontal, 8)
    }
}

private extension HydroCapability {
    var displayName: String {
        switch self {
        case .waterLevel: "Level"
        case .waterTemperature: "Temperature"
        case .wind: "Wind"
        case .airPressure: "Pressure"
        case .salinity: "Salinity"
        case .currentSpeed: "Current speed"
        case .currentDirection: "Current direction"
        }
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
        hapticsEnabled: .constant(true)
    )
}
