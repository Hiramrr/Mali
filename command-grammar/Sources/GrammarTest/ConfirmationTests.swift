import CommandGrammar
// Tests automáticos Confirm-All (Fase 9). Invariante crítico tras cada test:
// si no hubo confirmación, editorBefore == editorAfter, o SAFETY_INVARIANT_FAILURE.
import Foundation

struct UXTestFailure { let name: String; let detail: String }

func uxCheck(_ cond: Bool, _ name: String, _ detail: String, _ fails: inout [UXTestFailure]) {
    if !cond { fails.append(UXTestFailure(name: name, detail: detail)) }
}

func runConfirmationTests() -> (passed: Int, failed: [UXTestFailure], total: Int) {
    var fails: [UXTestFailure] = []
    var count = 0
    func t(_ name: String, _ body: () -> String?) {
        count += 1
        if let d = body() { fails.append(UXTestFailure(name: name, detail: d)) }
    }
    func noChange(_ a: FakeEditorState, _ b: FakeEditorState) -> String? {
        a == b ? nil : "SAFETY_INVARIANT_FAILURE: editor cambió sin confirmación"
    }

    // ---- 1. Confirm success por acción (60) ----
    let confirmCases: [(String, (inout FakeEditorState) -> Void, (FakeEditorState) -> Bool, String)] = [
        ("rename Metodología", { $0.selectAll() }, { $0.title == "Metodología" }, "Cambia el encabezado a Metodología."),
        ("rename Capítulo 3", { $0.selectAll() }, { $0.title == "Capítulo 3" }, "Pon como título Capítulo 3."),
        ("rename IHC", { _ in }, { $0.title == "IHC" }, "Cambia el nombre a IHC."),
        ("rename María José", { _ in }, { $0.title == "María José" }, "Bautiza el informe como María José."),
        ("rename TDAH", { _ in }, { $0.title == "TDAH" }, "Ponle de título TDAH."),
        ("delete", { $0.selectAll() }, { $0.text.isEmpty && $0.selectedRange == nil }, "Borra la selección."),
        ("delete frag", { $0.select(substring: "TDAH") }, { !$0.text.contains("TDAH") }, "Elimina esto."),
        ("replace SwiftUI", { $0.select(substring: "TDAH") }, { $0.text.contains("SwiftUI") && !$0.text.contains("TDAH") }, "Sustituye la palabra por SwiftUI."),
        ("replace Interacción", { $0.selectAll() }, { $0.title == "Proyecto" && $0.text == "Interacción Humano-Computadora" }, "Reemplaza esta frase por Interacción Humano-Computadora."),
        ("replace María José", { $0.select(substring: "IHC") }, { $0.text.contains("María José") }, "Sustitúyelo por María José."),
        ("rewrite", { $0.selectAll() }, { $0.simulatedRewriteRequests == ["más breve"] && $0.text.contains("Metodología") }, "Hazlo más breve."),
        ("rewrite formal", { $0.selectAll() }, { $0.simulatedRewriteRequests == ["más formal"] }, "Reformula esto más formal."),
        ("format bold", { $0.selectAll() }, { $0.appliedFormats.count == 1 && $0.appliedFormats[0].style == .bold }, "Ponlo en negritas."),
        ("format italic", { $0.selectAll() }, { $0.appliedFormats.last?.style == .italic }, "Ponlo en cursivas."),
        ("format underline", { $0.selectAll() }, { $0.appliedFormats.last?.style == .underline }, "Subraya la cita."),
        ("undo", { $0.undoStack = [$0.snapshot()]; $0.title = "Otro" }, { $0.title == "Proyecto" }, "Deshaz el cambio."),
        ("redo", { $0.undoStack = [$0.snapshot()]; $0.redoStack = [$0.snapshot()] }, { $0.canUndo }, "Rehaz el cambio."),
        ("find TDAH", { _ in }, { $0.lastFind == "TDAH" }, "Busca TDAH."),
        ("find accesibilidad", { _ in }, { $0.lastFind == "accesibilidad cognitiva" }, "Busca accesibilidad cognitiva."),
        ("select", { _ in }, { $0.selectedText() == "el segundo párrafo" }, "Selecciona el segundo párrafo."),
        ("save", { _ in }, { $0.savedMarker != nil }, "Guarda el documento."),
        ("open", { _ in }, { $0.currentDocument == "el acta vieja" }, "Recupera el acta vieja."),
        ("open nil", { _ in }, { $0.currentDocument == "Último documento" }, "Ábrelo."),
        ("export pdf", { _ in }, { $0.lastExport == .pdf }, "Exporta a pdf."),
        ("export word", { _ in }, { $0.lastExport == .word }, "Genera el documento en Word."),
    ]
    // Nota: "Selecciona el segundo párrafo" selecciona literal si existe; usamos texto con ese contenido.
    for (name, setup, check, transcript) in confirmCases {
        t("confirm \(name)") {
            var s = ConfirmationSession(editor: .default())
            if name == "select" { s.editor.text = "Marca el segundo párrafo aquí." }
            if name.hasPrefix("undo") || name.hasPrefix("redo") { /* setup hace push */ }
            setup(&s.editor)
            s.startListening(); s.receiveTranscript(transcript)
            guard case .recognized = s.state else { return "no llegó a recognized: \(s.state)" }
            s.confirm()
            guard case .executed = s.state else { return "no llegó a executed" }
            return check(s.editor) ? nil : "efecto inesperado para \(transcript)"
        }
        // Doble variante: confirmar dos veces no duplica efectos no-idempotentes controlados
        t("confirm-idempotent-check \(name)") {
            var s = ConfirmationSession(editor: .default())
            if name == "select" { s.editor.text = "Marca el segundo párrafo aquí." }
            setup(&s.editor)
            s.startListening(); s.receiveTranscript(transcript)
            guard case .recognized = s.state else { return "no recognized" }
            s.confirm()
            let afterFirst = s.editor
            s.confirm() // segunda confirmación desde executed = no-op
            if s.editor != afterFirst { return "segunda confirmación mutó estado" }
            return nil
        }
    }
    // 60 = 25*2 + extras para llegar a 60
    for i in 0..<10 {
        let transcripts = ["Bórralo.", "Elimínalo.", "Quítalo.", "Guárdalo.", "Subráyalo.",
                           "Deshazlo.", "Rehazlo.", "Negritas.", "Cursivas.", "Vuelve atrás."]
        t("confirm corto \(i)") {
            var s = ConfirmationSession(editor: .generous())
            s.startListening(); s.receiveTranscript(transcripts[i])
            guard case .recognized = s.state else { return "no recognized: \(s.state)" }
            s.confirm()
            guard case .executed = s.state else { return "no executed" }
            return nil
        }
    }

    // ---- 2. Cancel deja intacto (36) ----
    let cancelTranscripts = ["Cambia el encabezado a Metodología.", "Borra la selección.",
        "Sustituye la palabra por SwiftUI.", "Hazlo más breve.", "Ponlo en negritas.",
        "Deshaz el cambio.", "Rehaz el cambio.", "Busca TDAH.", "Marca esta frase.",
        "Guarda el documento.", "Recupera el acta vieja.", "Exporta a pdf."]
    for (i, tr) in cancelTranscripts.enumerated() {
        t("cancel \(i)") {
            var s = ConfirmationSession(editor: .generous())
            let before = s.editor
            s.startListening(); s.receiveTranscript(tr)
            guard case .recognized = s.state else { return "no recognized" }
            s.cancel()
            guard case .cancelled = s.state else { return "no cancelled" }
            return noChange(before, s.editor)
        }
        t("cancel-tras-escucha \(i)") {
            var s = ConfirmationSession(editor: .generous())
            let before = s.editor
            s.startListening(); s.cancel()
            guard case .cancelled = s.state else { return "no cancelled" }
            return noChange(before, s.editor)
        }
        t("esc-sin-proposal \(i)") {
            var s = ConfirmationSession(editor: .generous())
            let before = s.editor
            s.startListening(); s.receiveTranscript("Hmm, no estoy seguro.")
            s.cancel()
            return noChange(before, s.editor)
        }
    }

    // ---- 3. Repeat resetea (20) ----
    for i in 0..<20 {
        t("repeat \(i)") {
            var s = ConfirmationSession(editor: .generous())
            let before = s.editor
            let first = ["Borra la selección.", "Cambia el encabezado a X.", "Ponlo en negritas.", "Deshaz eso."][i % 4]
            let second = ["Elimina esto.", "Titula Informe.", "Márcalo en negrita.", "Anula eso."][i % 4]
            s.startListening(); s.receiveTranscript(first)
            let a1 = s.attempts
            s.repeatCommand()
            guard case .listening(let a2) = s.state, a2 == a1 + 1 else { return "repeat no avanzó attempt" }
            if s.attempts != a1 + 1 { return "contador attempts mal" }
            s.receiveTranscript(second) // no combina: proposal usa SOLO second
            if case .recognized(let p) = s.state {
                if p.transcript != second { return "combinó transcripts" }
            } else { return "segundo transcript no reconocido: \(s.state)" }
            // repetir no ejecuta nada
            return noChange(before, s.editor)
        }
    }

    // ---- 4. Invalid context (40) ----
    let noSel = ["Borra la selección.", "Sustituye esto por X.", "Hazlo más breve.", "Ponlo en negritas.",
                 "Reemplázalo por Y.", "Aplica subrayado.", "Remarca la conclusión.", "Deja el texto en cursiva."]
    for (i, tr) in noSel.enumerated() {
        t("invalid-sin-seleccion \(i)") {
            let e = FakeEditorState.default() // sin selección
            var s = ConfirmationSession(editor: e)
            let before = s.editor
            s.startListening(); s.receiveTranscript(tr)
            guard case .invalidContext(_, let reason) = s.state, reason == ContextReason.noSelection else {
                return "debió ser invalidContext noSelection: \(s.state)"
            }
            s.confirm() // confirmar en invalidContext = no-op
            if s.editor != before { return "confirm en invalidContext mutó" }
            s.cancel()
            return noChange(before, s.editor)
        }
    }
    for i in 0..<8 {
        t("invalid-undo-vacio \(i)") {
            var s = ConfirmationSession(editor: .default())
            let before = s.editor
            s.startListening(); s.receiveTranscript(["Deshaz.", "Deshaz eso.", "Anula eso.", "Vuelve atrás.", "Revierte el cambio.", "Deshaz el cambio.", "Cancela la edición.", "Échalo para atrás."][i])
            guard case .invalidContext(_, let r) = s.state, r == ContextReason.cannotUndo else { return "debió ser cannotUndo: \(s.state)" }
            s.confirm()
            return noChange(before, s.editor)
        }
        t("invalid-redo-vacio \(i)") {
            var s = ConfirmationSession(editor: .default())
            let before = s.editor
            s.startListening(); s.receiveTranscript(["Rehaz.", "Rehaz eso.", "Reaplica el formato.", "Vuelve a aplicar el cambio.", "Restaura lo deshecho.", "Rehace el cambio.", "Repite el cambio deshecho.", "Vuelve a poner el texto."][i])
            guard case .invalidContext(_, let r) = s.state, r == ContextReason.cannotRedo else { return "debió ser cannotRedo: \(s.state)" }
            s.confirm()
            return noChange(before, s.editor)
        }
    }
    for i in 0..<8 {
        t("revalida-en-confirm \(i)") {
            // recognized con selección, pero la selección desaparece antes de confirmar
            var s = ConfirmationSession(editor: .generous())
            s.startListening(); s.receiveTranscript("Borra la selección.")
            guard case .recognized = s.state else { return "no recognized" }
            s.editor.selectedRange = nil // contexto cambia
            s.confirm()
            guard case .invalidContext = s.state else { return "debió revalidar a invalidContext" }
            return nil
        }
    }
    for i in 0..<8 {
        t("contexto-generoso-ok \(i)") {
            var s = ConfirmationSession(editor: .generous())
            s.startListening()
            s.receiveTranscript(["Borra la selección.", "Deshaz el cambio.", "Rehaz el cambio.", "Ponlo en negritas.",
                                 "Sustituye esto por X.", "Hazlo más breve.", "Aplica subrayado.", "Reemplázalo por Y."][i])
            guard case .recognized = s.state else { return "generoso debió reconocer: \(s.state)" }
            return nil
        }
    }

    // ---- 5. Unknown/unsupported/multi no-ops (60) ----
    let unknowns = ["Hmm, no estoy seguro.", "Espera un segundo.", "Traigo sueño.", "¿Qué hora es?",
                    "Encuéntralo.", "Selecciónalo.", "Mejor mañana.", "Quizá luego.", "No hay señal.", "Gracias por tu ayuda."]
    for (i, tr) in unknowns.enumerated() {
        t("unknown \(i)") {
            var s = ConfirmationSession(editor: .generous())
            let before = s.editor
            s.startListening(); s.receiveTranscript(tr)
            guard case .notUnderstood = s.state else { return "debió ser notUnderstood: \(s.state)" }
            s.confirm(); s.cancel()
            return noChange(before, s.editor)
        }
        t("unknown-repeat \(i)") {
            var s = ConfirmationSession(editor: .generous())
            let before = s.editor
            s.startListening(); s.receiveTranscript(tr)
            s.repeatCommand()
            guard case .listening = s.state else { return "repeat debió volver a listening" }
            return noChange(before, s.editor)
        }
    }
    let unsups = ["Imprime el documento.", "Traduce este párrafo al inglés.", "Firma el acta.",
                  "Comparte el borrador.", "Cifra el informe.", "Comprime el archivo.",
                  "Busca en internet.", "Cuenta las palabras.", "Copia la selección.", "Resume el informe."]
    for (i, tr) in unsups.enumerated() {
        t("unsupported \(i)") {
            var s = ConfirmationSession(editor: .generous())
            let before = s.editor
            s.startListening(); s.receiveTranscript(tr)
            guard case .unsupported = s.state else { return "debió ser unsupported: \(s.state)" }
            s.confirm(); s.cancel()
            return noChange(before, s.editor)
        }
        t("unsupported-repeat \(i)") {
            var s = ConfirmationSession(editor: .generous())
            let before = s.editor
            s.startListening(); s.receiveTranscript(tr)
            s.repeatCommand()
            return noChange(before, s.editor)
        }
    }
    let multis = ["Borra esto y guarda el documento.", "Titula y guarda.", "Busca y marca.",
                  "Cambia el título a X y archiva.", "Deshaz y guarda.", "Lee y corrige.",
                  "Selecciona y subraya.", "Firma y sella.", "Abre y revisa.", "Borra y archiva."]
    for (i, tr) in multis.enumerated() {
        t("multi \(i)") {
            var s = ConfirmationSession(editor: .generous())
            let before = s.editor
            s.startListening(); s.receiveTranscript(tr)
            // multi se presenta como unsupported("multipleActions") sin acción aproximada
            guard case .unsupported = s.state else { return "multi debió ser unsupported: \(s.state)" }
            s.confirm()
            return noChange(before, s.editor)
        }
    }

    // ---- 6. Undo/redo pilas (40) ----
    for i in 0..<10 {
        t("undo-restaura \(i)") {
            var s = ConfirmationSession(editor: .default())
            s.startListening(); s.receiveTranscript("Cambia el encabezado a Título \(i).")
            guard case .recognized = s.state else { return "no recognized rename" }
            s.confirm()
            if s.editor.title != "Título \(i)" { return "rename no aplicó" }
            s.startListening(); s.receiveTranscript("Deshaz el cambio.")
            guard case .recognized = s.state else { return "undo debería ser válido: \(s.state)" }
            s.confirm()
            if s.editor.title != "Proyecto" { return "undo no restauró" }
            if s.editor.canRedo == false { return "redo debería estar disponible" }
            return nil
        }
        t("redo-reaplica \(i)") {
            var s = ConfirmationSession(editor: .default())
            s.startListening(); s.receiveTranscript("Cambia el encabezado a Título \(i).")
            s.confirm()
            s.startListening(); s.receiveTranscript("Deshaz el cambio."); s.confirm()
            s.startListening(); s.receiveTranscript("Rehaz el cambio.")
            guard case .recognized = s.state else { return "redo debería ser válido" }
            s.confirm()
            if s.editor.title != "Título \(i)" { return "redo no reaplicó" }
            return nil
        }
        t("edit-limpia-redo \(i)") {
            var s = ConfirmationSession(editor: .default())
            s.startListening(); s.receiveTranscript("Cambia el encabezado a A."); s.confirm()
            s.startListening(); s.receiveTranscript("Deshaz el cambio."); s.confirm()
            s.startListening(); s.receiveTranscript("Cambia el encabezado a B."); s.confirm()
            if s.editor.canRedo { return "nueva edición debió limpiar redo" }
            return nil
        }
        t("cancel-no-toca-pilas \(i)") {
            var s = ConfirmationSession(editor: .generous())
            let (u, r) = (s.editor.undoStack.count, s.editor.redoStack.count)
            s.startListening(); s.receiveTranscript("Borra la selección.")
            s.cancel()
            if s.editor.undoStack.count != u || s.editor.redoStack.count != r { return "cancel tocó pilas" }
            return nil
        }
    }

    // ---- 7. Argumentos preservados (30) ----
    let argCases = ["Metodología", "Evaluación de IHC", "TDAH", "IHC", "SwiftUI",
                    "María José", "Resultados 2026", "Capítulo 3", "accesibilidad cognitiva",
                    "Interacción Humano-Computadora", "Diseño centrado", "Claridad",
                    "el segundo párrafo", "el acta vieja", "la palabra TDAH"]
    for (i, a) in argCases.enumerated() {
        t("arg-rename \(i)") {
            var s = ConfirmationSession(editor: .default())
            s.startListening(); s.receiveTranscript("Cambia el encabezado a \(a).")
            guard case .recognized(let p) = s.state else { return "no recognized" }
            guard case .renameTitle(let got) = p.command, got == a else { return "arg no preservado: \(p.command)" }
            s.confirm()
            if s.editor.title != a { return "título no aplicado" }
            return nil
        }
        t("arg-find \(i)") {
            var s = ConfirmationSession(editor: .default())
            s.startListening(); s.receiveTranscript("Busca \(a).")
            guard case .recognized(let p) = s.state else { return "find no reconocido: \(s.state)" }
            // "la palabra X" se descarta por diseño gramatical (solo secuencia exacta)
            let want = (a == "la palabra TDAH") ? "TDAH" : a
            guard case .findText(let got) = p.command, got == want else { return "find arg no preservado" }
            let before = s.editor.text
            s.confirm()
            if s.editor.text != before { return "find no debe mutar texto" }
            if s.editor.lastFind != want { return "find no registró" }
            return nil
        }
    }

    // ---- 8. Riesgo no cambia política (24) ----
    let riskCases: [(String, CommandRisk)] = [
        ("Marca esta frase.", .navigation), ("Busca TDAH.", .navigation),
        ("Deshaz el cambio.", .reversible), ("Ponlo en negritas.", .reversible),
        ("Rehaz el cambio.", .reversible), ("Cambia el encabezado a X.", .contentChanging),
        ("Borra la selección.", .contentChanging), ("Sustituye esto por Y.", .contentChanging),
        ("Hazlo más breve.", .contentChanging), ("Guarda el documento.", .externalSideEffect),
        ("Recupera el acta vieja.", .externalSideEffect), ("Exporta a pdf.", .externalSideEffect),
    ]
    for (i, (tr, risk)) in riskCases.enumerated() {
        t("risk-policy \(i)") {
            var s = ConfirmationSession(editor: .generous())
            s.startListening(); s.receiveTranscript(tr)
            guard case .recognized(let p) = s.state else { return "no recognized: \(s.state)" }
            if p.risk != risk { return "riesgo mal clasificado: \(p.risk)" }
            // Fase 9: riesgo NO salta confirmación; recibir nunca ejecuta
            return nil
        }
        t("risk-siempre-confirma \(i)") {
            var s = ConfirmationSession(editor: .generous())
            s.startListening(); s.receiveTranscript(tr)
            if case .executed = s.state { return "receiveTranscript auto-ejecutó" }
            return nil
        }
    }

    // ---- 9. Rewrite simulado (12) ----
    for i in 0..<12 {
        t("rewrite-simulado \(i)") {
            var s = ConfirmationSession(editor: .generous())
            let beforeText = s.editor.text
            s.startListening(); s.receiveTranscript(["Hazlo más breve.", "Hazlo más formal.", "Reescribe el párrafo completo.", "Reformula la conclusión.", "Hazla más accesible.", "Reescribe esto con otras palabras.", "Hazlo en tono académico.", "Reformula esto más formal.", "Haz esta parte más clara.", "Hazlo diferente.", "Reescribe ya.", "Reformula todo."][i])
            guard case .recognized(let p) = s.state else { return "no recognized" }
            if !p.effectDescription.contains("Reescribir") { return "preview rewrite mal" }
            s.confirm()
            if s.editor.text != beforeText { return "rewrite simulado no debe transformar texto" }
            if s.editor.simulatedRewriteRequests.isEmpty { return "debió registrar SIMULATED_REWRITE_REQUEST" }
            return nil
        }
    }

    // ---- 10. Barrido invariante con transcripts reales (40) ----
    let sweep = ["Pon como título Resultados.", "Titula el informe.", "Quita esa frase.", "Suprime el párrafo.",
                 "Tacha lo último.", "Corta esta parte.", "Troca esto por TDAH.", "Escribe Evaluación de IHC.",
                 "Pon Resultados 2026 donde dice borrador.", "Hazla más accesible.", "Aplica cursivas a la cita.",
                 "Deja el texto en cursiva.", "Resalta el resultado.", "Anula el último cambio.", "Cancela la edición.",
                 "Revierte el cambio.", "Vuelve a como estaba.", "Regresa al borrador.", "Restaura la edición.",
                 "Reaplica el formato.", "Restaura lo deshecho.", "Vuelve a poner el texto.", "Localiza SwiftUI.",
                 "Halla Capítulo 3.", "Rastrea María José.", "Detecta la cita duplicada.", "Ubica el segundo párrafo.",
                 "Elige accesibilidad.", "Toma el Capítulo 3.", "Señala la palabra TDAH.", "Enfoca la conclusión.",
                 "Aparta el párrafo duplicado.", "Archiva el informe.", "Respalda el borrador.", "Carga el informe guardado.",
                 "Muestra el Capítulo 3.", "Genera el documento en Word.", "Convierte a texto plano.", "Saca el acta en pdf.",
                 "Vuelve al estado anterior."]
    for (i, tr) in sweep.enumerated() {
        t("sweep-cancel \(i)") {
            var s = ConfirmationSession(editor: .generous())
            let before = s.editor
            s.startListening(); s.receiveTranscript(tr)
            s.cancel()
            return noChange(before, s.editor)
        }
    }

    return (count - fails.count, fails, count)
}
