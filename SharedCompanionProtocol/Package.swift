// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SharedCompanionProtocol",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "SharedCompanionProtocol",
            targets: ["SharedCompanionProtocol"]
        )
    ],
    targets: [
        .target(
            name: "SharedCompanionProtocol",
            path: "Sources"
        )
    ]
)
