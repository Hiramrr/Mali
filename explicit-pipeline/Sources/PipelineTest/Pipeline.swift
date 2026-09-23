// Núcleo: modo explícito, contexto, 12 stub tools, validador determinista, recorder.
import Foundation
import FoundationModels

// La app conoce el modo ANTES de procesar la emisión. No se infiere con modelo.
enum VoiceInteractionMode: String, Sendable {
    case dictation
    case command
}

struct EditorContext: Sendable {
    let currentTitle: String
    let selectedText: String?
    let canUndo: Bool
    let canRedo: Bool
    let documentIsOpen: Bool
}

enum ValidationResult: Sendable {
    case valid
    case rejected(String)
    var label: String {
        switch self {
        case .valid: "VALID"
        case .rejected(let r): r
        }
    }
    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}

struct RecordedToolCall: Sendable {
    let tool: String
    let arguments: String
    let validation: ValidationResult
}

actor ToolRecorder {
    private(set) var calls: [RecordedToolCall] = []
    func record(_ c: RecordedToolCall) { calls.append(c) }
}

// MARK: - Argumentos

@Generable
struct RenameTitleArgs {
    @Guide(description: "The new title for the document.")
    var newTitle: String
}

@Generable
struct ReplaceArgs {
    @Guide(description: "The new text replacing the current selection.")
    var newText: String
}

@Generable
struct RewriteArgs {
    @Guide(description: "How to rewrite the current selection.")
    var instruction: String
}

@Generable
enum FormatStyle {
    case bold
    case italic
    case underline
}

@Generable
struct FormatArgs {
    @Guide(description: "Style to apply: bold, italic, or underline.")
    var style: FormatStyle
}

@Generable
struct SelectArgs {
    @Guide(description: "Which text to select, described as the user said it.")
    var target: String
}

@Generable
struct FindArgs {
    @Guide(description: "The text to find in the document.")
    var query: String
}

@Generable
struct NoArgs {}

// MARK: - Tools (stubs)

struct RenameTitleTool: Tool {
    var name: String { "renameTitle" }
    var description: String { "Change the document title to a new title." }
    let recorder: ToolRecorder
    func call(arguments: RenameTitleArgs) async throws -> String {
        let t = arguments.newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let v: ValidationResult = t.isEmpty ? .rejected("REJECTED_EMPTY_TITLE") : .valid
        await recorder.record(RecordedToolCall(tool: name, arguments: "newTitle=\(t)", validation: v))
        switch v { case .valid: return "SIMULATED_OK"; case .rejected(let r): return r }
    }
}

struct DeleteSelectionTool: Tool {
    var name: String { "deleteSelection" }
    var description: String { "Delete the currently selected text. Requires a text selection." }
    let context: EditorContext
    let recorder: ToolRecorder
    func call(arguments: NoArgs) async throws -> String {
        let v: ValidationResult = context.selectedText != nil ? .valid : .rejected("REJECTED_MISSING_SELECTION")
        await recorder.record(RecordedToolCall(tool: name, arguments: "{}", validation: v))
        switch v { case .valid: return "SIMULATED_OK"; case .rejected(let r): return r }
    }
}

struct ReplaceSelectionTool: Tool {
    var name: String { "replaceSelection" }
    var description: String { "Replace the current selection with new text. Requires a text selection." }
    let context: EditorContext
    let recorder: ToolRecorder
    func call(arguments: ReplaceArgs) async throws -> String {
        let t = arguments.newText.trimmingCharacters(in: .whitespacesAndNewlines)
        let v: ValidationResult
        if context.selectedText == nil { v = .rejected("REJECTED_MISSING_SELECTION") }
        else if t.isEmpty { v = .rejected("REJECTED_EMPTY_TEXT") }
        else { v = .valid }
        await recorder.record(RecordedToolCall(tool: name, arguments: "newText=\(t)", validation: v))
        switch v { case .valid: return "SIMULATED_OK"; case .rejected(let r): return r }
    }
}

struct RewriteSelectionTool: Tool {
    var name: String { "rewriteSelection" }
    var description: String { "Rewrite the current selection following an instruction. Requires a text selection." }
    let context: EditorContext
    let recorder: ToolRecorder
    func call(arguments: RewriteArgs) async throws -> String {
        let v: ValidationResult = context.selectedText != nil ? .valid : .rejected("REJECTED_MISSING_SELECTION")
        await recorder.record(RecordedToolCall(tool: name, arguments: "instruction=\(arguments.instruction)", validation: v))
        switch v { case .valid: return "SIMULATED_OK"; case .rejected(let r): return r }
    }
}

struct FormatSelectionTool: Tool {
    var name: String { "formatSelection" }
    var description: String { "Apply bold, italic, or underline to the current selection. Requires a text selection." }
    let context: EditorContext
    let recorder: ToolRecorder
    func call(arguments: FormatArgs) async throws -> String {
        let v: ValidationResult = context.selectedText != nil ? .valid : .rejected("REJECTED_MISSING_SELECTION")
        await recorder.record(RecordedToolCall(tool: name, arguments: "style=\(arguments.style)", validation: v))
        switch v { case .valid: return "SIMULATED_OK"; case .rejected(let r): return r }
    }
}

struct UndoTool: Tool {
    var name: String { "undo" }
    var description: String { "Undo the last change. Only when an undo step exists." }
    let context: EditorContext
    let recorder: ToolRecorder
    func call(arguments: NoArgs) async throws -> String {
        let v: ValidationResult = context.canUndo ? .valid : .rejected("REJECTED_CANNOT_UNDO")
        await recorder.record(RecordedToolCall(tool: name, arguments: "{}", validation: v))
        switch v { case .valid: return "SIMULATED_OK"; case .rejected(let r): return r }
    }
}

struct RedoTool: Tool {
    var name: String { "redo" }
    var description: String { "Redo the previously undone change. Only when a redo step exists." }
    let context: EditorContext
    let recorder: ToolRecorder
    func call(arguments: NoArgs) async throws -> String {
        let v: ValidationResult = context.canRedo ? .valid : .rejected("REJECTED_CANNOT_REDO")
        await recorder.record(RecordedToolCall(tool: name, arguments: "{}", validation: v))
        switch v { case .valid: return "SIMULATED_OK"; case .rejected(let r): return r }
    }
}

struct SelectTextTool: Tool {
    var name: String { "selectText" }
    var description: String { "Select a part of the document described by the user." }
    let recorder: ToolRecorder
    func call(arguments: SelectArgs) async throws -> String {
        let t = arguments.target.trimmingCharacters(in: .whitespacesAndNewlines)
        let v: ValidationResult = t.isEmpty ? .rejected("REJECTED_EMPTY_TARGET") : .valid
        await recorder.record(RecordedToolCall(tool: name, arguments: "target=\(t)", validation: v))
        switch v { case .valid: return "SIMULATED_OK"; case .rejected(let r): return r }
    }
}

struct FindTextTool: Tool {
    var name: String { "findText" }
    var description: String { "Find text in the document matching a query." }
    let recorder: ToolRecorder
    func call(arguments: FindArgs) async throws -> String {
        let q = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let v: ValidationResult = q.isEmpty ? .rejected("REJECTED_EMPTY_QUERY") : .valid
        await recorder.record(RecordedToolCall(tool: name, arguments: "query=\(q)", validation: v))
        switch v { case .valid: return "SIMULATED_OK"; case .rejected(let r): return r }
    }
}

struct SaveDocumentTool: Tool {
    var name: String { "saveDocument" }
    var description: String { "Save the current document. Requires an open document." }
    let context: EditorContext
    let recorder: ToolRecorder
    func call(arguments: NoArgs) async throws -> String {
        let v: ValidationResult = context.documentIsOpen ? .valid : .rejected("REJECTED_NO_DOCUMENT")
        await recorder.record(RecordedToolCall(tool: name, arguments: "{}", validation: v))
        switch v { case .valid: return "SIMULATED_OK"; case .rejected(let r): return r }
    }
}

struct OpenDocumentTool: Tool {
    var name: String { "openDocument" }
    var description: String { "Open a document requested by the user." }
    let recorder: ToolRecorder
    func call(arguments: NoArgs) async throws -> String {
        await recorder.record(RecordedToolCall(tool: name, arguments: "{}", validation: .valid))
        return "SIMULATED_OK"
    }
}

struct ExportDocumentTool: Tool {
    var name: String { "exportDocument" }
    var description: String { "Export the current document. Requires an open document." }
    let context: EditorContext
    let recorder: ToolRecorder
    func call(arguments: NoArgs) async throws -> String {
        let v: ValidationResult = context.documentIsOpen ? .valid : .rejected("REJECTED_NO_DOCUMENT")
        await recorder.record(RecordedToolCall(tool: name, arguments: "{}", validation: v))
        switch v { case .valid: return "SIMULATED_OK"; case .rejected(let r): return r }
    }
}

func makeTools(context: EditorContext, recorder: ToolRecorder) -> [any Tool] {
    [
        RenameTitleTool(recorder: recorder),
        DeleteSelectionTool(context: context, recorder: recorder),
        ReplaceSelectionTool(context: context, recorder: recorder),
        RewriteSelectionTool(context: context, recorder: recorder),
        FormatSelectionTool(context: context, recorder: recorder),
        UndoTool(context: context, recorder: recorder),
        RedoTool(context: context, recorder: recorder),
        SelectTextTool(recorder: recorder),
        FindTextTool(recorder: recorder),
        SaveDocumentTool(context: context, recorder: recorder),
        OpenDocumentTool(recorder: recorder),
        ExportDocumentTool(context: context, recorder: recorder),
    ]
}
