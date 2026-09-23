// Evalúa FINAL_ACTION_TEST raw (sin thresholds). Métricas desde
// ActionEvaluationRecord único + verificación contable.
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

let labels = ["RENAME_TITLE", "DELETE_SELECTION", "REPLACE_SELECTION", "REWRITE_SELECTION",
              "FORMAT_SELECTION", "UNDO", "REDO", "SELECT_TEXT", "FIND_TEXT",
              "SAVE_DOCUMENT", "OPEN_DOCUMENT", "EXPORT_DOCUMENT",
              "UNSUPPORTED", "NO_ACTION", "MULTI_ACTION"]
let supported: Set<String> = ["RENAME_TITLE", "DELETE_SELECTION", "REPLACE_SELECTION",
                              "REWRITE_SELECTION", "FORMAT_SELECTION", "UNDO", "REDO",
                              "SELECT_TEXT", "FIND_TEXT", "SAVE_DOCUMENT", "OPEN_DOCUMENT",
                              "EXPORT_DOCUMENT"]

struct ActionEvaluationRecord {
    let text: String
    let expected: String
    let predicted: String
    let top1: Double
    let top2label: String
    let top2: Double
    let margin: Double
    let category: String
    let familyID: String
    let uns: Bool
    let conf: Bool
    let para: Bool
    let short: Bool
}

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let modelsDir = cwd.appendingPathComponent("models")
let dataDir = cwd.appendingPathComponent("data")

let clock = ContinuousClock()
let t0 = clock.now
let compiledURL = try MLModel.compileModel(at: modelsDir.appendingPathComponent("ActionClassifier.mlmodel"))
let loadMs = ms(t0, clock.now)

@MainActor
func makeModel() throws -> NLModel { try NLModel(contentsOf: compiledURL) }
let nl = try makeModel()

@MainActor
func classify(_ text: String) -> (top1: String, s1: Double, top2: String, s2: Double) {
    let h = nl.predictedLabelHypotheses(for: text, maximumCount: 3)
    let s = h.sorted { $0.value > $1.value }
    guard !s.isEmpty else { return ("?", 0, "?", 0) }
    let second = s.count > 1 ? s[1] : ("?", 0.0)
    return (s[0].key, s[0].value, second.0, second.1)
}

let finRows = csvRows(try String(contentsOf: dataDir.appendingPathComponent("final_action_test.csv"), encoding: .utf8))
var records: [ActionEvaluationRecord] = []
var latencies: [Double] = []
for r in finRows where r.count >= 9 {
    let s0 = clock.now
    let c = classify(r[2])
    latencies.append(ms(s0, clock.now))
    records.append(ActionEvaluationRecord(
        text: r[2], expected: r[3], predicted: c.top1, top1: c.s1,
        top2label: c.top2, top2: c.s2, margin: c.s1 - c.s2,
        category: r[1], familyID: r[4],
        uns: r[5] == "1", conf: r[6] == "1", para: r[7] == "1", short: r[8] == "1"))
}

// ---- verificación contable ----
let total = records.count
var mat: [String: [String: Int]] = [:]
for e in labels { mat[e] = Dictionary(uniqueKeysWithValues: labels.map { ($0, 0) }) }
for r in records { mat[r.expected]![r.predicted, default: 0] += 1 }
let matSum = mat.values.flatMap(\.values).reduce(0, +)
let supSum = Dictionary(grouping: records, by: \.expected).values.map(\.count).reduce(0, +)
let catSum = Dictionary(grouping: records, by: \.category).values.map(\.count).reduce(0, +)
guard matSum == total && supSum == total && catSum == total else {
    fatalError("ERROR_METRIC_ACCOUNTING")
}
print("metric accounting: OK (\(total))")

let correct = records.filter { $0.expected == $0.predicted }.count
print(String(format: "Top-1 accuracy: %.2f%% (%d/%d)", 100.0 * Double(correct) / Double(total), correct, total))
print("")
print("Per-class P/R/F1/support:")
var f1s: [Double] = []
for l in labels {
    let tp = records.filter { $0.expected == l && $0.predicted == l }.count
    let fp = records.filter { $0.expected != l && $0.predicted == l }.count
    let fn = records.filter { $0.expected == l && $0.predicted != l }.count
    let sup = tp + fn
    let p = tp + fp > 0 ? Double(tp) / Double(tp + fp) : 0
    let rr = sup > 0 ? Double(tp) / Double(sup) : 0
    let f1 = p + rr > 0 ? 2 * p * rr / (p + rr) : 0
    f1s.append(f1)
    print(String(format: "%-18@ P=%5.1f%% R=%5.1f%% F1=%.3f n=%d", l as NSString, p * 100, rr * 100, f1, sup))
}
print(String(format: "Macro F1: %.4f", f1s.reduce(0, +) / Double(max(f1s.count, 1))))
print("")
print("Matriz 15x15 (filas=exp, cols=pred, orden: RN DL RP RW FM UN RD SL FN SV OP EX US NA MU):")
let short = ["RN", "DL", "RP", "RW", "FM", "UN", "RD", "SL", "FN", "SV", "OP", "EX", "US", "NA", "MU"]
print("      " + short.joined(separator: "  "))
for (i, e) in labels.enumerated() {
    let row = labels.map { String(mat[e]![$0]!) }.joined(separator: " ")
    print("\(short[i]): \(row)")
}
print("")

// Críticas
let unsRows = records.filter { $0.expected == "UNSUPPORTED" }
let unsSub = unsRows.filter { supported.contains($0.predicted) }.count
let wUns = wilson(k: unsSub, n: unsRows.count)
print(String(format: "Unsupported substitution: %d/%d = %.2f%%  Wilson [%.2f, %.2f]", unsSub, unsRows.count,
             100.0 * Double(unsSub) / Double(max(unsRows.count, 1)), wUns.0 * 100, wUns.1 * 100))
let naRows = records.filter { $0.expected == "NO_ACTION" }
let naFalse = naRows.filter { supported.contains($0.predicted) }.count
print(String(format: "NoAction false-action: %d/%d = %.2f%%", naFalse, naRows.count,
             100.0 * Double(naFalse) / Double(max(naRows.count, 1))))
let muRows = records.filter { $0.expected == "MULTI_ACTION" }
let muFalse = muRows.filter { supported.contains($0.predicted) }.count
print(String(format: "MultiAction false-single: %d/%d = %.2f%%", muFalse, muRows.count,
             100.0 * Double(muFalse) / Double(max(muRows.count, 1))))
let supRows = records.filter { supported.contains($0.expected) }
let supOk = supRows.filter { $0.expected == $0.predicted }.count
print(String(format: "Supported-action accuracy: %.2f%% (%d/%d)", 100.0 * Double(supOk) / Double(max(supRows.count, 1)), supOk, supRows.count))
print("")

func pair(_ a: String, _ b: String) {
    let ab = records.filter { $0.expected == a && $0.predicted == b }.count
    let ba = records.filter { $0.expected == b && $0.predicted == a }.count
    let na = records.filter { $0.expected == a }.count
    let nb = records.filter { $0.expected == b }.count
    print("\(a)->\(b): \(ab)/\(na)  \(b)->\(a): \(ba)/\(nb)")
}
print("Confusiones dirigidas:")
pair("UNDO", "REDO")
pair("FIND_TEXT", "SELECT_TEXT")
pair("SELECT_TEXT", "FORMAT_SELECTION")
pair("REPLACE_SELECTION", "REWRITE_SELECTION")
pair("SAVE_DOCUMENT", "EXPORT_DOCUMENT")
print("")

// Challenges
let crit = records.filter(\.uns)
let critFP = crit.filter { supported.contains($0.predicted) }.count
print(String(format: "UNSUPPORTED_CHALLENGE: %d/%d ->supported", critFP, crit.count))
let confSet = records.filter(\.conf)
let confOk = confSet.filter { $0.expected == $0.predicted }.count
print(String(format: "CONFUSABLE_CHALLENGE: %.1f%% (%d/%d)", 100.0 * Double(confOk) / Double(max(confSet.count, 1)), confOk, confSet.count))
let paraSet = records.filter(\.para)
let paraOk = paraSet.filter { $0.expected == $0.predicted }.count
print(String(format: "PARAPHRASE_CHALLENGE: %.1f%% (%d/%d)", 100.0 * Double(paraOk) / Double(max(paraSet.count, 1)), paraOk, paraSet.count))
let shortSet = records.filter(\.short)
let shortOk = shortSet.filter { $0.expected == $0.predicted }.count
print(String(format: "SHORT_STT_CHALLENGE: %.1f%% (%d/%d)", 100.0 * Double(shortOk) / Double(max(shortSet.count, 1)), shortOk, shortSet.count))
print("")

// Margins
let margins = records.map(\.margin).sorted()
let lowMargin = records.filter { $0.margin < 0.2 }
print(String(format: "Margin: med=%.3f p10=%.3f | margin<0.2: %d/%d", percentile(margins, 0.5), percentile(margins, 0.1), lowMargin.count, total))
print("Top1 score distribución (p10/med):", String(format: "%.3f/%.3f",
      percentile(records.map(\.top1).sorted(), 0.1), percentile(records.map(\.top1).sorted(), 0.5)))
print("")
let lats = latencies.sorted()
print(String(format: "Latency: load=%.0f ms mean=%.1f median=%.1f p95=%.1f min=%.1f max=%.1f", loadMs,
             lats.reduce(0, +) / Double(max(lats.count, 1)), percentile(lats, 0.5),
             percentile(lats, 0.95), lats.first ?? 0, lats.last ?? 0))
print("")
print("Fallos (\(total - correct)):")
for r in records where r.expected != r.predicted {
    print("--- [\(r.category)] exp=\(r.expected) pred=\(r.predicted) s1=\(String(format: "%.3f", r.top1)) s2=\(r.top2label)=\(String(format: "%.3f", r.top2)) fam=\(r.familyID)")
    print("TEXT: \(r.text)")
}
