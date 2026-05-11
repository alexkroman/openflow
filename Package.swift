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
        .package(path: "../tiny-audio-swift/swift")
    ],
    targets: [
        .target(
            name: "OpenFlowEngine",
            dependencies: [
                .product(name: "TinyAudio", package: "swift")
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
