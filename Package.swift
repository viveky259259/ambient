// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Ambient",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ambient", targets: ["ambient"]),
        .executable(name: "AmbientApp", targets: ["AmbientApp"]),
        .library(name: "AmbientCore", targets: ["AmbientCore"]),
    ],
    targets: [
        .target(name: "AmbientCore"),
        .executableTarget(name: "ambient", dependencies: ["AmbientCore"]),
        .executableTarget(
            name: "AmbientApp",
            dependencies: ["AmbientCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "AmbientCoreTests", dependencies: ["AmbientCore"]),
    ]
)
