import OceanCore
import OceanUI
import SpriteKit
import SwiftUI
import WatchKit

/// One page per ocean, each a live preview rather than a swatch — the whole
/// point is that the themes *move* differently, which a static colour chip
/// cannot show.
struct ThemePickerView: View {
    @Binding var selectedID: String
    @Binding var hapticsEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var page: String = ""

    var body: some View {
        TabView(selection: $page) {
            ForEach(OceanTheme.all) { theme in
                ThemePage(
                    theme: theme,
                    isCurrent: theme.id == selectedID,
                    choose: {
                        selectedID = theme.id
                        WKInterfaceDevice.current().play(.click)
                        dismiss()
                    }
                )
                .tag(theme.id)
            }

            SettingsPage(hapticsEnabled: $hapticsEnabled)
                .tag("settings")
        }
        .tabViewStyle(.verticalPage)
        .onAppear { page = selectedID }
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
        selectedID: .constant(OceanTheme.calmOcean.id),
        hapticsEnabled: .constant(true)
    )
}
