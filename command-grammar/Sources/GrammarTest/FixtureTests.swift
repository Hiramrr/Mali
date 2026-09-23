import CommandGrammar
// Tests de fixtures (Fase 10-balanced). No tocan política ni gramática.
import Foundation

func runFixtureTests() -> (passed: Int, failed: [UXTestFailure], total: Int) {
    var fails: [UXTestFailure] = []
    var count = 0
    func t(_ name: String, _ body: () -> String?) {
        count += 1
        if let d = body() { fails.append(UXTestFailure(name: name, detail: d)) }
    }
    let kinds: [FixtureKind] = [.navigation, .format, .undo, .redo, .delete, .replace, .rewrite, .rename, .external]
    // 1. creation: cada kind produce precondiciones válidas para su grupo
    let expectedByKind: [FixtureKind: String] = [.format: "formatSelection", .delete: "deleteSelection",
        .replace: "replaceSelection", .rewrite: "rewriteSelection", .undo: "undo", .redo: "redo",
        .navigation: "findText", .rename: "renameTitle", .external: "saveDocument"]
    for (i, k) in kinds.enumerated() {
        t("fixture-creation \(i)") {
            let e = fixture(for: k, index: i)
            let pre = fixturePreconditions(for: k, expected: expectedByKind[k]!, editor: e)
            return pre.ok ? nil : pre.reason
        }
        // 2. independence: mutar un fixture no afecta a otro recién creado
        t("fixture-independence \(i)") {
            var a = fixture(for: k, index: i)
            let b = fixture(for: k, index: i)
            a.title = "MUTADO"; a.text = ""; a.selectedRange = nil
            a.undoStack = []; a.redoStack = []
            let fresh = fixture(for: k, index: i)
            if fresh != b { return "fixture no determinista" }
            if fresh.title == "MUTADO" { return "fuga de estado entre fixtures" }
            return nil
        }
        // 3. precondition verification: fixture equivocado se detecta
        t("fixture-precondition \(i)") {
            let wrong = FakeEditorState.default() // sin selección ni historial
            let (ok, _) = fixturePreconditions(for: k, expected: expectedByKind[k]!, editor: wrong)
            let needsContext = ["format", "delete", "replace", "rewrite", "undo", "redo"].contains(k.rawValue)
            if needsContext && ok { return "debió marcar INVALID_TEST_FIXTURE" }
            if !needsContext && !ok { return "falso INVALID_TEST_FIXTURE" }
            return nil
        }
    }
    // 4. redo coherente: pide confirm (10C) y restaura destino visible tras Enter
    t("fixture-redo-coherente") {
        var s = RiskBasedSession(editor: fixture(for: .redo, index: 0))
        let before = s.editor.title
        s.startListening(); s.receiveTranscript("Rehaz el cambio.")
        guard case .recognized = s.state else { return "redo debió pedir confirm: \(s.state)" }
        s.confirm()
        guard case .executed = s.state else { return "redo no ejecutó tras confirm" }
        if s.editor.title == before { return "redo no restauró destino visible" }
        return nil
    }
    // 5. undo con acción real en pila (vía confirm en 10C)
    t("fixture-undo-real") {
        var s = RiskBasedSession(editor: fixture(for: .undo, index: 1))
        s.startListening(); s.receiveTranscript("Deshaz el cambio.")
        guard case .recognized = s.state else { return "undo debió pedir confirm: \(s.state)" }
        s.confirm()
        guard case .executed = s.state else { return "undo no ejecutó" }
        return nil
    }
    return (count - fails.count, fails, count)
}
