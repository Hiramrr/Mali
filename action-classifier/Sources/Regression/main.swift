// RegressionGate: evalúa CSVs (id,text,expected) como diagnóstico.
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

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let dataDir = cwd.appendingPathComponent("data")
let args = CommandLine.arguments
guard args.count >= 3 else {
    print("uso: Regression <modelo.mlmodel> <csv> [csv...]")
    exit(1)
}
let compiledURL = try MLModel.compileModel(at: URL(fileURLWithPath: args[1]))
let nl = try NLModel(contentsOf: compiledURL)
for file in args.dropFirst(2) {
    let text = try String(contentsOf: dataDir.appendingPathComponent(file), encoding: .utf8)
    var rows: [[String]] = []
    for line in text.components(separatedBy: "\n") {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
        rows.append(splitLine(line))
    }
    if rows.first?.first == "id" { rows.removeFirst() }
    var ok = 0
    var unsTot = 0, unsSub = 0
    for r in rows where r.count >= 3 {
        let h = nl.predictedLabelHypotheses(for: r[1], maximumCount: 1)
        let pred = h.sorted { $0.value > $1.value }.first?.key ?? "?"
        if pred == r[2] { ok += 1 }
        if r[2] == "UNSUPPORTED" {
            unsTot += 1
            let sup: Set<String> = ["RENAME_TITLE", "DELETE_SELECTION", "REPLACE_SELECTION",
                "REWRITE_SELECTION", "FORMAT_SELECTION", "UNDO", "REDO", "SELECT_TEXT",
                "FIND_TEXT", "SAVE_DOCUMENT", "OPEN_DOCUMENT", "EXPORT_DOCUMENT"]
            if sup.contains(pred) { unsSub += 1 }
        }
    }
    print(String(format: "%@: acc=%.1f%% (%d/%d) unsSub=%d/%d", file,
                 100.0 * Double(ok) / Double(max(rows.count, 1)), ok, rows.count, unsSub, unsTot))
}
