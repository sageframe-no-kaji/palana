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
        // SwiftTerm arrives at ho-11 for the interactive terminal — the
        // Palana app target's dependency only. PalanaCore stays
        // dependency-free: the emulator is chrome, not engine.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.14.0"),
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
            dependencies: [
                "PalanaCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "PalanaCoreTests",
            dependencies: ["PalanaCore"],
            // Transcripts are read via #filePath, not the bundle — exclude
            // them so SwiftPM stops warning about unhandled resources.
            exclude: ["Fixtures"]
        ),
        .testTarget(
            name: "PalanaTests",
            dependencies: ["Palana"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
