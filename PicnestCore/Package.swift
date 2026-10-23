// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PicnestCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PicnestCore", targets: ["PicnestCore"]),
        .executable(name: "ModelBench", targets: ["ModelBench"]),
    ],
    targets: [
        .target(
            name: "PicnestCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "ModelBench",
            dependencies: ["PicnestCore"]
        ),
        .testTarget(
            name: "ModelBenchTests",
            dependencies: ["ModelBench", "PicnestCore"]
        ),
        .testTarget(
            name: "PicnestCoreTests",
            dependencies: ["PicnestCore"],
            exclude: ["Fixtures/SOURCES.md"],
            resources: [.process("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
