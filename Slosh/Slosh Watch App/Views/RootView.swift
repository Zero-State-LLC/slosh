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

    /// Synthetic fixtures win when both flags are supplied. The launch argument
    /// overrides persisted selection so every curated route is scriptable.
    private static let debugRealWaterBody: WaterBody? = {
        #if DEBUG
        if let validationBody = PhysicalValidationMode.waterBody {
            return validationBody
        }
        #if targetEnvironment(simulator)
        guard debugHydroExperience == nil,
              let id = UserDefaults.standard.string(forKey: "realWater") else {
            return nil
        }
        return WaterBodies.body(id: id)
        #else
        return nil
        #endif
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
    @AppStorage(SettingsKey.placeID) private var placeID = ""

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    @State private var model = OceanModel(
        theme: .calmOcean,
        hydroExperience: RootView.debugHydroExperience
    )
    @State private var realWaterCoordinator = RealWaterAppCoordinator(
        forceFailure: RootView.debugRealWaterForceFailure
    )
    @State private var realWaterLoadState: RealWaterLoadState = .inactive
    @State private var crownEnergy = EnergyRange.default
    #if DEBUG
    @State private var physicalValidationDiagnostics = PhysicalValidationDiagnostics()
    #endif

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
        #if DEBUG
        if let validationTheme = PhysicalValidationMode.authoredTheme {
            return validationTheme
        }
        #endif
        return RootView.debugHydroExperience == nil && activeWaterBody == nil
            ? .theme(id: themeID)
            : .calmOcean
    }

    private var activeWaterBody: WaterBody? {
        guard RootView.debugHydroExperience == nil else { return nil }
        return RootView.debugRealWaterBody ?? WaterBodies.body(id: placeID)
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
                        .accessibilityLabel("Choose water")
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
            ThemePickerView(
                selectedThemeID: $themeID,
                selectedPlaceID: $placeID,
                hapticsEnabled: $hapticsEnabled,
                realWaterLoadState: realWaterLoadState
            )
        }
        .onAppear {
            crownEnergy = storedEnergy
            model.apply(theme: theme)
            model.apply(hydroExperience: RootView.debugHydroExperience)
            model.apply(energy: storedEnergy)
            model.haptics.isEnabled = hapticsEnabled
            #if DEBUG
            physicalValidationDiagnostics.install(on: model)
            model.haptics.onAttempt = { kind, fired, reason in
                physicalValidationDiagnostics.haptic(kind: kind, fired: fired, reason: reason)
            }
            #endif
            model.startRunning()
            activateRealWater()
        }
        .onDisappear {
            #if DEBUG
            physicalValidationDiagnostics.lifecycle("view-disappear")
            #endif
            deactivateRealWater()
            model.stopRunning()
        }
        .onChange(of: themeID) { _, newValue in
            model.apply(theme: theme)
        }
        .onChange(of: placeID) { _, _ in
            // Never show one place's forcing while another place is loading or
            // unavailable. Each selection starts from authored Calm ocean.
            deactivateRealWater()
            model.apply(hydroExperience: nil)
            model.apply(theme: theme)
            realWaterLoadState = activeWaterBody.map {
                .loading($0.id)
            } ?? .inactive
            if scenePhase == .active, !isLuminanceReduced { activateRealWater() }
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
                #if DEBUG
                physicalValidationDiagnostics.lifecycle("foreground-bright")
                #endif
                model.startRunning()
                activateRealWater()
            } else {
                #if DEBUG
                physicalValidationDiagnostics.lifecycle("scene-\(String(describing: phase))")
                #endif
                deactivateRealWater()
                model.stopRunning()
            }
        }
        .onChange(of: isLuminanceReduced) { _, dimmed in
            if dimmed {
                #if DEBUG
                physicalValidationDiagnostics.lifecycle("luminance-reduced")
                #endif
                deactivateRealWater()
                model.stopRunning()
            } else if scenePhase == .active {
                #if DEBUG
                physicalValidationDiagnostics.lifecycle("luminance-restored")
                #endif
                model.startRunning()
                activateRealWater()
            }
        }
    }

    private func activateRealWater() {
        realWaterCoordinator.activate(
            waterBody: activeWaterBody,
            model: model,
            onLoadState: { realWaterLoadState = $0 }
        )
    }

    private func deactivateRealWater() {
        realWaterCoordinator.deactivate()
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
