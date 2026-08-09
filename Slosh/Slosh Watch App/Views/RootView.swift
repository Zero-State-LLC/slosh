import OceanCore
import OceanUI
import SwiftUI

/// The whole app: water, edge to edge, with the controls hidden in the
/// hardware. Tilt it, shake it, tap it, turn the crown.
struct RootView: View {
    /// Synthetic fixtures exist only for deterministic simulator QA. They all
    /// use Calm ocean, so captures compare environmental state rather than
    /// authored themes. Release and physical-watch builds compile this to nil.
    private static let debugHydroExperience: HydroExperience? = {
        #if DEBUG && targetEnvironment(simulator)
        guard let name = UserDefaults.standard.string(forKey: "hydroFixture") else {
            return nil
        }
        return HydroFixtures.experience(named: name)
        #else
        return nil
        #endif
    }()

    /// Synthetic fixtures win when both flags are supplied. Live mode is an
    /// integration harness, not a Places picker, and currently recognizes one
    /// reviewed body of water only.
    private static let debugRealWaterBody: WaterBody? = {
        #if DEBUG && targetEnvironment(simulator)
        guard debugHydroExperience == nil,
              let id = UserDefaults.standard.string(forKey: "realWater") else {
            return nil
        }
        return WaterBodies.body(id: id)
        #else
        return nil
        #endif
    }()

    private static let debugRealWaterForceFailure: Bool = {
        #if DEBUG && targetEnvironment(simulator)
        UserDefaults.standard.bool(forKey: "realWaterOffline")
        #else
        false
        #endif
    }()

    @AppStorage(SettingsKey.themeID) private var themeID = OceanTheme.calmOcean.id
    @AppStorage(SettingsKey.energy) private var storedEnergy = EnergyRange.default
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    @State private var model = OceanModel(
        theme: .calmOcean,
        hydroExperience: RootView.debugHydroExperience
    )
    #if DEBUG && targetEnvironment(simulator)
    @State private var realWaterCoordinator = RealWaterAppCoordinator(
        forceFailure: RootView.debugRealWaterForceFailure
    )
    #endif
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

    private var theme: OceanTheme {
        RootView.debugHydroExperience == nil && RootView.debugRealWaterBody == nil
            ? .theme(id: themeID)
            : .calmOcean
    }

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
            model.apply(hydroExperience: RootView.debugHydroExperience)
            model.apply(energy: storedEnergy)
            model.haptics.isEnabled = hapticsEnabled
            model.startRunning()
            activateRealWater()
        }
        .onDisappear {
            deactivateRealWater()
            model.stopRunning()
        }
        .onChange(of: themeID) { _, newValue in
            model.apply(theme: theme)
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
                activateRealWater()
            } else {
                deactivateRealWater()
                model.stopRunning()
            }
        }
        .onChange(of: isLuminanceReduced) { _, dimmed in
            if dimmed {
                deactivateRealWater()
                model.stopRunning()
            } else if scenePhase == .active {
                model.startRunning()
                activateRealWater()
            }
        }
    }

    private func activateRealWater() {
        #if DEBUG && targetEnvironment(simulator)
        realWaterCoordinator.activate(
            waterBody: RootView.debugRealWaterBody,
            model: model
        )
        #endif
    }

    private func deactivateRealWater() {
        #if DEBUG && targetEnvironment(simulator)
        realWaterCoordinator.deactivate()
        #endif
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
