import OceanCore
import SpriteKit
import SwiftUI

/// The ocean, filling whatever space it is given.
///
/// The scene is built once and kept alive across redraws — rebuilding it would
/// restart the shader clock and jump the waves.
public struct WaterSurfaceView: View {
    private let scene: WaterScene
    private let onTap: ((CGPoint) -> Void)?

    public init(scene: WaterScene, onTap: ((CGPoint) -> Void)? = nil) {
        self.scene = scene
        self.onTap = onTap
    }

    public var body: some View {
        GeometryReader { geometry in
            SpriteView(scene: scene, preferredFramesPerSecond: 60)
                .onAppear { scene.size = geometry.size }
                .onChange(of: geometry.size) { _, newSize in
                    scene.size = newSize
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    // SpriteKit's origin is bottom-left; SwiftUI's is top-left.
                    let point = CGPoint(
                        x: location.x,
                        y: geometry.size.height - location.y
                    )
                    scene.tap(at: point)
                    onTap?(location)
                }
        }
    }
}
