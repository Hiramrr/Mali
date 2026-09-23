// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "IntentGateV2",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "TrainGate", path: "Sources/TrainGate"),
        .executableTarget(name: "EvalGate", path: "Sources/EvalGate"),
    ]
)
