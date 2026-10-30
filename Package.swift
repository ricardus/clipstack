// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clipstack",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Clipstack", path: "Sources/Clipstack")
    ]
)
