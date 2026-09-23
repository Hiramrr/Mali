import Foundation

/// Offsets use UTF-16, the same units as TextKit and NSString.
public struct TextRange: Equatable, Sendable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public func validated(in text: String) -> NSRange? {
        guard location >= 0, length >= 0, location <= text.utf16.count,
              length <= text.utf16.count - location else { return nil }
        let range = NSRange(location: location, length: length)
        guard let indices = Range(range, in: text),
              (indices.lowerBound == text.endIndex || text.indices.contains(indices.lowerBound)),
              (indices.upperBound == text.endIndex || text.indices.contains(indices.upperBound)) else { return nil }
        return range
    }
}

public enum EditorCommand: Equatable, Sendable {
    case insertText(String)
    case replaceSelection(String)
    case selectRange(TextRange)
    case selectAll
    case deleteBackward
    case deleteForward
    case undo
    case redo
    case toggleBold
    case toggleItalic
    case toggleCode
    case heading(Int)
    case bulletList
    case quote
    case insertLink
    /// Cambiar el título del documento. La sesión NO lo aplica directamente
    /// (no tiene acceso al NSDocument): lo intercepta `EditorScreen`, que sí
    /// conoce la URL actual y renombra el archivo. Si llega a `send`, se
    /// ignora para no escribir el título dentro del texto.
    case renameTitle(String)
    // Previsualización atómica para módulos (gestos). Mientras dura, el texto
    // mostrado no toca el binding, el guardado ni el historial: confirmar
    // registra un único undo (o ninguno si no hubo cambio) y cancelar
    // restaura el original. Perder el seguimiento cancela, nunca confirma.
    case beginPreview(TextRange)
    case showPreview(String)
    case commitPreview
    case cancelPreview
}

public struct DocumentHeading: Identifiable, Equatable, Sendable {
    public var id: Int { offset }
    public let title: String
    public let offset: Int
    public let level: Int
}

public enum DocumentOutline {
    public static func headings(in text: String) -> [DocumentHeading] {
        MarkdownDocument(text).headings
    }
}
