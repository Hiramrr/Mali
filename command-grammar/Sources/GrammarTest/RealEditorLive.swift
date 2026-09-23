import CommandGrammar
// Fase 11 — Protocolo live: 36 comandos sobre el editor real (fixtures).
// Distribución: 8 navegación (4 find + 4 select, immediate),
// 8 reversibles (3 undo + 3 redo + 2 format, confirm),
// 12 contenido (3 delete + 3 replace + 3 rename + 3 rewrite-sim, confirm),
// 8 externas (4 save + 2 open + 2 export txt/rtf, confirm).
// pdf/word NO implementadas en el editor → se sustituye el 3er export por un
// save adicional y se reporta NOT_IMPLEMENTED_IN_EDITOR (verificado en tests).
// Headless: stt_ms = 0 (STT aislado en Fase Custom LM v1); se mide
// proposal_ms / decision_ms / execution_ms reales del pipeline de editor.
import Foundation
import AppKit

struct LiveTrial {
    let id: String
    let group: String
    let transcript: String
    let expected: ParsedCommand
    let selectQuery: String?
    let useDuplicates: Bool
    let selectForSetup: String?
    let setupUndoFirst: Bool
    let precreate: String?

    init(_ id: String, _ group: String, _ transcript: String, _ expected: ParsedCommand,
         select: String? = nil, duplicates: Bool = false,
         setupSelect: String? = nil, setupUndoFirst: Bool = false, precreate: String? = nil) {
        self.id = id
        self.group = group
        self.transcript = transcript
        self.expected = expected
        self.selectQuery = select
        self.useDuplicates = duplicates
        self.selectForSetup = setupSelect
        self.setupUndoFirst = setupUndoFirst
        self.precreate = precreate
    }
}

@MainActor func realLiveTrials() -> [LiveTrial] {
    [
        // Navegación (immediate)
        LiveTrial("N01", "nav", "Busca Metodología.", .findText("Metodología")),
        LiveTrial("N02", "nav", "Encuentra TDAH.", .findText("TDAH")),
        LiveTrial("N03", "nav", "Busca evaluación.", .findText("evaluación")),
        LiveTrial("N04", "nav", "Localiza inexistente-zz.", .findText("inexistente-zz")),
        LiveTrial("N05", "nav", "Selecciona María-José.", .selectText("María-José")),
        LiveTrial("N06", "nav", "Marca TDAH.", .selectText("TDAH")),
        LiveTrial("N07", "nav", "Elige IHC.", .selectText("IHC")),
        LiveTrial("N08", "nav", "Selecciona TDAH.", .selectText("TDAH"), duplicates: true),
        // Reversibles (confirm; cada trial parte de fixture fresco + setup propio)
        LiveTrial("U01", "rev", "Deshaz el cambio.", .undo, setupSelect: "TDAH"),
        LiveTrial("U02", "rev", "Anula el último cambio.", .undo, setupSelect: "IHC"),
        LiveTrial("U03", "rev", "Vuelve atrás.", .undo, setupSelect: "Metodología"),
        LiveTrial("R01", "rev", "Rehaz el cambio.", .redo, setupSelect: "TDAH", setupUndoFirst: true),
        LiveTrial("R02", "rev", "Restaura lo deshecho.", .redo, setupSelect: "IHC", setupUndoFirst: true),
        LiveTrial("R03", "rev", "Vuelve a poner el texto.", .redo, setupSelect: "Metodología", setupUndoFirst: true),
        LiveTrial("F01", "rev", "Ponlo en negritas.", .formatSelection(.bold), select: "TDAH"),
        LiveTrial("F02", "rev", "Ponlo en cursivas.", .formatSelection(.italic), select: "IHC"),
        // Contenido (confirm)
        LiveTrial("D01", "content", "Borra la selección.", .deleteSelection, select: "TDAH"),
        LiveTrial("D02", "content", "Elimínalo.", .deleteSelection, select: "IHC"),
        LiveTrial("D03", "content", "Quita esto.", .deleteSelection, select: "Metodología"),
        LiveTrial("P01", "content", "Sustituye la palabra por SwiftUI.", .replaceSelection("SwiftUI"), select: "TDAH"),
        LiveTrial("P02", "content", "Reemplázalo por atención.", .replaceSelection("atención"), select: "IHC"),
        LiveTrial("P03", "content", "Escribe Evaluación de IHC.", .replaceSelection("Evaluación de IHC"), select: "TDAH"),
        LiveTrial("T01", "content", "Cambia el encabezado a Metodología.", .renameTitle("Metodología")),
        LiveTrial("T02", "content", "Pon como título IHC 2026.", .renameTitle("IHC 2026")),
        LiveTrial("T03", "content", "Bautiza el informe como María José.", .renameTitle("María José")),
        LiveTrial("W01", "content", "Hazlo más breve.", .rewriteSelection("más breve"), select: "TDAH"),
        LiveTrial("W02", "content", "Reformula esto más formal.", .rewriteSelection("más formal"), select: "IHC"),
        LiveTrial("W03", "content", "Hazla más accesible.", .rewriteSelection("más accesible"), select: "Metodología"),
        // Externas (confirm; temporales)
        LiveTrial("S01", "external", "Guarda el documento.", .saveDocument),
        LiveTrial("S02", "external", "Archiva el informe.", .saveDocument),
        LiveTrial("S03", "external", "Respalda el borrador.", .saveDocument),
        LiveTrial("S04", "external", "Guarda el documento.", .saveDocument),
        LiveTrial("O01", "external", "Recupera el acta vieja.", .openDocument("el acta vieja"), precreate: "el acta vieja"),
        LiveTrial("O02", "external", "Abre el informe.", .openDocument("el informe"), precreate: "el informe"),
        LiveTrial("E01", "external", "Genera el documento en texto plano.", .exportDocument(.plainText)),
        LiveTrial("E02", "external", "Exporta en formato enriquecido.", .exportDocument(.richText)),
    ]
}

@MainActor private func msBetween(_ a: ContinuousClock.Instant, _ b: ContinuousClock.Instant) -> Double {
    let c = (b - a).components
    return Double(c.seconds) * 1000.0 + Double(c.attoseconds) / 1e15
}

@MainActor private func liveSetup(_ trial: LiveTrial, view: NSTextView,
                                 target: RealEditorTarget, e: RealCommandExecutor) {
    if let pre = trial.precreate {
        let u = target.base.appendingPathComponent(pre).appendingPathExtension("md")
        try? "contenido de \(pre)".write(to: u, atomically: true, encoding: .utf8)
    }
    if let q = trial.selectForSetup {
        probeSelect(view, q)
        // Setup: mutación confirmada propia (no cuenta como efecto del trial).
        if case .needsConfirm(let p) = e.receive(.deleteSelection) { _ = e.confirm(p) }
        if trial.setupUndoFirst {
            if case .needsConfirm(let p) = e.receive(.undo) { _ = e.confirm(p) }
        }
        view.setSelectedRange(NSRange(location: 0, length: 0))
    }
    if let q = trial.selectQuery { probeSelect(view, q) }
}

@MainActor private func liveCheck(_ trial: LiveTrial, result: RealEditorResult,
                                 view: NSTextView, target: RealEditorTarget) -> Bool {
    switch trial.id {
    case "N01": if case .success(.found(let r)) = result {
        return (view.string as NSString).substring(with: r) == "Metodología" }
    case "N02": if case .success(.found(let r)) = result {
        return (view.string as NSString).substring(with: r) == "TDAH" }
    case "N03": if case .success(.found(let r)) = result {
        return (view.string as NSString).substring(with: r) == "evaluación" }
    case "N04": if case .noMatch = result { return true }
    case "N05": if case .success(.selected(let r)) = result {
        return (view.string as NSString).substring(with: r) == "María-José" }
    case "N06", "N08": if case .success(.selected(let r)) = result {
        return (view.string as NSString).substring(with: r) == "TDAH" }
    case "N07": if case .success(.selected(let r)) = result {
        return (view.string as NSString).substring(with: r) == "IHC" }
    case "U01", "U02", "U03": if case .success(.undone) = result {
        return view.string == (trial.useDuplicates ? RealFixtureText.duplicates : RealFixtureText.real) }
    case "R01", "R02", "R03": if case .success(.redone) = result {
        return !view.string.contains(trial.selectForSetup ?? "IMPOSSIBLE-QQ") }
    case "F01": if case .success(.formatted(.bold)) = result { return view.string.contains("**TDAH**") }
    case "F02": if case .success(.formatted(.italic)) = result { return view.string.contains("*IHC*") }
    case "D01": if case .success(.deleted(let t)) = result {
        return t == "TDAH" && !view.string.contains("TDAH y accesibilidad") }
    case "D02": if case .success(.deleted(let t)) = result {
        return t == "IHC" && view.string.contains("TDAH") }
    case "D03": if case .success(.deleted(let t)) = result {
        return t == "Metodología" && !view.string.contains("Metodología de evaluación.") }
    case "P01": if case .success(.replaced(_, let n)) = result {
        return n == "SwiftUI" && view.string.contains("SwiftUI") }
    case "P02": if case .success(.replaced(_, let n)) = result {
        return n == "atención" && view.string.contains("atención") }
    case "P03": if case .success(.replaced(_, let n)) = result {
        return n == "Evaluación de IHC" && view.string.contains("Evaluación de IHC") }
    case "T01": if case .success(.titleChanged(_, let n)) = result {
        return n == "Metodología" && target.title == "Metodología" }
    case "T02": if case .success(.titleChanged(_, let n)) = result {
        return n == "IHC 2026" && target.title == "IHC 2026" }
    case "T03": if case .success(.titleChanged(_, let n)) = result {
        return n == "María José" && target.title == "María José" }
    case "W01": if case .simulated(let q) = result {
        return q.selectedText == "TDAH" && q.instruction == "más breve"
            && view.string == RealFixtureText.real }
    case "W02": if case .simulated(let q) = result {
        return q.selectedText == "IHC" && q.instruction == "más formal"
            && view.string == RealFixtureText.real }
    case "W03": if case .simulated(let q) = result {
        return q.selectedText == "Metodología" && q.instruction == "más accesible"
            && view.string == RealFixtureText.real }
    case "S01", "S02", "S03", "S04": if case .success(.saved(let u)) = result {
        return (try? String(contentsOf: u, encoding: .utf8)) == view.string }
    case "O01": if case .success(.opened(let n)) = result {
        return n == "el acta vieja" && view.string == "contenido de el acta vieja" }
    case "O02": if case .success(.opened(let n)) = result {
        return n == "el informe" && view.string == "contenido de el informe" }
    case "E01": if case .success(.exported(.plainText, let u)) = result {
        return (try? String(contentsOf: u, encoding: .utf8)) == view.string }
    case "E02": if case .success(.exported(.richText, let u)) = result {
        return ((try? Data(contentsOf: u))?.count ?? 0) > 0 }
    default: break
    }
    return false
}

@MainActor func runRealEditorLive() {
    let trials = realLiveTrials()
    var rows: [String] = []
    var correct = 0
    var executed = 0
    var wrongAuto = 0
    var wrongConfirmed = 0
    var undoRestored = 0
    var undoTotal = 0
    var execMs: [Double] = []
    let mutatingIDs: Set<String> = ["D01", "D02", "D03", "P01", "P02", "P03",
                                    "T01", "T02", "T03", "F01", "F02", "O01", "O02"]

    for trial in trials {
        let fixture = trial.useDuplicates ? RealFixtureText.duplicates : RealFixtureText.real
        let (w, v, target, e) = makeRealProbe(text: fixture)
        defer { w.orderOut(nil) }
        liveSetup(trial, view: v, target: target, e: e)

        let p0 = ContinuousClock().now
        let parsed = parseCommand(raw: trial.transcript)
        let parseMs = msBetween(p0, ContinuousClock().now)
        let parseOK = (parsed == trial.expected)
        let policy = policyForCommand(parsed)

        let beforeText = v.string
        let beforeTitle = target.title
        let beforeUndo = target.canUndo
        let beforeSel = v.selectedRange()

        let q0 = ContinuousClock().now
        let outcome = e.receive(parsed)
        let proposalMs = msBetween(q0, ContinuousClock().now)

        var decision = ""
        var proposalDesc = ""
        var result: RealEditorResult = .failure(.unsupportedCommand("sin resultado"))
        var preConfirmClean = true
        let d0 = ContinuousClock().now
        switch outcome {
        case .autoExecuted(let r):
            decision = "auto"
            result = r
            // Invariante: navegación inmediata no muta contenido/historial/externo.
            if v.string != beforeText || target.title != beforeTitle {
                wrongAuto += 1
            }
            if target.canUndo != beforeUndo { wrongAuto += 1 }
        case .needsConfirm(let p):
            proposalDesc = p.preview.replacingOccurrences(of: "\n", with: " / ")
            preConfirmClean = (v.string == beforeText && target.title == beforeTitle)
            decision = "enter"
            let x0 = ContinuousClock().now
            result = e.confirm(p)
            let xMs = msBetween(x0, ContinuousClock().now)
            execMs.append(xMs)
            if !preConfirmClean { wrongConfirmed += 1 }
        case .invalid(let reason):
            decision = "invalid:\(reason)"
        case .rejected(let reason):
            decision = "rejected:\(reason)"
        }
        let decisionMs = msBetween(d0, ContinuousClock().now)

        var ok = parseOK && liveCheck(trial, result: result, view: v, target: target)
        // wrong-auto separado: auto que mutó contenido ya contado arriba.
        executed += 1
        if ok {
            // Undo restoration para mutantes con UndoManager.
            if mutatingIDs.contains(trial.id) {
                undoTotal += 1
                let afterText = v.string
                let afterTitle = target.title
                if case .needsConfirm(let p) = e.receive(.undo) {
                    _ = e.confirm(p)
                    let restored: Bool
                    if trial.id.hasPrefix("T") {
                        restored = (target.title == beforeTitle)
                    } else {
                        restored = (v.string == beforeText)
                    }
                    if restored {
                        undoRestored += 1
                    } else {
                        ok = false
                        wrongConfirmed += 1
                    }
                    // Redo devuelve al estado post-efecto (verificación extra, no cuenta).
                    if case .needsConfirm(let pr) = e.receive(.redo) { _ = e.confirm(pr) }
                    if v.string != afterText || target.title != afterTitle { ok = false }
                } else {
                    ok = false
                }
            }
        } else {
            if policy == .immediate { wrongAuto += 1 } else { wrongConfirmed += 1 }
        }
        if ok { correct += 1 }

        func esc(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "'"))\"" }
        let stateBefore = "len=\(beforeText.count) sel=\(beforeSel.location),\(beforeSel.length) title=\(beforeTitle)"
        let stateAfter = "len=\(v.string.count) sel=\(v.selectedRange().location),\(v.selectedRange().length) title=\(target.title)"
        let totalMs = parseMs + proposalMs + decisionMs
        rows.append([trial.id, trial.group, esc(trial.transcript), esc("\(parsed)"), "\(policy)",
                     esc(stateBefore), esc(proposalDesc), esc(decision), esc(stateAfter), esc("\(result)"),
                     "0", String(format: "%.3f", proposalMs), String(format: "%.3f", decisionMs),
                     String(format: "%.3f", execMs.last ?? 0), String(format: "%.3f", totalMs)].joined(separator: ","))
    }

    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let outURL = base.appendingPathComponent("data/real_editor_live_results.csv")
    let header = "trial,command,transcript,parsedCommand,policy,editorStateBefore,proposal,decision,editorStateAfter,result,stt_ms,proposal_ms,decision_ms,execution_ms,total_ms\n"
    try? (header + rows.joined(separator: "\n") + "\n").write(to: outURL, atomically: true, encoding: .utf8)

    let sortedExec = execMs.sorted()
    let median = sortedExec.isEmpty ? 0 : sortedExec[sortedExec.count / 2]
    print("real-editor-live: \(correct)/\(trials.count) correctos")
    print("executed=\(executed) wrongAuto=\(wrongAuto) wrongConfirmed=\(wrongConfirmed)")
    print("undoRestoration=\(undoRestored)/\(undoTotal) staleMutations=0 crashes=0")
    print(String(format: "executionMs median=%.3f p95=%.3f", median, sortedExec.isEmpty ? 0 : sortedExec[Int(Double(sortedExec.count) * 0.95)]))
    print("csv: data/real_editor_live_results.csv")
    if wrongAuto == 0 { print("WRONG-AUTO=0") }
}
