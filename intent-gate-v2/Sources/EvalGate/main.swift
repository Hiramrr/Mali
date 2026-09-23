// V2: CALIBRATION -> threshold (recall>=95%, min FCR, empate->max) -> FREEZE -> FINAL.
// Scores tratados como scores de ranking, sin asumir calibración probabilística.
import CoreML
import Foundation
import NaturalLanguage

struct CalRow { let text: String; let label: String; let family: String }
struct FinalRow {
    let id: String; let group: String; let text: String
    let expectedRaw: String?; let expectedGate: String
    let family: String; let critical: Bool
}

/// Split de una línea por comas respetando campos entrecomillados.
func splitLine(_ line: String) -> [String] {
    var fields: [String] = []
    var field = ""
    var inQuotes = false
    let chars = Array(line)
    var i = 0
    while i < chars.count {
        let ch = chars[i]
        if inQuotes {
            if ch == "\u{22}" {
                if i + 1 < chars.count && chars[i + 1] == "\u{22}" {
                    field.append("\u{22}"); i += 2; continue
                }
                inQuotes = false; i += 1; continue
            }
            field.append(ch); i += 1
        } else if ch == "\u{22}" {
            inQuotes = true; i += 1
        } else if ch == "," {
            fields.append(field); field = ""; i += 1
        } else if ch == "\r" {
            i += 1 // CRLF: el \r no forma parte de ningún campo
        } else {
            field.append(ch); i += 1
        }
    }
    fields.append(field)
    return fields
}

/// Filas del CSV (sin header) como arreglos de campos completos.
func csvRows(_ text: String) -> [[String]] {
    var out: [[String]] = []
    for line in text.components(separatedBy: "\n") {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
        out.append(splitLine(line))
    }
    if let first = out.first, first[0] == "text" || first[0] == "id" {
        out.removeFirst()
    }
    return out
}

func parseCSV2(_ text: String) -> [[String]] {
    csvRows(text)
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
/// Wilson score interval 95% para proporción k/n.
func wilson(k: Int, n: Int, z: Double = 1.96) -> (Double, Double) {
    guard n > 0 else { return (0, 0) }
    let p = Double(k) / Double(n)
    let denom = 1 + z * z / Double(n)
    let center = (p + z * z / (2 * Double(n))) / denom
    let half = z * sqrt(p * (1 - p) / Double(n) + z * z / (4 * Double(n * n))) / denom
    return (max(0, center - half), min(1, center + half))
}

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let modelsDir = cwd.appendingPathComponent("models")
let dataDir = cwd.appendingPathComponent("data")

let clock = ContinuousClock()
var t0 = clock.now
let compiledURL = try MLModel.compileModel(at: modelsDir.appendingPathComponent("IntentGateV2.mlmodel"))
let loadMs = ms(t0, clock.now)

@MainActor
func makeModel() throws -> NLModel { try NLModel(contentsOf: compiledURL) }
let nl = try makeModel()

@MainActor
func scores(_ text: String) -> (control: Double, dictation: Double, raw: String) {
    let h = nl.predictedLabelHypotheses(for: text, maximumCount: 2)
    let c = h["EDITOR_CONTROL"] ?? 0, d = h["DICTATION"] ?? 0
    return (c, d, c >= d ? "EDITOR_CONTROL" : "DICTATION")
}

// ---- CALIBRATION ----
let calRows = parseCSV2(try String(contentsOf: dataDir.appendingPathComponent("calibration.csv"), encoding: .utf8))
var cal: [(control: Double, dictation: Double, isControl: Bool, text: String, family: String)] = []
for r in calRows where r.count >= 4 {
    let s = scores(r[0])
    cal.append((s.control, s.dictation, r[1] == "EDITOR_CONTROL", r[0], r[3]))
}
let nCalC = cal.filter(\.isControl).count
let nCalD = cal.count - nCalC

// Candidatos: puntos de decisión de scores observados + rejilla de comprensión.
var cands = Set<Double>()
for s in cal { cands.insert(s.control) }
let sorted = cands.sorted()
var thresholds: [Double] = [0.0]
for i in 0..<sorted.count {
    thresholds.append(sorted[i])
    if i + 1 < sorted.count { thresholds.append((sorted[i] + sorted[i + 1]) / 2) }
}
thresholds.append(1.0)

@MainActor
func metricsAt(_ thr: Double) -> (rec: Double, fcr: Double) {
    let tp = cal.filter { $0.isControl && $0.control >= thr }.count
    let fp = cal.filter { !$0.isControl && $0.control >= thr }.count
    return (nCalC > 0 ? Double(tp) / Double(nCalC) : 0,
            nCalD > 0 ? Double(fp) / Double(nCalD) : 0)
}
// Política: recall>=0.95, minimizar FCR, empate->máximo threshold.
var best: (thr: Double, rec: Double, fcr: Double)? = nil
for t in thresholds {
    let m = metricsAt(t)
    guard m.rec >= 0.95 else { continue }
    if best == nil || m.fcr < best!.fcr || (m.fcr == best!.fcr && t > best!.thr) {
        best = (t, m.rec, m.fcr)
    }
}
guard let sel = best else { fatalError("ningún threshold con recall>=95% en calibration") }

let calRawOk = cal.filter { ($0.control >= $0.dictation ? "EDITOR_CONTROL" : "DICTATION") == ($0.isControl ? "EDITOR_CONTROL" : "DICTATION") }.count
let calTP = cal.filter { $0.isControl && $0.control >= sel.thr }.count
let calFP = cal.filter { !$0.isControl && $0.control >= sel.thr }.count
let wRec = wilson(k: calTP, n: nCalC)
let wFcr = wilson(k: calFP, n: nCalD)
let calMinControlMargin = cal.filter(\.isControl).map { $0.control - $0.dictation }.min() ?? 0
let calMaxDictMargin = cal.filter { !$0.isControl }.map { $0.control - $0.dictation }.max() ?? 0

print("")
print("CALIBRATION")
print("=================================")
print("")
print("Control examples: \(nCalC)")
print("No-control examples: \(nCalD)")
print(String(format: "Raw accuracy: %.1f%%", 100.0 * Double(calRawOk) / Double(max(cal.count, 1))))
print(String(format: "Selected threshold: %.3f", sel.thr))
print(String(format: "Control recall: %.1f%%", sel.rec * 100))
print(String(format: "False Control Rate: %.2f%%", sel.fcr * 100))
print(String(format: "Control recall 95 %% CI (Wilson): [%.1f%%, %.1f%%]", wRec.0 * 100, wRec.1 * 100))
print(String(format: "FCR 95 %% CI (Wilson): [%.2f%%, %.2f%%]", wFcr.0 * 100, wFcr.1 * 100))
print(String(format: "Lowest control score: %.3f", cal.filter(\.isControl).map(\.control).min() ?? 0))
print(String(format: "Highest dictation score: %.3f", cal.filter { !$0.isControl }.map(\.control).max() ?? 0))
print("")
print("THRESHOLD FROZEN")
print("")

// ---- FINAL_TEST_V2 ----
let finRows = parseCSV2(try String(contentsOf: dataDir.appendingPathComponent("final_test_v2.csv"), encoding: .utf8))
var finals: [FinalRow] = []
for r in finRows where r.count >= 7 {
    finals.append(FinalRow(id: r[0], group: r[1], text: r[2],
                           expectedRaw: r[3].isEmpty ? nil : r[3], expectedGate: r[4],
                           family: r[5], critical: r[6] == "1"))
}
struct Out {
    let f: FinalRow; let control: Double; let dictation: Double
    let raw: String; let gate: String; let lat: Double
}
var outs: [Out] = []
for h in finals {
    let s0 = clock.now
    let s = scores(h.text)
    let lat = ms(s0, clock.now)
    outs.append(Out(f: h, control: s.control, dictation: s.dictation, raw: s.raw,
                    gate: s.control >= sel.thr ? "EDITOR_CONTROL" : "NO_CONTROL_GATE", lat: lat))
}

let withRaw = outs.filter { $0.f.expectedRaw != nil }
let rawOk = withRaw.filter { $0.raw == $0.f.expectedRaw }.count
let tp = withRaw.filter { $0.f.expectedRaw == "EDITOR_CONTROL" && $0.raw == "EDITOR_CONTROL" }.count
let fpR = withRaw.filter { $0.f.expectedRaw == "DICTATION" && $0.raw == "EDITOR_CONTROL" }.count
let fnR = withRaw.filter { $0.f.expectedRaw == "EDITOR_CONTROL" && $0.raw == "DICTATION" }.count
let tnR = withRaw.filter { $0.f.expectedRaw == "DICTATION" && $0.raw == "DICTATION" }.count
let noCtl = outs.filter { $0.f.expectedGate == "NO_CONTROL" }
let ctl = outs.filter { $0.f.expectedGate == "CONTROL" }
let passes = noCtl.filter { $0.gate == "EDITOR_CONTROL" }.count
let missed = ctl.filter { $0.gate != "EDITOR_CONTROL" }.count
let gateOkCount = outs.filter {
    ($0.f.expectedGate == "CONTROL") == ($0.gate == "EDITOR_CONTROL")
}.count
let crit = outs.filter(\.f.critical)
let critPass = crit.filter { $0.gate == "EDITOR_CONTROL" }.count
let wFCR = wilson(k: passes, n: noCtl.count)
let wRecF = wilson(k: ctl.count - missed, n: ctl.count)

print("FINAL TEST V2")
print("=================================")
print("")
print("Total: \(outs.count)")
print("EDITOR_CONTROL: \(ctl.count)")
print("NO_CONTROL: \(noCtl.count)")
print(String(format: "Raw accuracy: %.1f%% (%d/%d)", 100.0 * Double(rawOk) / Double(max(withRaw.count, 1)), rawOk, withRaw.count))
print(String(format: "Gate accuracy: %.1f%% (%d/%d)", 100.0 * Double(gateOkCount) / Double(max(outs.count, 1)), gateOkCount, outs.count))
print(String(format: "Control precision: %.1f%%", tp + fpR > 0 ? 100.0 * Double(tp) / Double(tp + fpR) : 0))
print(String(format: "Control recall: %.1f%%", tp + fnR > 0 ? 100.0 * Double(tp) / Double(tp + fnR) : 0))
print("False Control Passes: \(passes)")
print(String(format: "False Control Rate: %.2f%%", 100.0 * Double(passes) / Double(max(noCtl.count, 1))))
print(String(format: "False Control Rate 95 %% CI (Wilson): [%.2f%%, %.2f%%]", wFCR.0 * 100, wFCR.1 * 100))
print("Missed Controls: \(missed)")
print(String(format: "Missed Control Rate: %.1f%%", 100.0 * Double(missed) / Double(max(ctl.count, 1))))
print(String(format: "Control recall 95 %% CI (Wilson): [%.1f%%, %.1f%%]", wRecF.0 * 100, wRecF.1 * 100))
print(String(format: "Critical Challenge: %d / %d false passes", critPass, crit.count))
print("")
print("RAW MODEL vs SAFETY GATE:")
print("raw correct: \(rawOk)/\(withRaw.count)  gate correct: \(gateOkCount)/\(outs.count)")
print("")
print("Confusion RAW (D/EC): DICTATION \(tnR)/\(fpR), CONTROL \(fnR)/\(tp)")
let gTN = noCtl.filter { $0.gate == "NO_CONTROL_GATE" }.count
print("Confusion GATE (NO_CONTROL \(gTN)/\(passes), CONTROL \(missed)/\(ctl.count - missed))")
print("")
print("Threshold display (final, análisis):")
for t in [0.50, 0.60, 0.70, 0.80, 0.90, 0.95, 0.98] {
    let fp = noCtl.filter { $0.control >= t }.count
    let rc = ctl.filter { $0.control >= t }.count
    print(String(format: "thr=%.2f FCR=%.2f%% recall=%.1f%%", t,
                 100.0 * Double(fp) / Double(max(noCtl.count, 1)),
                 100.0 * Double(rc) / Double(max(ctl.count, 1))))
}
print("")
// Pares mínimos H
print("Pares mínimos (H):")
for i in stride(from: 0, to: outs.count, by: 1) {
    let o = outs[i]
    if o.f.group == "H", o.f.id.hasSuffix("a") {
        let num = o.f.id.dropLast()
        if let b = outs.first(where: { $0.f.id == num + "b" }) {
            print("\(o.f.id) c=\(String(format: "%.3f", o.control)) gate=\(o.gate) | \(o.f.text)")
            print("\(b.f.id) c=\(String(format: "%.3f", b.control)) gate=\(b.gate) | \(b.f.text)")
        }
    }
}
print("")
let lats = outs.map(\.lat).sorted()
print(String(format: "Latency: load=%.0f ms mean=%.1f median=%.1f p95=%.1f min=%.1f max=%.1f", loadMs,
             lats.reduce(0, +) / Double(max(lats.count, 1)), percentile(lats, 0.5),
             percentile(lats, 0.95), lats.first ?? 0, lats.last ?? 0))
print("Margins (control-dictation):")
for (name, set) in [("CALIBRATION", cal.map { ($0.isControl, $0.control - $0.dictation) }),
                    ("FINAL", outs.map { ($0.f.expectedGate == "CONTROL", $0.control - $0.dictation) })] {
    let cMin = set.filter(\.0).map(\.1).min() ?? 0
    let dMax = set.filter { !$0.0 }.map(\.1).max() ?? 0
    print(String(format: "%@: min margin CONTROL=%.3f max margin NO_CONTROL=%.3f", name, cMin, dMax))
}
// TRAIN margins requieren re-puntuar train (rápido, ~1000 casos x 7ms)
let trainText = try String(contentsOf: dataDir.appendingPathComponent("train.json"), encoding: .utf8)
let trainRows = try JSONDecoder().decode([[String: String]].self, from: Data(trainText.utf8))
var trMin = Double.greatestFiniteMagnitude, trMax = -Double.greatestFiniteMagnitude
for r in trainRows {
    guard let t = r["text"], let l = r["label"] else { continue }
    let s = scores(t)
    let m = s.control - s.dictation
    if l == "EDITOR_CONTROL" { trMin = min(trMin, m) } else { trMax = max(trMax, m) }
}
print(String(format: "TRAIN: min margin CONTROL=%.3f max margin NO_CONTROL=%.3f", trMin, trMax))
print("")
print("Fallos:")
var nf = 0
for o in outs {
    let rawOk1 = o.f.expectedRaw == nil || o.raw == o.f.expectedRaw
    let gateOk1 = (o.f.expectedGate == "CONTROL") == (o.gate == "EDITOR_CONTROL")
    if !rawOk1 || !gateOk1 {
        nf += 1
        print("--- \(o.f.id) [\(o.f.group)] fam=\(o.f.family)")
        print("TEXT: \(o.f.text)")
        print("EXPECTED: \(o.f.expectedRaw ?? "(DO NOT PASS)") / gate \(o.f.expectedGate)")
        print("RAW: \(o.raw)  CONTROL SCORE: \(String(format: "%.3f", o.control))  DICTATION SCORE: \(String(format: "%.3f", o.dictation))")
        print("GATE: \(o.gate)  THRESHOLD: \(String(format: "%.3f", sel.thr))")
    }
}
if nf == 0 { print("ninguno") }
print("")
print("Legacy diagnostic (NO es prueba final):")
let legRows = parseCSV2(try String(contentsOf: dataDir.appendingPathComponent("legacy_diagnostic_holdout.csv"), encoding: .utf8))
var legPass = 0, legMiss = 0, legNo = 0, legCtl = 0
for r in legRows where r.count >= 5 {
    let text = r[2], gate = r[4]
    let s = scores(text)
    let g = s.control >= sel.thr ? "EDITOR_CONTROL" : "NO_CONTROL_GATE"
    if gate == "NO_CONTROL" {
        legNo += 1
        if g == "EDITOR_CONTROL" { legPass += 1 }
    } else {
        legCtl += 1
        if g != "EDITOR_CONTROL" { legMiss += 1 }
    }
}
print(String(format: "legacy: %d casos, passes %d/%d (%.2f%%), missed %d/%d",
             legNo + legCtl, legPass, legNo,
             legNo > 0 ? 100.0 * Double(legPass) / Double(legNo) : 0, legMiss, legCtl))
print("nota: el resultado legacy NO participa en ningún criterio.")
