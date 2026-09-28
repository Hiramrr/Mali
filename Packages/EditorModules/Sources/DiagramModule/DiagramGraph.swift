import Foundation

/// Grafo de un bloque ```diagram. Puro Foundation: el parser y el layout se prueban sin AppKit.
public struct DiagramGraph: Equatable, Sendable {
    public enum Direction: Sendable, Equatable { case topBottom, leftRight }
    public var direction: Direction
    public var nodes: [DiagramNode]
    public var edges: [DiagramEdge]

    public init(direction: Direction = .topBottom, nodes: [DiagramNode] = [], edges: [DiagramEdge] = []) {
        self.direction = direction
        self.nodes = nodes
        self.edges = edges
    }

    /// Descripción textual para VoiceOver: una conexión por frase.
    public var accessibilityDescription: String {
        let names = Dictionary(nodes.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
        let connections = edges.map { edge in
            let from = names[edge.from] ?? edge.from
            let to = names[edge.to] ?? edge.to
            return edge.label.map { "\(from) flecha \($0) flecha \(to)" } ?? "\(from) flecha \(to)"
        }
        let lonely = nodes.filter { node in !edges.contains { $0.from == node.id || $0.to == node.id } }.map(\.text)
        return (["Diagrama"] + connections + lonely).joined(separator: ". ")
    }
}

public struct DiagramNode: Equatable, Sendable {
    public enum Shape: Sendable, Equatable { case rounded, decision, terminal, stadium }
    public var id: String
    public var text: String
    public var shape: Shape

    public init(id: String, text: String, shape: Shape = .rounded) {
        self.id = id
        self.text = text
        self.shape = shape
    }
}

public struct DiagramEdge: Equatable, Sendable {
    public var from: String
    public var to: String
    public var label: String?

    public init(from: String, to: String, label: String? = nil) {
        self.from = from
        self.to = to
        self.label = label
    }
}

public struct DiagramParseError: Error, Equatable, Sendable {
    public let line: Int
    public let message: String
}

/// Parser del DSL de `Docs/Diagramas.md`. Cada línea es una directiva, un nodo o una cadena de aristas:
/// `a[Texto] -> b{¿Sí?} -- Sí --> c((Fin))`. También admite `-->`, `-- texto ->` y `-->|texto|`.
public enum DiagramParser {
    public static let maxLines = 200
    public static let maxNodes = 60
    public static let maxEdges = 120

    public static func parse(_ source: String) throws(DiagramParseError) -> DiagramGraph {
        var graph = DiagramGraph()
        var index: [String: Int] = [:]
        var declared: Set<String> = []
        let lines = source.components(separatedBy: .newlines)
        guard lines.count <= maxLines else { throw DiagramParseError(line: maxLines + 1, message: "Demasiadas líneas") }

        func register(_ endpoint: Endpoint) {
            if let position = index[endpoint.id] {
                // La primera forma explícita gana; una referencia suelta no cambia nada.
                if let shape = endpoint.shape, !declared.contains(endpoint.id) {
                    graph.nodes[position].shape = shape.shape
                    graph.nodes[position].text = shape.text
                    declared.insert(endpoint.id)
                }
                return
            }
            index[endpoint.id] = graph.nodes.count
            graph.nodes.append(DiagramNode(id: endpoint.id, text: endpoint.shape?.text ?? endpoint.id, shape: endpoint.shape?.shape ?? .rounded))
            if endpoint.shape != nil { declared.insert(endpoint.id) }
        }

        for (number, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let words = line.split(separator: " ", omittingEmptySubsequences: true)
            if words.first?.lowercased() == "direction" {
                guard words.count == 2 else { throw DiagramParseError(line: number + 1, message: "Dirección inválida") }
                switch words[1].uppercased() {
                case "TB", "TD": graph.direction = .topBottom
                case "LR": graph.direction = .leftRight
                default: throw DiagramParseError(line: number + 1, message: "Dirección inválida")
                }
                continue
            }
            var scanner = Scanner(Array(line), line: number + 1)
            var previous = try scanner.endpoint()
            register(previous)
            while try !scanner.atEnd() {
                let label = try scanner.connector()
                let next = try scanner.endpoint()
                register(next)
                graph.edges.append(DiagramEdge(from: previous.id, to: next.id, label: label))
                previous = next
            }
        }
        guard !graph.nodes.isEmpty else { throw DiagramParseError(line: 1, message: "Diagrama vacío") }
        guard graph.nodes.count <= maxNodes, graph.edges.count <= maxEdges else {
            throw DiagramParseError(line: lines.count, message: "Diagrama demasiado grande")
        }
        return graph
    }

    struct Endpoint {
        let id: String
        let shape: (shape: DiagramNode.Shape, text: String)?
    }

    struct Scanner {
        let characters: [Character]
        let line: Int
        var position = 0

        init(_ characters: [Character], line: Int) {
            self.characters = characters
            self.line = line
        }

        func fail(_ message: String) -> DiagramParseError { DiagramParseError(line: line, message: message) }

        func peek(_ offset: Int = 0) -> Character? {
            characters.indices.contains(position + offset) ? characters[position + offset] : nil
        }

        func starts(with text: String) -> Bool {
            var offset = 0
            for character in text {
                guard peek(offset) == character else { return false }
                offset += 1
            }
            return true
        }

        mutating func skipSpaces() {
            while let character = peek(), character == " " || character == "\t" { position += 1 }
        }

        mutating func atEnd() throws(DiagramParseError) -> Bool {
            skipSpaces()
            return position >= characters.count
        }

        mutating func endpoint() throws(DiagramParseError) -> Endpoint {
            skipSpaces()
            var id = ""
            while let character = peek(), character.isASCII,
                  character.isLetter || character.isNumber || character == "_" || character == "." || character == "-" {
                // `-` es parte del id salvo que empiece una flecha (`->`, `--`).
                if character == "-", let next = peek(1), next == "-" || next == ">" { break }
                id.append(character)
                position += 1
            }
            guard !id.isEmpty else { throw fail("Falta el id del nodo") }
            let shape: (DiagramNode.Shape, String)?
            if starts(with: "[(") {
                shape = (.stadium, try delimited(open: 2, close: ")]"))
            } else if starts(with: "((") {
                shape = (.terminal, try delimited(open: 2, close: "))"))
            } else if starts(with: "[") {
                shape = (.rounded, try delimited(open: 1, close: "]"))
            } else if starts(with: "{") {
                shape = (.decision, try delimited(open: 1, close: "}"))
            } else if starts(with: "(") {
                shape = (.stadium, try delimited(open: 1, close: ")"))
            } else {
                shape = nil
            }
            return Endpoint(id: id, shape: shape)
        }

        /// Texto hasta el cierre, con escapes `\]`, `\}`, `\)`…
        mutating func delimited(open: Int, close: String) throws(DiagramParseError) -> String {
            position += open
            var text = ""
            while position < characters.count {
                if characters[position] == "\\", let next = peek(1) {
                    text.append(next)
                    position += 2
                    continue
                }
                if starts(with: close) {
                    position += close.count
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { throw fail("Texto de nodo vacío") }
                    return trimmed
                }
                text.append(characters[position])
                position += 1
            }
            throw fail("Falta cerrar \(close)")
        }

        /// Flecha con etiqueta opcional; devuelve la etiqueta.
        mutating func connector() throws(DiagramParseError) -> String? {
            skipSpaces()
            if starts(with: "-->") || starts(with: "->") {
                position += starts(with: "-->") ? 3 : 2
                skipSpaces()
                guard peek() == "|" else { return nil }
                position += 1
                var label = ""
                while let character = peek(), character != "|" {
                    label.append(character)
                    position += 1
                }
                guard peek() == "|" else { throw fail("Falta cerrar la etiqueta |") }
                position += 1
                return clean(label)
            }
            guard starts(with: "--") else { throw fail("Se esperaba una flecha ->") }
            position += 2
            var label = ""
            while position < characters.count, !starts(with: "->") {
                label.append(characters[position])
                position += 1
            }
            guard starts(with: "->") else { throw fail("Falta la punta de la flecha ->") }
            position += 2
            while label.hasSuffix("-") { label.removeLast() }
            return clean(label)
        }

        func clean(_ label: String) -> String? {
            let trimmed = label.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
