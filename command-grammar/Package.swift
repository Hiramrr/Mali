// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GrammarTest",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "GrammarTest", path: "Sources/GrammarTest"),
    ]
)
