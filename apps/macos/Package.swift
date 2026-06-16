// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ShoutOut",
    platforms: [
        .macOS("15.0")
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "ShoutOutCore",
            path: "Sources/Core"
        ),
        .executableTarget(
            name: "ShoutOut",
            dependencies: [
                "ShoutOutCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources",
            exclude: ["Core", "Resources"],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
            ]
        ),
        .testTarget(
            name: "ShoutOutCoreTests",
            dependencies: ["ShoutOutCore"],
            path: "Tests/ShoutOutCoreTests"
        )
    ]
)
