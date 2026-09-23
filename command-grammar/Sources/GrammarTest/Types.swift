// Tipos del parser. Swift normal, sin @Generable, sin ML.
import Foundation

enum FormatStyle: String, Equatable {
    case bold
    case italic
    case underline
}

enum ExportFormat: String, Equatable {
    case pdf
    case word
    case plainText
    case richText
}

enum ParsedCommand: Equatable {
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

struct CommandToken {
    let raw: String
    let normalized: String
    let range: Range<String.Index>
}

struct CommandTranscript {
    let raw: String
    let normalized: String
}
