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
        // Sparkle for auto-updates
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.0")
    ],
    targets: [
        .executableTarget(
            name: "PathChanger",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "PathChanger",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources/en.lproj"),
                .process("Resources/ja.lproj")
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
