// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "hdmi-defubar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "DefubarCore"),
        .executableTarget(name: "hdmi-defubar", dependencies: ["DefubarCore"]),
        .testTarget(name: "DefubarCoreTests", dependencies: ["DefubarCore"]),
    ]
)
