// Fase 10C: solo NAVIGATION es inmediata. Reversible/content/external →
// confirm. B20 demostró que reversible ≠ seguro para autoejecución.
import Foundation

// MARK: - Política

enum ConfirmationPolicy: String, Equatable {
    case immediate
    case confirm
}

// Fase 10C: AUTO = navigation only. Reversible → CONFIRM (B20: la
// reversibilidad sola no justifica autoejecución). Riesgos intactos.
func policyFor(risk: CommandRisk) -> ConfirmationPolicy {
    switch risk {
    case .navigation: return .immediate
    case .reversible, .contentChanging, .externalSideEffect: return .confirm
    }
}

func policyForCommand(_ cmd: ParsedCommand) -> ConfirmationPolicy {
    policyFor(risk: riskOf(cmd))
}

// MARK: - Feedback inmediato

func immediateFeedback(for cmd: ParsedCommand, in editor: FakeEditorState) -> String {
    switch cmd {
    case .findText(let a): return "✓ Encontrado: \"\(a)\""
    case .selectText: return "✓ Seleccionado: \"\(editor.selectedText())\""
    case .undo: return "✓ Deshecho — ⌘Z adicional disponible si aplica"
    case .redo: return "✓ Rehecho"
    case .formatSelection(let s): return "✓ \(styleName(s).capitalized) aplicadas — ⌘Z para deshacer"
    default: return "✓ Listo"
    }
}

// MARK: - Registro de ejecución automática

struct AutoExecutedRecord: Equatable {
    var transcript: String
    var command: String
    var risk: CommandRisk
    var stateBefore: FakeEditorState
    var stateAfter: FakeEditorState
    var undoAvailableAfter: Bool
}

// MARK: - Sesión risk-based (reutiliza validator, previews, apply)

struct RiskBasedSession {
    var editor: FakeEditorState
    var state: CommandInteractionState = .idle
    var attempts: Int = 0
    var events: [InteractionEvent] = []
    var autoLog: [AutoExecutedRecord] = []

    mutating func log(_ kind: String) { events.append(InteractionEvent(kind: kind, at: Date())) }

    mutating func startListening() {
        state = .listening(attempt: attempts + 1)
        attempts += 1
        log("listening")
    }

    /// ParsedCommand → Validator → Risk Policy → immediate | confirm | repeat/close | invalid.
    /// Inválidos NUNCA llegan a confirmación (0 confirmations).
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
            if let reason = contextError(for: cmd, in: editor) {
                let proposal = makeProposal(transcript: transcript, command: cmd, editor: editor)
                state = .invalidContext(proposal, reason: reason); log("invalidContext")
                return
            }
            if policyForCommand(cmd) == .immediate {
                let before = editor
                applyConfirmed(cmd, to: &editor)
                let proposal = makeProposal(transcript: transcript, command: cmd, editor: before)
                autoLog.append(AutoExecutedRecord(
                    transcript: transcript, command: "\(cmd)", risk: riskOf(cmd),
                    stateBefore: before, stateAfter: editor,
                    undoAvailableAfter: editor.canUndo))
                state = .executed(proposal); log("auto_executed")
            } else {
                let proposal = makeProposal(transcript: transcript, command: cmd, editor: editor)
                state = .recognized(proposal); log("recognized")
            }
        }
    }

    /// Enter: solo confirma proposals pendientes (content/external).
    mutating func confirm() {
        guard case .recognized(let proposal) = state else { return }
        if policyForCommand(proposal.command) == .immediate { return } // inmediato no se confirma
        if let reason = contextError(for: proposal.command, in: editor) {
            state = .invalidContext(proposal, reason: reason); log("invalidContext"); return
        }
        applyConfirmed(proposal.command, to: &editor)
        state = .executed(proposal); log("executed")
    }

    mutating func cancel() {
        switch state {
        case .idle, .executed, .cancelled: break
        default: state = .cancelled; log("cancelled")
        }
    }

    mutating func repeatCommand() {
        state = .listening(attempt: attempts + 1)
        attempts += 1
        log("repeat")
    }

    /// Feedback tras ejecución inmediata (no requiere Enter).
    func feedback() -> String? {
        guard case .executed(let proposal) = state else { return nil }
        guard policyForCommand(proposal.command) == .immediate else { return nil }
        if let rec = autoLog.last, rec.transcript == proposal.transcript {
            return immediateFeedback(for: proposal.command, in: rec.stateAfter)
        }
        return nil
    }
}
