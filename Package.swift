// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LocalFlow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LocalFlowCore", targets: ["LocalFlowCore"]),
        .executable(name: "LocalFlow", targets: ["LocalFlow"])
    ],
    targets: [
        .target(name: "LocalFlowCore"),
        .executableTarget(
            name: "LocalFlow",
            dependencies: ["LocalFlowCore"]
        ),
        .testTarget(
            name: "LocalFlowCoreTests",
            dependencies: ["LocalFlowCore"]
        )
    ]
)
