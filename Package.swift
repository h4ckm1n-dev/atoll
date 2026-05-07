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
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.3.0"),
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
