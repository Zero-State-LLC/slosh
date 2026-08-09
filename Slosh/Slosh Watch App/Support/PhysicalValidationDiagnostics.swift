#if DEBUG
import Foundation
import OceanCore
import OceanUI
import OSLog
import WatchKit

/// DEBUG-only activation and deterministic routing for physical-device sessions.
/// No symbol or behavior from this file exists in Release builds.
enum PhysicalValidationMode {
    static let isEnabled = UserDefaults.standard.bool(forKey: "physicalValidation")
    static let requestedRoute = UserDefaults.standard.string(forKey: "validationRoute")

    static var authoredTheme: OceanTheme? {
        guard isEnabled, let route = requestedRoute else { return nil }
        switch route {
        case "calm": return .calmOcean
        case "breaking-surf": return .breakingSurf
        case "storm-at-night": return .stormAtNight
        default: return nil
        }
    }

    static var waterBody: WaterBody? {
        guard isEnabled, requestedRoute == "san-francisco-bay" else { return nil }
        return WaterBodies.body(id: "san-francisco-bay")
    }
}

@MainActor
final class PhysicalValidationDiagnostics {
    private static let logger = Logger(
        subsystem: "com.example.Slosh.watchkitapp",
        category: "PhysicalValidation"
    )

    private weak var model: OceanModel?

    func install(on model: OceanModel) {
        guard PhysicalValidationMode.isEnabled else { return }
        self.model = model
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        model.scene.onDiagnostics = { [weak self] snapshot in
            Task { @MainActor in self?.log(snapshot) }
        }
        logSession(event: "session-start")
    }

    func lifecycle(_ event: String) {
        guard PhysicalValidationMode.isEnabled else { return }
        logSession(event: event)
    }

    func haptic(kind: HapticKind?, fired: Bool, reason: String) {
        guard PhysicalValidationMode.isEnabled else { return }
        let name = kind?.rawValue ?? "none"
        Self.logger.info("haptic kind=\(name, privacy: .public) fired=\(fired) reason=\(reason, privacy: .public)")
    }

    private func log(_ snapshot: WaterScene.DiagnosticSnapshot) {
        let motion = model?.physicalMotionDiagnostics
        let device = WKInterfaceDevice.current()
        let thermal = Self.thermalName(ProcessInfo.processInfo.thermalState)
        let battery = device.batteryLevel >= 0
            ? String(format: "%.0f", device.batteryLevel * 100)
            : "NOT_COMPUTABLE"
        let rawX = motion.map { String(format: "%.4f", $0.rawGravityX) } ?? "NOT_COMPUTABLE"
        let rawY = motion.map { String(format: "%.4f", $0.rawGravityY) } ?? "NOT_COMPUTABLE"
        let crown = motion.map { String(describing: $0.crownOrientation) } ?? "NOT_COMPUTABLE"
        let wrist = motion.map { String(describing: $0.wristLocation) } ?? "NOT_COMPUTABLE"
        let message = String(
            format: "route=%@ rawGravity=(%@,%@) correctedGravity=(%.4f,%.4f) magnitude=%.4f heading=%.4f flow=(%.4f,%.4f) fps.instant=%.1f fps.rolling=%.1f fps.average=%.1f fps.minimum=%.1f slowFrames=%d frames=%d duration=%.1f crown=%@ wrist=%@ thermal=%@ batteryPercent=%@",
            PhysicalValidationMode.requestedRoute ?? "current",
            rawX, rawY,
            snapshot.gravityX, snapshot.gravityY, snapshot.inPlaneMagnitude,
            snapshot.heading, snapshot.flowX, snapshot.flowY,
            snapshot.frameRate.instantaneousFPS,
            snapshot.frameRate.rollingFPS,
            snapshot.frameRate.averageFPS,
            snapshot.frameRate.minimumRollingFPS,
            snapshot.frameRate.slowFrameCount,
            snapshot.frameRate.observedFrameCount,
            snapshot.frameRate.duration,
            crown, wrist, thermal, battery
        )
        Self.logger.info("\(message, privacy: .public)")
    }

    private func logSession(event: String) {
        let device = WKInterfaceDevice.current()
        let battery = device.batteryLevel >= 0
            ? String(format: "%.0f", device.batteryLevel * 100)
            : "NOT_COMPUTABLE"
        let message = "event=\(event) route=\(PhysicalValidationMode.requestedRoute ?? "current") system=\(device.systemName) watchOS=\(device.systemVersion) model=\(device.model) crown=\(String(describing: device.crownOrientation)) wrist=\(String(describing: device.wristLocation)) thermal=\(Self.thermalName(ProcessInfo.processInfo.thermalState)) batteryPercent=\(battery)"
        Self.logger.notice("\(message, privacy: .public)")
    }

    private static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
#endif
