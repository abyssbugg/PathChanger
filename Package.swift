// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PathChanger",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PathChanger", targets: ["PathChanger"])
    ],
    dependencies: [
        // Sparkle for auto-updates.
        // Pinned exactly: a `from:` range let the SwiftPM and Xcode-wrapper lockfiles drift to
        // different versions (2.8.1 vs 2.9.5), so the framework you shipped depended on which
        // build path you used. Upgrading is a deliberate, separately testable change.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.8.1")
    ],
    targets: [
        .executableTarget(
            name: "PathChanger",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "PathChanger",
            resources: [
                .process("Resources/en.lproj"),
                .process("Resources/ja.lproj"),
                .process("Resources/Fonts")
            ]
        ),
        // Test target - tests the executable target directly
        .testTarget(
            name: "PathChangerTests",
            dependencies: ["PathChanger"],
            path: "Tests/PathChangerTests"
        )
    ]
)
