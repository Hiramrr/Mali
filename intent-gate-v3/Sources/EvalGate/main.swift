// V3: T_CONTROL + T_DICTATION solo con CALIBRATION -> FREEZE -> FINAL_TEST_V3.
// Política operacional: CONTROL+thr->AUTO_CONTROL; DICTATION+thr->AUTO_DICTATION;
// NO_ACTION predicho->NO_ACTION; resto->UNCERTAIN.
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

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let modelsDir = cwd.appendingPathComponent("models")
let dataDir = cwd.appendingPathComponent("data")

let clock = ContinuousClock()
let t0 = clock.now
let compiledURL = try MLModel.compileModel(at: modelsDir.appendingPathComponent("IntentGateV3.mlmodel"))
let loadMs = ms(t0, clock.now)

@MainActor
func makeModel() throws -> NLModel { try NLModel(contentsOf: compiledURL) }
let nl = try makeModel()

@MainActor
func scores(_ text: String) -> (c: Double, d: Double, n: Double, raw: String) {
    let h = nl.predictedLabelHypotheses(for: text, maximumCount: 3)
    let c = h["EDITOR_CONTROL"] ?? 0, d = h["DICTATION"] ?? 0, na = h["NO_ACTION"] ?? 0
    let raw: String
    if c >= d && c >= na { raw = "EDITOR_CONTROL" }
    else if d >= na { raw = "DICTATION" } else { raw = "NO_ACTION" }
    return (c, d, na, raw)
}

// ---- CALIBRATION ----
let calRows = csvRows(try String(contentsOf: dataDir.appendingPathComponent("calibration.csv"), encoding: .utf8))
struct Cal { let c: Double; let d: Double; let na: Double; let raw: String; let label: String }
var cal: [Cal] = []
for r in calRows where r.count >= 2 {
    let s = scores(r[0])
    cal.append(Cal(c: s.c, d: s.d, na: s.n, raw: s.raw, label: r[1]))
}
let calC = cal.filter { $0.label == "EDITOR_CONTROL" }
let calD = cal.filter { $0.label == "DICTATION" }
let calN = cal.filter { $0.label == "NO_ACTION" }

@MainActor
func candidates(_ vals: [Double]) -> [Double] {
    let s = Set(vals).sorted()
    var out: [Double] = [0.0]
    for i in 0..<s.count {
        out.append(s[i])
        if i + 1 < s.count { out.append((s[i] + s[i + 1]) / 2) }
    }
    out.append(1.0)
    return out
}

// T_CONTROL: recall>=95%, min False Automatic Control Rate, empate->max.
var tC: (thr: Double, rec: Double, fcr: Double)? = nil
for t in candidates(cal.map(\.c)) {
    let tp = calC.filter { $0.c >= t }.count
    let fp = cal.filter { $0.label != "EDITOR_CONTROL" && $0.c >= t }.count
    let rec = calC.isEmpty ? 0 : Double(tp) / Double(calC.count)
    let fcr = (cal.count - calC.count) > 0 ? Double(fp) / Double(cal.count - calC.count) : 0
    guard rec >= 0.95 else { continue }
    if tC == nil || fcr < tC!.fcr || (fcr == tC!.fcr && t > tC!.thr) {
        tC = (t, rec, fcr)
    }
}
// T_DICTATION: dict recall>=95%, min Control-as-Dictation, empate->max.
var tD: (thr: Double, rec: Double, cadr: Double)? = nil
for t in candidates(cal.map(\.d)) {
    let tp = calD.filter { $0.d >= t }.count
    let cd = calC.filter { $0.d >= t }.count
    let rec = calD.isEmpty ? 0 : Double(tp) / Double(calD.count)
    let cadr = calC.isEmpty ? 0 : Double(cd) / Double(calC.count)
    guard rec >= 0.95 else { continue }
    if tD == nil || cadr < tD!.cadr || (cadr == tD!.cadr && t > tD!.thr) {
        tD = (t, rec, cadr)
    }
}
guard let TC = tC, let TD = tD else { fatalError("sin thresholds factibles en calibration") }

@MainActor
func operate(c: Double, d: Double, raw: String) -> String {
    if raw == "EDITOR_CONTROL" && c >= TC.thr { return "AUTO_CONTROL" }
    if raw == "DICTATION" && d >= TD.thr { return "AUTO_DICTATION" }
    if raw == "NO_ACTION" { return "NO_ACTION" }
    return "UNCERTAIN"
}

@MainActor
func calOp() -> [String] {
    cal.map { operate(c: $0.c, d: $0.d, raw: $0.raw) }
}

// ---- Calibration report (antes de abrir FINAL) ----
@MainActor
func reportCalibration() {
    let ops = calOp()
    var rawOk = 0
    for (r, _) in zip(cal, ops) {
        if r.raw == r.label { rawOk += 1 }
    }
    let autoC = zip(cal, ops).filter { $0.1 == "AUTO_CONTROL" }
    let calTP = autoC.filter { $0.0.label == "EDITOR_CONTROL" }.count
    let calFP = autoC.count - calTP
    print("")
    print("CALIBRATION")
    print("=================================")
    print("n=\(cal.count) C=\(calC.count) D=\(calD.count) N=\(calN.count)")
    print(String(format: "Raw 3-class accuracy: %.1f%%", 100.0 * Double(rawOk) / Double(max(cal.count, 1))))
    print(String(format: "T_CONTROL: %.3f (recall %.1f%%, FCR %.2f%%)", TC.thr, TC.rec * 100, TC.fcr * 100))
    print(String(format: "T_DICTATION: %.3f (dict recall %.1f%%, C-as-D %.2f%%)", TD.thr, TD.rec * 100, TD.cadr * 100))
    print("THRESHOLD FROZEN")
    print("")
}
reportCalibration()

// ---- FINAL_TEST_V3 ----
struct FRow {
    let id: String; let group: String; let text: String; let raw: String?
    let family: String; let critical: Bool; let coverage: Bool; let ambiguity: Bool; let pair: String
}
let finRows = csvRows(try String(contentsOf: dataDir.appendingPathComponent("final_test_v3.csv"), encoding: .utf8))
var finals: [FRow] = []
for r in finRows where r.count >= 9 {
    finals.append(FRow(id: r[0], group: r[1], text: r[2],
                       raw: r[3].isEmpty ? nil : r[3], family: r[4],
                       critical: r[5] == "1", coverage: r[6] == "1",
                       ambiguity: r[7] == "1", pair: r[8]))
}
struct Out {
    let f: FRow; let c: Double; let d: Double; let na: Double
    let raw: String; let op: String; let lat: Double
}
var outs: [Out] = []
for h in finals {
    let s0 = clock.now
    let s = scores(h.text)
    let lat = ms(s0, clock.now)
    outs.append(Out(f: h, c: s.c, d: s.d, na: s.n, raw: s.raw,
                    op: operate(c: s.c, d: s.d, raw: s.raw), lat: lat))
}

// ---- Métricas ----
let withRaw = outs.filter { $0.f.raw != nil }
let rawOkF = withRaw.filter { $0.raw == $0.f.raw }.count
let labs = ["DICTATION", "EDITOR_CONTROL", "NO_ACTION"]
func pr(_ exp: String) -> (p: Double, r: Double) {
    let tp = withRaw.filter { $0.f.raw == exp && $0.raw == exp }.count
    let fp = withRaw.filter { $0.f.raw != exp && $0.raw == exp }.count
    let fn = withRaw.filter { $0.f.raw == exp && $0.raw != exp }.count
    return (tp + fp > 0 ? Double(tp) / Double(tp + fp) : 0,
            tp + fn > 0 ? Double(tp) / Double(tp + fn) : 0)
}
let ctlRows = outs.filter { $0.f.raw == "EDITOR_CONTROL" }
let nonCtl = outs.filter { $0.f.raw != "EDITOR_CONTROL" }
let autoCtl = outs.filter { $0.op == "AUTO_CONTROL" }
let fcr = autoCtl.filter { $0.f.raw != "EDITOR_CONTROL" }.count
let autoCtlRec = ctlRows.filter { $0.op == "AUTO_CONTROL" }.count
let dangerous = ctlRows.filter { $0.op == "AUTO_DICTATION" }.count
let dictRows = outs.filter { $0.f.raw == "DICTATION" }
let falseDict = outs.filter { $0.f.raw != "DICTATION" && $0.op == "AUTO_DICTATION" }.count
let naRows = outs.filter { $0.f.raw == nil || $0.f.raw == "NO_ACTION" }
let naRec = naRows.filter { $0.op == "NO_ACTION" }.count
let unc = outs.filter { $0.op == "UNCERTAIN" }.count
let cov = autoCtl.count + outs.filter { $0.op == "AUTO_DICTATION" }.count
let crit = outs.filter(\.f.critical)
let critPass = crit.filter { $0.op == "AUTO_CONTROL" }.count
let covCh = outs.filter(\.f.coverage)
let covRec = covCh.filter { $0.op == "AUTO_CONTROL" }.count
let amb = outs.filter(\.f.ambiguity)
let ambOk = amb.filter { $0.op != "AUTO_CONTROL" }.count
let fcDict = autoCtl.filter { $0.f.raw == "DICTATION" }.count
let fcNA = autoCtl.filter { $0.f.raw != "EDITOR_CONTROL" && $0.f.raw != "DICTATION" }.count
let wFCR = wilson(k: fcr, n: nonCtl.count)
let wRec = wilson(k: autoCtlRec, n: ctlRows.count)
let wDan = wilson(k: dangerous, n: ctlRows.count)

print("FINAL TEST V3")
print("=================================")
print("Total: \(outs.count)")
print("DICTATION: \(dictRows.count)  CONTROL: \(ctlRows.count)  NO_ACTION: \(naRows.count)")
print(String(format: "Raw 3-class accuracy: %.1f%% (%d/%d)", 100.0 * Double(rawOkF) / Double(max(withRaw.count, 1)), rawOkF, withRaw.count))
for l in labs {
    let m = pr(l)
    print(String(format: "%@: P=%.1f%% R=%.1f%%", l, m.p * 100, m.r * 100))
}
print(String(format: "False Automatic Control Rate: %d/%d = %.2f%%", fcr, nonCtl.count, 100.0 * Double(fcr) / Double(max(nonCtl.count, 1))))
print(String(format: "  95%% CI (Wilson): [%.2f%%, %.2f%%]", wFCR.0 * 100, wFCR.1 * 100))
print(String(format: "Automatic Control Recall: %d/%d = %.1f%%", autoCtlRec, ctlRows.count, 100.0 * Double(autoCtlRec) / Double(max(ctlRows.count, 1))))
print(String(format: "  95%% CI (Wilson): [%.1f%%, %.1f%%]", wRec.0 * 100, wRec.1 * 100))
print(String(format: "Dangerous Dictation Insertions: %d  [%.2f%%, %.2f%%]", dangerous, wDan.0 * 100, wDan.1 * 100))
print(String(format: "False Dictation Rate: %d/%d = %.2f%%", falseDict, outs.count - dictRows.count, 100.0 * Double(falseDict) / Double(max(outs.count - dictRows.count, 1))))
print(String(format: "NO_ACTION Recall: %d/%d = %.1f%%", naRec, naRows.count, 100.0 * Double(naRec) / Double(max(naRows.count, 1))))
print(String(format: "UNCERTAIN Rate: %d/%d = %.1f%%", unc, outs.count, 100.0 * Double(unc) / Double(max(outs.count, 1))))
print(String(format: "Automatic Coverage: %d/%d = %.1f%%", cov, outs.count, 100.0 * Double(cov) / Double(max(outs.count, 1))))
print("False Control from DICTATION: \(fcDict)  from NO_ACTION: \(fcNA)")
print(String(format: "Critical Negative: %d/%d passes", critPass, crit.count))
print(String(format: "Control Coverage: %d/%d recall", covRec, covCh.count))
print(String(format: "Ambiguity (no AUTO_CONTROL): %d/%d", ambOk, amb.count))
print("")
print("Matriz raw 3x3 (filas=exp D/C/N, cols=pred D/C/N):")
for e in labs {
    let row = labs.map { p in withRaw.filter { $0.f.raw == e && $0.raw == p }.count }
    print("\(e): \(row.map(String.init).joined(separator: " / "))")
}
print("Matriz operacional (filas=exp raw, cols=AUTO_D/AUTO_C/NO_ACTION/UNCERTAIN):")
for e in ["DICTATION", "EDITOR_CONTROL", "NO_ACTION"] {
    let set = outs.filter { $0.f.raw == e }
    let cells = ["AUTO_DICTATION", "AUTO_CONTROL", "NO_ACTION", "UNCERTAIN"].map { o in set.filter { $0.op == o }.count }
    print("\(e): \(cells.map(String.init).joined(separator: " / "))")
}
print("")
print("Pares mínimos:")
for o in outs where o.f.group == "H" && o.f.pair.hasSuffix("") {
    if o.f.id.hasSuffix("a") {
        if let b = outs.first(where: { $0.f.id == String(o.f.id.dropLast()) + "b" }) {
            print("\(o.f.id) raw=\(o.raw) op=\(o.op) c=\(String(format: "%.3f", o.c)) | \(o.f.text)")
            print("\(b.f.id) raw=\(b.raw) op=\(b.op) c=\(String(format: "%.3f", b.c)) | \(b.f.text)")
        }
    }
}
print("")
let lats = outs.map(\.lat).sorted()
print(String(format: "Latency: load=%.0f ms mean=%.1f median=%.1f p95=%.1f min=%.1f max=%.1f", loadMs,
             lats.reduce(0, +) / Double(max(lats.count, 1)), percentile(lats, 0.5),
             percentile(lats, 0.95), lats.first ?? 0, lats.last ?? 0))
print("")
print("Fallos operativos (no AUTO esperado / AUTO indebido):")
var nf = 0
for o in outs {
    let bad: Bool
    if o.f.raw == "EDITOR_CONTROL" {
        bad = o.op != "AUTO_CONTROL" // missed / dangerous / uncertain
    } else if o.f.raw == "DICTATION" {
        bad = o.op == "AUTO_CONTROL" || o.raw != "DICTATION" // falso control o raw erróneo
    } else {
        bad = o.op == "AUTO_CONTROL" || o.op == "AUTO_DICTATION" // NO_ACTION nunca debe automatizarse
    }
    if bad {
        nf += 1
        print("--- \(o.f.id) [\(o.f.group)] fam=\(o.f.family)")
        print("TEXT: \(o.f.text)")
        print("EXPECTED RAW: \(o.f.raw ?? "(NO_ACTION)")")
        print("RAW: \(o.raw) c=\(String(format: "%.3f", o.c)) d=\(String(format: "%.3f", o.d)) na=\(String(format: "%.3f", o.na))")
        print("OP: \(o.op) (T_C=\(String(format: "%.3f", TC.thr)) T_D=\(String(format: "%.3f", TD.thr)))")
    }
}
if nf == 0 { print("ninguno") }
print("")
print("Legacy diagnostic (NO criterio):")
let legRows = csvRows(try String(contentsOf: dataDir.appendingPathComponent("legacy_diagnostic_holdout.csv"), encoding: .utf8))
var legCtl = 0, legAuto = 0
for r in legRows where r.count >= 5 {
    let s = scores(r[2])
    let op = operate(c: s.c, d: s.d, raw: s.raw)
    if r[4] == "CONTROL" { legCtl += 1; if op == "AUTO_CONTROL" { legAuto += 1 } }
}
print("legacy CONTROL->AUTO_CONTROL: \(legAuto)/\(legCtl)")
