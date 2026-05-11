// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "OpenFlowEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenFlowEngine", targets: ["OpenFlowEngine"]),
        .executable(name: "openflow-prompt-test", targets: ["OpenFlowPromptTest"])
    ],
    dependencies: [
        .package(path: "../tiny-audio-swift/swift"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.30.3"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.1.6")
    ],
    targets: [
        .target(
            name: "OpenFlowEngine",
            dependencies: [
                .product(name: "TinyAudio", package: "swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ]
        ),
        .executableTarget(
            name: "OpenFlowPromptTest",
            dependencies: ["OpenFlowEngine"]
        ),
        .testTarget(
            name: "OpenFlowEngineTests",
            dependencies: ["OpenFlowEngine"]
        )
    ]
)
