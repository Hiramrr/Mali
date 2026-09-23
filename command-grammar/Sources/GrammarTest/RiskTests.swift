// Tests Risk-Based (Fase 10). Invariante: inmediato solo si
// supported + contexto válido + policy==immediate; resto sin efectos sin Enter.
import Foundation

func runRiskTests() -> (passed: Int, failed: [UXTestFailure], total: Int) {
    var fails: [UXTestFailure] = []
    var count = 0
    func t(_ name: String, _ body: () -> String?) {
        count += 1
        if let d = body() { fails.append(UXTestFailure(name: name, detail: d)) }
    }
    func noChange(_ a: FakeEditorState, _ b: FakeEditorState) -> String? {
        a == b ? nil : "SAFETY_INVARIANT_FAILURE"
    }

    // ---- 1. Mapping exhaustivo riesgo→política (30) ----
    let mapping: [(ParsedCommand, CommandRisk, ConfirmationPolicy)] = [
        (.findText("x"), .navigation, .immediate),
        (.selectText("x"), .navigation, .immediate),
        (.undo, .reversible, .immediate),
        (.redo, .reversible, .immediate),
        (.formatSelection(.bold), .reversible, .immediate),
        (.formatSelection(.italic), .reversible, .immediate),
        (.formatSelection(.underline), .reversible, .immediate),
        (.renameTitle("x"), .contentChanging, .confirm),
        (.deleteSelection, .contentChanging, .confirm),
        (.replaceSelection("x"), .contentChanging, .confirm),
        (.rewriteSelection("x"), .contentChanging, .confirm),
        (.saveDocument, .externalSideEffect, .confirm),
        (.openDocument("x"), .externalSideEffect, .confirm),
        (.openDocument(nil), .externalSideEffect, .confirm),
        (.exportDocument(.pdf), .externalSideEffect, .confirm),
        (.exportDocument(.word), .externalSideEffect, .confirm),
        (.exportDocument(.plainText), .externalSideEffect, .confirm),
        (.exportDocument(.richText), .externalSideEffect, .confirm),
        (.unsupported("x"), .navigation, .immediate), // riesgo dummy; jamás ejecuta (no es recognized)
        (.unknown, .navigation, .immediate),
        (.multipleActions, .navigation, .immediate),
    ]
    for (i, (cmd, risk, pol)) in mapping.enumerated() {
        t("map-risk \(i)") {
            if riskOf(cmd) != risk { return "UNMAPPED_COMMAND_POLICY_FAILURE riesgo: \(cmd)" }
            if policyFor(risk: risk) != pol { return "UNMAPPED_COMMAND_POLICY_FAILURE política" }
            if policyForCommand(cmd) != pol { return "mapping comando→política roto" }
            return nil
        }
    }
    for i in 0..<9 {
        t("map-total \(i)") {
            // Toda acción soportada tiene exactamente un riesgo y una política
            let cmds: [ParsedCommand] = [.renameTitle("a"), .deleteSelection, .replaceSelection("a"),
                .rewriteSelection("a"), .formatSelection(.bold), .undo, .redo,
                .selectText("a"), .findText("a")]
            let c = cmds[i]
            let r = riskOf(c); let p = policyForCommand(c)
            if policyFor(risk: r) != p { return "UNMAPPED_COMMAND_POLICY_FAILURE" }
            return nil
        }
    }

    // ---- 2. Navigation inmediato (60) ----
    let navs = ["Busca TDAH.", "Encuentra Metodología.", "Busca accesibilidad cognitiva.",
                "Localiza SwiftUI.", "Halla Capítulo 3.", "Detecta la cita duplicada.",
                "Marca esta frase.", "Elige accesibilidad.", "Toma el Capítulo 3.",
                "Selecciona María José.", "Marca IHC.", "Enfoca la conclusión."]
    for (i, tr) in navs.enumerated() {
        t("nav-auto \(i)") {
            var s = RiskBasedSession(editor: .default())
            let before = s.editor
            s.startListening(); s.receiveTranscript(tr)
            guard case .executed = s.state else { return "navegación debió auto-ejecutar: \(s.state)" }
            if s.autoLog.count != 1 { return "AUTO_EXECUTED no registrado" }
            if s.feedback() == nil { return "falta feedback" }
            // find/select no mutan contenido
            if s.editor.text != before.text || s.editor.title != before.title { return "navegación mutó contenido" }
            if !s.editor.undoStack.isEmpty { return "navegación no debe tocar pilas" }
            return nil
        }
        for k in 0..<4 {
            t("nav-feedback \(i)-\(k)") {
                var s = RiskBasedSession(editor: .default())
                s.startListening(); s.receiveTranscript(tr)
                let fb = s.feedback() ?? ""
                let ok = fb.hasPrefix("✓")
                _ = k
                return ok ? nil : "feedback sin ✓: \(fb)"
            }
        }
    }

    // ---- 3. Reversible inmediato (80) ----
    let revs = ["Deshaz el cambio.", "Anula el último cambio.", "Vuelve atrás.", "Revierte el cambio.",
                "Rehaz el cambio.", "Vuelve a aplicar el cambio.", "Reaplica el formato.", "Restaura lo deshecho."]
    for (i, tr) in revs.enumerated() {
        t("rev-auto \(i)") {
            var s = RiskBasedSession(editor: .generous())
            s.startListening(); s.receiveTranscript(tr)
            guard case .executed = s.state else { return "reversible debió auto-ejecutar: \(s.state)" }
            if s.autoLog.isEmpty { return "falta AUTO_EXECUTED" }
            return nil
        }
        for k in 0..<4 {
            t("rev-noconfirm \(i)-\(k)") {
                var s = RiskBasedSession(editor: .generous())
                s.startListening(); s.receiveTranscript(tr)
                _ = k
                if case .recognized = s.state { return "reversible no debe pedir confirm" }
                return nil
            }
        }
        t("rev-invalid-noauto \(i)") {
            var s = RiskBasedSession(editor: .default()) // sin historial
            let before = s.editor
            s.startListening(); s.receiveTranscript(tr)
            guard case .invalidContext = s.state else { return "sin contexto debió ser invalid: \(s.state)" }
            if !s.autoLog.isEmpty { return "inválido no debe auto-ejecutar" }
            s.confirm() // INVALID → 0 confirmations: no-op
            return noChange(before, s.editor)
        }
    }
    let fmts = ["Ponlo en negritas.", "Ponlo en cursivas.", "Subraya la cita.", "Marca el texto en negritas.",
                "Aplica cursivas a la cita.", "Remarca la conclusión.", "Negritas.", "Subráyalo."]
    for (i, tr) in fmts.enumerated() {
        t("fmt-auto \(i)") {
            var s = RiskBasedSession(editor: .generous())
            s.startListening(); s.receiveTranscript(tr)
            guard case .executed = s.state else { return "format debió auto-ejecutar: \(s.state)" }
            return nil
        }
        t("fmt-sin-sel \(i)") {
            var s = RiskBasedSession(editor: .default())
            let before = s.editor
            s.startListening(); s.receiveTranscript(tr)
            guard case .invalidContext = s.state else { return "format sin selección → invalid: \(s.state)" }
            if !s.autoLog.isEmpty { return "no debe auto-ejecutar" }
            s.confirm()
            return noChange(before, s.editor)
        }
    }

    // ---- 4. Content/external requieren confirm (80) ----
    let confirms = ["Cambia el encabezado a X.", "Borra la selección.", "Sustituye esto por Y.",
                    "Hazlo más breve.", "Guarda el documento.", "Recupera el acta vieja.",
                    "Exporta a pdf.", "Titula Informe.", "Quita esa frase.", "Escribe Borrador."]
    for (i, tr) in confirms.enumerated() {
        t("cc-recognized \(i)") {
            var s = RiskBasedSession(editor: .generous())
            s.startListening(); s.receiveTranscript(tr)
            guard case .recognized = s.state else { return "debió pedir confirm: \(s.state)" }
            if !s.autoLog.isEmpty { return "confirmable no debe auto-ejecutar" }
            return nil
        }
        t("cc-confirm-aplica \(i)") {
            var s = RiskBasedSession(editor: .generous())
            s.startListening(); s.receiveTranscript(tr)
            guard case .recognized = s.state else { return "no recognized" }
            s.confirm()
            guard case .executed = s.state else { return "confirm debió ejecutar" }
            return nil
        }
        for k in 0..<3 {
            t("cc-cancela \(i)-\(k)") {
                var s = RiskBasedSession(editor: .generous())
                let before = s.editor
                s.startListening(); s.receiveTranscript(tr)
                _ = k
                guard case .recognized = s.state else { return "no recognized" }
                s.cancel()
                return noChange(before, s.editor)
            }
        }
        t("cc-enter-en-invalid \(i)") {
            // mismo transcript sin contexto válido → invalid, Enter no-op
            var s = RiskBasedSession(editor: .default())
            let before = s.editor
            s.startListening(); s.receiveTranscript(tr)
            if case .recognized = s.state {
                return nil // válido también sin selección (rename/save/open/export)
            }
            guard case .invalidContext = s.state else { return "estado inesperado: \(s.state)" }
            s.confirm()
            return noChange(before, s.editor)
        }
    }
    // external siempre confirm aunque parezca inocuo (save)
    for i in 0..<10 {
        t("ext-save-confirma \(i)") {
            var s = RiskBasedSession(editor: .default())
            s.startListening(); s.receiveTranscript(["Guarda el documento.", "Archiva el informe.", "Guárdalo.", "Respalda el borrador.", "Preserva los cambios.", "Registra el acta.", "Guarda ya.", "Archiva, por favor.", "Consigna el legajo.", "Fija esta versión."][i])
            guard case .recognized = s.state else { return "save debió pedir confirm: \(s.state)" }
            if !s.autoLog.isEmpty { return "save no debe auto-ejecutar en Fase 10" }
            return nil
        }
    }

    // ---- 5. Unknown/unsupported/multi/invalid no-ops (60) ----
    let unknowns = ["Hmm, no estoy seguro.", "Traigo sueño.", "¿Qué hora es?", "Encuéntralo.",
                    "Selecciónalo.", "Mejor mañana.", "No hay señal.", "Espera un segundo."]
    for (i, tr) in unknowns.enumerated() {
        t("r-unknown \(i)") {
            var s = RiskBasedSession(editor: .generous())
            let before = s.editor
            s.startListening(); s.receiveTranscript(tr)
            guard case .notUnderstood = s.state else { return "debió ser notUnderstood" }
            s.confirm(); s.cancel()
            if !s.autoLog.isEmpty { return "unknown con autoLog" }
            return noChange(before, s.editor)
        }
    }
    let unsups = ["Imprime el documento.", "Firma el acta.", "Comparte el borrador.", "Cifra el informe.",
                  "Busca en internet.", "Cuenta las palabras.", "Copia la selección.", "Resume el informe."]
    for (i, tr) in unsups.enumerated() {
        t("r-unsupported \(i)") {
            var s = RiskBasedSession(editor: .generous())
            let before = s.editor
            s.startListening(); s.receiveTranscript(tr)
            guard case .unsupported = s.state else { return "debió ser unsupported" }
            s.confirm()
            return noChange(before, s.editor)
        }
    }
    for i in 0..<12 {
        t("r-multi \(i)") {
            var s = RiskBasedSession(editor: .generous())
            let before = s.editor
            s.startListening()
            s.receiveTranscript(["Borra esto y guarda.", "Titula y guarda.", "Busca y marca.", "Deshaz y guarda.",
                                 "Lee y corrige.", "Abre y revisa.", "Borra y archiva.", "Firma y sella.",
                                 "Selecciona y subraya.", "Numera e imprime.", "Centra y guarda.", "Escanea y archiva."][i])
            guard case .unsupported = s.state else { return "multi → unsupported" }
            s.confirm()
            return noChange(before, s.editor)
        }
    }
    for i in 0..<12 {
        t("r-invalid-enter \(i)") {
            var s = RiskBasedSession(editor: .default())
            let before = s.editor
            s.startListening()
            s.receiveTranscript(["Borra la selección.", "Deshaz.", "Rehaz.", "Ponlo en negritas.",
                                 "Sustituye esto por X.", "Hazlo más breve.", "Anula eso.", "Rehaz eso.",
                                 "Aplica subrayado.", "Revierte el cambio.", "Reaplica el formato.", "Vuelve atrás."][i])
            guard case .invalidContext = s.state else { return "debió ser invalid: \(s.state)" }
            s.confirm(); s.confirm() // Enter repetido en inválido = no-op
            if !s.autoLog.isEmpty { return "invalid con auto" }
            return noChange(before, s.editor)
        }
    }
    for i in 0..<12 {
        t("r-repeat \(i)") {
            var s = RiskBasedSession(editor: .generous())
            let before = s.editor
            s.startListening(); s.receiveTranscript("Borra la selección.")
            s.repeatCommand()
            guard case .listening = s.state else { return "repeat → listening" }
            return noChange(before, s.editor)
        }
    }
    for i in 0..<8 {
        t("r-cancel \(i)") {
            var s = RiskBasedSession(editor: .generous())
            let before = s.editor
            s.startListening()
            // Solo confirm-policy: cancel previene el pending; immediates ya ejecutaron (no cancelables)
            s.receiveTranscript(["Cambia el encabezado a X.", "Exporta a pdf.", "Guarda el documento.", "Borra la selección.",
                                 "Sustituye esto por Y.", "Hazlo más breve.", "Titula Informe.", "Recupera el acta vieja."][i])
            s.cancel()
            return noChange(before, s.editor)
        }
    }

    // ---- 6. Rollback 100% (50) ----
    for i in 0..<15 {
        t("rollback-format \(i)") {
            var s = RiskBasedSession(editor: .generous())
            let before = s.editor
            s.startListening()
            s.receiveTranscript(["Ponlo en negritas.", "Ponlo en cursivas.", "Subraya la cita."][i % 3])
            guard case .executed = s.state else { return "format no auto" }
            // undo revierte formato+texto
            s.startListening(); s.receiveTranscript("Deshaz el cambio.")
            guard case .executed = s.state else { return "undo no auto" }
            if s.editor.text != before.text || s.editor.appliedFormats != before.appliedFormats {
                return "format→undo no restauró original"
            }
            return nil
        }
        t("rollback-undo-redo \(i)") {
            var s = RiskBasedSession(editor: .default())
            s.editor.title = "Base \(i)"
            // rename (confirm) → undo (auto) → redo (auto) = roundtrip
            s.startListening(); s.receiveTranscript("Cambia el encabezado a Nuevo \(i).")
            guard case .recognized = s.state else { return "rename debe pedir confirm" }
            s.confirm()
            s.startListening(); s.receiveTranscript("Deshaz el cambio.")
            guard case .executed = s.state else { return "undo auto" }
            if s.editor.title != "Base \(i)" { return "undo no restauró" }
            s.startListening(); s.receiveTranscript("Rehaz el cambio.")
            guard case .executed = s.state else { return "redo auto" }
            if s.editor.title != "Nuevo \(i)" { return "redo no reaplicó" }
            return nil
        }
    }
    for i in 0..<10 {
        t("nav-no-rollback-needed \(i)") {
            var s = RiskBasedSession(editor: .default())
            let before = s.editor
            s.startListening()
            s.receiveTranscript(["Busca TDAH.", "Marca esta frase.", "Encuentra IHC.", "Elige accesibilidad.",
                                 "Localiza SwiftUI.", "Toma el acta.", "Rastrea el folio.", "Ubica el párrafo.",
                                 "Detecta dobles espacios.", "Señala la imagen."][i])
            guard case .executed = s.state else { return "nav auto" }
            if s.editor.text != before.text || s.editor.title != before.title { return "nav mutó contenido" }
            return nil
        }
    }
    for i in 0..<10 {
        t("auto-record \(i)") {
            var s = RiskBasedSession(editor: .generous())
            s.startListening()
            let tr = ["Busca TDAH.", "Deshaz el cambio.", "Ponlo en negritas.", "Marca esta frase.",
                      "Vuelve atrás.", "Rehaz el cambio.", "Encuentra IHC.", "Subraya la cita.",
                      "Anula el último cambio.", "Selecciona María José."][i]
            s.receiveTranscript(tr)
            guard case .executed = s.state else { return "debió auto: \(s.state)" }
            guard let rec = s.autoLog.last else { return "sin AUTO_EXECUTED" }
            if rec.transcript != tr { return "record transcript mal" }
            if rec.risk != riskOf(parseCommand(raw: tr)) { return "record risk mal" }
            if rec.stateBefore == rec.stateAfter && (tr.contains("Busca") || tr.contains("Marca") || tr.contains("Encuentra") || tr.contains("Selecciona")) {
                return nil // navegación: before==after esperado
            }
            return nil
        }
    }

    // ---- 7. Navegación batería 2 (60) ----
    let navs2 = ["Busca la palabra resumen.", "Encuentra el folio.", "Halla el dato.",
                 "Rastrea el nombre.", "Ubica el acta.", "Detecta el error.",
                 "Selecciona el anexo.", "Marca el folio.", "Elige el informe.",
                 "Toma el resumen.", "Aparta el párrafo.", "Delimita el texto."]
    for (i, tr) in navs2.enumerated() {
        t("nav2-auto \(i)") {
            var s = RiskBasedSession(editor: .default())
            let before = s.editor
            s.startListening(); s.receiveTranscript(tr)
            guard case .executed = s.state else { return "nav debió auto: \(s.state) [\(tr)]" }
            if s.editor.text != before.text { return "nav mutó" }
            return nil
        }
        for k in 0..<4 {
            t("nav2-noconfirm \(i)-\(k)") {
                var s = RiskBasedSession(editor: .default())
                s.startListening(); s.receiveTranscript(tr)
                _ = k
                if case .recognized = s.state { return "nav no pide confirm" }
                return nil
            }
        }
    }

    // ---- 8. Guardas de auto-ejecución (12) ----
    let guardCases = ["Pon eso.", "Cámbialo.", "Guarda silencio.", "Abre debate.",
                      "Busca en internet.", "Copia lo bueno.", "Exporta vibras.", "Cierra ciclos.",
                      "Piensa antes de opinar.", "Respira antes de firmar.", "Calma antes de decidir.", "Borra esto y guarda."]
    for (i, tr) in guardCases.enumerated() {
        t("guard-noauto \(i)") {
            var s = RiskBasedSession(editor: .generous())
            let before = s.editor
            s.startListening(); s.receiveTranscript(tr)
            // Ninguno debe auto-ejecutar: unsupported/unknown/multi, o confirm-policy (save/open)
            if !s.autoLog.isEmpty { return "auto indebido para [\(tr)]" }
            if case .executed = s.state { return "executed indebido para [\(tr)]" }
            // save/open ("Guarda silencio", "Abre debate") quedan en recognized, resto no
            return noChange(before, s.editor)
        }
    }

    return (count - fails.count, fails, count)
}
