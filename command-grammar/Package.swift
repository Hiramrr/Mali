// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GrammarTest",
    platforms: [.macOS(.v26)],
    products: [
        // Librería importable por la app: gramática probada como fuente única.
        // Solo cambio de acceso (public); cero cambios funcionales.
        .library(name: "CommandGrammar", targets: ["CommandGrammar"]),
    ],
    targets: [
        .target(name: "CommandGrammar", path: "Sources/CommandGrammar"),
        .executableTarget(name: "GrammarTest", dependencies: ["CommandGrammar"], path: "Sources/GrammarTest"),
    ]
)
