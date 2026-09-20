// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EditorModules",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "EditorUI", targets: ["EditorUI"]),
        .library(name: "DocumentKit", targets: ["DocumentKit"])
    ],
    targets: [
        .target(name: "EditorCore"),
        .target(name: "DocumentKit", dependencies: ["EditorCore"]),
        .target(name: "DesignSystem", dependencies: ["EditorCore"]),
        .target(name: "EditorEngine", dependencies: ["EditorCore", "DesignSystem"]),
        .target(name: "ExportFeature", dependencies: ["EditorCore", "DesignSystem"]),
        .target(name: "EditorUI", dependencies: ["EditorCore", "EditorEngine", "DesignSystem", "ExportFeature"]),
        .testTarget(name: "EditorModulesTests", dependencies: ["EditorCore", "DocumentKit", "EditorEngine", "DesignSystem"])
    ]
)
