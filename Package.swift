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
    dependencies: [],
    targets: [
        .executableTarget(
            name: "PathChanger",
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
