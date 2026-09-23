// Fase Confirmation UX — capa DESPUÉS de Speech→Grammar→ParsedCommand.
// CONGELADO: Grammar/Types/LM/contextualStrings/Speech sin cambios funcionales.
// Política Fase 9: ALL SUPPORTED COMMANDS REQUIRE CONFIRMATION (baseline segura).
// Solo Enter confirma; Esc/R nunca mutan. Sin Foundation Models, sin editor real.
import Foundation

// MARK: - Editor simulado (solo muta tras confirmación válida)

struct EditorSnapshot: Equatable {
    var title: String
    var text: String
    var selectedRange: Range<String.Index>?
    var appliedFormats: [AppliedFormat]
    var simulatedRewriteRequests: [String]
    var lastFind: String?
    var savedMarker: String?
    var lastExport: ExportFormat?
    var currentDocument: String?
}

struct AppliedFormat: Equatable {
    var range: Range<String.Index>
    var style: FormatStyle
}

struct FakeEditorState: Equatable {
    var title: String
    var text: String
    var selectedRange: Range<String.Index>?
    var currentDocument: String?
    var undoStack: [EditorSnapshot] = []
    var redoStack: [EditorSnapshot] = []
    var appliedFormats: [AppliedFormat] = []
    var simulatedRewriteRequests: [String] = []
    var lastFind: String? = nil
    var savedMarker: String? = nil
    var lastExport: ExportFormat? = nil

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    static func `default`() -> FakeEditorState {
        FakeEditorState(
            title: "Proyecto",
            text: "Metodología y resultados sobre TDAH e IHC.",
            selectedRange: nil,
            currentDocument: "borrador"
        )
    }

    /// Editor "generoso" para análisis de peor caso: con selección e historial.
    static func generous() -> FakeEditorState {
        var e = FakeEditorState.default()
        e.selectedRange = e.text.range(of: "resultados")
        e.undoStack = [e.snapshot()]
        e.redoStack = [e.snapshot()]
        return e
    }

    func snapshot() -> EditorSnapshot {
        EditorSnapshot(title: title, text: text, selectedRange: selectedRange,
                       appliedFormats: appliedFormats,
                       simulatedRewriteRequests: simulatedRewriteRequests,
                       lastFind: lastFind, savedMarker: savedMarker,
                       lastExport: lastExport, currentDocument: currentDocument)
    }

    mutating func restore(_ s: EditorSnapshot) {
        title = s.title; text = s.text; selectedRange = s.selectedRange
        appliedFormats = s.appliedFormats
        simulatedRewriteRequests = s.simulatedRewriteRequests
        lastFind = s.lastFind; savedMarker = s.savedMarker
        lastExport = s.lastExport; currentDocument = s.currentDocument
    }

    mutating func pushHistory() {
        undoStack.append(snapshot())
        redoStack.removeAll()
    }

    mutating func selectAll() { selectedRange = text.startIndex..<text.endIndex }

    /// Selecciona la primera ocurrencia; si no existe, deja nil.
    mutating func select(substring: String) {
        selectedRange = substring.isEmpty ? nil : text.range(of: substring)
    }

    func selectedText() -> String {
        guard let r = selectedRange else { return "" }
        return String(text[r])
    }
}

// MARK: - Propuesta, estados, riesgo (riesgo NO operativo en Fase 9)

struct CommandProposal: Equatable {
    let transcript: String
    let command: ParsedCommand
    let effectDescription: String
    let risk: CommandRisk
}

enum CommandInteractionState: Equatable {
    case idle
    case listening(attempt: Int)
    case recognized(CommandProposal)
    case unsupported(String)
    case notUnderstood
    case invalidContext(CommandProposal, reason: String)
    case executed(CommandProposal)
    case cancelled
}

enum CommandRisk: String, Equatable {
    case navigation
    case reversible
    case contentChanging
    case externalSideEffect
}

func riskOf(_ cmd: ParsedCommand) -> CommandRisk {
    switch cmd {
    case .selectText, .findText: return .navigation
    case .undo, .redo, .formatSelection: return .reversible
    case .renameTitle, .deleteSelection, .replaceSelection, .rewriteSelection: return .contentChanging
    case .saveDocument, .openDocument, .exportDocument: return .externalSideEffect
    case .unsupported, .unknown, .multipleActions: return .navigation
    }
}

// MARK: - Preview por acción (legible, con estado actual)

func styleName(_ s: FormatStyle) -> String {
    switch s { case .bold: return "negritas"; case .italic: return "cursiva"; case .underline: return "subrayado" }
}

func exportName(_ f: ExportFormat) -> String {
    switch f { case .pdf: return "PDF"; case .word: return "Word"; case .plainText: return "texto plano"; case .richText: return "texto enriquecido" }
}

func effectDescription(for cmd: ParsedCommand, in editor: FakeEditorState) -> String {
    switch cmd {
    case .renameTitle(let a): return "Cambiar título:\n\"\(editor.title)\"\n→\n\"\(a)\""
    case .deleteSelection: return "Eliminar selección:\n\"\(editor.selectedText())\""
    case .replaceSelection(let a): return "Reemplazar:\n\"\(editor.selectedText())\"\n→\n\"\(a)\""
    case .rewriteSelection(let a): return "Reescribir selección\nInstrucción:\n\"\(a)\""
    case .formatSelection(let s): return "Aplicar \(styleName(s)) a:\n\"\(editor.selectedText())\""
    case .undo: return "Deshacer último cambio"
    case .redo: return "Rehacer último cambio"
    case .selectText(let a): return "Seleccionar:\n\"\(a)\""
    case .findText(let a): return "Buscar:\n\"\(a)\""
    case .saveDocument: return "Guardar documento"
    case .openDocument(let a): return "Abrir:\n\"\(a ?? "Último documento")\""
    case .exportDocument(let f): return "Exportar como \(exportName(f))"
    case .unsupported: return "Ese comando no está disponible."
    case .unknown: return "No entendí el comando."
    case .multipleActions: return "Prueba una acción a la vez."
    }
}

func makeProposal(transcript: String, command: ParsedCommand, editor: FakeEditorState) -> CommandProposal {
    CommandProposal(transcript: transcript, command: command,
                    effectDescription: effectDescription(for: command, in: editor),
                    risk: riskOf(command))
}

// MARK: - Validación de contexto (antes de confirmación ejecutable)

enum ContextReason {
    static let noSelection = "No hay texto seleccionado."
    static let cannotUndo = "Nada que deshacer."
    static let cannotRedo = "Nada que rehacer."
}

func contextError(for cmd: ParsedCommand, in editor: FakeEditorState) -> String? {
    switch cmd {
    case .deleteSelection, .replaceSelection, .rewriteSelection, .formatSelection:
        return editor.selectedRange == nil ? ContextReason.noSelection : nil
    case .undo: return editor.canUndo ? nil : ContextReason.cannotUndo
    case .redo: return editor.canRedo ? nil : ContextReason.cannotRedo
    default: return nil
    }
}

// MARK: - Aplicación de efectos (SOLO vía confirm)

/// Aplica el comando al editor. Llamar únicamente desde confirm() con contexto válido.
func applyConfirmed(_ cmd: ParsedCommand, to editor: inout FakeEditorState) {
    switch cmd {
    case .renameTitle(let a):
        editor.pushHistory(); editor.title = a
    case .deleteSelection:
        guard let r = editor.selectedRange else { return }
        editor.pushHistory(); editor.text.removeSubrange(r); editor.selectedRange = nil
    case .replaceSelection(let a):
        guard let r = editor.selectedRange else { return }
        editor.pushHistory(); editor.text.replaceSubrange(r, with: a); editor.selectedRange = nil
    case .rewriteSelection(let a):
        // Simulado: sin Foundation Models, sin transformar texto.
        editor.pushHistory(); editor.simulatedRewriteRequests.append(a)
    case .formatSelection(let s):
        guard let r = editor.selectedRange else { return }
        editor.pushHistory(); editor.appliedFormats.append(AppliedFormat(range: r, style: s))
    case .undo:
        guard editor.canUndo else { return }
        editor.redoStack.append(editor.snapshot())
        editor.restore(editor.undoStack.removeLast())
    case .redo:
        guard editor.canRedo else { return }
        editor.undoStack.append(editor.snapshot())
        editor.restore(editor.redoStack.removeLast())
    case .selectText(let a):
        editor.select(substring: a)
    case .findText(let a):
        editor.lastFind = a
    case .saveDocument:
        editor.savedMarker = editor.currentDocument ?? editor.title
    case .openDocument(let a):
        editor.currentDocument = a ?? "Último documento"
    case .exportDocument(let f):
        editor.lastExport = f
    case .unsupported, .unknown, .multipleActions:
        break
    }
}

// MARK: - Sesión de interacción (máquina de estados + métricas)

struct InteractionEvent {
    var kind: String
    var at: Date
}

struct ConfirmationSession {
    var editor: FakeEditorState
    var state: CommandInteractionState = .idle
    var attempts: Int = 0
    var events: [InteractionEvent] = []
    /// Diagnóstico opcional (NO usado para decidir): confidence/alt-count del STT.
    var lastDiagnostics: String = ""

    mutating func log(_ kind: String) { events.append(InteractionEvent(kind: kind, at: Date())) }

    mutating func startListening() {
        state = .listening(attempt: attempts + 1)
        attempts += 1
        log("listening")
    }

    /// Recibe transcript (del STT o simulado), parsea con gramática congelada.
    mutating func receiveTranscript(_ transcript: String) {
        let cmd = parseCommand(raw: transcript)
        log("transcript")
        switch cmd {
        case .unsupported:
            state = .unsupported(transcript); log("unsupported")
        case .unknown:
            state = .notUnderstood; log("notUnderstood")
        case .multipleActions:
            state = .unsupported("multipleActions"); log("multi")
        default:
            let proposal = makeProposal(transcript: transcript, command: cmd, editor: editor)
            if let reason = contextError(for: cmd, in: editor) {
                state = .invalidContext(proposal, reason: reason); log("invalidContext")
            } else {
                state = .recognized(proposal); log("recognized")
            }
        }
    }

    /// Enter: único camino con efecto. Revalida contexto.
    mutating func confirm() {
        guard case .recognized(let proposal) = state else { return }
        if let reason = contextError(for: proposal.command, in: editor) {
            state = .invalidContext(proposal, reason: reason); log("invalidContext"); return
        }
        applyConfirmed(proposal.command, to: &editor)
        state = .executed(proposal); log("executed")
    }

    /// Esc: sin cambios.
    mutating func cancel() {
        switch state {
        case .idle, .executed, .cancelled: break
        default: state = .cancelled; log("cancelled")
        }
    }

    /// R: descarta transcript, nueva captura, sin combinar ni majority vote.
    mutating func repeatCommand() {
        switch state {
        case .idle, .executed, .cancelled: break
        default: break
        }
        state = .listening(attempt: attempts + 1)
        attempts += 1
        lastDiagnostics = ""
        log("repeat")
    }
}
