// swift-tools-version:6.0
import PackageDescription

// Ambient's libraries are layered (docs/superpowers/specs/2026-11-13-modular-packages-design.md): AmbientBase holds
// utilities, AmbientContracts the vocabulary every module shares, and AmbientCore the rest, until it's split further.
let package = Package(
    name: "Ambient",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ambient", targets: ["ambient"]),
        .executable(name: "AmbientApp", targets: ["AmbientApp"]),
        .library(name: "AmbientBase", targets: ["AmbientBase"]),
        .library(name: "AmbientContracts", targets: ["AmbientContracts"]),
        .library(name: "AmbientCore", targets: ["AmbientCore"]),
    ],
    targets: [
        .target(
            name: "AmbientBase",
            linkerSettings: [.linkedFramework("Security")]
        ),
        .target(name: "AmbientContracts", dependencies: ["AmbientBase"]),
        .target(name: "AmbientCore", dependencies: ["AmbientBase", "AmbientContracts"]),
        .executableTarget(name: "ambient", dependencies: ["AmbientCore"]),
        .executableTarget(
            name: "AmbientApp",
            dependencies: ["AmbientCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "AmbientBaseTests", dependencies: ["AmbientBase"]),
        // Fixtures/ holds golden files, read by path rather than as resources.
        .testTarget(name: "AmbientContractsTests", dependencies: ["AmbientContracts"], exclude: ["Fixtures"]),
        // Fixtures/ holds golden files, read by path rather than as resources.
        .testTarget(name: "AmbientCoreTests", dependencies: ["AmbientCore"], exclude: ["Fixtures"]),
        // The CLI's own parsing: `ambient mcp`'s JSON-RPC and tools, and `ambient task model`'s arguments.
        .testTarget(name: "AmbientCLITests", dependencies: ["ambient"]),
    ],
    // The libraries and the CLI build in Swift 6 mode; the AppKit app opts into 5 above.
    swiftLanguageModes: [.v5, .v6]
)
