import CoreML
import Foundation
import NaturalLanguage
let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let compiled = try MLModel.compileModel(at: cwd.appendingPathComponent("models/IntentGate.mlmodel"))
let nl = try NLModel(contentsOf: compiled)
let lines = try String(contentsOf: cwd.appendingPathComponent("models/validation.csv"), encoding: .utf8).split(separator: "\n").dropFirst()
var low: [(Double, String, String)] = []
for l in lines {
    let parts = l.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    guard parts.count >= 2 else { continue }
    var text = parts[0]; if text.hasPrefix("\"") { text = String(text.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"") }
    let h = nl.predictedLabelHypotheses(for: text, maximumCount: 2)
    low.append((h["EDITOR_CONTROL"] ?? 0, parts[1], text))
}
print("== 5 controles con menor score ==")
for (s, lab, t) in low.filter({ $0.1 == "EDITOR_CONTROL" }).sorted(by: { $0.0 < $1.0 }).prefix(5) { print(String(format: "%.3f %@", s, t)) }
print("== 5 dictados con mayor score ==")
for (s, lab, t) in low.filter({ $0.1 == "DICTATION" }).sorted(by: { $0.0 > $1.0 }).prefix(5) { print(String(format: "%.3f %@", s, t)) }
