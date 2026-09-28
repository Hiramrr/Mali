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
    dependencies: [
        // Gramática de comandos probada como fuente única (librería del
        // paquete command-grammar; sin duplicar lógica congelada).
        .package(path: "../../command-grammar"),
    ],
    targets: [
        .target(name: "EditorCore"),
        .target(name: "ModuleKit", dependencies: ["EditorCore"]),
        .target(name: "VoiceModule", dependencies: ["EditorCore", "ModuleKit", .product(name: "CommandGrammar", package: "command-grammar")]),
        .target(name: "GestureModule", dependencies: ["EditorCore", "ModuleKit"]),
        .target(name: "DocumentKit", dependencies: ["EditorCore"]),
        .target(name: "DesignSystem", dependencies: ["EditorCore"]),
        // Pieza extraíble: diagramas ```diagram en lectura, PDF y Word (Docs/Diagramas.md).
        .target(name: "DiagramModule"),
        .target(name: "EditorEngine", dependencies: ["EditorCore", "DesignSystem", "DiagramModule"]),
        .target(name: "ExportFeature", dependencies: ["EditorCore", "DesignSystem", "EditorEngine"]),
        .target(name: "EditorUI", dependencies: ["EditorCore", "EditorEngine", "DesignSystem", "DocumentKit", "ExportFeature", "ModuleKit"]),
        .testTarget(name: "EditorModulesTests", dependencies: ["EditorCore", "DocumentKit", "EditorEngine", "EditorUI", "DesignSystem", "ExportFeature", "ModuleKit", "VoiceModule", "GestureModule", "DiagramModule"])
    ]
)
