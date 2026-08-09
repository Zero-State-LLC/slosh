import Foundation
import OceanCore
import OceanUI
import SpriteKit
import WatchKit

/// Owns the live water scene and the sensor lifecycle. Kept out of the views so
/// `RootView` stays a layout.
///
/// Not actor-isolated, deliberately: everything here is reached from the view
/// layer or from the CoreMotion handler, and that handler is explicitly
/// delivered to `.main`, so the class is single-threaded by construction.
final class OceanModel {
    let scene = WaterScene()
    let haptics = Haptics()

    private let source: MotionSource

    init(theme: OceanTheme, hydroExperience: HydroExperience? = nil) {
        // The watch simulator has no motion sensors, so there the water is
        // driven by a drag gesture instead. Everything downstream is identical.
        #if targetEnvironment(simulator)
        source = SimulatedMotionProvider()
        #else
        source = WatchMotionProvider()
        #endif

        scene.size = CGSize(width: Screen.width, height: Screen.width * 1.25)
        scene.scaleMode = .resizeFill
        scene.motionSource = source
        scene.theme = theme
        apply(hydroExperience: hydroExperience)
    }

    /// Non-nil only in the simulator, where drags stand in for the wrist.
    var simulatedMotion: SimulatedMotionProvider? {
        source as? SimulatedMotionProvider
    }

    var physicalMotionDiagnostics: WatchMotionProvider.DiagnosticState? {
        (source as? WatchMotionProvider)?.diagnosticState
    }

    // MARK: - Lifecycle

    /// Sensors and rendering run only while the app is frontmost. This is the
    /// whole battery story: a backgrounded ocean costs nothing.
    func startRunning() {
        source.start()
        scene.resume()
        scene.isPaused = false
    }

    func stopRunning() {
        source.stop()
        scene.isRunning = false
        scene.isPaused = true
    }

    // MARK: - Input

    func apply(theme: OceanTheme) {
        scene.theme = theme
    }

    func apply(energy: Double) {
        scene.energy = energy
    }

    func apply(hydroExperience: HydroExperience?) {
        scene.environmentalForcing = hydroExperience?.forcing
        scene.hydroThemeModifiers = hydroExperience?.themeModifiers
    }

    func tapped() {
        haptics.playBreak(scene.theme.haptic)
    }
}
