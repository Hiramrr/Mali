// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FMToolTest",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "FMToolTest",
            path: "Sources/FMToolTest"
        )
    ]
)
