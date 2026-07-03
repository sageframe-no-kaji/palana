// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Palana",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "PalanaCore",
            targets: ["PalanaCore"]
        ),
        .executable(
            name: "Palana",
            targets: ["Palana"]
        ),
    ],
    dependencies: [
        // None at scaffold stage. Dependencies arrive with the ho that needs them.
    ],
    targets: [
        .target(
            name: "PalanaCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "Palana",
            dependencies: ["PalanaCore"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "PalanaCoreTests",
            dependencies: ["PalanaCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
