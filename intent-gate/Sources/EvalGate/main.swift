// EvalGate: threshold SOLO con validation -> FREEZE -> holdout.
// Estrategia de zona: single-threshold. controlScore >= thr -> EDITOR_CONTROL,
// en otro caso NO_CONTROL_GATE (UNCERTAIN queda plegado en NO_CONTROL_GATE:
// operacionalmente nada cruza el gate). El label raw se imprime siempre.
import CoreML
import Foundation
import NaturalLanguage

struct Row: Codable {
    let text: String
    let label: String
    let category: String
}
struct HoldoutRow {
    let id: String
    let group: String
    let text: String
    let expectedRaw: String?   // nil en grupo H
    let expectedGate: String   // CONTROL | NO_CONTROL
}

// Parser CSV con índice (soporta "" escapado y saltos dentro de comillas si los hubiera).
func parseCSV2(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var field = "", row: [String] = [], inQuotes = false
    let chars = Array(text)
    var i = 0
    while i < chars.count {
        let ch = chars[i]
        if inQuotes {
            if ch == "\"" {
                if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 2; continue }
                inQuotes = false; i += 1; continue
            }
            field.append(ch); i += 1
        } else if ch == "\"" { inQuotes = true; i += 1 }
        else if ch == "," { row.append(field); field = ""; i += 1 }
        else if ch == "\n" { row.append(field); rows.append(row); row = []; field = ""; i += 1 }
        else if ch == "\r" { i += 1 }
        else { field.append(ch); i += 1 }
    }
    if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
    return rows
}

func ms(_ start: ContinuousClock.Instant, _ end: ContinuousClock.Instant) -> Double {
    let c = (end - start).components
    return Double(c.seconds) * 1000.0 + Double(c.attoseconds) / 1e15
}
func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let rank = p * Double(sorted.count - 1)
    let lo = Int(rank.rounded(.down)), hi = Int(rank.rounded(.up))
    if lo == hi { return sorted[lo] }
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (rank - Double(lo))
}
func dirSize(_ url: URL) -> Int64 {
    var total: Int64 = 0
    if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
        for case let f as URL in e {
            total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
    return total
}

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let modelsDir = cwd.appendingPathComponent("models")

// ---- Carga del modelo ----
let clock = ContinuousClock()
var t0 = clock.now
let compiledURL = try MLModel.compileModel(at: modelsDir.appendingPathComponent("IntentGate.mlmodel"))
let loadMs = ms(t0, clock.now)
let nl = try NLModel(contentsOf: compiledURL)
print(String(format: "model load (compile+NLModel): %.0f ms", loadMs))

@MainActor
func scores(_ text: String) -> (control: Double, dictation: Double, raw: String) {
    let h = nl.predictedLabelHypotheses(for: text, maximumCount: 2)
    let c = h["EDITOR_CONTROL"] ?? 0, d = h["DICTATION"] ?? 0
    return (c, d, c >= d ? "EDITOR_CONTROL" : "DICTATION")
}

// ---- Validation: selección de threshold (FPR<=2%, max recall) ----
let valText = try String(contentsOf: modelsDir.appendingPathComponent("validation.csv"), encoding: .utf8)
let valRows = parseCSV2(valText).dropFirst()
var valScores: [(control: Double, isControl: Bool)] = []
for r in valRows where r.count >= 2 {
    let s = scores(r[0])
    valScores.append((s.control, r[1] == "EDITOR_CONTROL"))
}
let nValControl = valScores.filter(\.isControl).count
let nValDict = valScores.count - nValControl
var best: (thr: Double, fpr: Double, rec: Double)? = nil
for cand in stride(from: 0.01, through: 0.99, by: 0.01) {
    let fp = valScores.filter { !$0.isControl && $0.control >= cand }.count
    let tp = valScores.filter { $0.isControl && $0.control >= cand }.count
    let fpr = nValDict > 0 ? Double(fp) / Double(nValDict) : 0
    let rec = nValControl > 0 ? Double(tp) / Double(nValControl) : 0
    if fpr <= 0.02, best == nil || rec > best!.rec {
        best = (cand, fpr, rec)
    }
}
guard let sel = best else { fatalError("ningún threshold cumple FPR<=2% en validation") }
print(String(format: "Selected threshold: %.2f", sel.thr))
print(String(format: "Validation FPR: %.2f%%", sel.fpr * 100))
print(String(format: "Validation control recall: %.1f%% (%d control, %d dictation)",
             sel.rec * 100, nValControl, nValDict))
print("FREEZE THRESHOLD — a partir de aquí solo holdout")

// ---- Holdout ----
let holdText = try String(contentsOf: cwd.appendingPathComponent("data/holdout.csv"), encoding: .utf8)
let holdRows = parseCSV2(holdText).dropFirst()
var holdout: [HoldoutRow] = []
for r in holdRows where r.count >= 5 {
    holdout.append(HoldoutRow(id: r[0], group: r[1], text: r[2],
                              expectedRaw: r[3].isEmpty ? nil : r[3], expectedGate: r[4]))
}
print("holdout: \(holdout.count) casos")

struct Outcome {
    let h: HoldoutRow
    let control: Double
    let dictation: Double
    let raw: String
    let gate: String  // EDITOR_CONTROL | NO_CONTROL_GATE
    let latencyMs: Double
}
var outcomes: [Outcome] = []
for h in holdout {
    let s0 = clock.now
    let s = scores(h.text)
    let lat = ms(s0, clock.now)
    let gate = s.control >= sel.thr ? "EDITOR_CONTROL" : "NO_CONTROL_GATE"
    outcomes.append(Outcome(h: h, control: s.control, dictation: s.dictation,
                            raw: s.raw, gate: gate, latencyMs: lat))
    // Salida por caso
    print("--------------------------------------------------")
    print("")
    print("INPUT:")
    print(h.text)
    print("")
    print("EXPECTED:")
    print(h.expectedRaw ?? "(sin raw: DO NOT PASS)")
    print("")
    print("CONTROL SCORE:")
    print(String(format: "%.3f", s.control))
    print("")
    print("DICTATION SCORE:")
    print(String(format: "%.3f", s.dictation))
    print("")
    print("CONTROL THRESHOLD:")
    print(String(format: "%.2f", sel.thr))
    print("")
    print("GATE:")
    print(gate)
    print("")
    let pass: Bool
    if h.expectedGate == "CONTROL" { pass = gate == "EDITOR_CONTROL" && h.expectedRaw == s.raw }
    else { pass = gate == "NO_CONTROL_GATE" }
    if h.expectedGate == "NO_CONTROL" && gate == "EDITOR_CONTROL" {
        print("✗ FALSE CONTROL GATE")
    } else if pass {
        print(h.expectedGate == "CONTROL" ? "✓ CORRECT" : "✓ SAFE")
    } else {
        print("✗ MISSED CONTROL")
    }
    print("")
    print("--------------------------------------------------")
}

// ---- Métricas ----
let withRaw = outcomes.filter { $0.h.expectedRaw != nil }
let rawCorrect = withRaw.filter { $0.raw == $0.h.expectedRaw }.count
let tp = withRaw.filter { $0.h.expectedRaw == "EDITOR_CONTROL" && $0.raw == "EDITOR_CONTROL" }.count
let fpRaw = withRaw.filter { $0.h.expectedRaw == "DICTATION" && $0.raw == "EDITOR_CONTROL" }.count
let fnRaw = withRaw.filter { $0.h.expectedRaw == "EDITOR_CONTROL" && $0.raw == "DICTATION" }.count
let tnRaw = withRaw.filter { $0.h.expectedRaw == "DICTATION" && $0.raw == "DICTATION" }.count
let noControlCases = outcomes.filter { $0.h.expectedGate == "NO_CONTROL" }
let falsePasses = noControlCases.filter { $0.gate == "EDITOR_CONTROL" }.count
let controlCases = outcomes.filter { $0.h.expectedGate == "CONTROL" }
let missed = controlCases.filter { $0.gate != "EDITOR_CONTROL" }.count
let groupG = outcomes.filter { $0.h.group == "G" }
let groupGPass = groupG.filter { $0.gate == "EDITOR_CONTROL" }.count

print("")
print("========================================")
print("INTENT GATE HOLDOUT")
print("========================================")
print("")
print(String(format: "Raw classifier accuracy: %.1f%% (%d/%d)",
             100.0 * Double(rawCorrect) / Double(max(withRaw.count, 1)), rawCorrect, withRaw.count))
print(String(format: "Control precision: %.1f%%  recall: %.1f%%",
             tp + fpRaw > 0 ? 100.0 * Double(tp) / Double(tp + fpRaw) : 0,
             tp + fnRaw > 0 ? 100.0 * Double(tp) / Double(tp + fnRaw) : 0))
print(String(format: "Dictation precision: %.1f%%  recall: %.1f%%",
             tnRaw + fnRaw > 0 ? 100.0 * Double(tnRaw) / Double(tnRaw + fnRaw) : 0,
             tnRaw + fpRaw > 0 ? 100.0 * Double(tnRaw) / Double(tnRaw + fpRaw) : 0))
print("")
print(String(format: "False Control Gate Passes: %d/%d", falsePasses, noControlCases.count))
print(String(format: "False Control Gate Rate: %.2f%%",
             100.0 * Double(falsePasses) / Double(max(noControlCases.count, 1))))
print(String(format: "Missed Control Gate: %d/%d", missed, controlCases.count))
print(String(format: "Missed Control Rate: %.1f%%",
             100.0 * Double(missed) / Double(max(controlCases.count, 1))))
print(String(format: "CRITICAL GROUP FALSE PASSES: %d/%d", groupGPass, groupG.count))
print("")
print("Confusion matrix RAW (rows=expected, cols=D/EC):")
print("DICTATION: \(tnRaw) / \(fpRaw)")
print("EDITOR_CONTROL: \(fnRaw) / \(tp)")
print("Confusion matrix GATE (rows=expected gate, cols=NO_CONTROL/EDITOR_CONTROL):")
let gTN = noControlCases.filter { $0.gate == "NO_CONTROL_GATE" }.count
print("NO_CONTROL: \(gTN) / \(falsePasses)")
print("CONTROL: \(missed) / \(controlCases.count - missed)")
print("")
print("Threshold analysis (holdout, solo análisis):")
for t in [0.50, 0.70, 0.80, 0.90, 0.95, 0.98] {
    let fp = noControlCases.filter { $0.control >= t }.count
    let rc = controlCases.filter { $0.control >= t }.count
    print(String(format: "thr=%.2f FPR=%.2f%% recall=%.1f%%",
                 t, 100.0 * Double(fp) / Double(max(noControlCases.count, 1)),
                 100.0 * Double(rc) / Double(max(controlCases.count, 1))))
}
print("")
let lats = outcomes.map(\.latencyMs).sorted()
print("Latency (ms, inferencia por caso):")
print(String(format: "mean=%.1f median=%.1f p95=%.1f min=%.1f max=%.1f",
             lats.reduce(0, +) / Double(max(lats.count, 1)), percentile(lats, 0.5),
             percentile(lats, 0.95), lats.first ?? 0, lats.last ?? 0))
let mlmodelURL = modelsDir.appendingPathComponent("IntentGate.mlmodel")
let mlmodelSize = Int64((try? mlmodelURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
print(String(format: ".mlmodel size: %.1f MB", Double(mlmodelSize) / 1e6))
print(String(format: "compiled model size: %.1f MB", Double(dirSize(compiledURL)) / 1e6))
var ru = rusage()
getrusage(Int32(RUSAGE_SELF), &ru)
print(String(format: "RSS aproximado: %.0f MB", Double(ru.ru_maxrss) / 1024.0 / 1024.0))
print("")
print("Fallos (raw o gate):")
var nFail = 0
for o in outcomes {
    let rawOk = o.h.expectedRaw == nil || o.raw == o.h.expectedRaw
    let gateOk = (o.h.expectedGate == "CONTROL") == (o.gate == "EDITOR_CONTROL")
    if !rawOk || !gateOk {
        nFail += 1
        print("--- \(o.h.id) [\(o.h.group)] exp_raw=\(o.h.expectedRaw ?? "-") exp_gate=\(o.h.expectedGate) raw=\(o.raw) gate=\(o.gate) c=\(String(format: "%.3f", o.control)) | \(o.h.text)")
    }
}
if nFail == 0 { print("ninguno") }
