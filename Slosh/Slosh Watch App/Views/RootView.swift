import OceanCore
import OceanUI
import SwiftUI

/// The whole app: water, edge to edge, with the controls hidden in the
/// hardware. Tilt it, shake it, tap it, turn the crown.
struct RootView: View {
    @AppStorage(SettingsKey.themeID) private var themeID = OceanTheme.calmOcean.id
    @AppStorage(SettingsKey.energy) private var storedEnergy = EnergyRange.default
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    @State private var model = OceanModel(theme: .theme(id: OceanTheme.calmOcean.id))
    @State private var crownEnergy = EnergyRange.default

    /// `simctl launch … -startInPicker YES` opens straight to the picker.
    /// The simulator offers no way to script a tap, so without this the whole
    /// theme-selection screen can only be checked by hand.
    @State private var showingPicker = {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "startInPicker")
        #else
        false
        #endif
    }()

    private var theme: OceanTheme { .theme(id: themeID) }

    var body: some View {
        // The NavigationStack is not for navigation — watchOS only renders a
        // `.toolbar` inside one, and the toolbar is the only visible chrome
        // the app has.
        NavigationStack {
            water
                .ignoresSafeArea()
                .containerBackground(Color(theme.deep), for: .navigation)
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            showingPicker = true
                        } label: {
                            Image(systemName: "drop.fill")
                        }
                        .accessibilityLabel("Choose ocean")
                    }
                }
        }
        .focusable()
        .digitalCrownRotation(
            $crownEnergy,
            from: EnergyRange.minimum,
            through: EnergyRange.maximum,
            by: EnergyRange.step,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .sheet(isPresented: $showingPicker) {
            ThemePickerView(selectedID: $themeID, hapticsEnabled: $hapticsEnabled)
        }
        .onAppear {
            crownEnergy = storedEnergy
            model.apply(theme: theme)
            model.apply(energy: storedEnergy)
            model.haptics.isEnabled = hapticsEnabled
            model.startRunning()
        }
        .onDisappear { model.stopRunning() }
        .onChange(of: themeID) { _, newValue in
            model.apply(theme: .theme(id: newValue))
        }
        .onChange(of: crownEnergy) { _, newValue in
            model.apply(energy: newValue)
            storedEnergy = newValue
        }
        .onChange(of: hapticsEnabled) { _, newValue in
            model.haptics.isEnabled = newValue
        }
        .onChange(of: scenePhase) { _, phase in
            // Nothing runs unless the app is frontmost and the screen is lit.
            if phase == .active, !isLuminanceReduced {
                model.startRunning()
            } else {
                model.stopRunning()
            }
        }
        .onChange(of: isLuminanceReduced) { _, dimmed in
            if dimmed {
                model.stopRunning()
            } else if scenePhase == .active {
                model.startRunning()
            }
        }
    }

    @ViewBuilder
    private var water: some View {
        let surface = WaterSurfaceView(scene: model.scene) { _ in
            model.tapped()
        }

        // Drag stands in for the wrist where there are no sensors. Compiled
        // out entirely on device, so it can never shadow a system edge swipe.
        #if targetEnvironment(simulator)
        surface.simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    model.simulatedMotion?.drag(
                        toUnitX: Double(value.location.x) / Screen.width,
                        unitY: Double(value.location.y) / (Screen.width * 1.25)
                    )
                }
                .onEnded { _ in model.simulatedMotion?.endDrag() }
        )
        #else
        surface
        #endif
    }
}

#Preview {
    RootView()
}
