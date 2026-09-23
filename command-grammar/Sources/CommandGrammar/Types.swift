// Tipos del parser. Swift normal, sin @Generable, sin ML.
import Foundation

public enum FormatStyle: String, Equatable, Sendable {
    case bold
    case italic
    case underline
}

public enum ExportFormat: String, Equatable, Sendable {
    case pdf
    case word
    case plainText
    case richText
}

public enum ParsedCommand: Equatable, Sendable {
    case renameTitle(String)
    case deleteSelection
    case replaceSelection(String)
    case rewriteSelection(String)
    case formatSelection(FormatStyle)
    case undo
    case redo
    case selectText(String)
    case findText(String)
    case saveDocument
    case openDocument(String?)
    case exportDocument(ExportFormat)
    case unsupported(String)
    case multipleActions
    case unknown
}

public struct CommandToken: Sendable {
    public let raw: String
    public let normalized: String
    public let range: Range<String.Index>
}

public struct CommandTranscript: Sendable {
    public let raw: String
    public let normalized: String
}
