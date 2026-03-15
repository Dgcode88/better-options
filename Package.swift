// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LogiRemap",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "LogiRemap", targets: ["LogiRemap"]),
    ],
    targets: [
        .executableTarget(
            name: "LogiRemap",
            path: "Sources"
        ),
    ]
)
