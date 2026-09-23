import CommandGrammar
// Fase Alternatives+Confidence — evaluación sobre los mismos 180 WAVs.
// CONGELADO: Grammar/Types/contextualStrings/LM/weight/preset/locale/audios/protocolo.
// - top1 utterance = concatenación de segment tops en orden de rango
//   (los flags alternatives+confidence segmentan más fino que Fase 8).
// - N-best a nivel utterance SOLO si 1 segmento (alt_1..alt_5 en orden,
//   sin reordenar, sin deduplicar, sin combinar entre alternativas).
// - Multi-segmento: alternativas por segmento en segment CSV; a nivel
//   utterance solo Top-1 (no existe N-best sin combinar; combinar está prohibido).
// - Top-2 = {top1,alt1}; Top-3 = {top1,alt1,alt2}; Top-5 = TODO lo registrado
//   (top1+alt_1..alt_5). "Never recovered" = fuera de todo lo registrado.
// - STRONG: expected aparece >=2 y ningún otro SOPORTADO aparece >=2.
//   MIXED: expected aparece >=1 pero no STRONG. NONE: expected no aparece.
//   (unknown/unsupported no compiten; solo acciones soportadas compiten).
import Foundation
import Speech
import AVFoundation

struct SegmentHypotheses {
    let rangeStart: Double
    let rangeDuration: Double
    let top: AttributedString
    let alternatives: [AttributedString]
}

struct UtteranceAlternatives {
    let id: String
    let expectedSpoken: String
    let expected: String
    let argumentExpected: String
    let category: String
    let challenge: String
    let audioFile: String
    let segments: [SegmentHypotheses]
    let top1: String
    let top1Confidence: Double?
    let alts: [AlternativeHypothesis] // utterance-level; vacío si multi-segmento
    let sttMs: Double
    var isMultiSegment: Bool { segments.count > 1 }
}

func collectSegments(url: URL, locale: Locale, lmConfig: SFSpeechLanguageModel.Configuration) async throws -> ([SegmentHypotheses], Double) {
    let t0 = ContinuousClock().now
    var preset = DictationTranscriber.Preset.phrase
    preset.contentHints.insert(.customizedLanguage(modelConfiguration: lmConfig))
    preset.reportingOptions.insert(.alternativeTranscriptions)
    preset.attributeOptions.insert(.transcriptionConfidence)
    let transcriber = DictationTranscriber(
        locale: locale,
        contentHints: preset.contentHints,
        transcriptionOptions: preset.transcriptionOptions,
        reportingOptions: preset.reportingOptions,
        attributeOptions: preset.attributeOptions
    )
    let file = try AVAudioFile(forReading: url)
    let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [transcriber],
                                            analysisContext: commandContext())
    let collectTask = Task { () -> [SegmentHypotheses] in
        var segs: [SegmentHypotheses] = []
        do {
            for try await r in await transcriber.results {
                let start = r.range.start.seconds
                let dur = r.range.duration.seconds
                segs.append(SegmentHypotheses(
                    rangeStart: start.isFinite ? start : 0,
                    rangeDuration: dur.isFinite ? dur : 0,
                    top: r.text,
                    alternatives: r.alternatives
                ))
            }
        } catch {
            print("DBG alts stream error: \(error)")
        }
        return segs
    }
    try await analyzer.finalizeAndFinishThroughEndOfInput()
    let segs = await collectTask.value
    let end = ContinuousClock().now
    return (segs, durationMs(t0, end))
}

func buildUtteranceAlternatives(row: V2Row, segs: [SegmentHypotheses], sttMs: Double) -> UtteranceAlternatives {
    let ordered = segs.sorted { $0.rangeStart < $1.rangeStart }
    let top1 = ordered.map { NSAttributedString($0.top).string }.joined()
    var segConfs: [Double] = []
    for s in ordered { if let c = confidenceOf(s.top) { segConfs.append(c) } }
    let top1Conf: Double? = segConfs.isEmpty ? nil : segConfs.reduce(0, +) / Double(segConfs.count)
    var alts: [AlternativeHypothesis] = []
    if ordered.count == 1, let only = ordered.first {
        alts = Array(only.alternatives.prefix(5)).map {
            AlternativeHypothesis(transcript: NSAttributedString($0).string, confidence: confidenceOf($0))
        }
    }
    return UtteranceAlternatives(
        id: row.id, expectedSpoken: row.expectedSpoken, expected: row.expected,
        argumentExpected: row.argumentExpected, category: row.category, challenge: row.challenge,
        audioFile: "data/audio_v2/\(row.id).wav",
        segments: ordered, top1: top1, top1Confidence: top1Conf, alts: alts, sttMs: sttMs
    )
}

// MARK: - Estadística descriptiva

func descStats(_ xs: [Double]) -> (mean: Double, median: Double, p10: Double, p25: Double, p75: Double, p90: Double, min: Double, max: Double, n: Int) {
    guard !xs.isEmpty else { return (0, 0, 0, 0, 0, 0, 0, 0, 0) }
    let s = xs.sorted()
    func pct(_ p: Double) -> Double {
        let idx = min(s.count - 1, Int((p / 100.0 * Double(s.count)).rounded(.up)) - 1)
        return s[max(0, idx)]
    }
    return (mean(s), median(s), pct(10), pct(25), pct(75), pct(90), s.first!, s.last!, s.count)
}

func fmtConf(_ c: Double?) -> String {
    guard let c else { return "" }
    return String(format: "%.3f", c)
}

// MARK: - Evaluación principal

func runEvalAlternatives() async {
    // Verificación gramática congelada
    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let audioDir = base.appendingPathComponent("data/audio_v2", isDirectory: true)
    let locale = Locale(identifier: "es_MX")
    let lmConfig: SFSpeechLanguageModel.Configuration?
    do { lmConfig = try loadCustomLMConfiguration() }
    catch { print("eval-alts error: \(error)"); return }
    let rows: [V2Row]
    do { rows = try loadProtocolV2() }
    catch { print("eval-alts error: \(error)"); return }
    print("eval-alts: \(rows.count) utterances, CUSTOM LM + alternatives + confidence, locale es_MX")
    print("reportingOptions=[.alternativeTranscriptions] attributeOptions=[.transcriptionConfidence] (+ preset .phrase defaults)")
    var utterances: [UtteranceAlternatives] = []
    var missing: [String] = []
    for r in rows {
        let wav = audioDir.appendingPathComponent("\(r.id).wav")
        guard FileManager.default.fileExists(atPath: wav.path) else { missing.append(r.id); continue }
        do {
            let (segs, ms) = try await collectSegments(url: wav, locale: locale, lmConfig: lmConfig!)
            utterances.append(buildUtteranceAlternatives(row: r, segs: segs, sttMs: ms))
        } catch {
            print("eval-alts STT error \(r.id): \(error)")
        }
    }
    if !missing.isEmpty { print("Faltan \(missing.count) WAVs: \(missing.prefix(5).joined(separator: ","))") }
    // Accounting
    let ids = utterances.map(\.id)
    guard utterances.count == 180, Set(ids).count == 180 else {
        print("ERROR_METRIC_ACCOUNTING: records=\(utterances.count) unique=\(Set(ids).count), esperado 180/180")
        return
    }
    writeAlternativesCSVs(utterances)
    printAlternativesSummary(utterances)
}

// MARK: - Hipótesis y parses por utterance

/// Hipótesis utterance en orden: [top1] + alts (sin dedup, sin reordenar).
func hypotheses(of u: UtteranceAlternatives) -> [String] {
    [u.top1] + u.alts.map(\.transcript)
}

func canons(of u: UtteranceAlternatives) -> [String] {
    hypotheses(of: u).map { canonCommand(parseCommand(raw: $0)) }
}

/// Top-K (K=2,3): primeros K. Top-5: TODO lo registrado.
func topKCanons(of u: UtteranceAlternatives, k: Int) -> [String] {
    let c = canons(of: u)
    if k >= 5 { return c }
    return Array(c.prefix(min(k, c.count)))
}

func oracleHit(of u: UtteranceAlternatives, k: Int) -> Bool {
    topKCanons(of: u, k: k).contains(u.expected)
}

func transcriptHit(of u: UtteranceAlternatives, k: Int) -> Bool {
    let ref = normalizedForLeakage(u.expectedSpoken)
    let hyps = hypotheses(of: u)
    let take = k >= 5 ? hyps : Array(hyps.prefix(min(k, hyps.count)))
    return take.contains { normalizedForLeakage($0) == ref }
}

func recoveryClass(of u: UtteranceAlternatives) -> String {
    // Solo tiene sentido llamarlo en Top-1 failures.
    let counts = Dictionary(grouping: canons(of: u), by: { $0 }).mapValues(\.count)
    let expCount = counts[u.expected] ?? 0
    if expCount == 0 { return "NONE" }
    let otherSupportedMax = counts.filter { $0.key != u.expected && isSupportedCommand($0.key) }.values.max() ?? 0
    if expCount >= 2 && otherSupportedMax <= 1 { return "STRONG" }
    return "MIXED"
}

func consensus(of u: UtteranceAlternatives, includeUnknown: Bool) -> (cmd: String, frac: Double, n: Int) {
    var c = canons(of: u)
    if !includeUnknown { c = c.filter { $0 != "unknown" } }
    guard !c.isEmpty else { return ("—", 0, 0) }
    let counts = Dictionary(grouping: c, by: { $0 }).mapValues(\.count)
    let best = counts.max { $0.value < $1.value }!
    return (best.key, Double(best.value) / Double(c.count), c.count)
}

// MARK: - CSVs

func writeAlternativesCSVs(_ us: [UtteranceAlternatives]) {
    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    // 1. alternatives_results.csv
    var csv = "id,audio_file,expected_spoken_text,expected_command,expected_argument,category,challenge,seg_count,top1_transcript,top1_confidence,top1_parsed,top1_canon,top1_correct,top1_arg_grade,alternative_count"
    for i in 1...5 { csv += ",alt_\(i)_transcript,alt_\(i)_confidence,alt_\(i)_parsed,alt_\(i)_canon,alt_\(i)_arg_grade" }
    csv += ",stt_ms\n"
    for u in us {
        let topCanon = canonCommand(parseCommand(raw: u.top1))
        var line = "\(u.id),\(u.audioFile),\(csvEscape(u.expectedSpoken)),\(u.expected),\(csvEscape(u.argumentExpected)),\(u.category),\(csvEscape(u.challenge)),\(u.segments.count),\(csvEscape(u.top1)),\(fmtConf(u.top1Confidence)),\(csvEscape("\(parseCommand(raw: u.top1))")),\(topCanon),\((topCanon == u.expected) ? 1 : 0),\(argumentGrade(expected: u.argumentExpected, got: extractArgument(parseCommand(raw: u.top1)))),\(u.alts.count)"
        for i in 0..<5 {
            if i < u.alts.count {
                let a = u.alts[i]
                let p = parseCommand(raw: a.transcript)
                line += ",\(csvEscape(a.transcript)),\(fmtConf(a.confidence)),\(csvEscape("\(p)")),\(canonCommand(p)),\(argumentGrade(expected: u.argumentExpected, got: extractArgument(p)))"
            } else {
                line += ",,,,,"
            }
        }
        line += ",\(String(format: "%.1f", u.sttMs))\n"
        csv += line
    }
    try? csv.write(to: base.appendingPathComponent("data/alternatives_results.csv"), atomically: true, encoding: .utf8)
    // 2. segment_alternatives.csv (una fila por segmento)
    var seg = "id,seg_index,range_start_s,range_dur_s,top_transcript,top_confidence,top_canon,alt_count"
    for i in 1...5 { seg += ",seg_alt_\(i)_transcript,seg_alt_\(i)_confidence,seg_alt_\(i)_canon" }
    seg += "\n"
    for u in us {
        for (j, s) in u.segments.enumerated() {
            let topStr = NSAttributedString(s.top).string
            var line = "\(u.id),\(j),\(String(format: "%.3f", s.rangeStart)),\(String(format: "%.3f", s.rangeDuration)),\(csvEscape(topStr)),\(fmtConf(confidenceOf(s.top))),\(canonCommand(parseCommand(raw: topStr))),\(s.alternatives.count)"
            for i in 0..<5 {
                if i < s.alternatives.count {
                    let aStr = NSAttributedString(s.alternatives[i]).string
                    line += ",\(csvEscape(aStr)),\(fmtConf(confidenceOf(s.alternatives[i]))),\(canonCommand(parseCommand(raw: aStr)))"
                } else {
                    line += ",,,"
                }
            }
            line += "\n"
            seg += line
        }
    }
    try? seg.write(to: base.appendingPathComponent("data/segment_alternatives.csv"), atomically: true, encoding: .utf8)
    // 3. error_recovery.csv (solo Top-1 failures)
    var err = "id,expected_command,category,challenge,expected_spoken_text,top1_transcript,top1_confidence,top1_canon,recovered_top2,recovered_top3,recovered_top5,recovery_class,consensus_full,consensus_full_frac,consensus_nonunknown,consensus_nonunknown_frac,multi_segment,arg_grade_top1,best_arg_grade,arg_improved\n"
    for u in us where canonCommand(parseCommand(raw: u.top1)) != u.expected {
        let topCanon = canonCommand(parseCommand(raw: u.top1))
        let (cf, ff, _) = consensus(of: u, includeUnknown: true)
        let (cn, fn, _) = consensus(of: u, includeUnknown: false)
        let order = ["WRONG": 0, "MINOR_STT_ERROR": 1, "CASE_ONLY_DIFFERENCE": 2, "EXACT": 3]
        let gTop = argumentGrade(expected: u.argumentExpected, got: extractArgument(parseCommand(raw: u.top1)))
        var best = gTop
        for h in hypotheses(of: u) {
            let g = argumentGrade(expected: u.argumentExpected, got: extractArgument(parseCommand(raw: h)))
            if (order[g] ?? 0) > (order[best] ?? 0) { best = g }
        }
        err += "\(u.id),\(u.expected),\(u.category),\(csvEscape(u.challenge)),\(csvEscape(u.expectedSpoken)),\(csvEscape(u.top1)),\(fmtConf(u.top1Confidence)),\(topCanon),\(oracleHit(of: u, k: 2) ? 1 : 0),\(oracleHit(of: u, k: 3) ? 1 : 0),\(oracleHit(of: u, k: 5) ? 1 : 0),\(recoveryClass(of: u)),\(cf),\(String(format: "%.2f", ff)),\(cn),\(String(format: "%.2f", fn)),\(u.isMultiSegment ? 1 : 0),\(gTop),\(best),\(((order[best] ?? 0) > (order[gTop] ?? 0)) ? 1 : 0)\n"
    }
    try? err.write(to: base.appendingPathComponent("data/error_recovery.csv"), atomically: true, encoding: .utf8)
    print("CSVs: alternatives_results.csv (\(us.count)), segment_alternatives.csv, error_recovery.csv")
}

// MARK: - Resumen

func printAlternativesSummary(_ us: [UtteranceAlternatives]) {
    let n = us.count
    let top1OK = us.filter { canonCommand(parseCommand(raw: $0.top1)) == $0.expected }.count
    let o2 = us.filter { oracleHit(of: $0, k: 2) }.count
    let o3 = us.filter { oracleHit(of: $0, k: 3) }.count
    let o5 = us.filter { oracleHit(of: $0, k: 5) }.count
    let fails = us.filter { canonCommand(parseCommand(raw: $0.top1)) != $0.expected }
    let r2 = fails.filter { oracleHit(of: $0, k: 2) }.count
    let r3 = fails.filter { oracleHit(of: $0, k: 3) }.count
    let r5 = fails.filter { oracleHit(of: $0, k: 5) }.count
    let never = fails.count - r5
    // Accounting
    if top1OK + fails.count != n || r2 > r3 || r3 > r5 || r5 + never != fails.count {
        print("ERROR_METRIC_ACCOUNTING")
    }
    let multi = us.filter(\.isMultiSegment).count
    let altCounts = us.map(\.alts.count)
    print("\n========================================\nSPEECH ALTERNATIVES ANALYSIS\n========================================\n")
    print("Total audio:\n\(n)\n")
    print("Single-segment: \(n - multi)  Multi-segment: \(multi) (N-best utterance solo en single-segment)")
    print("Alternatives por utterance: mean \(String(format: "%.2f", mean(altCounts.map(Double.init)))) min \(altCounts.min() ?? 0) max \(altCounts.max() ?? 0)")
    print("\nTOP-K COMMAND ORACLE\n")
    print("Top-1:\n\(top1OK)/\(n) = \(String(format: "%.1f", 100*Double(top1OK)/Double(n)))%\n")
    print("Top-2:\n\(o2)/\(n) = \(String(format: "%.1f", 100*Double(o2)/Double(n)))%\n")
    print("Top-3:\n\(o3)/\(n) = \(String(format: "%.1f", 100*Double(o3)/Double(n)))%\n")
    print("Top-5 (todo lo registrado):\n\(o5)/\(n) = \(String(format: "%.1f", 100*Double(o5)/Double(n)))%\n")
    print("TOP-1 FAILURES:\n\(fails.count)\n")
    print("Recovered by Top-2:\n\(r2)\n")
    print("Recovered by Top-3:\n\(r3)\n")
    print("Recovered by Top-5:\n\(r5)\n")
    print("Never recovered:\n\(never)\n")
    // Transcript oracle (diagnóstico)
    let t2 = us.filter { transcriptHit(of: $0, k: 2) }.count
    let t3 = us.filter { transcriptHit(of: $0, k: 3) }.count
    let t5 = us.filter { transcriptHit(of: $0, k: 5) }.count
    print("TRANSCRIPT ORACLE (normalizado, diagnóstico): Top-2 \(t2)/\(n) Top-3 \(t3)/\(n) Top-5 \(t5)/\(n)\n")
    // Recovery classes
    let strong = fails.filter { recoveryClass(of: $0) == "STRONG" }.count
    let mixed = fails.filter { recoveryClass(of: $0) == "MIXED" }.count
    let none = fails.filter { recoveryClass(of: $0) == "NONE" }.count
    print("RECOVERY CLASS (failures): STRONG \(strong) MIXED \(mixed) NONE \(none)\n")
    // Confidence
    let correctConfs = us.filter { canonCommand(parseCommand(raw: $0.top1)) == $0.expected }.compactMap(\.top1Confidence)
    let incorrectConfs = fails.compactMap(\.top1Confidence)
    let nilConf = us.filter { $0.top1Confidence == nil }.count
    let cs = descStats(correctConfs), ics = descStats(incorrectConfs)
    func show(_ s: (mean: Double, median: Double, p10: Double, p25: Double, p75: Double, p90: Double, min: Double, max: Double, n: Int)) -> String {
        String(format: "n=%d mean=%.3f median=%.3f p10=%.3f p25=%.3f p75=%.3f p90=%.3f min=%.3f max=%.3f", s.n, s.mean, s.median, s.p10, s.p25, s.p75, s.p90, s.min, s.max)
    }
    print("CONFIDENCE\n")
    print("Correct Top-1 median:\n\(String(format: "%.3f", cs.median))\n")
    print("Incorrect Top-1 median:\n\(String(format: "%.3f", ics.median))\n")
    print("Correct: \(show(cs))")
    print("Incorrect: \(show(ics))")
    print("Sin confidence (nil): \(nilConf)")
    // Alternative-level confidence availability
    let allAltConfs = us.flatMap { $0.alts.map(\.confidence) }
    let altNil = allAltConfs.filter { $0 == nil }.count
    print("Alternative-level confidence: disponible (\(allAltConfs.count - altNil)/\(allAltConfs.count) con valor, \(altNil) nil)")
    // Thresholds
    print("\nTHRESHOLDS (accept if conf >= t; nil = reject)\n")
    var thrCSV = "threshold,accepted,coverage,accepted_accuracy,incorrect_accepted,correct_rejected\n"
    for t in [0.50, 0.60, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95] {
        let accepted = us.filter { ($0.top1Confidence ?? -1) >= t }
        let rejected = us.filter { ($0.top1Confidence ?? -1) < t }
        let accOK = accepted.filter { canonCommand(parseCommand(raw: $0.top1)) == $0.expected }.count
        let rejOK = rejected.filter { canonCommand(parseCommand(raw: $0.top1)) == $0.expected }.count
        let cov = Double(accepted.count) / Double(n)
        let acc = accepted.isEmpty ? 0 : Double(accOK) / Double(accepted.count)
        print(String(format: "t=%.2f accepted=%d/%d (%.1f%%) acc=%.1f%% incorrect_accepted=%d correct_rejected=%d",
                     t, accepted.count, n, 100*cov, 100*acc, accepted.count - accOK, rejOK))
        thrCSV += String(format: "%.2f,%d,%.4f,%.4f,%d,%d\n", t, accepted.count, cov, acc, accepted.count - accOK, rejOK)
    }
    try? thrCSV.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("data/confidence_analysis.csv"), atomically: true, encoding: .utf8)
    // Safety
    print("\nSAFETY\n")
    let unsup = us.filter { $0.category == "unsupported" }
    let unk = us.filter { $0.category == "unknown" }
    func safety(_ group: [UtteranceAlternatives], k: Int) -> Int {
        group.filter { u in topKCanons(of: u, k: k).contains { isSupportedCommand($0) } }.count
    }
    print("UNSUPPORTED\ncases:\n\(unsup.count)\n")
    print("supported command appears in Top-2:\n\(safety(unsup, k: 2))\n")
    print("Top-3:\n\(safety(unsup, k: 3))\n")
    print("Top-5:\n\(safety(unsup, k: 5))\n")
    print("UNKNOWN\ncases:\n\(unk.count)\n")
    print("supported command appears in Top-2:\n\(safety(unk, k: 2))\n")
    print("Top-3:\n\(safety(unk, k: 3))\n")
    print("Top-5:\n\(safety(unk, k: 5))\n")
    // Unsafe alternatives listadas
    print("UNSAFE ALTERNATIVES (expected non-actionable -> supported en alts):")
    var unsafeCount = 0
    for u in (unsup + unk) {
        for (j, h) in hypotheses(of: u).enumerated() {
            let c = canonCommand(parseCommand(raw: h))
            if isSupportedCommand(c) {
                print("UNSAFE \(u.id) rank\(j) [\(h)] -> \(c) (expected \(u.expected))")
                unsafeCount += 1
            }
        }
    }
    if unsafeCount == 0 { print("(ninguna)") }
    // Challenges
    print("\nCHALLENGES (Top1/Top2/Top3/Top5 oracle)\n")
    func has(_ u: UtteranceAlternatives, _ t: String) -> Bool { u.challenge.split(separator: ";").map(String.init).contains(t) }
    let groups: [(String, (UtteranceAlternatives) -> Bool)] = [
        ("UNDO/REDO", { has($0, "undo_redo") }), ("FORMAT", { has($0, "format") }),
        ("FIND/SELECT", { has($0, "find_select") }), ("SAVE/EXPORT", { has($0, "save_export") }),
        ("SHORT", { has($0, "short") }), ("ARGUMENTS", { has($0, "argument") }),
    ]
    for (name, pred) in groups {
        let g = us.filter(pred)
        guard !g.isEmpty else { continue }
        print("\(name) n=\(g.count): Top1 \(g.filter { canonCommand(parseCommand(raw: $0.top1)) == $0.expected }.count) Top2 \(g.filter { oracleHit(of: $0, k: 2) }.count) Top3 \(g.filter { oracleHit(of: $0, k: 3) }.count) Top5 \(g.filter { oracleHit(of: $0, k: 5) }.count)")
    }
    // Argument recovery
    print("\nARGUMENT RECOVERY (utterances con argumento esperado no vacío)\n")
    let withArg = us.filter { !$0.argumentExpected.isEmpty }
    let order = ["WRONG": 0, "MINOR_STT_ERROR": 1, "CASE_ONLY_DIFFERENCE": 2, "EXACT": 3]
    func bestGrade(_ u: UtteranceAlternatives) -> String {
        var best = "WRONG"
        for h in hypotheses(of: u) {
            let g = argumentGrade(expected: u.argumentExpected, got: extractArgument(parseCommand(raw: h)))
            if (order[g] ?? 0) > (order[best] ?? 0) { best = g }
        }
        return best
    }
    for label in ["EXACT", "CASE_ONLY_DIFFERENCE", "MINOR_STT_ERROR", "WRONG"] {
        let t1 = withArg.filter {
            argumentGrade(expected: $0.argumentExpected, got: extractArgument(parseCommand(raw: $0.top1))) == label
        }.count
        let b = withArg.filter { bestGrade($0) == label }.count
        print("\(label): top1 \(t1) best-in-alts \(b)")
    }
    let improved = withArg.filter {
        let gTop = argumentGrade(expected: $0.argumentExpected, got: extractArgument(parseCommand(raw: $0.top1)))
        return (order[bestGrade($0)] ?? 0) > (order[gTop] ?? 0)
    }
    print("Mejoradas por alternativas: \(improved.count)/\(withArg.count)")
    for u in improved { print("ARG-IMPROVED \(u.id) [\(u.top1)] -> best \(bestGrade(u))") }
    // Fallos Top-1 con alternatives
    print("\nTOP-1 FAILURES CON ALTERNATIVES:\n")
    for u in fails {
        let hyps = hypotheses(of: u)
        let parts = hyps.enumerated().map { (j, h) in
            "r\(j)=[\(h)]->\(canonCommand(parseCommand(raw: h)))"
        }.joined(separator: " | ")
        print("FAIL \(u.id) exp=\(u.expected) class=\(recoveryClass(of: u)) multiSeg=\(u.isMultiSegment) \(parts)")
    }
}
