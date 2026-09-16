// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ShoutOut",
    platforms: [
        .macOS("15.0")
    ],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", revision: "3e978558404df4ad1bbb0a5634a03df2b0f9dfa5"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.31.3"),
        .package(
            url: "https://github.com/huggingface/swift-transformers.git",
            .upToNextMinor(from: "1.1.6")
        ),
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
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "Sources",
            exclude: ["Core", "Resources"],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
            ]
        ),
        .executableTarget(
            name: "LanguagePassSmoke",
            dependencies: [
                "ShoutOutCore",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "Tools/LanguagePassSmoke"
        ),
        .testTarget(
            name: "ShoutOutCoreTests",
            dependencies: ["ShoutOutCore"],
            path: "Tests/ShoutOutCoreTests"
        )
    ]
)
