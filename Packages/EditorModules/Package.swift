// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EditorModules",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "EditorUI", targets: ["EditorUI"]),
        .library(name: "DocumentKit", targets: ["DocumentKit"]),
        .library(name: "ModuleKit", targets: ["ModuleKit"]),
        .library(name: "VoiceModule", targets: ["VoiceModule"]),
        .library(name: "GestureModule", targets: ["GestureModule"])
    ],
    targets: [
        .target(name: "EditorCore"),
        .target(name: "ModuleKit", dependencies: ["EditorCore"]),
        .target(name: "VoiceModule", dependencies: ["EditorCore", "ModuleKit"]),
        .target(name: "GestureModule", dependencies: ["EditorCore", "ModuleKit"]),
        .target(name: "DocumentKit", dependencies: ["EditorCore"]),
        .target(name: "DesignSystem", dependencies: ["EditorCore"]),
        .target(name: "EditorEngine", dependencies: ["EditorCore", "DesignSystem"]),
        .target(name: "ExportFeature", dependencies: ["EditorCore", "DesignSystem"]),
        .target(name: "EditorUI", dependencies: ["EditorCore", "EditorEngine", "DesignSystem", "DocumentKit", "ExportFeature", "ModuleKit"]),
        .testTarget(name: "EditorModulesTests", dependencies: ["EditorCore", "DocumentKit", "EditorEngine", "DesignSystem", "ExportFeature", "ModuleKit", "VoiceModule", "GestureModule"])
    ]
)
