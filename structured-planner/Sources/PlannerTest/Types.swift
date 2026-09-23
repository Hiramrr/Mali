// Tipos @Generable del planner. Sin tools registradas en la sesión.
import Foundation
import FoundationModels

@Generable
enum FormatStyle: String, Sendable, Codable {
    case bold
    case italic
    case underline
}

@Generable
enum ExportFormat: String, Sendable, Codable {
    case pdf
    case plainText
    case richText
    case word
}

@Generable
enum EditorAction: Sendable {
    case renameTitle(newTitle: String)
    case deleteSelection
    case replaceSelection(newText: String)
    case rewriteSelection(instruction: String)
    case formatSelection(style: FormatStyle)
    case undo
    case redo
    case selectText(target: String)
    case findText(query: String)
    case saveDocument
    case openDocument(reference: String)
    case exportDocument(format: ExportFormat)
}

@Generable
struct ActionSequence: Sendable {
    @Guide(description: "Editor actions in the order requested.", .count(1...4))
    var actions: [EditorAction]
}

@Generable
enum CommandPlan: Sendable {
    case actions(ActionSequence)
    case unsupported(request: String)
    case noAction
}

extension EditorAction {
    var toolName: String {
        switch self {
        case .renameTitle: "renameTitle"
        case .deleteSelection: "deleteSelection"
        case .replaceSelection: "replaceSelection"
        case .rewriteSelection: "rewriteSelection"
        case .formatSelection: "formatSelection"
        case .undo: "undo"
        case .redo: "redo"
        case .selectText: "selectText"
        case .findText: "findText"
        case .saveDocument: "saveDocument"
        case .openDocument: "openDocument"
        case .exportDocument: "exportDocument"
        }
    }
}
