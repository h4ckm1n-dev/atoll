// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Atoll",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "AtollCore",
            targets: ["AtollCore"]
        ),
        .executable(
            name: "AtollHooks",
            targets: ["AtollHooks"]
        ),
        .executable(
            name: "AtollSetup",
            targets: ["AtollSetup"]
        ),
        .executable(
            name: "AtollApp",
            targets: ["AtollApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0"),
        // Pinned to 0.9.x: WhisperKit 1.0.0 added an `ArgmaxCLI` executable target
        // that creates a duplicate-ID resolution error when SwiftPM does universal
        // builds (`--arch arm64 --arch x86_64`) in package-app.sh. v1 migration is
        // a separate follow-up — needs investigation of the new package structure.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", "0.9.0"..<"0.18.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.2"),
    ],
    targets: [
        .target(
            name: "CSQLiteShim",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "AtollCore",
            dependencies: ["CSQLiteShim"]
        ),
        .target(
            name: "AtollDictation",
            dependencies: [
                "AtollCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .executableTarget(
            name: "AtollHooks",
            dependencies: ["AtollCore"]
        ),
        .executableTarget(
            name: "AtollSetup",
            dependencies: ["AtollCore"]
        ),
        .executableTarget(
            name: "AtollApp",
            dependencies: [
                "AtollCore",
                "AtollDictation",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "AtollCoreTests",
            dependencies: ["AtollCore"]
        ),
        .testTarget(
            name: "AtollAppTests",
            dependencies: ["AtollApp", "AtollCore"]
        ),
    ]
)
