// Fase 10 evaluación: sim-19-risk + risk-live (40). Sin retranscribir.
import Foundation
import Speech
import AVFoundation

func runRiskTestsPrinter() {
    let (passed, failed, total) = runRiskTests()
    print("risk-tests: \(passed)/\(total)")
    for f in failed { print("FAIL \(f.name): \(f.detail)") }
    if failed.isEmpty { print("RISK-INVARIANTS-OK") }
}

// MARK: - sim-19-risk: ¿qué habría hecho RISK-BASED con los 19 fallos reales?

func runSim19Risk() {
    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    guard let text = try? String(contentsOf: base.appendingPathComponent("data/alternatives_results.csv"), encoding: .utf8) else {
        print("sim-19-risk error: falta data/alternatives_results.csv"); return
    }
    var fails: [(id: String, top1: String, expected: String)] = []
    for line in text.components(separatedBy: "\n").dropFirst() {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
        let p = Runner.splitCSVLine(line)
        guard p.count > 8, !p[0].isEmpty else { continue }
        if canonCommand(parseCommand(raw: p[8])) != p[3] {
            fails.append((id: p[0], top1: p[8], expected: p[3]))
        }
    }
    print("sim-19-risk: failures: \(fails.count) (esperado 19)")
    var noEffect = 0, safeImm = 0, wrongImm = 0, confirmable = 0
    var out = "id,expected,top1_transcript,parsed,risk,policy,auto_execute,modifies_content,clase\n"
    for f in fails {
        let cmd = parseCommand(raw: f.top1)
        let canon = canonCommand(cmd)
        let risk = riskOf(cmd)
        let wouldAuto: Bool
        let modifies: Bool
        var clase: String
        switch cmd {
        case .unsupported, .unknown, .multipleActions:
            wouldAuto = false; modifies = false; clase = "NO EFFECT"; noEffect += 1
        default:
            if contextError(for: cmd, in: .generous()) != nil {
                wouldAuto = false; modifies = false; clase = "NO EFFECT"; noEffect += 1
            } else if policyForCommand(cmd) == .immediate {
                wouldAuto = true
                switch cmd {
                case .findText, .selectText: modifies = false
                default: modifies = true // undo/redo/format: reversible pero mutan
                }
                // wrong por construcción (es un Top-1 failure); inmediato+reversible = SAFE
                clase = "SAFE IMMEDIATE"; safeImm += 1
                // ¿podría ser WRONG IMMEDIATE? Solo si inmediato + irreversible. No existe tal caso.
                if modifies && (risk == .contentChanging || risk == .externalSideEffect) {
                    clase = "WRONG IMMEDIATE EFFECT"; wrongImm += 1; safeImm -= 1
                }
            } else {
                wouldAuto = false
                modifies = true; clase = "CONFIRMABLE WRONG EFFECT"; confirmable += 1
            }
        }
        if f.id == "V173" {
            print("V173: parsed=\(cmd) risk=\(risk.rawValue) policy=\(policyForCommand(cmd).rawValue) auto=\(wouldAuto) → delete es contentChanging, SIGUE requiriendo confirmación ✓")
        }
        out += "\(f.id),\(f.expected),\(csvEscape(f.top1)),\(csvEscape("\(cmd)")),\(risk.rawValue),\(policyForCommand(cmd).rawValue),\(wouldAuto ? 1 : 0),\(modifies ? 1 : 0),\(clase)\n"
        _ = canon
    }
    try? out.write(to: base.appendingPathComponent("data/ux_risk_sim19.csv"), atomically: true, encoding: .utf8)
    print("NO EFFECT: \(noEffect)")
    print("SAFE IMMEDIATE: \(safeImm)")
    print("WRONG IMMEDIATE EFFECT: \(wrongImm) (objetivo 0)")
    print("CONFIRMABLE WRONG EFFECT: \(confirmable)")
    print("CSV: data/ux_risk_sim19.csv")
}

// MARK: - balanced-live: 48 trials con fixture fresco por trial (sin estado persistente)

func fixtureKindFor(expected: String) -> FixtureKind {
    switch expected {
    case "findText", "selectText": return .navigation
    case "undo": return .undo
    case "redo": return .redo
    case "formatSelection": return .format
    case "renameTitle": return .rename
    case "deleteSelection": return .delete
    case "replaceSelection": return .replace
    case "rewriteSelection": return .rewrite
    default: return .external
    }
}

func runBalancedLive() async {
    await runBalancedLive(protoFile: "data/balanced_live_protocol.csv",
                          outFile: "data/balanced_live_results.csv",
                          title: "BALANCED LIVE")
}

func runSafeAutoLive() async {
    await runBalancedLive(protoFile: "data/safeauto_live_protocol.csv",
                          outFile: "data/safeauto_live_results.csv",
                          title: "SAFEAUTO LIVE")
}

func runBalancedLive(protoFile: String, outFile: String, title: String) async {
    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let protoURL = base.appendingPathComponent(protoFile)
    guard FileManager.default.fileExists(atPath: protoURL.path) else {
        print("\(title): falta \(protoFile)"); return
    }
    guard let text = try? String(contentsOf: protoURL, encoding: .utf8) else { return }
    let locale = Locale(identifier: "es_MX")
    let lmConfig: SFSpeechLanguageModel.Configuration?
    do { lmConfig = try loadCustomLMConfiguration() }
    catch { print("balanced-live: \(error)"); return }
    let outURL = base.appendingPathComponent(outFile)
    if !FileManager.default.fileExists(atPath: outURL.path) {
        try? "paso,grupo,instruccion,expected,fixture,speech_start,speech_end,transcript_final,proposal_shown,decision,action_completed,command,risk,policy,context_valid_before,auto_executed,confirmed,repeated,effect_correct,stt_ms,proposal_generation_ms,decision_ms,execution_ms,total_ms\n".write(to: outURL, atomically: true, encoding: .utf8)
    }
    let iso: (Date) -> String = { d in
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }
    var idx = 0
    print("=== \(title) (fixture fresco por trial; auto=sin Enter; confirm=Enter; esc; r) ===")
    for line in text.components(separatedBy: "\n").dropFirst() {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
        let p = Runner.splitCSVLine(line)
        guard p.count >= 4, !p[0].isEmpty else { continue }
        let (paso, grupo, instruccion, expected) = (p[0], p[1], p[2], p[3])
        // Estado independiente por trial
        var session = RiskBasedSession(editor: fixture(for: fixtureKindFor(expected: expected), index: idx))
        idx += 1
        let (ready, msg) = fixturePreconditions(for: fixtureKindFor(expected: expected), expected: expected, editor: session.editor)
        print("\n[\(paso) \(grupo)] DI/HAZ: \(instruccion)")
        print(msg)
        guard ready else { continue } // NO contar como fallo del sistema de voz
        print("Enter para hablar (mic)...")
        _ = readLine()
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent("balanced.wav")
        do {
            let tSpeechStart = Date()
            try await recordMic(to: wav)
            let tSpeechEnd = Date()
            let (transcript, sttMs) = try await transcribeFileCustom(wav, locale: locale, lmConfig: lmConfig!)
            let tProp0 = Date()
            session.startListening()
            session.receiveTranscript(transcript)
            let tProp1 = Date()
            let proposalGenMs = tProp1.timeIntervalSince(tProp0) * 1000.0
            let parsedNow = parseCommand(raw: transcript)
            let ctxValid = contextError(for: parsedNow, in: session.editor) == nil
            // Nota: receiveTranscript ya validó con el fixture; ctxValid se registra tal cual.
            let shown: String
            let cmdStr: String
            let riskStr: String
            let polStr: String
            var auto = false
            switch session.state {
            case .executed(let prop) where policyForCommand(prop.command) == .immediate:
                auto = true
                shown = session.feedback() ?? "✓ Listo"
                print("\(shown) (auto, sin Enter)")
                cmdStr = "\(prop.command)"; riskStr = prop.risk.rawValue; polStr = "immediate"
            case .recognized(let prop):
                print("Reconocido:\n\(prop.effectDescription)\n[\(prop.risk.rawValue)]")
                print("Decisión: [Enter] confirmar  [esc] cancelar  [r] repetir")
                shown = prop.effectDescription.replacingOccurrences(of: "\n", with: " / ")
                cmdStr = "\(prop.command)"; riskStr = prop.risk.rawValue; polStr = "confirm"
            case .unsupported: print("Ese comando no está disponible. ([esc] cerrar / [r] repetir)"); shown = "Ese comando no está disponible."; cmdStr = "unsupported"; riskStr = ""; polStr = ""
            case .notUnderstood: print("No entendí el comando. ([r] repetir / [esc] cancelar)"); shown = "No entendí el comando."; cmdStr = "unknown"; riskStr = ""; polStr = ""
            case .invalidContext(_, let r): print("\(r) ([r] repetir / [esc] cerrar)"); shown = r; cmdStr = "invalidContext"; riskStr = ""; polStr = ""
            default: print("Estado: \(session.state)"); shown = "\(session.state)"; cmdStr = ""; riskStr = ""; polStr = ""
            }
            var decision = "auto"
            var decisionMs = 0.0
            var executionMs = 0.0
            if !auto {
                let tD0 = Date()
                let input = readLine() ?? ""
                let tE0 = Date()
                if input.lowercased() == "r" { session.repeatCommand(); decision = "repeat" }
                else if input.lowercased() == "esc" { session.cancel(); decision = "cancel" }
                else { session.confirm(); decision = "confirm" }
                let tEnd = Date()
                decisionMs = tEnd.timeIntervalSince(tD0) * 1000.0
                executionMs = tEnd.timeIntervalSince(tE0) * 1000.0
                let completed: String
                switch session.state {
                case .executed: completed = "executed"
                case .cancelled: completed = "cancelled"
                case .listening: completed = "listening-repeat"
                default: completed = "\(session.state)"
                }
                let totalMs = tEnd.timeIntervalSince(tSpeechEnd) * 1000.0
                let correct = (completed == "executed" && canonCommand(parseCommand(raw: transcript)) == expected) ? "yes" : "no"
                let row = "\(paso),\(grupo),\(csvEscape(instruccion)),\(expected),\(fixtureKindFor(expected: expected).rawValue),\(iso(tSpeechStart)),\(iso(tSpeechEnd)),\(csvEscape(transcript)),\(csvEscape(shown)),\(decision),\(csvEscape(completed)),\(csvEscape(cmdStr)),\(riskStr),\(polStr),\(ctxValid ? 1 : 0),0,\(decision == "confirm" && completed == "executed" ? 1 : 0),\(decision == "repeat" ? 1 : 0),\(correct),\(String(format: "%.0f", sttMs)),\(String(format: "%.3f", proposalGenMs)),\(String(format: "%.0f", decisionMs)),\(String(format: "%.3f", executionMs)),\(String(format: "%.0f", totalMs))\n"
                if let fh = try? FileHandle(forWritingTo: outURL) {
                    fh.seekToEndOfFile(); fh.write(Data(row.utf8)); try? fh.close()
                }
            } else {
                let tEnd = Date()
                let totalMs = tEnd.timeIntervalSince(tSpeechEnd) * 1000.0
                let correct = canonCommand(parseCommand(raw: transcript)) == expected ? "yes" : "no"
                let row = "\(paso),\(grupo),\(csvEscape(instruccion)),\(expected),\(fixtureKindFor(expected: expected).rawValue),\(iso(tSpeechStart)),\(iso(tSpeechEnd)),\(csvEscape(transcript)),\(csvEscape(shown)),auto,executed,\(csvEscape(cmdStr)),\(riskStr),\(polStr),\(ctxValid ? 1 : 0),1,0,0,\(correct),\(String(format: "%.0f", sttMs)),\(String(format: "%.3f", proposalGenMs)),0,0,\(String(format: "%.0f", totalMs))\n"
                if let fh = try? FileHandle(forWritingTo: outURL) {
                    fh.seekToEndOfFile(); fh.write(Data(row.utf8)); try? fh.close()
                }
            }
        } catch {
            print("balanced-live error: \(error)")
        }
    }
    print("\nSesión completa. Resultados en \(outFile)")
}

func runRiskLive() async {
    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let protoURL = base.appendingPathComponent("data/risk_live_protocol.csv")
    guard FileManager.default.fileExists(atPath: protoURL.path) else {
        print("risk-live: falta data/risk_live_protocol.csv"); return
    }
    guard let text = try? String(contentsOf: protoURL, encoding: .utf8) else { return }
    let locale = Locale(identifier: "es_MX")
    let lmConfig: SFSpeechLanguageModel.Configuration?
    do { lmConfig = try loadCustomLMConfiguration() }
    catch { print("risk-live: \(error)"); return }
    let outURL = base.appendingPathComponent("data/risk_live_results.csv")
    if !FileManager.default.fileExists(atPath: outURL.path) {
        try? "paso,modo,instruccion,expected,speech_start,speech_end,transcript_final,proposal_shown,decision,action_completed,command,risk,policy,stt_ms,proposal_generation_ms,decision_ms,execution_ms,total_ms,correct_effect\n".write(to: outURL, atomically: true, encoding: .utf8)
    }
    var session = RiskBasedSession(editor: .default())
    session.editor.selectAll()
    let iso: (Date) -> String = { d in
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }
    print("=== RISK LIVE (inmediato=sin Enter; confirm=Enter; esc=cancelar; r=repetir) ===")
    for line in text.components(separatedBy: "\n").dropFirst() {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
        let p = Runner.splitCSVLine(line)
        guard p.count >= 3, !p[0].isEmpty else { continue }
        let (paso, modo, instruccion) = (p[0], p[1], p[2])
        let expected = p.count > 3 ? p[3] : ""
        print("\n[\(paso) modo=\(modo)] DI/HAZ: \(instruccion)")
        print("Enter para hablar (mic)...")
        _ = readLine()
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent("risk.wav")
        do {
            let tSpeechStart = Date()
            try await recordMic(to: wav)
            let tSpeechEnd = Date()
            let (transcript, sttMs) = try await transcribeFileCustom(wav, locale: locale, lmConfig: lmConfig!)
            let tProp0 = Date()
            session.startListening()
            session.receiveTranscript(transcript)
            let tProp1 = Date()
            let proposalGenMs = tProp1.timeIntervalSince(tProp0) * 1000.0
            let shown: String
            let cmdStr: String
            let riskStr: String
            let polStr: String
            var auto = false
            switch session.state {
            case .executed(let prop) where policyForCommand(prop.command) == .immediate:
                auto = true
                shown = session.feedback() ?? "✓ Listo"
                print("\(shown) (auto, sin Enter)")
                cmdStr = "\(prop.command)"; riskStr = prop.risk.rawValue; polStr = "immediate"
            case .recognized(let prop):
                print("Reconocido:\n\(prop.effectDescription)\n[\(prop.risk.rawValue)]")
                print("Decisión: [Enter] confirmar  [esc] cancelar  [r] repetir")
                shown = prop.effectDescription.replacingOccurrences(of: "\n", with: " / ")
                cmdStr = "\(prop.command)"; riskStr = prop.risk.rawValue; polStr = "confirm"
            case .unsupported: print("Ese comando no está disponible. ([esc] cerrar / [r] repetir)"); shown = "Ese comando no está disponible."; cmdStr = "unsupported"; riskStr = ""; polStr = ""
            case .notUnderstood: print("No entendí el comando. ([r] repetir / [esc] cancelar)"); shown = "No entendí el comando."; cmdStr = "unknown"; riskStr = ""; polStr = ""
            case .invalidContext(_, let r): print("\(r) ([r] repetir / [esc] cerrar)"); shown = r; cmdStr = "invalidContext"; riskStr = ""; polStr = ""
            default: print("Estado: \(session.state)"); shown = "\(session.state)"; cmdStr = ""; riskStr = ""; polStr = ""
            }
            var decision = "auto"
            var decisionMs = 0.0
            var executionMs = 0.0
            if !auto {
                let tD0 = Date()
                let input = readLine() ?? ""
                let tE0 = Date()
                if input.lowercased() == "r" { session.repeatCommand(); decision = "repeat" }
                else if input.lowercased() == "esc" { session.cancel(); decision = "cancel" }
                else { session.confirm(); decision = "confirm" }
                let tEnd = Date()
                decisionMs = tEnd.timeIntervalSince(tD0) * 1000.0
                executionMs = tEnd.timeIntervalSince(tE0) * 1000.0
                let tTotalEnd = tEnd
                let completed: String
                switch session.state {
                case .executed: completed = "executed"
                case .cancelled: completed = "cancelled"
                case .listening: completed = "listening-repeat"
                default: completed = "\(session.state)"
                }
                let totalMs = tTotalEnd.timeIntervalSince(tSpeechEnd) * 1000.0
                let correct = !expected.isEmpty && completed == "executed" && cmdStr.contains(expected) ? "yes" : (completed == "executed" ? "check" : "n/a")
                let row = "\(paso),\(modo),\(csvEscape(instruccion)),\(expected),\(iso(tSpeechStart)),\(iso(tSpeechEnd)),\(csvEscape(transcript)),\(csvEscape(shown)),\(decision),\(csvEscape(completed)),\(csvEscape(cmdStr)),\(riskStr),\(polStr),\(String(format: "%.0f", sttMs)),\(String(format: "%.3f", proposalGenMs)),\(String(format: "%.0f", decisionMs)),\(String(format: "%.3f", executionMs)),\(String(format: "%.0f", totalMs)),\(correct)\n"
                if let fh = try? FileHandle(forWritingTo: outURL) {
                    fh.seekToEndOfFile(); fh.write(Data(row.utf8)); try? fh.close()
                }
            } else {
                let tEnd = Date()
                let totalMs = tEnd.timeIntervalSince(tSpeechEnd) * 1000.0
                let row = "\(paso),\(modo),\(csvEscape(instruccion)),\(expected),\(iso(tSpeechStart)),\(iso(tSpeechEnd)),\(csvEscape(transcript)),\(csvEscape(shown)),auto,executed,\(csvEscape(cmdStr)),\(riskStr),\(polStr),\(String(format: "%.0f", sttMs)),\(String(format: "%.3f", proposalGenMs)),0,0,\(String(format: "%.0f", totalMs)),n/a\n"
                if let fh = try? FileHandle(forWritingTo: outURL) {
                    fh.seekToEndOfFile(); fh.write(Data(row.utf8)); try? fh.close()
                }
            }
            print("Estado editor: título=\"\(session.editor.title)\"")
        } catch {
            print("risk-live error: \(error)")
        }
    }
    print("\nSesión completa. Resultados en data/risk_live_results.csv")
}
