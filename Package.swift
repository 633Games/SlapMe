// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SlapMe",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SPUAccel", targets: ["SPUAccel"]),
        .executable(name: "slapme-helper", targets: ["SlapMeHelper"]),
        .executable(name: "SlapMe", targets: ["SlapMe"]),
    ],
    targets: [
        .target(
            name: "SPUAccel",
            path: "Sources/SPUAccel"
        ),
        .executableTarget(
            name: "SlapMeHelper",
            dependencies: ["SPUAccel"],
            path: "Sources/SlapMeHelper"
        ),
        .executableTarget(
            name: "SlapMe",
            path: "Sources/SlapMe",
            resources: [
                .copy("Resources"),
            ]
        ),
    ]
)
