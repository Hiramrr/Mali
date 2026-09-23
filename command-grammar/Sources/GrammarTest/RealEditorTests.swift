// Fase 11 — Tests del pipeline real (ParsedCommand → Validator → Policy → Executor → NSTextView).
import Foundation
import AppKit

@MainActor private func realConfirm(_ e: RealCommandExecutor, _ cmd: ParsedCommand) -> RealEditorResult {
    let out = e.receive(cmd)
    guard case .needsConfirm(let p) = out else {
        return .failure(.unsupportedCommand("test esperaba needsConfirm, fue \(out)"))
    }
    return e.confirm(p)
}

@MainActor func runRealEditorTests() -> (passed: Int, failed: [UXTestFailure], total: Int) {
    var fails: [UXTestFailure] = []
    var count = 0
    func t(_ name: String, _ body: () -> String?) {
        count += 1
        if let d = body() { fails.append(UXTestFailure(name: name, detail: d)) }
    }

    // ---- 1. Navegación inmediata (14) ----
    t("r-nav-find-exact") {
        let (w, v, target, _) = makeRealProbe(); defer { w.orderOut(nil) }
        let before = v.string
        guard case .success(.found(let r)) = target.findText("TDAH") else { return "find TDAH falló" }
        if (before as NSString).substring(with: r) != "TDAH" { return "rango mal" }
        if v.string != before { return "find mutó contenido" }
        return nil
    }
    t("r-nav-find-moves-selection") {
        let (w, v, target, _) = makeRealProbe(); defer { w.orderOut(nil) }
        let before = v.string
        guard case .success(.found(let r)) = target.findText("Metodología") else { return "find exacto falló" }
        if (before as NSString).substring(with: r) != "Metodología" { return "rango mal" }
        if v.string != before { return "find mutó contenido" }
        return nil
    }
    t("r-nav-find-no-match") {
        let (w, _, target, _) = makeRealProbe(); defer { w.orderOut(nil) }
        let before = (target.text, target.sel.location)
        guard case .noMatch = target.findText("zz-sin-match") else { return "debió ser noMatch" }
        if target.text != before.0 { return "noMatch mutó" }
        return nil
    }
    t("r-nav-find-unicode") {
        let (w, v, target, _) = makeRealProbe(); defer { w.orderOut(nil) }
        for q in ["evaluación", "🧠", "ユーザー", "María-José"] {
            guard case .success(.found(let r)) = target.findText(q) else { return "find unicode falló: \(q)" }
            if (v.string as NSString).substring(with: r) != q { return "rango unicode mal: \(q)" }
        }
        if v.string != RealFixtureText.real { return "find unicode mutó" }
        return nil
    }
    t("r-nav-find-after-cursor") {
        let (w, v, target, _) = makeRealProbe(text: RealFixtureText.duplicates); defer { w.orderOut(nil) }
        let first = (v.string as NSString).range(of: "Metodología")
        v.setSelectedRange(NSRange(location: first.location + first.length, length: 0))
        guard case .success(.found(let r)) = target.findText("Metodología") else { return "find falló" }
        if r.location <= first.location { return "regla: primera después del cursor" }
        return nil
    }
    t("r-nav-find-normalized") {
        let (w, _, target, _) = makeRealProbe(); defer { w.orderOut(nil) }
        guard case .success(.found) = target.findText("metodologia") else { return "fallback normalizado falló" }
        return nil
    }
    t("r-nav-select-exact") {
        let (w, v, target, _) = makeRealProbe(); defer { w.orderOut(nil) }
        let before = v.string
        guard case .success(.selected(let r)) = target.selectText("IHC") else { return "select falló" }
        if (before as NSString).substring(with: r) != "IHC" { return "rango mal" }
        if v.selectedRange() != r { return "selección real no aplicada" }
        if v.string != before { return "select mutó contenido" }
        return nil
    }
    t("r-nav-select-no-match") {
        let (w, _, target, _) = makeRealProbe(); defer { w.orderOut(nil) }
        let before = target.text
        if target.selectText("qq-zz") != .noMatch("qq-zz") { return "debió ser noMatch" }
        if target.text != before { return "mutó" }
        return nil
    }
    t("r-nav-select-duplicate") {
        let (w, v, target, _) = makeRealProbe(text: RealFixtureText.duplicates); defer { w.orderOut(nil) }
        v.setSelectedRange(NSRange(location: 0, length: 0))
        guard case .success(.selected(let r)) = target.selectText("TDAH") else { return "select dup falló" }
        if r != (v.string as NSString).range(of: "TDAH") { return "no eligió la primera tras cursor" }
        return nil
    }
    t("r-nav-history-untouched") {
        let (w, _, target, _) = makeRealProbe(); defer { w.orderOut(nil) }
        _ = target.findText("TDAH"); _ = target.selectText("IHC")
        if target.canUndo || target.canRedo { return "navegación tocó historial" }
        return nil
    }
    t("r-nav-immediate-policy") {
        if policyForCommand(.findText("x")) != .immediate { return "find debe ser immediate" }
        if policyForCommand(.selectText("x")) != .immediate { return "select debe ser immediate" }
        let (w, _, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        guard case .autoExecuted(.success(.found)) = e.receive(.findText("TDAH")) else {
            return "find no fue inmediato"
        }
        return nil
    }
    t("r-nav-validator-applies") {
        // find/select pasan por Validator: unsupported/unknown jamás auto-ejecutan.
        let (w, _, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        let before = target.text
        for bad in [ParsedCommand.unsupported("x"), .unknown, .multipleActions] {
            if case .autoExecuted = e.receive(bad) { return "rechazado auto-ejecutó: \(bad)" }
        }
        if target.text != before { return "rechazo mutó" }
        return nil
    }
    t("r-nav-title-history-unchanged") {
        let (w, _, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        let (title, rev) = (target.title, target.revision)
        _ = e.receive(.findText("TDAH")); _ = e.receive(.selectText("IHC"))
        if target.title != title || target.revision != rev { return "nav no debe tocar título/revisión" }
        return nil
    }
    t("r-nav-find-records-query") {
        let (w, _, target, _) = makeRealProbe(); defer { w.orderOut(nil) }
        _ = target.findText("TDAH")
        if target.lastFind != "TDAH" { return "lastFind no registrado" }
        return nil
    }

    // ---- 2. Delete (8) ----
    t("r-del-proposal-clean") {
        let (w, v, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        let before = target.text
        guard case .needsConfirm = e.receive(.deleteSelection) else { return "delete requiere confirm" }
        if target.text != before { return "antes de Enter: 0 mutación" }
        return nil
    }
    t("r-del-confirm") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        guard case .success(.deleted(let removed)) = realConfirm(e, .deleteSelection) else {
            return "delete no ejecutó"
        }
        if removed != "TDAH" { return "removed mal" }
        if v.string.contains("TDAH y accesibilidad cognitiva.") { return "no borró" }
        return nil
    }
    t("r-del-undo-restores") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        let before = v.string
        _ = realConfirm(e, .deleteSelection)
        _ = realConfirm(e, .undo)
        if v.string != before { return "undo no restauró" }
        return nil
    }
    t("r-del-single-undo") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "🧠")
        let before = v.string
        _ = realConfirm(e, .deleteSelection)
        if v.string.contains("🧠") { return "no borró emoji" }
        _ = realConfirm(e, .undo)
        if v.string != before { return "un solo undo debe restaurar" }
        return nil
    }
    t("r-del-no-selection") {
        let (w, _, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        guard case .invalid = e.receive(.deleteSelection) else { return "sin selección debe ser inválido" }
        return nil
    }
    t("r-del-preview-real") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "IHC")
        guard case .needsConfirm(let p) = e.receive(.deleteSelection) else { return "sin proposal" }
        if !p.preview.contains("IHC") { return "preview debe mostrar selectedText: \(p.preview)" }
        return nil
    }
    t("r-del-registers-undo") {
        let (w, v, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        if target.canUndo { return "setup no debe dejar historial" }
        _ = realConfirm(e, .deleteSelection)
        if !target.canUndo { return "delete debe registrar UndoManager" }
        return nil
    }
    t("r-del-redo") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        _ = realConfirm(e, .deleteSelection)
        let deleted = v.string
        _ = realConfirm(e, .undo)
        _ = realConfirm(e, .redo)
        if v.string != deleted { return "redo no re-aplicó" }
        return nil
    }

    // ---- 3. Replace (7) ----
    t("r-rep-proposal-clean") {
        let (w, v, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        let before = target.text
        guard case .needsConfirm = e.receive(.replaceSelection("atención")) else { return "requiere confirm" }
        if target.text != before { return "0 mutación antes de Enter" }
        return nil
    }
    t("r-rep-confirm") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        guard case .success(.replaced(let old, let new)) = realConfirm(e, .replaceSelection("atención")) else {
            return "replace falló"
        }
        if old != "TDAH" || new != "atención" { return "old/new mal" }
        if !v.string.contains("atención") { return "no reemplazó" }
        return nil
    }
    t("r-rep-undo-redo") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        let before = v.string
        _ = realConfirm(e, .replaceSelection("atención"))
        let replaced = v.string
        _ = realConfirm(e, .undo)
        if v.string != before { return "undo no restauró original" }
        _ = realConfirm(e, .redo)
        if v.string != replaced { return "redo no reaplicó" }
        return nil
    }
    t("r-rep-requires-selection") {
        let (w, _, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        guard case .invalid = e.receive(.replaceSelection("x")) else { return "requiere selección" }
        return nil
    }
    t("r-rep-preview") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "IHC")
        guard case .needsConfirm(let p) = e.receive(.replaceSelection("diseño")) else { return "sin proposal" }
        if !(p.preview.contains("IHC") && p.preview.contains("diseño") && p.preview.contains("→")) {
            return "preview old→new mal: \(p.preview)"
        }
        return nil
    }
    t("r-rep-japanese") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "ユーザー")
        let before = v.string
        _ = realConfirm(e, .replaceSelection("interfaz"))
        if !v.string.contains("interfaz") { return "no reemplazó japonés" }
        _ = realConfirm(e, .undo)
        if v.string != before { return "undo japonés falló" }
        return nil
    }
    t("r-rep-single-op") {
        let (w, v, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        let before = v.string
        _ = realConfirm(e, .replaceSelection("atención cognitiva y más texto"))
        _ = realConfirm(e, .undo)
        if v.string != before { return "replace debe ser una sola operación de Undo" }
        if target.canRedo == false { return "redo debería estar disponible" }
        return nil
    }

    // ---- 4. Format (10) ----
    t("r-fmt-bold") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        guard case .success(.formatted(.bold)) = realConfirm(e, .formatSelection(.bold)) else { return "bold falló" }
        if !v.string.contains("**TDAH**") { return "sin marcadores: \(v.string)" }
        return nil
    }
    t("r-fmt-italic") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "IHC")
        _ = realConfirm(e, .formatSelection(.italic))
        if !v.string.contains("*IHC*") { return "italic falló" }
        return nil
    }
    t("r-fmt-underline") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "IHC")
        _ = realConfirm(e, .formatSelection(.underline))
        if !v.string.contains("<u>IHC</u>") { return "underline falló: \(v.string)" }
        return nil
    }
    t("r-fmt-undo-each") {
        for style in [FormatStyle.bold, .italic, .underline] {
            let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
            probeSelect(v, "TDAH")
            _ = realConfirm(e, .formatSelection(style))
            _ = realConfirm(e, .undo)
            if v.string != RealFixtureText.real { return "undo formato falló: \(style)" }
        }
        return nil
    }
    t("r-fmt-requires-selection") {
        let (w, _, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        guard case .invalid = e.receive(.formatSelection(.bold)) else { return "requiere selección" }
        return nil
    }
    t("r-fmt-before-enter-clean") {
        let (w, v, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        let before = target.text
        _ = e.receive(.formatSelection(.bold))
        if target.text != before { return "0 mutación antes de Enter" }
        return nil
    }
    t("r-fmt-toggle") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        _ = realConfirm(e, .formatSelection(.bold))
        probeSelect(v, "TDAH")
        _ = realConfirm(e, .formatSelection(.bold))
        if v.string != RealFixtureText.real { return "toggle unwrap falló" }
        return nil
    }
    t("r-fmt-accented") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "María-José")
        _ = realConfirm(e, .formatSelection(.bold))
        if !v.string.contains("**María-José**") { return "formato con acentos falló" }
        return nil
    }
    t("r-fmt-preview") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        guard case .needsConfirm(let p) = e.receive(.formatSelection(.italic)) else { return "sin proposal" }
        if !(p.preview.contains("TDAH") && p.preview.contains("cursiva")) { return "preview mal: \(p.preview)" }
        return nil
    }
    t("r-fmt-single-undo") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "evaluación")
        let before = v.string
        _ = realConfirm(e, .formatSelection(.bold))
        _ = realConfirm(e, .undo)
        if v.string != before { return "formato debe ser una sola op de Undo" }
        return nil
    }

    // ---- 5. Undo/Redo + C20 (8) ----
    t("r-ur-confirm-policy") {
        for c in [ParsedCommand.undo, .redo, .formatSelection(.bold)] {
            if policyForCommand(c) != .confirm { return "\(c) debe ser confirm" }
        }
        return nil
    }
    t("r-ur-empty-invalid") {
        let (w, _, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        guard case .invalid = e.receive(.undo) else { return "undo vacío inválido" }
        guard case .invalid = e.receive(.redo) else { return "redo vacío inválido" }
        return nil
    }
    t("r-ur-before-enter-clean") {
        let (w, v, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        _ = realConfirm(e, .deleteSelection)
        let before = target.text
        _ = e.receive(.undo)
        if target.text != before { return "undo: 0 mutación antes de Enter" }
        return nil
    }
    t("r-ur-c20-prefixes") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        _ = realConfirm(e, .deleteSelection)
        guard case .needsConfirm(let pu) = e.receive(.undo) else { return "undo sin proposal" }
        if !pu.preview.hasPrefix("↶") || pu.preview.contains("↷") { return "undo ambiguo: \(pu.preview)" }
        _ = e.confirm(pu)
        guard case .needsConfirm(let pr) = e.receive(.redo) else { return "redo sin proposal" }
        if !pr.preview.hasPrefix("↷") || pr.preview.contains("↶") { return "redo ambiguo: \(pr.preview)" }
        return nil
    }
    t("r-ur-c20-manager-label") {
        let (w, _, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        _ = realConfirm(e, .renameTitle("Metodología"))
        guard case .needsConfirm(let p) = e.receive(.undo) else { return "sin proposal" }
        if p.preview != "↶ Deshacer: Renombrar título" { return "C20 etiqueta UndoManager: \(p.preview)" }
        return nil
    }
    t("r-ur-cycle") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "IHC")
        let before = v.string
        _ = realConfirm(e, .replaceSelection("diseño"))
        _ = realConfirm(e, .undo)
        if v.string != before { return "undo no restauró" }
        _ = realConfirm(e, .redo)
        if !v.string.contains("diseño") { return "redo no reaplicó" }
        return nil
    }
    t("r-ur-real-manager") {
        let (w, v, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        _ = realConfirm(e, .deleteSelection)
        if !target.canUndo { return "debe usar UndoManager real" }
        if v.undoManager == nil { return "sin UndoManager" }
        return nil
    }
    t("r-ur-distinct-models") {
        // El modelo de datos distingue undo de redo aunque el texto sea igual.
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        _ = realConfirm(e, .deleteSelection)
        guard case .needsConfirm(let pu) = e.receive(.undo),
              case .needsConfirm(let pr) = e.receive(.redo) else {
            // redo aún inválido (nada que rehacer): también distingue.
            return nil
        }
        if pu.preview == pr.preview { return "previews idénticos" }
        _ = v
        return nil
    }

    // ---- 6. Stale proposal (6) ----
    t("r-stale-selection") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        let before = v.string
        guard case .needsConfirm(let p) = e.receive(.deleteSelection) else { return "sin proposal" }
        probeSelect(v, "IHC") // usuario cambia selección
        if e.confirm(p) != .failure(.staleProposal) { return "debió ser STALE" }
        if v.string != before { return "STALE mutó" }
        return nil
    }
    t("r-stale-text") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        guard case .needsConfirm(let p) = e.receive(.replaceSelection("x")) else { return "sin proposal" }
        v.undoManager?.beginUndoGrouping()
        v.insertText("!", replacementRange: NSRange(location: 0, length: 0))
        v.undoManager?.endUndoGrouping()
        if e.confirm(p) != .failure(.staleProposal) { return "debió ser STALE" }
        if !v.string.contains("TDAH") { return "STALE reemplazó" }
        return nil
    }
    t("r-stale-title") {
        let (w, _, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        guard case .needsConfirm(let p) = e.receive(.renameTitle("A")) else { return "sin proposal" }
        _ = target.renameTitle(to: "Externo")
        if e.confirm(p) != .failure(.staleProposal) { return "debió ser STALE" }
        if target.title != "Externo" { return "STALE cambió título" }
        return nil
    }
    t("r-stale-cancelled") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        let before = v.string
        guard case .needsConfirm(let p) = e.receive(.deleteSelection) else { return "sin proposal" }
        e.cancel()
        if e.confirm(p) != .failure(.staleProposal) { return "proposal cancelada no ejecuta" }
        if v.string != before { return "mutó" }
        return nil
    }
    t("r-stale-revalidate-context") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        let before = v.string
        guard case .needsConfirm(let p) = e.receive(.deleteSelection) else { return "sin proposal" }
        v.setSelectedRange(NSRange(location: 0, length: 0))
        let r = e.confirm(p)
        if r != .invalidContext(.noSelection) { return "revalidación: \(r)" }
        if v.string != before { return "mutó" }
        return nil
    }
    t("r-stale-clears-pending") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        guard case .needsConfirm(let p) = e.receive(.deleteSelection) else { return "sin proposal" }
        v.setSelectedRange(NSRange(location: 0, length: 0))
        _ = e.confirm(p)
        if e.pending != nil { return "pending debe limpiarse" }
        return nil
    }

    // ---- 7. Invariante de confirmación (10) ----
    let mutating: [(String, ParsedCommand, (NSTextView) -> Void)] = [
        ("undo", .undo, { probeSelect($0, "TDAH") }),
        ("redo", .redo, { probeSelect($0, "TDAH") }),
        ("format", .formatSelection(.bold), { probeSelect($0, "TDAH") }),
        ("delete", .deleteSelection, { probeSelect($0, "TDAH") }),
        ("replace", .replaceSelection("x"), { probeSelect($0, "TDAH") }),
        ("rename", .renameTitle("X"), { _ in }),
        ("rewrite", .rewriteSelection("breve"), { probeSelect($0, "TDAH") }),
        ("save", .saveDocument, { _ in }),
        ("open", .openDocument("qq"), { _ in }),
        ("export", .exportDocument(.plainText), { _ in }),
    ]
    for (name, cmd, setup) in mutating {
        t("r-conf-invariant-\(name)") {
            let (w, v, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
            // Prepara historial para undo/redo sin contar como efecto del trial.
            if name == "undo" || name == "redo" {
                probeSelect(v, "TDAH")
                _ = realConfirm(e, .deleteSelection)
                if name == "redo" { _ = realConfirm(e, .undo) }
                v.setSelectedRange(NSRange(location: 0, length: 0))
            } else {
                setup(v)
            }
            let beforeText = target.text
            let beforeTitle = target.title
            let out = e.receive(cmd)
            if target.text != beforeText || target.title != beforeTitle {
                return "\(name): mutó antes de Enter"
            }
            _ = out
            e.cancel()
            if target.text != beforeText { return "\(name): cancel mutó" }
            return nil
        }
    }

    // ---- 8. Rewrite simulado (5) ----
    t("r-rew-captures") {
        let (w, v, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        let sel = v.selectedRange()
        guard case .needsConfirm(let p) = e.receive(.rewriteSelection("más breve")) else { return "sin proposal" }
        guard case .simulated(let req) = e.confirm(p) else { return "debe ser simulated" }
        if req.selectedText != "TDAH" || req.instruction != "más breve" || req.range != sel {
            return "captura incompleta: \(req)"
        }
        if target.simulated != [req] { return "no registrado" }
        return nil
    }
    t("r-rew-no-mutation") {
        let (w, v, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        let before = target.text
        let couldUndo = target.canUndo
        _ = realConfirm(e, .rewriteSelection("formal"))
        if target.text != before { return "rewrite no debe transformar texto" }
        if target.canUndo != couldUndo { return "rewrite no debe tocar UndoManager" }
        _ = v
        return nil
    }
    t("r-rew-preview") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        guard case .needsConfirm(let p) = e.receive(.rewriteSelection("más breve")) else { return "sin proposal" }
        if !(p.preview.contains("más breve") && p.preview.contains("TDAH")) { return "preview mal" }
        return nil
    }
    t("r-rew-requires-selection") {
        let (w, _, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        guard case .invalid = e.receive(.rewriteSelection("x")) else { return "requiere selección" }
        return nil
    }
    t("r-rew-range-real") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "ユーザー")
        guard case .needsConfirm(let p) = e.receive(.rewriteSelection("aclara")) else { return "sin proposal" }
        guard case .simulated(let req) = e.confirm(p) else { return "no simulated" }
        if (v.string as NSString).substring(with: req.range) != "ユーザー" { return "rango irreal" }
        return nil
    }

    // ---- 9. Rename (5) ----
    t("r-ren-preview") {
        let (w, _, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        guard case .needsConfirm(let p) = e.receive(.renameTitle("Metodología")) else { return "sin proposal" }
        if !(p.preview.contains("Proyecto") && p.preview.contains("Metodología") && p.preview.contains("→")) {
            return "preview mal: \(p.preview)"
        }
        return nil
    }
    t("r-ren-confirm") {
        let (w, _, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        guard case .success(.titleChanged(let o, let n)) = realConfirm(e, .renameTitle("Metodología")) else {
            return "rename falló"
        }
        if o != "Proyecto" || n != "Metodología" || target.title != "Metodología" { return "título mal" }
        return nil
    }
    t("r-ren-undo-redo") {
        let (w, _, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        _ = realConfirm(e, .renameTitle("Metodología"))
        _ = realConfirm(e, .undo)
        if target.title != "Proyecto" { return "undo título falló" }
        _ = realConfirm(e, .redo)
        if target.title != "Metodología" { return "redo título falló" }
        return nil
    }
    t("r-ren-text-untouched") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        let before = v.string
        _ = realConfirm(e, .renameTitle("IHC"))
        if v.string != before { return "rename no debe tocar texto" }
        return nil
    }
    t("r-ren-before-enter") {
        let (w, _, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        _ = e.receive(.renameTitle("X"))
        if target.title != "Proyecto" { return "0 mutación antes de Enter" }
        return nil
    }

    // ---- 10. Save/Open/Export (10) ----
    t("r-doc-save") {
        let (w, v, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        guard case .success(.saved(let u)) = realConfirm(e, .saveDocument) else { return "save falló" }
        let disk = try? String(contentsOf: u, encoding: .utf8)
        if disk != v.string { return "save no escribió el texto real" }
        if !u.path.hasPrefix(target.base.path) { return "save fuera de temporales" }
        return nil
    }
    t("r-doc-open") {
        let (w, v, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        let f = target.base.appendingPathComponent("acta-1.md")
        try? "contenido del acta".write(to: f, atomically: true, encoding: .utf8)
        v.string = "borrador distinto"
        guard case .success(.opened(let n)) = realConfirm(e, .openDocument("acta-1")) else { return "open falló" }
        if n != "acta-1" || v.string != "contenido del acta" { return "open no cargó" }
        return nil
    }
    t("r-doc-open-nil") {
        let (w, v, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        let f = target.base.appendingPathComponent("doc-a.md")
        try? "uno".write(to: f, atomically: true, encoding: .utf8)
        _ = realConfirm(e, .openDocument("doc-a"))
        v.string = "modificado"
        _ = realConfirm(e, .openDocument(nil))
        if v.string != "uno" { return "open nil debe reabrir último" }
        return nil
    }
    t("r-doc-open-missing") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        let before = v.string
        guard case .failure(.ioError) = realConfirm(e, .openDocument("no-existe")) else {
            return "open inexistente debe ser ioError"
        }
        if v.string != before { return "open fallido mutó" }
        return nil
    }
    t("r-doc-export-txt") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        guard case .success(.exported(.plainText, let u)) = realConfirm(e, .exportDocument(.plainText)) else {
            return "export txt falló"
        }
        if (try? String(contentsOf: u, encoding: .utf8)) != v.string { return "txt mal" }
        if u.pathExtension != "txt" { return "ext mal" }
        return nil
    }
    t("r-doc-export-rtf") {
        let (w, _, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        guard case .success(.exported(.richText, let u)) = realConfirm(e, .exportDocument(.richText)) else {
            return "export rtf falló"
        }
        let d = try? Data(contentsOf: u)
        if (d?.count ?? 0) == 0 { return "rtf vacío" }
        return nil
    }
    t("r-doc-export-pdf-word-honest") {
        let (w, _, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        if realConfirm(e, .exportDocument(.pdf)) != .failure(.notImplementedInEditor("export pdf")) {
            return "pdf debe ser NOT_IMPLEMENTED"
        }
        if realConfirm(e, .exportDocument(.word)) != .failure(.notImplementedInEditor("export word")) {
            return "word debe ser NOT_IMPLEMENTED"
        }
        return nil
    }
    t("r-doc-no-personal-files") {
        let (w, _, target, _) = makeRealProbe(); defer { w.orderOut(nil) }
        if !target.base.path.hasPrefix(FileManager.default.temporaryDirectory.path) {
            return "base debe ser temporal"
        }
        return nil
    }
    t("r-doc-open-undoable") {
        let (w, v, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        let before = v.string
        let f = target.base.appendingPathComponent("otro.md")
        try? "nuevo".write(to: f, atomically: true, encoding: .utf8)
        _ = realConfirm(e, .openDocument("otro"))
        _ = realConfirm(e, .undo)
        if v.string != before { return "open debe ser deshacible" }
        return nil
    }
    t("r-doc-save-before-enter") {
        let (w, _, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        guard case .needsConfirm = e.receive(.saveDocument) else { return "save requiere confirm" }
        let u = target.base.appendingPathComponent("fixture.md")
        if FileManager.default.fileExists(atPath: u.path) { return "save escribió antes de Enter" }
        return nil
    }

    // ---- 11. Rangos Unicode (8) ----
    t("r-uni-valid-ascii") {
        if RealRanges.validated(NSRange(location: 0, length: 5), in: "hello world") == nil { return "ascii válido" }
        return nil
    }
    t("r-uni-invalid-bounds") {
        if RealRanges.validated(NSRange(location: -1, length: 1), in: "hola") != nil { return "negativo" }
        if RealRanges.validated(NSRange(location: 0, length: 99), in: "hola") != nil { return "overflow" }
        return nil
    }
    t("r-uni-partial-emoji") {
        if RealRanges.validated(NSRange(location: 1, length: 1), in: "a🧠b") != nil {
            return "medio grafema debe ser inválido"
        }
        if RealRanges.validated(NSRange(location: 1, length: 2), in: "a🧠b") == nil {
            return "emoji completo válido"
        }
        return nil
    }
    t("r-uni-zwj") {
        let text = "x👩🏽‍💻y"
        let full = (text as NSString).range(of: "👩🏽‍💻")
        if RealRanges.validated(NSRange(location: full.location, length: 1), in: text) != nil {
            return "ZWJ parcial inválido"
        }
        if RealRanges.validated(full, in: text) == nil { return "ZWJ completo válido" }
        return nil
    }
    t("r-uni-accents-jp") {
        for (text, q) in [("evaluación", "evaluación"), ("María-José", "María-José"),
                          ("ユーザーインターフェース", "ユーザー")] {
            let r = (text as NSString).range(of: q)
            if RealRanges.validated(r, in: text) == nil { return "rango válido rechazado: \(q)" }
        }
        return nil
    }
    t("r-uni-select-jp") {
        let (w, v, target, _) = makeRealProbe(); defer { w.orderOut(nil) }
        guard case .success(.selected(let r)) = target.selectText("ユーザー") else { return "select jp falló" }
        if (v.string as NSString).substring(with: r) != "ユーザー" { return "rango jp mal" }
        return nil
    }
    t("r-uni-delete-emoji-clean") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "🧠")
        let before = v.string
        _ = realConfirm(e, .deleteSelection)
        if v.string.contains("🧠") { return "no borró" }
        if before.utf16.count - v.string.utf16.count != ("🧠" as NSString).length {
            return "borrado parcial de grafema"
        }
        return nil
    }
    t("r-uni-no-corruption-sweep") {
        // Toda operación sobre cada token sensible: sin crash, sin rangos corruptos.
        for q in ["evaluación", "María-José", "🧠", "ユーザー", "7.5%", "ñ"] {
            let (w, v, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
            switch target.selectText(q) {
            case .success(.selected(let r)):
                if RealRanges.validated(r, in: v.string) == nil { return "rango corrupto: \(q)" }
                _ = realConfirm(e, .deleteSelection)
                if Range(NSRange(location: 0, length: v.string.utf16.count), in: v.string) == nil {
                    return "texto corrupto tras borrar \(q)"
                }
            case .noMatch:
                if q != "ñ" { return "debió encontrar: \(q)" }
            default:
                return "resultado inesperado: \(q)"
            }
        }
        return nil
    }

    // ---- 12. Sesión: cancel/repeat/doble-confirm (5) ----
    t("r-ses-cancel") {
        let (w, v, target, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        let before = target.text
        _ = e.receive(.deleteSelection)
        e.cancel()
        if e.pending != nil { return "pending debe limpiarse" }
        if target.text != before { return "cancel mutó" }
        return nil
    }
    t("r-ses-double-confirm") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        guard case .needsConfirm(let p) = e.receive(.deleteSelection) else { return "sin proposal" }
        _ = e.confirm(p)
        let after = v.string
        if e.confirm(p) != .failure(.staleProposal) { return "doble confirm debe fallar" }
        if v.string != after { return "doble confirm duplicó" }
        return nil
    }
    t("r-ses-wrong-proposal-id") {
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        let before = v.string
        _ = e.receive(.deleteSelection)
        probeSelect(v, "IHC")
        _ = e.receive(.deleteSelection)
        // Confirmar la proposal vieja (id distinto) no ejecuta.
        let fake = RealProposal(id: -1, command: .deleteSelection, preview: "", snapshot: e.pending!.snapshot)
        if e.confirm(fake) != .failure(.staleProposal) { return "id viejo debe fallar" }
        if v.string != before { return "mutó" }
        e.cancel()
        return nil
    }
    t("r-ses-effect-kinds") {
        // Cada acción exitosa reporta su efecto real (no Bool).
        let (w, v, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        probeSelect(v, "TDAH")
        guard case .success(.deleted) = realConfirm(e, .deleteSelection) else { return "deleted" }
        guard case .success(.undone) = realConfirm(e, .undo) else { return "undone" }
        guard case .success(.redone) = realConfirm(e, .redo) else { return "redone" }
        guard case .success(.titleChanged) = realConfirm(e, .renameTitle("X")) else { return "titleChanged" }
        _ = v
        return nil
    }
    t("r-ses-auto-log") {
        let (w, _, _, e) = makeRealProbe(); defer { w.orderOut(nil) }
        _ = e.receive(.findText("TDAH"))
        _ = e.receive(.selectText("IHC"))
        if e.autoCount != 2 { return "autoCount debe ser 2" }
        return nil
    }

    return (count - fails.count, fails, count)
}

@MainActor func runRealEditorTestsPrinter() {
    let (p, f, n) = runRealEditorTests()
    print("real-editor-tests: \(p)/\(n)")
    for x in f { print("FAIL \(x.name): \(x.detail)") }
    if f.isEmpty { print("REAL-EDITOR-INVARIANTS-OK") }
}
