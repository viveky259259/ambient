// swift-tools-version:6.2
import PackageDescription

// The offline voice helper. Separate from Ambient's own package so that Ambient keeps no dependencies; it's
// downloaded only by people who choose the offline voice.
let package = Package(
    name: "AmbientVoice",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(name: "Ambient", path: ".."),
        .package(url: "https://github.com/mlalma/kokoro-ios.git", exact: "1.0.11"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.2"),
    ],
    targets: [
        .executableTarget(
            name: "ambient-voice",
            dependencies: [
                .product(name: "AmbientCore", package: "Ambient"),
                .product(name: "KokoroSwift", package: "kokoro-ios"),
                .product(name: "MLX", package: "mlx-swift"),
            ]
        ),
    ]
)
