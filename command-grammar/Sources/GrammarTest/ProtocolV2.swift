// Protocolo v2: validación, leakage, grabación única, evaluación pareada A/B.
// Gramática congelada: solo llama a parseCommand, nunca la modifica.
import Foundation
import Speech
import AVFoundation

// MARK: - Helpers comunes

func canonCommand(_ p: ParsedCommand) -> String {
    switch p {
    case .renameTitle: return "renameTitle"
    case .deleteSelection: return "deleteSelection"
    case .replaceSelection: return "replaceSelection"
    case .rewriteSelection: return "rewriteSelection"
    case .formatSelection(let s): return "formatSelection:\(s.rawValue)"
    case .undo: return "undo"
    case .redo: return "redo"
    case .selectText: return "selectText"
    case .findText: return "findText"
    case .saveDocument: return "saveDocument"
    case .openDocument: return "openDocument"
    case .exportDocument(let f): return "exportDocument:\(f.rawValue)"
    case .unsupported: return "unsupported"
    case .multipleActions: return "multipleActions"
    case .unknown: return "unknown"
    }
}

func isSupportedCommand(_ canon: String) -> Bool {
    canon.hasPrefix("renameTitle") || canon.hasPrefix("deleteSelection")
        || canon.hasPrefix("replaceSelection") || canon.hasPrefix("rewriteSelection")
        || canon.hasPrefix("formatSelection") || canon == "undo" || canon == "redo"
        || canon.hasPrefix("selectText") || canon.hasPrefix("findText")
        || canon == "saveDocument" || canon == "openDocument"
        || canon.hasPrefix("exportDocument")
}

func extractArgument(_ p: ParsedCommand) -> String {
    switch p {
    case .renameTitle(let s): return s
    case .replaceSelection(let s): return s
    case .rewriteSelection(let s): return s
    case .selectText(let s): return s
    case .findText(let s): return s
    case .openDocument(let s): return s ?? ""
    default: return ""
    }
}

func wordsNorm(_ s: String) -> [String] {
    normalizedForLeakage(s).split(separator: " ").map(String.init).filter { !$0.isEmpty }
}

func levenshteinWords(_ a: [String], _ b: [String]) -> Int {
    let m = a.count, n = b.count
    if m == 0 { return n }
    if n == 0 { return m }
    var dp = Array(0...n)
    for i in 1...m {
        var prev = dp[0]
        dp[0] = i
        for j in 1...n {
            let tmp = dp[j]
            dp[j] = a[i-1] == b[j-1] ? prev : min(prev + 1, dp[j] + 1, dp[j-1] + 1)
            prev = tmp
        }
    }
    return dp[n]
}

func levenshteinChars(_ a: String, _ b: String) -> Int {
    let ac = Array(a), bc = Array(b)
    let m = ac.count, n = bc.count
    if m == 0 { return n }
    if n == 0 { return m }
    var dp = Array(0...n)
    for i in 1...m {
        var prev = dp[0]
        dp[0] = i
        for j in 1...n {
            let tmp = dp[j]
            dp[j] = ac[i-1] == bc[j-1] ? prev : min(prev + 1, dp[j] + 1, dp[j-1] + 1)
            prev = tmp
        }
    }
    return dp[n]
}

func wer(ref: String, hyp: String) -> (errors: Int, refWords: Int, rate: Double) {
    let r = wordsNorm(ref)
    let h = wordsNorm(hyp)
    if r.isEmpty { return (h.isEmpty ? 0 : h.count, 0, h.isEmpty ? 0 : 1) }
    let e = levenshteinWords(r, h)
    return (e, r.count, Double(e) / Double(r.count))
}

func argumentGrade(expected: String, got: String) -> String {
    if expected == got { return "EXACT" }
    if expected.isEmpty || got.isEmpty { return "WRONG" }
    if expected.lowercased() == got.lowercased() { return "CASE_ONLY_DIFFERENCE" }
    if normalizedForLeakage(expected) == normalizedForLeakage(got) { return "MINOR_STT_ERROR" }
    // Error menor: 1 palabra distinta con distancia de caracteres <= 2 (ej. TDA vs TDAH)
    let ew = wordsNorm(expected), gw = wordsNorm(got)
    if ew.count == gw.count && ew.count > 0 {
        var diffs = 0
        var maxCharDist = 0
        for (x, y) in zip(ew, gw) {
            if x != y { diffs += 1; maxCharDist = max(maxCharDist, levenshteinChars(x, y)) }
        }
        if diffs == 1 && maxCharDist <= 2 { return "MINOR_STT_ERROR" }
    }
    return "WRONG"
}

func median(_ xs: [Double]) -> Double {
    guard !xs.isEmpty else { return 0 }
    let s = xs.sorted()
    if s.count % 2 == 1 { return s[s.count/2] }
    return (s[s.count/2 - 1] + s[s.count/2]) / 2
}

func percentile(_ xs: [Double], _ p: Double) -> Double {
    guard !xs.isEmpty else { return 0 }
    let s = xs.sorted()
    let idx = min(s.count - 1, Int((p / 100.0 * Double(s.count)).rounded(.up)) - 1)
    return s[max(0, idx)]
}

func mean(_ xs: [Double]) -> Double {
    guard !xs.isEmpty else { return 0 }
    return xs.reduce(0, +) / Double(xs.count)
}

struct V2Row {
    let id: String
    let category: String
    let expectedSpoken: String
    let expected: String
    let argumentExpected: String
    let challenge: String
}

func loadProtocolV2() throws -> [V2Row] {
    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let url = base.appendingPathComponent("data/speech_protocol_v2.csv")
    let text = try String(contentsOf: url, encoding: .utf8)
    var rows: [V2Row] = []
    for line in text.components(separatedBy: "\n").dropFirst() {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
        let p = Runner.splitCSVLine(line)
        guard p.count >= 4, !p[0].isEmpty else { continue }
        rows.append(V2Row(
            id: p[0],
            category: p.count > 1 ? p[1] : "",
            expectedSpoken: p.count > 2 ? p[2] : "",
            expected: p.count > 3 ? p[3] : "",
            argumentExpected: p.count > 4 ? p[4] : "",
            challenge: p.count > 5 ? p[5] : ""
        ))
    }
    return rows
}

func durationMs(_ from: ContinuousClock.Instant, _ to: ContinuousClock.Instant) -> Double {
    let comps = (to - from).components
    return Double(comps.seconds) * 1000.0 + Double(comps.attoseconds) / 1e15
}

// MARK: - validate-v2: parse limpio vs esperado

func runValidateV2() {
    do {
        let rows = try loadProtocolV2()
        var ok = 0
        var fails: [String] = []
        for r in rows {
            let got = canonCommand(parseCommand(raw: r.expectedSpoken))
            if got == r.expected { ok += 1 }
            else { fails.append("FAIL \(r.id) [\(r.expectedSpoken)] exp=\(r.expected) got=\(parseCommand(raw: r.expectedSpoken)) [canon=\(got)]") }
        }
        print("validate-v2 clean-parse: \(ok)/\(rows.count) = \(String(format: "%.1f", 100*Double(ok)/Double(max(1,rows.count))))%")
        for f in fails { print(f) }
    } catch {
        print("validate-v2 error: \(error)")
    }
}

// MARK: - leakage: LM vs FINAL (normalizado exacto debe ser 0)

func runLeakageCheck() {
    do {
        let rows = try loadProtocolV2()
        let finalSet = Set(rows.map { normalizedForLeakage($0.expectedSpoken) })
        let lm = allCustomLMPhrases()
        var hits: [String] = []
        for p in lm {
            if finalSet.contains(normalizedForLeakage(p)) {
                hits.append(p)
            }
        }
        print("leakage check: LM phrases=\(lm.count) (directas=\(customLMPhraseCounts.count) + templates_expandidas=\(expandCustomLMTemplates().count))")
        print("FINAL únicas normalizadas=\(finalSet.count)")
        if hits.isEmpty {
            print("LEAKAGE_OK 0 coincidencias literales normalizadas")
        } else {
            print("LEAKAGE_FAIL \(hits.count) coincidencias:")
            for h in hits { print("  HIT [\(h)] norm=[\(normalizedForLeakage(h))]") }
        }
        // Detalle doc
        print("phraseCount entries=\(customLMPhraseCounts.count) templateCount=\(customLMTemplates.count) aproxFrases=\(lm.count)")
    } catch {
        print("leakage error: \(error)")
    }
}

// MARK: - prepare-lm

func runPrepareLM() async {
    let tGen0 = ContinuousClock().now
    let data = buildCustomLMData()
    let tGen1 = ContinuousClock().now
    let genMs = durationMs(tGen0, tGen1)
    let paths = customLMPaths()
    do {
        let tExp0 = ContinuousClock().now
        try await data.export(to: paths.asset)
        let tExp1 = ContinuousClock().now
        let expMs = durationMs(tExp0, tExp1)
        let assetSize = (try? FileManager.default.attributesOfItem(atPath: paths.asset.path)[.size] as? Int) ?? 0
        print("training data generation: \(String(format: "%.1f", genMs)) ms")
        print("export: \(String(format: "%.1f", expMs)) ms asset=\(paths.asset.path) size=\(assetSize) bytes")
        print("phraseCount entries=\(customLMPhraseCounts.count) templates=\(customLMTemplates.count) aproxFrases=\(allCustomLMPhrases().count) weight=\(customLMWeightValue) locale=es_MX")
        // Vocabulario aproximado: unigramas de LM
        let vocab = Set(allCustomLMPhrases().flatMap { wordsNorm($0) })
        print("vocabulary size (aprox unigramas LM)=\(vocab.count)")
        let cfg = SFSpeechLanguageModel.Configuration(languageModel: paths.lm, vocabulary: paths.vocab, weight: customLMWeight())
        let tPrep0 = ContinuousClock().now
        let prepError: Error? = await withCheckedContinuation { cont in
            SFSpeechLanguageModel.prepareCustomLanguageModel(for: paths.asset, configuration: cfg, ignoresCache: true) { err in
                cont.resume(returning: err)
            }
        }
        let tPrep1 = ContinuousClock().now
        let prepMs = durationMs(tPrep0, tPrep1)
        if let e = prepError {
            print("prepareCustomLanguageModel ERROR: \(e)")
        } else {
            let lmSize = (try? FileManager.default.attributesOfItem(atPath: paths.lm.path)[.size] as? Int) ?? 0
            let vocabSize = (try? FileManager.default.attributesOfItem(atPath: paths.vocab.path)[.size] as? Int) ?? 0
            print("prepareCustomLanguageModel: \(String(format: "%.1f", prepMs)) ms (NO cuenta como latencia por comando)")
            print("compiled LM size=\(lmSize) bytes at \(paths.lm.path)")
            print("compiled vocab size=\(vocabSize) bytes at \(paths.vocab.path)")
        }
    } catch {
        print("prepare-lm error: \(error)")
    }
}

// MARK: - record-v2: graba cada utterance UNA SOLA VEZ a data/audio_v2/<id>.wav

func runRecordV2() async {
    do {
        let rows = try loadProtocolV2()
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let audioDir = base.appendingPathComponent("data/audio_v2", isDirectory: true)
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        print("Protocolo v2: \(rows.count) utterances. Se graba UNA SOLA VEZ por id en data/audio_v2/")
        print("Habla natural, sin prefijos (no digas 'sí/hola'), evita truncados.")
        for r in rows {
            let wav = audioDir.appendingPathComponent("\(r.id).wav")
            if FileManager.default.fileExists(atPath: wav.path) {
                print("[\(r.id)] ya existe \(wav.lastPathComponent), se omite (no regrabar).")
                continue
            }
            print("\n[\(r.id) \(r.category) \(r.challenge)] DI:")
            print(r.expectedSpoken)
            print("Enter para grabar \(r.id).wav ...")
            _ = readLine()
            do {
                try await recordMic(to: wav)
                print("Guardado \(wav.path)")
                print("Enter para continuar (o Ctrl-C para pausar; al reanudar omite existentes)...")
                _ = readLine()
            } catch {
                print("error grabando \(r.id): \(error)")
            }
        }
        let count = (try? FileManager.default.contentsOfDirectory(atPath: audioDir.path).filter { $0.hasSuffix(".wav") }.count) ?? 0
        print("\nrecord-v2 completo. WAVs en data/audio_v2: \(count)/\(rows.count)")
    } catch {
        print("record-v2 error: \(error)")
    }
}

// MARK: - eval-v2: mismos WAV con A y B + gramática congelada + métricas

struct EvalRow {
    var id: String
    var expectedSpoken: String
    var expected: String
    var category: String
    var challenge: String
    var argumentExpected: String
    var audioFile: String
    var bTranscript: String
    var bWER: Double
    var bWERErrors: Int
    var bRefWords: Int
    var bParsed: String
    var bParsedCanon: String
    var bCorrect: Bool
    var bArg: String
    var bArgGrade: String
    var bSTTms: Double
    var bParseMs: Double
    var cTranscript: String
    var cWER: Double
    var cWERErrors: Int
    var cRefWords: Int
    var cParsed: String
    var cParsedCanon: String
    var cCorrect: Bool
    var cArg: String
    var cArgGrade: String
    var cSTTms: Double
    var cParseMs: Double
}

func csvEscape(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

// MARK: - dump-lm: vuelca phrases/templates/config para auditoría

func runDumpLM() {
    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let dir = base.appendingPathComponent("data/custom_lm", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let phrases = allCustomLMPhrases()
    try? phrases.joined(separator: "\n").write(to: dir.appendingPathComponent("phrases.txt"), atomically: true, encoding: .utf8)
    var tmpl = "templates (body<TAB>count):\n"
    for t in customLMTemplates { tmpl += "\(t.body)\t\(t.count)\n" }
    tmpl += "\nclasses:\n"
    for (k, v) in customLMClasses.sorted(by: { $0.key < $1.key }) {
        tmpl += "<\(k)> = \(v.joined(separator: " | "))\n"
    }
    try? tmpl.write(to: dir.appendingPathComponent("templates.txt"), atomically: true, encoding: .utf8)
    let paths = customLMPaths()
    let assetSize = (try? FileManager.default.attributesOfItem(atPath: paths.asset.path)[.size] as? Int) ?? 0
    let lmSize = (try? FileManager.default.attributesOfItem(atPath: paths.lm.path)[.size] as? Int) ?? 0
    let vocabSize = (try? FileManager.default.attributesOfItem(atPath: paths.vocab.path)[.size] as? Int) ?? 0
    let vocabUni = Set(phrases.flatMap { wordsNorm($0) })
    let cfg = """
    {
      "locale": "es_MX",
      "locale_note": "guion bajo, coincide DictationTranscriber y SFCustomLanguageModelData; verificado en supportedLocales",
      "identifier": "\(customLMIdentifier)",
      "version": "\(customLMVersion)",
      "weight": \(customLMWeightValue),
      "weight_note": "única configuración a priori (moderada 0.6), sin tuning post-FINAL",
      "phraseCount_entries": \(customLMPhraseCounts.count),
      "templateCount": \(customLMTemplates.count),
      "aproxFrases": \(phrases.count),
      "vocab_unigramas_aprox": \(vocabUni.count),
      "asset_bin_bytes": \(assetSize),
      "compiled_lm_bytes": \(lmSize),
      "compiled_vocab_bytes": \(vocabSize),
      "contextualStrings": "idénticas baseline (commandContext(), sin cambios)",
      "preset": "phrase (.phrase + customizedLanguage hint en B; resto idéntico)"
    }
    """
    try? cfg.write(to: dir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
    print("dump-lm: phrases=\(phrases.count) en data/custom_lm/phrases.txt, templates.txt, config.json")
}

// MARK: - smoke-ab: un archivo con A y B (humo, NO oficial)

func runSmokeAB(path: String) async {
    let url = URL(fileURLWithPath: path)
    let locale = Locale(identifier: "es_MX")
    do {
        let (bText, bMs) = try await transcribeFileBaseline(url, locale: locale)
        print("BASELINE RAW: \(bText) (\(String(format: "%.0f", bMs)) ms) -> \(parseCommand(raw: bText))")
        do {
            let cfg = try loadCustomLMConfiguration()
            let (cText, cMs) = try await transcribeFileCustom(url, locale: locale, lmConfig: cfg)
            print("CUSTOM   RAW: \(cText) (\(String(format: "%.0f", cMs)) ms) -> \(parseCommand(raw: cText))")
        } catch {
            print("custom error: \(error)")
        }
    } catch {
        print("baseline error: \(error)")
    }
}

func runEvalV2() async {    do {
        let rows = try loadProtocolV2()
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let audioDir = base.appendingPathComponent("data/audio_v2", isDirectory: true)
        let locale = Locale(identifier: "es_MX")
        let lmConfig: SFSpeechLanguageModel.Configuration? = try? loadCustomLMConfiguration()
        if lmConfig == nil {
            print("AVISO: sin modelo compilado; eval-v2 requiere `prepare-lm`. Se intentará solo baseline? No: se aborta para no generar comparación inválida.")
            print("Ejecuta primero: swift run GrammarTest prepare-lm")
            return
        }
        print("eval-v2: \(rows.count) utterances, mismos WAV para A y B, locale es_MX")
        var out: [EvalRow] = []
        var missing: [String] = []
        for r in rows {
            let wav = audioDir.appendingPathComponent("\(r.id).wav")
            guard FileManager.default.fileExists(atPath: wav.path) else {
                missing.append(r.id)
                continue
            }
            // A — BASELINE
            let (bText, bSTTms): (String, Double)
            do { (bText, bSTTms) = try await transcribeFileBaseline(wav, locale: locale) }
            catch { print("baseline STT error \(r.id): \(error)"); continue }
            let p0 = ContinuousClock().now
            let bParsed = parseCommand(raw: bText)
            let p1 = ContinuousClock().now
            let bParseMs = durationMs(p0, p1)
            let bCanon = canonCommand(bParsed)
            let bW = wer(ref: r.expectedSpoken, hyp: bText)
            let bArg = extractArgument(bParsed)
            // B — CUSTOM
            let (cText, cSTTms): (String, Double)
            do { (cText, cSTTms) = try await transcribeFileCustom(wav, locale: locale, lmConfig: lmConfig!) }
            catch { print("custom STT error \(r.id): \(error)"); continue }
            let q0 = ContinuousClock().now
            let cParsed = parseCommand(raw: cText)
            let q1 = ContinuousClock().now
            let cParseMs = durationMs(q0, q1)
            let cCanon = canonCommand(cParsed)
            let cW = wer(ref: r.expectedSpoken, hyp: cText)
            let cArg = extractArgument(cParsed)
            out.append(EvalRow(
                id: r.id, expectedSpoken: r.expectedSpoken, expected: r.expected,
                category: r.category, challenge: r.challenge, argumentExpected: r.argumentExpected,
                audioFile: "data/audio_v2/\(r.id).wav",
                bTranscript: bText, bWER: bW.rate, bWERErrors: bW.errors, bRefWords: bW.refWords,
                bParsed: "\(bParsed)", bParsedCanon: bCanon, bCorrect: (bCanon == r.expected),
                bArg: bArg, bArgGrade: argumentGrade(expected: r.argumentExpected, got: bArg),
                bSTTms: bSTTms, bParseMs: bParseMs,
                cTranscript: cText, cWER: cW.rate, cWERErrors: cW.errors, cRefWords: cW.refWords,
                cParsed: "\(cParsed)", cParsedCanon: cCanon, cCorrect: (cCanon == r.expected),
                cArg: cArg, cArgGrade: argumentGrade(expected: r.argumentExpected, got: cArg),
                cSTTms: cSTTms, cParseMs: cParseMs
            ))
            print("[\(r.id)] B:\(bCanon)\(bCanon == r.expected ? "✓" : "✗") C:\(cCanon)\(cCanon == r.expected ? "✓" : "✗") | B[\(bText)] C[\(cText)]")
        }
        if !missing.isEmpty {
            print("Faltan \(missing.count) WAVs: \(missing.prefix(10).joined(separator: ","))... Graba con `record-v2` primero.")
        }
        // Guarda CSV por utterance
        let outURL = base.appendingPathComponent("data/eval_v2_results.csv")
        var csv = "id,expected_spoken_text,expected_command,category,challenge,audio_file,argument_expected,baseline_transcript,baseline_wer,baseline_parsed_command,baseline_parsed_canon,baseline_correct,baseline_argument,baseline_arg_grade,baseline_stt_ms,baseline_parse_ms,custom_transcript,custom_wer,custom_parsed_command,custom_parsed_canon,custom_correct,custom_argument,custom_arg_grade,custom_stt_ms,custom_parse_ms\n"
        for e in out {
            csv += "\(e.id),\(csvEscape(e.expectedSpoken)),\(e.expected),\(e.category),\(csvEscape(e.challenge)),\(e.audioFile),\(csvEscape(e.argumentExpected)),\(csvEscape(e.bTranscript)),\(String(format: "%.4f", e.bWER)),\(csvEscape(e.bParsed)),\(e.bParsedCanon),\(e.bCorrect ? 1 : 0),\(csvEscape(e.bArg)),\(e.bArgGrade),\(String(format: "%.1f", e.bSTTms)),\(String(format: "%.3f", e.bParseMs)),\(csvEscape(e.cTranscript)),\(String(format: "%.4f", e.cWER)),\(csvEscape(e.cParsed)),\(e.cParsedCanon),\(e.cCorrect ? 1 : 0),\(csvEscape(e.cArg)),\(e.cArgGrade),\(String(format: "%.1f", e.cSTTms)),\(String(format: "%.3f", e.cParseMs))\n"
        }
        try csv.write(to: outURL, atomically: true, encoding: .utf8)
        print("\nResultados por utterance en \(outURL.path) (\(out.count) filas)")
        printEvalSummary(out)
    } catch {
        print("eval-v2 error: \(error)")
    }
}

func printEvalSummary(_ rows: [EvalRow]) {
    guard !rows.isEmpty else { print("sin filas"); return }
    let n = rows.count
    let bCorrect = rows.filter { $0.bCorrect }.count
    let cCorrect = rows.filter { $0.cCorrect }.count
    let bb = rows.filter { $0.bCorrect && $0.cCorrect }.count
    let bw_c = rows.filter { !$0.bCorrect && $0.cCorrect }.count
    let bc_w = rows.filter { $0.bCorrect && !$0.cCorrect }.count
    let ww = rows.filter { !$0.bCorrect && !$0.cCorrect }.count
    let bErr = rows.reduce(0) { $0 + $1.bWERErrors }
    let bRef = rows.reduce(0) { $0 + $1.bRefWords }
    let cErr = rows.reduce(0) { $0 + $1.cWERErrors }
    let cRef = rows.reduce(0) { $0 + $1.cRefWords }
    let bWER = bRef > 0 ? Double(bErr)/Double(bRef) : 0
    let cWER = cRef > 0 ? Double(cErr)/Double(cRef) : 0
    let bAcc = Double(bCorrect)/Double(n), cAcc = Double(cCorrect)/Double(n)
    let absImp = cAcc - bAcc
    let relErrRed = (1 - bAcc) > 0 ? ((1 - bAcc) - (1 - cAcc)) / (1 - bAcc) : 0
    print("\n=== MÉTRICA PRIMARIA: END-TO-END COMMAND ACCURACY ===")
    print("Baseline: \(bCorrect)/\(n) = \(String(format: "%.1f", 100*bAcc))%")
    print("Custom:   \(cCorrect)/\(n) = \(String(format: "%.1f", 100*cAcc))%")
    print("Mejora absoluta: \(String(format: "%+.1f", 100*absImp)) puntos")
    print("Reducción relativa de error: \(String(format: "%.1f", 100*relErrRed))%")
    print("\n=== WER (mismos audios) ===")
    print("Baseline WER: \(String(format: "%.1f", 100*bWER))% (\(bErr)/\(bRef))")
    print("Custom WER:   \(String(format: "%.1f", 100*cWER))% (\(cErr)/\(cRef))")
    print("Mejora absoluta WER: \(String(format: "%+.1f", 100*(bWER-cWER))) puntos")
    if bWER > 0 { print("Reducción relativa WER: \(String(format: "%.1f", 100*(bWER-cWER)/bWER))%") }
    print("\n=== COMPARACIÓN PAREADA ===")
    print("Ambos correctos (B✓ C✓): \(bb)")
    print("Solo custom corrige (B✗ C✓): \(bw_c)")
    print("Regresiones (B✓ C✗) CUSTOM_LM_REGRESSIONS: \(bc_w) = \(String(format: "%.1f", 100*Double(bc_w)/Double(n)))%")
    print("Ambos fallan (B✗ C✗): \(ww)")
    // Challenges
    func acc(_ pred: (EvalRow) -> Bool, _ correct: (EvalRow) -> Bool) -> String {
        let s = rows.filter(pred)
        guard !s.isEmpty else { return "n=0" }
        let b = s.filter { correct($0) }.count
        // Devuelve baseline y custom por separado fuera; aquí genérico
        return "\(b)/\(s.count)=\(String(format: "%.1f", 100*Double(b)/Double(s.count)))%"
    }
    func hasChallenge(_ r: EvalRow, _ t: String) -> Bool { r.challenge.split(separator: ";").map(String.init).contains(t) }
    print("\n=== STT-SPECIFIC CHALLENGES (baseline vs custom, command accuracy) ===")
    let groups: [(String, (EvalRow) -> Bool)] = [
        ("UNDO/REDO", { hasChallenge($0, "undo_redo") }),
        ("FORMAT", { hasChallenge($0, "format") }),
        ("FIND/SELECT", { hasChallenge($0, "find_select") }),
        ("SAVE/EXPORT", { hasChallenge($0, "save_export") }),
        ("SHORT", { hasChallenge($0, "short") }),
        ("ARGUMENTS", { hasChallenge($0, "argument") }),
        ("RENAME", { $0.category == "rename" }),
        ("DELETE", { $0.category == "delete" }),
        ("REPLACE", { $0.category == "replace" }),
        ("REWRITE", { $0.category == "rewrite" }),
        ("FIND", { $0.category == "find" }),
        ("SELECT", { $0.category == "select" }),
        ("SAVE", { $0.category == "save" }),
        ("OPEN", { $0.category == "open" }),
        ("EXPORT", { $0.category == "export" }),
    ]
    for (name, pred) in groups {
        let s = rows.filter(pred)
        guard !s.isEmpty else { continue }
        let bb2 = s.filter { $0.bCorrect }.count
        let cc2 = s.filter { $0.cCorrect }.count
        print("\(name): n=\(s.count) baseline \(bb2)/\(s.count)=\(String(format: "%.1f", 100*Double(bb2)/Double(s.count)))% custom \(cc2)/\(s.count)=\(String(format: "%.1f", 100*Double(cc2)/Double(s.count)))%")
    }
    print("\n=== ARGUMENT METRICS ===")
    for label in ["EXACT", "CASE_ONLY_DIFFERENCE", "MINOR_STT_ERROR", "WRONG"] {
        let b = rows.filter { $0.bArgGrade == label }.count
        let c = rows.filter { $0.cArgGrade == label }.count
        print("\(label): baseline \(b) custom \(c)")
    }
    let bAccept = rows.filter { ["EXACT","CASE_ONLY_DIFFERENCE","MINOR_STT_ERROR"].contains($0.bArgGrade) }.count
    let cAccept = rows.filter { ["EXACT","CASE_ONLY_DIFFERENCE","MINOR_STT_ERROR"].contains($0.cArgGrade) }.count
    print("Argument acceptable (EXACT+CASE+MINOR): baseline \(bAccept)/\(n)=\(String(format: "%.1f", 100*Double(bAccept)/Double(n)))% custom \(cAccept)/\(n)=\(String(format: "%.1f", 100*Double(cAccept)/Double(n)))%")
    let bStrict = rows.filter { ["EXACT","CASE_ONLY_DIFFERENCE"].contains($0.bArgGrade) }.count
    let cStrict = rows.filter { ["EXACT","CASE_ONLY_DIFFERENCE"].contains($0.cArgGrade) }.count
    print("Argument strict (EXACT+CASE): baseline \(bStrict)/\(n) custom \(cStrict)/\(n)")
    print("\n=== UNSUPPORTED / UNKNOWN SAFETY ===")
    let unsup = rows.filter { $0.category == "unsupported" }
    let unk = rows.filter { $0.category == "unknown" }
    if !unsup.isEmpty {
        let bBad = unsup.filter { isSupportedCommand($0.bParsedCanon) }.count
        let cBad = unsup.filter { isSupportedCommand($0.cParsedCanon) }.count
        print("Unsupported hablado n=\(unsup.count): baseline→supported \(bBad) custom→supported \(cBad) (objetivo 0)")
    }
    if !unk.isEmpty {
        let bBad = unk.filter { isSupportedCommand($0.bParsedCanon) }.count
        let cBad = unk.filter { isSupportedCommand($0.cParsedCanon) }.count
        print("Unknown hablado n=\(unk.count): baseline→supported \(bBad) custom→supported \(cBad) (objetivo 0)")
    }
    print("\n=== LATENCIAS (ms) ===")
    let bSTT = rows.map(\.bSTTms), cSTT = rows.map(\.cSTTms)
    let bP = rows.map(\.bParseMs), cP = rows.map(\.cParseMs)
    let bE2E = rows.map { $0.bSTTms + $0.bParseMs }, cE2E = rows.map { $0.cSTTms + $0.cParseMs }
    print("STT baseline mean \(String(format: "%.0f", mean(bSTT))) median \(String(format: "%.0f", median(bSTT))) p95 \(String(format: "%.0f", percentile(bSTT, 95)))")
    print("STT custom   mean \(String(format: "%.0f", mean(cSTT))) median \(String(format: "%.0f", median(cSTT))) p95 \(String(format: "%.0f", percentile(cSTT, 95)))")
    print("Parser baseline mean \(String(format: "%.3f", mean(bP))) median \(String(format: "%.3f", median(bP)))")
    print("Parser custom   mean \(String(format: "%.3f", mean(cP))) median \(String(format: "%.3f", median(cP)))")
    print("E2E baseline mean \(String(format: "%.0f", mean(bE2E))) median \(String(format: "%.0f", median(bE2E)))")
    print("E2E custom   mean \(String(format: "%.0f", mean(cE2E))) median \(String(format: "%.0f", median(cE2E)))")
    print("\n=== FALLOS BASELINE (todos) ===")
    for e in rows where !e.bCorrect {
        print("B-FAIL \(e.id) exp=\(e.expected) got=\(e.bParsedCanon) raw=[\(e.bTranscript)] ref=[\(e.expectedSpoken)]")
    }
    print("\n=== FALLOS CUSTOM (todos) ===")
    for e in rows where !e.cCorrect {
        print("C-FAIL \(e.id) exp=\(e.expected) got=\(e.cParsedCanon) raw=[\(e.cTranscript)] ref=[\(e.expectedSpoken)]")
    }
}
