// V4: T_CONTROL (recall>=97%, min FCR, empate->max) -> FREEZE -> FINAL.
// Métricas desde EvaluationRecord único + verificación contable.
import CoreML
import Foundation
import NaturalLanguage

let Q = "\u{22}"

func splitLine(_ line: String) -> [String] {
    var fields: [String] = []
    var field = ""
    var inQuotes = false
    let chars = Array(line)
    var i = 0
    while i < chars.count {
        let ch = chars[i]
        if inQuotes {
            if ch == Character(Q) {
                if i + 1 < chars.count && chars[i + 1] == Character(Q) {
                    field.append(Character(Q)); i += 2; continue
                }
                inQuotes = false; i += 1; continue
            }
            field.append(ch); i += 1
        } else if ch == Character(Q) {
            inQuotes = true; i += 1
        } else if ch == "," {
            fields.append(field); field = ""; i += 1
        } else if ch == "\r" {
            i += 1
        } else {
            field.append(ch); i += 1
        }
    }
    fields.append(field)
    return fields
}

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
func wilson(k: Int, n: Int, z: Double = 1.96) -> (Double, Double) {
    guard n > 0 else { return (0, 0) }
    let p = Double(k) / Double(n)
    let denom = 1 + z * z / Double(n)
    let center = (p + z * z / (2 * Double(n))) / denom
    let half = z * sqrt(p * (1 - p) / Double(n) + z * z / (4 * Double(n * n))) / denom
    return (max(0, center - half), min(1, center + half))
}

struct EvaluationRecord {
    let expected: String      // EDITOR_CONTROL | NON_CONTROL
    let rawPrediction: String // EDITOR_CONTROL | NON_CONTROL
    let controlScore: Double
    let gatePassed: Bool
    let category: String
    let familyID: String
}

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let modelsDir = cwd.appendingPathComponent("models")
let dataDir = cwd.appendingPathComponent("data")

let clock = ContinuousClock()
let t0 = clock.now
let compiledURL = try MLModel.compileModel(at: modelsDir.appendingPathComponent("IntentGateV4.mlmodel"))
let loadMs = ms(t0, clock.now)

@MainActor
func makeModel() throws -> NLModel { try NLModel(contentsOf: compiledURL) }
let nl = try makeModel()

@MainActor
func predict(_ text: String) -> (raw: String, c: Double) {
    let h = nl.predictedLabelHypotheses(for: text, maximumCount: 2)
    let c = h["EDITOR_CONTROL"] ?? 0
    return (c >= 0.5 ? "EDITOR_CONTROL" : "NON_CONTROL", c)
}

// ---- CALIBRATION ----
let calRows = csvRows(try String(contentsOf: dataDir.appendingPathComponent("calibration.csv"), encoding: .utf8))
var calScores: [(c: Double, isCtl: Bool)] = []
for r in calRows where r.count >= 2 {
    let p = predict(r[0])
    calScores.append((p.c, r[1] == "EDITOR_CONTROL"))
}
let nCalC = calScores.filter(\.isCtl).count
let nCalN = calScores.count - nCalC

@MainActor
func calCandidates() -> [Double] {
    let s = Set(calScores.map(\.c)).sorted()
    var out: [Double] = [0.0]
    for i in 0..<s.count {
        out.append(s[i])
        if i + 1 < s.count { out.append((s[i] + s[i + 1]) / 2) }
    }
    out.append(1.0)
    return out
}

@MainActor
func metricsAt(_ thr: Double) -> (rec: Double, fcr: Double) {
    let tp = calScores.filter { $0.isCtl && $0.c >= thr }.count
    let fp = calScores.filter { !$0.isCtl && $0.c >= thr }.count
    return (nCalC > 0 ? Double(tp) / Double(nCalC) : 0,
            nCalN > 0 ? Double(fp) / Double(nCalN) : 0)
}

var TC = 0.0
var usedFallback = false
var best97: (thr: Double, rec: Double, fcr: Double)? = nil
for t in calCandidates() {
    let m = metricsAt(t)
    guard m.rec >= 0.97 else { continue }
    if best97 == nil || m.fcr < best97!.fcr || (m.fcr == best97!.fcr && t > best97!.thr) {
        best97 = (t, m.rec, m.fcr)
    }
}
if let b = best97 {
    TC = b.thr
    print(String(format: "T_CONTROL: %.3f (recall %.1f%%, FCR %.2f%%) regla estándar", b.thr, b.rec * 100, b.fcr * 100))
} else {
    usedFallback = true
    var bf: (thr: Double, rec: Double, fcr: Double)? = nil
    for t in calCandidates() {
        let m = metricsAt(t)
        if bf == nil || m.rec > bf!.rec || (m.rec == bf!.rec && (m.fcr < bf!.fcr || (m.fcr == bf!.fcr && t > bf!.thr))) {
            bf = (t, m.rec, m.fcr)
        }
    }
    TC = bf!.thr
    print(String(format: "T_CONTROL: %.3f (recall %.1f%%, FCR %.2f%%) FALLBACK: 97%% inalcanzable", bf!.thr, bf!.rec * 100, bf!.fcr * 100))
}
print("THRESHOLD FROZEN")
print("")

// ---- FINAL_TEST_V4 ----
let finRows = csvRows(try String(contentsOf: dataDir.appendingPathComponent("final_test_v4.csv"), encoding: .utf8))
struct FMeta {
    let id: String; let group: String; let text: String; let raw: String
    let family: String; let critical: Bool; let coverage: Bool; let pair: String
}
var metas: [FMeta] = []
for r in finRows where r.count >= 8 {
    metas.append(FMeta(id: r[0], group: r[1], text: r[2], raw: r[3], family: r[4],
                       critical: r[5] == "1", coverage: r[6] == "1", pair: r[7]))
}
var records: [EvaluationRecord] = []
var latencies: [Double] = []
for m in metas {
    let s0 = clock.now
    let p = predict(m.text)
    latencies.append(ms(s0, clock.now))
    records.append(EvaluationRecord(expected: m.raw, rawPrediction: p.raw, controlScore: p.c,
                                    gatePassed: p.c >= TC, category: m.group, familyID: m.family))
}

// ---- verificación contable ----
let total = records.count
let rawTP = records.filter { $0.expected == "EDITOR_CONTROL" && $0.rawPrediction == "EDITOR_CONTROL" }.count
let rawTN = records.filter { $0.expected == "NON_CONTROL" && $0.rawPrediction == "NON_CONTROL" }.count
let rawFP = records.filter { $0.expected == "NON_CONTROL" && $0.rawPrediction == "EDITOR_CONTROL" }.count
let rawFN = records.filter { $0.expected == "EDITOR_CONTROL" && $0.rawPrediction == "NON_CONTROL" }.count
let gateTP = records.filter { $0.expected == "EDITOR_CONTROL" && $0.gatePassed }.count
let gateTN = records.filter { $0.expected == "NON_CONTROL" && !$0.gatePassed }.count
let gateFP = records.filter { $0.expected == "NON_CONTROL" && $0.gatePassed }.count
let gateFN = records.filter { $0.expected == "EDITOR_CONTROL" && !$0.gatePassed }.count
let catSum = Dictionary(grouping: records, by: \.category).values.map(\.count).reduce(0, +)
guard rawTP + rawTN + rawFP + rawFN == total,
      gateTP + gateTN + gateFP + gateFN == total,
      catSum == total else {
    fatalError("ERROR_METRIC_ACCOUNTING")
}
print("metric accounting: OK (\(total) registros)")

let nExpC = rawTP + rawFN
let nExpN = rawTN + rawFP
let rawAcc = Double(rawTP + rawTN) / Double(total)
let cPrec = rawTP + rawFP > 0 ? Double(rawTP) / Double(rawTP + rawFP) : 0
let cRec = nExpC > 0 ? Double(rawTP) / Double(nExpC) : 0
let nPrec = rawTN + rawFN > 0 ? Double(rawTN) / Double(rawTN + rawFN) : 0
let nRec = nExpN > 0 ? Double(rawTN) / Double(nExpN) : 0
let fcr = nExpN > 0 ? Double(gateFP) / Double(nExpN) : 0
let miss = nExpC > 0 ? Double(gateFN) / Double(nExpC) : 0
let gateRec = nExpC > 0 ? Double(gateTP) / Double(nExpC) : 0
let wFCR = wilson(k: gateFP, n: nExpN)
let wRec = wilson(k: gateTP, n: nExpC)

print("")
print("FINAL TEST V4")
print("=================================")
print("Total: \(total)  CONTROL: \(nExpC)  NON_CONTROL: \(nExpN)")
print(String(format: "Raw accuracy: %.2f%%", rawAcc * 100))
print(String(format: "Control precision: %.1f%%  recall: %.1f%%", cPrec * 100, cRec * 100))
print(String(format: "NON_CONTROL precision: %.1f%%  recall: %.1f%%", nPrec * 100, nRec * 100))
print("False Control Passes: \(gateFP)")
print(String(format: "False Control Rate: %.2f%%  Wilson95 [%.2f%%, %.2f%%]", fcr * 100, wFCR.0 * 100, wFCR.1 * 100))
print("Missed Controls: \(gateFN)")
print(String(format: "Missed Control Rate: %.2f%%", miss * 100))
print(String(format: "Gate Control Recall: %.1f%%  Wilson95 [%.1f%%, %.1f%%]", gateRec * 100, wRec.0 * 100, wRec.1 * 100))
print("")
print("Matriz raw (filas NON/CONTROL, cols NON/CONTROL):")
print("NON: \(rawTN) / \(rawFP)")
print("CONTROL: \(rawFN) / \(rawTP)")
print("Matriz gate (filas NON/CONTROL, cols DO_NOT_PASS/PASS):")
print("NON: \(gateTN) / \(gateFP)")
print("CONTROL: \(gateFN) / \(gateTP)")
print("")

// Challenges (por flags; pares por columna pair)
var critIdx: [Int] = [], covIdx: [Int] = []
for (i, m) in metas.enumerated() {
    if m.critical { critIdx.append(i) }
    if m.coverage { covIdx.append(i) }
}
let critFP = critIdx.filter { records[$0].gatePassed }.count
let wCrit = wilson(k: critFP, n: critIdx.count)
let covTP = covIdx.filter { records[$0].gatePassed }.count
let wCov = wilson(k: covTP, n: covIdx.count)
print(String(format: "CRITICAL_NEGATIVE: %d/%d passes  Wilson95 [%.2f%%, %.2f%%]", critFP, critIdx.count, wCrit.0 * 100, wCrit.1 * 100))
print(String(format: "CONTROL_COVERAGE: %d/%d recall  Wilson95 [%.1f%%, %.1f%%]", covTP, covIdx.count, wCov.0 * 100, wCov.1 * 100))

// Short utterances (categoría corto) y pares mínimos
let shortIdx = metas.indices.filter { metas[$0].family.contains("short") || metas[$0].family.contains("corto") }
let shortCtl = shortIdx.filter { records[$0].expected == "EDITOR_CONTROL" }
let shortNon = shortIdx.filter { records[$0].expected == "NON_CONTROL" }
print("Short: control \(shortCtl.filter { records[$0].gatePassed }.count)/\(shortCtl.count) pass, non \(shortNon.filter { !records[$0].gatePassed }.count)/\(shortNon.count) blocked")
print("Pares mínimos J:")
var pairOK = 0, pairN = 0
for (i, m) in metas.enumerated() where m.group == "J" && m.id.hasSuffix("a") {
    let bID = String(m.id.dropLast()) + "b"
    if let j = metas.firstIndex(where: { $0.id == bID }) {
        pairN += 1
        let aOK = !records[i].gatePassed && records[i].expected == "NON_CONTROL"
        let bOK = records[j].gatePassed && records[j].expected == "EDITOR_CONTROL"
        if aOK && bOK { pairOK += 1 }
        print("\(m.id) c=\(String(format: "%.3f", records[i].controlScore)) \(records[i].gatePassed ? "PASS" : "BLOCK") | \(bID) c=\(String(format: "%.3f", records[j].controlScore)) \(records[j].gatePassed ? "PASS" : "BLOCK")")
    }
}
print("\(pairOK)/\(pairN) pares separados correctamente")
print("")

// Distribuciones de scores
let ctlScores = records.filter { $0.expected == "EDITOR_CONTROL" }.map(\.controlScore).sorted()
let nonScores = records.filter { $0.expected == "NON_CONTROL" }.map(\.controlScore).sorted()
print(String(format: "CONTROL scores: min=%.3f p10=%.3f med=%.3f p90=%.3f max=%.3f",
             ctlScores.first ?? 0, percentile(ctlScores, 0.1), percentile(ctlScores, 0.5),
             percentile(ctlScores, 0.9), ctlScores.last ?? 0))
print(String(format: "NON_CONTROL scores: min=%.3f p10=%.3f med=%.3f p90=%.3f max=%.3f",
             nonScores.first ?? 0, percentile(nonScores, 0.1), percentile(nonScores, 0.5),
             percentile(nonScores, 0.9), nonScores.last ?? 0))
print("")
let lats = latencies.sorted()
print(String(format: "Latency: load=%.0f ms mean=%.1f median=%.1f p95=%.1f min=%.1f max=%.1f", loadMs,
             lats.reduce(0, +) / Double(max(lats.count, 1)), percentile(lats, 0.5),
             percentile(lats, 0.95), lats.first ?? 0, lats.last ?? 0))
print("")
print("Fallos:")
var nf = 0
for (i, m) in metas.enumerated() {
    let r = records[i]
    let bad = (r.expected == "EDITOR_CONTROL") != r.gatePassed || r.rawPrediction != r.expected
    if bad {
        nf += 1
        print("--- \(m.id) [\(m.group)] fam=\(m.family)")
        print("TEXT: \(m.text)")
        print("EXPECTED: \(m.raw)  RAW: \(r.rawPrediction)  SCORE: \(String(format: "%.3f", r.controlScore))")
        print("GATE: \(r.gatePassed ? "PASS" : "DO_NOT_PASS")  T=\(String(format: "%.3f", TC))")
    }
}
if nf == 0 { print("ninguno") }
print("")
print("Regression diagnostic (NO criterio):")
for (name, file) in [("V2", "obs_v2final.csv"), ("V3", "obs_v3final.csv")] {
    let rows = csvRows(try String(contentsOf: dataDir.appendingPathComponent(file), encoding: .utf8))
    var tp2 = 0, fn2 = 0, fp2 = 0, tn2 = 0
    for r in rows where r.count >= 4 {
        // binario: solo EDITOR_CONTROL es control; DICTATION o vacío es non-control
        let expCtl = r[3] == "EDITOR_CONTROL"
        let p = predict(r[2])
        let pass = p.c >= TC
        if expCtl { if pass { tp2 += 1 } else { fn2 += 1 } }
        else { if pass { fp2 += 1 } else { tn2 += 1 } }
    }
    let tot = tp2 + fn2 + fp2 + tn2
    print("\(name): n=\(tot) passes \(fp2)/\(fp2 + tn2) missed \(fn2)/\(tp2 + fn2)")
}
