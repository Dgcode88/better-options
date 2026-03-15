// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BetterOptions",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "BetterOptions", targets: ["BetterOptions"]),
    ],
    targets: [
        .executableTarget(
            name: "BetterOptions",
            path: "Sources"
        ),
    ]
)
