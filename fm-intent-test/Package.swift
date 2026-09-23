// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FMIntentTest",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "FMIntentTest",
            path: "Sources/FMIntentTest"
        )
    ]
)
