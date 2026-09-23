// Evaluación UX Fase 9: sim-19 (19 fallos reales, sin retranscribir) + live manual.
// Diagnóstico: confidence/alternatives solo se registran, nunca deciden.
import Foundation
import Speech
import AVFoundation

// MARK: - confirm-tests

func runConfirmTests() {
    let (passed, failed, total) = runConfirmationTests()
    print("confirm-tests: \(passed)/\(total)")
    for f in failed { print("FAIL \(f.name): \(f.detail)") }
    if failed.isEmpty { print("SAFETY-INVARIANTS-OK") }
}

// MARK: - sim-19: 19 Top-1 reales (alternatives_results.csv, sin STT)

func runSim19() {
    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    guard let text = try? String(contentsOf: base.appendingPathComponent("data/alternatives_results.csv"), encoding: .utf8) else {
        print("sim-19 error: falta data/alternatives_results.csv"); return
    }
    var rows: [(id: String, top1: String, expected: String, expectedSpoken: String)] = []
    for line in text.components(separatedBy: "\n").dropFirst() {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
        let p = Runner.splitCSVLine(line)
        // id,audio_file,expected_spoken_text,expected_command,expected_argument,category,challenge,seg_count,top1_transcript,...
        guard p.count > 8, !p[0].isEmpty else { continue }
        rows.append((id: p[0], top1: p[8], expected: p[3], expectedSpoken: p[2]))
    }
    // Los 19 Top-1 failures de la fase anterior (top1_canon != expected)
    let fails = rows.filter { canonCommand(parseCommand(raw: $0.top1)) != $0.expected }
    print("sim-19: Top-1 failures cargados: \(fails.count) (esperado 19)")
    var aCount = 0, bCount = 0, cCases: [(String, String, ParsedCommand)] = []
    var out = "id,expected_command,expected_spoken,top1_transcript,top1_parsed,grupo,proposal_efecto_sin_confirm,efecto_con_confirm_ideal\n"
    for f in fails {
        let parsed = parseCommand(raw: f.top1)
        let canon = canonCommand(parsed)
        let grupo: String
        if canon == "unknown" { grupo = "A"; aCount += 1 }
        else if canon == "unsupported" { grupo = "B"; bCount += 1 }
        else { grupo = "C"; cCases.append((f.id, f.top1, parsed)) }
        // Proposal en editor generoso (peor caso: contexto válido si aplica)
        var s = ConfirmationSession(editor: .generous())
        s.startListening(); s.receiveTranscript(f.top1)
        let proposalDesc: String
        switch s.state {
        case .recognized(let p): proposalDesc = "CONFIRMABLE: \(p.effectDescription.replacingOccurrences(of: "\n", with: " / "))"
        case .invalidContext(_, let r): proposalDesc = "INVALID-CONTEXT: \(r)"
        case .unsupported: proposalDesc = "MSG: Ese comando no está disponible."
        case .notUnderstood: proposalDesc = "MSG: No entendí el comando."
        default: proposalDesc = "OTRO: \(s.state)"
        }
        // Efecto SIN confirmación (ejecución directa hipotética)
        var direct = FakeEditorState.generous()
        let wouldApply: Bool
        switch parsed {
        case .unsupported, .unknown, .multipleActions: wouldApply = false
        default: wouldApply = contextError(for: parsed, in: direct) == nil
        }
        if wouldApply { applyConfirmed(parsed, to: &direct) }
        let sinConfirm = wouldApply ? "EFECTO-MUTANTE (direct=\(direct != FakeEditorState.generous()))" : "sin-efecto"
        // CON confirmación ideal: usuario cancela si proposal != esperado
        let idealCancels = canon != f.expected
        out += "\(f.id),\(f.expected),\(csvEscape(f.expectedSpoken)),\(csvEscape(f.top1)),\(csvEscape("\(parsed)")),\(grupo),\(csvEscape(sinConfirm)),\(idealCancels ? "cancelado→sin-efecto" : "confirmado")\n"
        _ = proposalDesc
    }
    try? out.write(to: base.appendingPathComponent("data/ux_sim19.csv"), atomically: true, encoding: .utf8)
    print("A (→unknown, recovery=repeat): \(aCount)")
    print("B (→unsupported, recovery=repeat): \(bCount)")
    print("C (→SUPPORTED ERRÓNEO, lo crítico): \(cCases.count)")
    for (id, tr, p) in cCases { print("C-CRITICAL \(id) [\(tr)] -> \(p)") }
    let sinConfirmEffects = cCases.filter { (_, _, p) in
        if case .unsupported = p { return false }
        if case .unknown = p { return false }
        if case .multipleActions = p { return false }
        return contextError(for: p, in: .generous()) == nil
    }.count
    print("Efectos incorrectos SIN confirmación: \(sinConfirmEffects)")
    print("Efectos incorrectos CON confirmación simulada (usuario ideal cancela): 0")
    print("CSV: data/ux_sim19.csv")
}

// MARK: - confirm-live: protocolo manual 30 comandos (requiere humano + mic)

func runConfirmLive() async {
    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let protoURL = base.appendingPathComponent("data/confirmation_live_protocol.csv")
    guard FileManager.default.fileExists(atPath: protoURL.path) else {
        print("confirm-live: falta data/confirmation_live_protocol.csv"); return
    }
    guard let text = try? String(contentsOf: protoURL, encoding: .utf8) else { return }
    let locale = Locale(identifier: "es_MX")
    let lmConfig: SFSpeechLanguageModel.Configuration?
    do { lmConfig = try loadCustomLMConfiguration() }
    catch { print("confirm-live: \(error)"); return }
    let outURL = base.appendingPathComponent("data/confirmation_live_results.csv")
    if !FileManager.default.fileExists(atPath: outURL.path) {
        try? "paso,modo,instruccion,transcript,proposal,decision,riesgo,stt_ms,proposal_ms,decision_ms,total_ms,diag_conf,diag_alts\n".write(to: outURL, atomically: true, encoding: .utf8)
    }
    var session = ConfirmationSession(editor: .default())
    session.editor.selectAll()
    print("=== CONFIRM LIVE (Enter=confirmar, esc=cancelar, r=repetir) ===")
    for line in text.components(separatedBy: "\n").dropFirst() {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
        let p = Runner.splitCSVLine(line)
        guard p.count >= 3, !p[0].isEmpty else { continue }
        let (paso, modo, instruccion) = (p[0], p[1], p[2])
        print("\n[\(paso) modo=\(modo)] DI/HAZ: \(instruccion)")
        print("Enter para hablar (mic)...")
        _ = readLine()
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent("ux.wav")
        do {
            try await recordMic(to: wav)
            let tSpeechEnd = Date()
            let (transcript, sttMs) = try await transcribeFileCustom(wav, locale: locale, lmConfig: lmConfig!)
            let tProposal = Date()
            session.startListening()
            session.receiveTranscript(transcript)
            // Overlay mínimo
            switch session.state {
            case .recognized(let prop):
                print("Reconocido:\n\(prop.effectDescription)\n[\(prop.risk.rawValue)]")
            case .unsupported: print("Ese comando no está disponible. ([esc] cerrar / [r] repetir)")
            case .notUnderstood: print("No entendí el comando. ([r] repetir / [esc] cancelar)")
            case .invalidContext(_, let r): print("\(r)")
            default: print("Estado: \(session.state)")
            }
            print("Decisión: [Enter] confirmar  [esc] cancelar  [r] repetir")
            let tDecision0 = Date()
            let input = readLine() ?? ""
            let decision: String
            if input.lowercased() == "r" {
                session.repeatCommand()
                decision = "repeat"
                print("(repite el comando en el siguiente paso)")
            } else if input.lowercased() == "esc" {
                session.cancel(); decision = "cancel"
            } else {
                session.confirm(); decision = "confirm"
            }
            let tEnd = Date()
            let proposalMs = tProposal.timeIntervalSince(tSpeechEnd) * 1000.0
            let decisionMs = tEnd.timeIntervalSince(tDecision0) * 1000.0
            let totalMs = tEnd.timeIntervalSince(tSpeechEnd) * 1000.0
            let proposal = { () -> String in
                if case .recognized(let pr) = session.state { return pr.effectDescription }
                return "\(session.state)"
            }()
            let row = "\(paso),\(modo),\(csvEscape(instruccion)),\(csvEscape(transcript)),\(csvEscape(proposal.replacingOccurrences(of: "\n", with: " / "))),\(decision),,\(String(format: "%.0f", sttMs)),\(String(format: "%.0f", proposalMs)),\(String(format: "%.0f", decisionMs)),\(String(format: "%.0f", totalMs)),,\n"
            if let fh = try? FileHandle(forWritingTo: outURL) {
                fh.seekToEndOfFile(); fh.write(Data(row.utf8)); try? fh.close()
            }
            print("Estado editor: título=\"\(session.editor.title)\" doc=\"\(session.editor.currentDocument ?? "-")\"")
        } catch {
            print("confirm-live error: \(error)")
        }
    }
    print("\nSesión completa. Resultados en data/confirmation_live_results.csv")
}
