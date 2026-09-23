import CommandGrammar
// Fixtures independientes por trial (Fase 10-balanced).
// Política, validator, riesgo y mapping SIN cambios.
// Cada trial parte de fixture(for:) nuevo; jamás se reutiliza estado.
import Foundation

enum FixtureKind: String {
    case navigation
    case format
    case undo
    case redo
    case delete
    case replace
    case rewrite
    case rename
    case external
}

func richDocumentText() -> String {
    "La interacción humano computadora estudia TDAH y accesibilidad cognitiva. " +
    "Metodología del Capítulo 3 con María José e IHC. Resultados 2026 y SwiftUI."
}

/// Fixture determinista en función del índice (variedad sin perder validez).
func fixture(for kind: FixtureKind, index: Int) -> FakeEditorState {
    var e = FakeEditorState(
        title: "Informe \(index)",
        text: richDocumentText(),
        selectedRange: nil,
        currentDocument: "acta-\(index)"
    )
    switch kind {
    case .navigation:
        break // sin precondiciones
    case .format, .delete, .replace, .rewrite:
        // Selección no vacía; varía el fragmento por índice
        let frags = ["TDAH", "Metodología", "accesibilidad cognitiva", "Capítulo 3", "María José", "IHC"]
        e.select(substring: frags[index % frags.count])
    case .undo:
        e.pushHistory() // canUndo real con snapshot previo
        e.title = "\(e.title) v2"
    case .redo:
        let s0 = e.snapshot() // base "Informe i"
        e.title = "\(e.title) v2"
        let s2 = e.snapshot() // destino visible del redo
        e.title = s0.title
        e.undoStack = [s0]
        e.redoStack = [s2]
    case .rename:
        break // título válido existente
    case .external:
        break // documento abierto
    }
    return e
}

/// Precondiciones por grupo de riesgo (lo que el validator exigirá).
func fixturePreconditions(for kind: FixtureKind, expected: String, editor: FakeEditorState) -> (ok: Bool, reason: String) {
    switch expected {
    case "deleteSelection", "replaceSelection", "rewriteSelection", "formatSelection":
        if kind == .format || kind == .delete || kind == .replace || kind == .rewrite {
            guard editor.selectedRange != nil, !editor.selectedText().isEmpty else {
                return (false, "INVALID_TEST_FIXTURE: selección vacía")
            }
        }
    case "undo":
        guard editor.canUndo else { return (false, "INVALID_TEST_FIXTURE: canUndo false") }
    case "redo":
        guard editor.canRedo else { return (false, "INVALID_TEST_FIXTURE: canRedo false") }
    default:
        break
    }
    return (true, "FIXTURE READY")
}
