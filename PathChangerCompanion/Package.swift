// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PathChangerCompanion",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .executable(name: "PathChangerCompanion", targets: ["PathChangerCompanion"])
    ],
    dependencies: [
        .package(path: "../SharedCompanionProtocol")
    ],
    targets: [
        .executableTarget(
            name: "PathChangerCompanion",
            dependencies: [
                .product(name: "SharedCompanionProtocol", package: "SharedCompanionProtocol")
            ],
            path: "."
        )
    ]
)
