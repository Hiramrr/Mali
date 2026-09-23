// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PipelineTest",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "PipelineTest", path: "Sources/PipelineTest")
    ]
)
