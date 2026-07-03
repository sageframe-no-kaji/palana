// swift-tools-version: 6.0
//
// The ho-01 spike. Throwaway by design — this package is deleted at the
// close of ho-01. The findings graduate; the code does not.

import PackageDescription

let package = Package(
    name: "PalanaSpike",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .target(name: "PalanaSpikeKit"),
        .executableTarget(name: "PalanaSpike", dependencies: ["PalanaSpikeKit"]),
        .executableTarget(name: "FetchProbe", dependencies: ["PalanaSpikeKit"]),
    ],
    swiftLanguageModes: [.v6]
)
