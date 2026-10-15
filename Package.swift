// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Pulse", targets: ["Pulse"]),
        .library(name: "PulseCore", targets: ["PulseCore"]),
    ],
    targets: [
        .target(name: "PulseCore", path: "Sources/PulseCore"),
        .executableTarget(name: "Pulse", dependencies: ["PulseCore"], path: "Sources/Pulse"),
    ]
)
