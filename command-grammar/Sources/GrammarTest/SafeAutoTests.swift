import CommandGrammar
// Tests Fase 10C: invariante estructural + regresiones B20/B42/V173.
import Foundation

func runSafeAutoTests() -> (passed: Int, failed: [UXTestFailure], total: Int) {
    var fails: [UXTestFailure] = []
    var count = 0
    func t(_ name: String, _ body: () -> String?) {
        count += 1
        if let d = body() { fails.append(UXTestFailure(name: name, detail: d)) }
    }

    // Invariante estructural: IMMEDIATE ⇒ navigation y sin mutar doc/historial/externo.
    // Solo navegación puede auto-ejecutar; navegación solo toca selección/find.
    let navCmds: [ParsedCommand] = [.findText("TDAH"), .selectText("IHC"), .findText("x"), .selectText("y")]
    for (i, cmd) in navCmds.enumerated() {
        t("safe-immediate-nav \(i)") {
            if policyForCommand(cmd) != .immediate { return "navegación debe ser immediate" }
            var e = FakeEditorState.generous()
            let before = e
            applyConfirmed(cmd, to: &e)
            if e.title != before.title || e.text != before.text { return "UNSAFE: mutó contenido" }
            if e.appliedFormats != before.appliedFormats { return "UNSAFE: mutó formato" }
            if e.undoStack != before.undoStack || e.redoStack != before.redoStack { return "UNSAFE: mutó historial" }
            if e.savedMarker != before.savedMarker || e.lastExport != before.lastExport { return "UNSAFE: efecto externo" }
            if e.currentDocument != before.currentDocument { return "UNSAFE: identidad doc" }
            if e.simulatedRewriteRequests != before.simulatedRewriteRequests { return "UNSAFE: rewrite" }
            return nil
        }
    }
    // Todo lo que muta estado debe ser CONFIRM.
    let mutating: [ParsedCommand] = [.renameTitle("x"), .deleteSelection, .replaceSelection("x"),
        .rewriteSelection("x"), .formatSelection(.bold), .undo, .redo,
        .saveDocument, .openDocument("x"), .exportDocument(.pdf)]
    for (i, cmd) in mutating.enumerated() {
        t("safe-mutating-confirm \(i)") {
            if policyForCommand(cmd) != .confirm {
                return "UNSAFE_AUTO_EXECUTION_POLICY_FAILURE: \(cmd)"
            }
            return nil
        }
    }
    // Exhaustividad: todo ParsedCommand → un riesgo → una política; IMMEDIATE ⇒ navigation.
    let all: [ParsedCommand] = [.renameTitle("a"), .deleteSelection, .replaceSelection("a"),
        .rewriteSelection("a"), .formatSelection(.italic), .undo, .redo, .selectText("a"),
        .findText("a"), .saveDocument, .openDocument(nil), .exportDocument(.word),
        .unsupported("z"), .unknown, .multipleActions]
    for (i, cmd) in all.enumerated() {
        t("safe-exhaustive \(i)") {
            let p = policyForCommand(cmd)
            if p == .immediate && riskOf(cmd) != .navigation {
                return "UNSAFE_AUTO_EXECUTION_POLICY_FAILURE: \(cmd)"
            }
            return nil
        }
    }
    // B20: "Restaura lo desecho" → undo → CONFIRM, sin auto, sin mutación previa.
    t("b20-regression") {
        let tr = "Restaura lo desecho"
        guard case .undo = parseCommand(raw: tr) else { return "B20 ya no parsea a undo" }
        var s = RiskBasedSession(editor: fixture(for: .redo, index: 0))
        let before = s.editor
        s.startListening(); s.receiveTranscript(tr)
        guard case .recognized = s.state else { return "B20 debió pedir confirm: \(s.state)" }
        if !s.autoLog.isEmpty { return "B20_AUTO_EFFECT: auto-ejecutó" }
        if s.editor != before { return "mutó antes de confirmar" }
        return nil
    }
    // B42: transcript erróneo que cae en format → CONFIRM, sin auto.
    t("b42-regression") {
        let tr = "Subraya el acta vieja"
        let cmd = parseCommand(raw: tr)
        guard case .formatSelection = cmd else { return "B42 ya no cae en format: \(cmd)" }
        var s = RiskBasedSession(editor: .generous())
        s.editor.selectAll() // contexto válido: el peligro real
        let before = s.editor
        s.startListening(); s.receiveTranscript(tr)
        guard case .recognized = s.state else { return "B42 debió pedir confirm: \(s.state)" }
        if !s.autoLog.isEmpty { return "B42 auto-ejecutó formato erróneo" }
        if s.editor != before { return "mutó antes de confirmar" }
        return nil
    }
    // V173: unknown esperado → delete → CONFIRM, sin auto.
    t("v173-regression") {
        let tr = "Borra información accidentalmente afecta"
        guard case .deleteSelection = parseCommand(raw: tr) else { return "V173 ya no es delete" }
        var s = RiskBasedSession(editor: .generous())
        let before = s.editor
        s.startListening(); s.receiveTranscript(tr)
        guard case .recognized = s.state else { return "V173 debió pedir confirm" }
        if !s.autoLog.isEmpty { return "V173 auto-ejecutó" }
        if s.editor != before { return "mutó antes de confirmar" }
        return nil
    }
    // navigation sigue inmediata (12 transcripciones variadas).
    let navtrs = ["Busca TDAH.", "Encuentra IHC.", "Localiza SwiftUI.", "Halla Capítulo 3.",
                  "Marca esta frase.", "Selecciona María José.", "Elige accesibilidad.", "Toma el Capítulo 3.",
                  "Rastrea el folio.", "Ubica el acta.", "Detecta dobles espacios.", "Señala la imagen."]
    for (i, tr) in navtrs.enumerated() {
        t("safe-nav-still-immediate \(i)") {
            var s = RiskBasedSession(editor: .default())
            s.startListening(); s.receiveTranscript(tr)
            guard case .executed = s.state else { return "nav debió auto: \(s.state)" }
            return nil
        }
    }
    return (count - fails.count, fails, count)
}
