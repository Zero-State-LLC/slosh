// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OceanCore",
    platforms: [.watchOS(.v10), .iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OceanCore", targets: ["OceanCore"]),
        .library(name: "OceanUI", targets: ["OceanUI"]),
    ],
    targets: [
        // Motion handling and themes. No UI framework, so it runs anywhere.
        .target(name: "OceanCore"),

        // The water itself: SpriteKit scene plus the fragment shader.
        // SpriteKit is the only route to per-pixel shading on watchOS —
        // Metal and SwiftUI's colorEffect are both unavailable there.
        .target(name: "OceanUI", dependencies: ["OceanCore"]),

        // Test suite as a plain executable rather than XCTest: it runs from
        // the command line with only the Swift toolchain installed.
        .executableTarget(name: "oceancheck", dependencies: ["OceanCore"]),
        .executableTarget(name: "hydrocheck", dependencies: ["OceanCore"]),
    ]
)
