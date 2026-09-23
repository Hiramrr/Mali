// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PlannerTest",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "PlannerTest", path: "Sources/PlannerTest")
    ]
)
