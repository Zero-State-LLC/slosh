// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OceanCore",
    platforms: [.watchOS(.v10), .iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OceanCore", targets: ["OceanCore"]),
        .library(name: "OceanUI", targets: ["OceanUI"]),
        .library(name: "HydroProviders", targets: ["HydroProviders"]),
    ],
    targets: [
        // Motion handling and themes. No UI framework, so it runs anywhere.
        .target(name: "OceanCore"),

        // The water itself: SpriteKit scene plus the fragment shader.
        // SpriteKit is the only route to per-pixel shading on watchOS —
        // Metal and SwiftUI's colorEffect are both unavailable there.
        .target(name: "OceanUI", dependencies: ["OceanCore"]),

        // Provider transport and adapters. URLSession, provider URLs, and NOAA
        // and USGS DTOs stop here and never enter the portable OceanCore target.
        .target(name: "HydroProviders", dependencies: ["OceanCore"]),

        // Research-only types. Not library products, so Watch and iPhone apps
        // that link OceanCore / HydroProviders do not ship the RW4F resolver,
        // NHD fixture adapter, or metadata-candidate adapters. Debug CLIs
        // (resolutioncheck, providercheck) still depend on these targets.
        .target(name: "OceanCoreResearch", dependencies: ["OceanCore"]),
        .target(
            name: "HydroProvidersResearch",
            dependencies: ["OceanCore", "OceanCoreResearch", "HydroProviders"]
        ),

        // Test suite as a plain executable rather than XCTest: it runs from
        // the command line with only the Swift toolchain installed.
        .executableTarget(name: "oceancheck", dependencies: ["OceanCore", "OceanUI"]),
        .executableTarget(name: "hydrocheck", dependencies: ["OceanCore"]),
        .executableTarget(
            name: "providercheck",
            dependencies: ["OceanCore", "HydroProviders", "HydroProvidersResearch"],
            resources: [.process("Fixtures")]
        ),
        .executableTarget(
            name: "resolutioncheck",
            dependencies: ["OceanCore", "OceanCoreResearch", "HydroProviders", "HydroProvidersResearch"],
            resources: [.process("Fixtures"), .copy("Artifacts")]
        ),
        .executableTarget(name: "placeintake", dependencies: ["OceanCore"]),
    ]
)
