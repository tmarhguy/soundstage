// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SoundStage",
    platforms: [.macOS("14.4")],
    products: [
        .executable(name: "SoundStage", targets: ["SoundStage"])
    ],
    targets: [
        .target(name: "SoundStageCore", path: "Sources/SoundStageCore"),
        .executableTarget(
            name: "SoundStage",
            dependencies: ["SoundStageCore"],
            path: "Sources/SoundStage"
        ),
        .testTarget(
            name: "SoundStageTests",
            dependencies: ["SoundStageCore"],
            path: "Tests/SoundStageTests"
        )
    ]
)
