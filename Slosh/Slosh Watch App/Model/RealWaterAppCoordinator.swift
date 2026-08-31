import Foundation
import OceanCore
import OSLog

/// Watch-side Real Water is intentionally dormant in the shipping app. The live
/// provider stack remains available to the iPhone Places app and command-line
/// provider checks, but this target must not link provider networking until Real
/// Water is a product feature with reviewed privacy disclosures.
@MainActor
final class RealWaterAppCoordinator {
    private static let logger = Logger(
        subsystem: "com.example.Slosh.watchkitapp",
        category: "RealWater"
    )
    private var task: Task<Void, Never>?
    private let forceFailure: Bool

    init(forceFailure: Bool = false) {
        self.forceFailure = forceFailure
    }

    func activate(
        waterBody: WaterBody?,
        model: OceanModel,
        onLoadState: @escaping (RealWaterLoadState) -> Void
    ) {
        task?.cancel()
        task = nil
        guard let waterBody else {
            onLoadState(.inactive)
            return
        }
        if forceFailure {
            onLoadState(.failed(waterBody.id, "Real Water is unavailable on watch"))
        } else {
            onLoadState(.unavailable(waterBody.id))
        }
        Self.logger.debug("Watch app excludes real-water provider networking")
    }

    func deactivate() {
        task?.cancel()
        task = nil
    }
}
