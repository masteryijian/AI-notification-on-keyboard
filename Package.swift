// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "pixiu-agent-led",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "pixiu-led", targets: ["PixiuLED"]),
    ],
    targets: [
        .executableTarget(name: "PixiuLED"),
        .testTarget(name: "PixiuLEDTests", dependencies: ["PixiuLED"]),
    ]
)
