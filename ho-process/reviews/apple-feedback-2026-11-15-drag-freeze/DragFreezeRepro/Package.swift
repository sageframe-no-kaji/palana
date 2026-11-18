// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DragFreezeRepro",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "DragFreezeRepro")]
)
