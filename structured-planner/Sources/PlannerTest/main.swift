// Planner: FM como parser (guided generation, greedy, tools disallowed).
// Sin tools registradas. Métricas desde PlanRecord único.
import Foundation
import FoundationModels

struct PlanTest: Sendable {
    let id: String
    let group: String
    let utterance: String
    let hasSelection: Bool
    let canUndo: Bool
    let canRedo: Bool
    let documentIsOpen: Bool
    let expected: String       // "actions:A+B" | "UNSUPPORTED" | "NOACTION"
    let expectedArgs: [String: String]
    let preserveLang: Bool
}

struct PlanRecord: Sendable {
    let test: PlanTest
    let plan: CommandPlan?
    let latencyMs: Double
    let genError: String?
}

let instructions = """
You parse spoken commands for a text editor. Return the requested editor actions in the same order they were requested. Preserve explicit user-provided text verbatim.
If the request is not an editor operation, return noAction. If it requests an operation not represented by the supported action schema, return unsupported. Never replace an unsupported request with a similar supported action.
"""

func prompt(hasSel: Bool, undo: Bool, redo: Bool, open: Bool, voice: String) -> String {
    """
    HAS SELECTION:
    \(hasSel)

    CAN UNDO:
    \(undo)

    CAN REDO:
    \(redo)

    DOCUMENT OPEN:
    \(open)

    USER SAID:
    \(voice)
    """
}

func milliseconds(_ s: ContinuousClock.Instant, _ e: ContinuousClock.Instant) -> Double {
    let c = (e - s).components
    return Double(c.seconds) * 1000.0 + Double(c.attoseconds) / 1e15
}

func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let rank = p * Double(sorted.count - 1)
    let lo = Int(rank.rounded(.down)), hi = Int(rank.rounded(.up))
    if lo == hi { return sorted[lo] }
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (rank - Double(lo))
}

// Normalización mínima para verificador literal: NFC, trim, espacios,
// comillas externas, puntuación final. Sin traducción ni sinónimos.
func normLit(_ s: String) -> String {
    var t = s.precomposedStringWithCanonicalMapping
    t = t.trimmingCharacters(in: .whitespacesAndNewlines)
    t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'"))
        || (t.hasPrefix("«") && t.hasSuffix("»")) {
        t = String(t.dropFirst().dropLast())
    }
    t = t.trimmingCharacters(in: .whitespacesAndNewlines)
    while t.hasSuffix(".") || t.hasSuffix("!") || t.hasSuffix("?") || t.hasSuffix(",") || t.hasSuffix(";") {
        t = String(t.dropLast())
    }
    return t
}

// Acciones y si requieren contexto / tienen args literales.
func actionNeedsSelection(_ name: String) -> Bool {
    ["deleteSelection", "replaceSelection", "rewriteSelection", "formatSelection"].contains(name)
}

@main
struct PlannerApp {
    static func main() async {
        let model = SystemLanguageModel.default
        print("Availability: \(model.availability)")
        guard case .available = model.availability else {
            print("Modelo no disponible. Fin sin sustitutos.")
            return
        }
        let options: GenerationOptions = {
            if #available(macOS 27, *) {
                return GenerationOptions(samplingMode: .greedy, toolCallingMode: .disallowed)
            } else {
                return GenerationOptions()
            }
        }()
        print("GenerationOptions: samplingMode=.greedy toolCallingMode=.disallowed (cero tools registradas)")
        let records = await runFinal(model: model, options: options)
        printReport(records: records)
        await runRegression(model: model, options: options)
    }

    static func loadFinal() -> [PlanTest] {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("data/final_command_planner_v1.csv")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var out: [PlanTest] = []
        for line in text.components(separatedBy: "\n").dropFirst() {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let p = splitCSV(line)
            guard p.count >= 10 else { continue }
            var args: [String: String] = [:]
            for kv in p[8].split(separator: ";") {
                let k2 = kv.split(separator: "=", maxSplits: 1).map(String.init)
                if k2.count == 2 { args[k2[0]] = k2[1] }
            }
            out.append(PlanTest(id: p[0], group: p[1], utterance: p[2],
                                hasSelection: p[3] == "true", canUndo: p[4] == "true",
                                canRedo: p[5] == "true", documentIsOpen: p[6] == "true",
                                expected: p[7], expectedArgs: args, preserveLang: p[9] == "1"))
        }
        return out
    }

    static func splitCSV(_ line: String) -> [String] {
        var fields: [String] = []
        var f = ""
        var q = false
        let ch = Array(line)
        var i = 0
        while i < ch.count {
            let c = ch[i]
            if q {
                if c == "\"" {
                    if i + 1 < ch.count && ch[i + 1] == "\"" { f.append("\""); i += 2; continue }
                    q = false; i += 1; continue
                }
                f.append(c); i += 1
            } else if c == "\"" { q = true; i += 1 }
            else if c == "," { fields.append(f); f = ""; i += 1 }
            else { f.append(c); i += 1 }
        }
        fields.append(f)
        return fields
    }

    static func runFinal(model: SystemLanguageModel, options: GenerationOptions) async -> [PlanRecord] {
        let tests = loadFinal()
        print("FINAL_COMMAND_PLANNER_V1: \(tests.count) tests")
        let clock = ContinuousClock()
        var records: [PlanRecord] = []
        for t in tests {
            let session = LanguageModelSession(model: model, instructions: instructions)
            let s = clock.now
            do {
                let resp = try await session.respond(
                    to: prompt(hasSel: t.hasSelection, undo: t.canUndo, redo: t.canRedo,
                               open: t.documentIsOpen, voice: t.utterance),
                    generating: CommandPlan.self, options: options)
                records.append(PlanRecord(test: t, plan: resp.content,
                                          latencyMs: milliseconds(s, clock.now), genError: nil))
            } catch {
                records.append(PlanRecord(test: t, plan: nil,
                                          latencyMs: milliseconds(s, clock.now), genError: "\(error)"))
            }
            print(".", terminator: "")
            fflush(stdout)
        }
        print("\n")
        return records
    }

    // Validador determinista: (validation, literalOK)
    static func validate(plan: CommandPlan, test: PlanTest) -> (String, Bool) {
        switch plan {
        case .noAction:
            return ("NO_ACTION", true)
        case .unsupported:
            return ("UNSUPPORTED", true)
        case .actions(let seq):
            // literales
            var litOK = true
            for a in seq.actions {
                switch a {
                case .renameTitle(let v): if !verbatim(v, test.utterance) { litOK = false }
                case .replaceSelection(let v): if !verbatim(v, test.utterance) { litOK = false }
                case .findText(let v): if !verbatim(v, test.utterance) { litOK = false }
                case .selectText(let v): if !verbatim(v, test.utterance) { litOK = false }
                case .openDocument(let v): if !verbatim(v, test.utterance) { litOK = false }
                default: break
                }
            }
            if !litOK { return ("REJECTED_ARGUMENT_NOT_VERBATIM", false) }
            for a in seq.actions {
                let n = a.toolName
                if actionNeedsSelection(n) && !test.hasSelection { return ("NEEDS_CONTEXT", true) }
                if n == "undo" && !test.canUndo { return ("NEEDS_CONTEXT", true) }
                if n == "redo" && !test.canRedo { return ("NEEDS_CONTEXT", true) }
                if (n == "saveDocument" || n == "exportDocument") && !test.documentIsOpen {
                    return ("NEEDS_CONTEXT", true)
                }
            }
            return ("VALID", true)
        }
    }

    static func verbatim(_ arg: String, _ utterance: String) -> Bool {
        let a = normLit(arg)
        if a.isEmpty { return false }
        return normLit(utterance).contains(a)
    }

    static func printReport(records: [PlanRecord]) {
        print("========================================")
        print("STRUCTURED COMMAND PLANNER")
        print("========================================")
        print("Total: \(records.count)")
        // Disposition
        var dispOK = 0
        for r in records {
            guard let p = r.plan else { continue }
            let exp = r.test.expected
            if exp == "NOACTION" {
                if case .noAction = p { dispOK += 1 }
            } else if exp == "UNSUPPORTED" {
                if case .unsupported = p { dispOK += 1 }
            } else {
                if case .actions(let s) = p,
                   s.actions.map(\.toolName) == exp.split(separator: "+").map(String.init) {
                    dispOK += 1
                }
            }
        }
        print(String(format: "Plan Disposition Accuracy: %.1f%% (%d/%d)",
                     100.0 * Double(dispOK) / Double(max(records.count, 1)), dispOK, records.count))
        // Single (A + D con 1 acción + E-lit/H/I singleton... aquí: grupos con expected de 1 acción)
        let singles = records.filter {
            $0.test.expected != "NOACTION" && $0.test.expected != "UNSUPPORTED"
                && !$0.test.expected.contains("+")
        }
        var sOk = 0
        for r in singles {
            if case .actions(let s) = r.plan, s.actions.count == 1,
               s.actions[0].toolName == r.test.expected { sOk += 1 }
        }
        print(String(format: "Single Action Accuracy: %.1f%% (%d/%d)",
                     100.0 * Double(sOk) / Double(max(singles.count, 1)), sOk, singles.count))
        // Unsupported
        let uns = records.filter { $0.test.expected == "UNSUPPORTED" }
        let unsOk = uns.filter {
            if case .unsupported = $0.plan { return true }
            return false
        }.count
        let subs = uns.filter {
            if case .actions = $0.plan { return true }
            return false
        }
        print(String(format: "Unsupported Accuracy: %.1f%% (%d/%d)", 100.0 * Double(unsOk) / Double(max(uns.count, 1)), unsOk, uns.count))
        print("Unsupported substitutions: \(subs.count)")
        for r in subs {
            if case .actions(let s) = r.plan {
                print("  \(r.test.id) -> \(s.actions.map(\.toolName).joined(separator: "+")) | \(r.test.utterance)")
            }
        }
        // NoAction
        let na = records.filter { $0.test.expected == "NOACTION" }
        let naOk = na.filter {
            if case .noAction = $0.plan { return true }
            return false
        }.count
        let naFalse = na.filter {
            if case .actions = $0.plan { return true }
            return false
        }.count
        print(String(format: "NoAction Accuracy: %.1f%% (%d/%d)", 100.0 * Double(naOk) / Double(max(na.count, 1)), naOk, na.count))
        print(String(format: "False Action Rate: %.1f%% (%d/%d)", 100.0 * Double(naFalse) / Double(max(na.count, 1)), naFalse, na.count))
        // Args: raw + validated
        var rawT = 0, rawOk = 0, valFails: [String] = []
        for r in records {
            guard case .actions(let s) = r.plan else { continue }
            for a in s.actions {
                let (k, v): (String, String?)
                switch a {
                case .renameTitle(let x): (k, v) = ("newTitle", x)
                case .replaceSelection(let x): (k, v) = ("newText", x)
                case .findText(let x): (k, v) = ("query", x)
                case .selectText(let x): (k, v) = ("target", x)
                case .openDocument(let x): (k, v) = ("reference", x)
                case .formatSelection(let x): (k, v) = ("style", "\(x)")
                case .exportDocument(let x): (k, v) = ("format", "\(x)")
                default: continue
                }
                if let exp = r.test.expectedArgs[k], !exp.isEmpty {
                    rawT += 1
                    if normLit(v ?? "") == normLit(exp) { rawOk += 1 }
                    else { valFails.append("\(r.test.id) \(k): exp=[\(exp)] got=[\(v ?? "")]") }
                }
            }
        }
        print(String(format: "Argument Accuracy raw: %.1f%% (%d/%d)", 100.0 * Double(rawOk) / Double(max(rawT, 1)), rawOk, rawT))
        // validated literal: re-chequea contra utterance
        var litBad = 0
        for r in records {
            guard case .actions = r.plan else { continue }
            let (_, litOK) = validate(plan: r.plan!, test: r.test)
            if !litOK { litBad += 1 }
        }
        print("Literal validator rejections: \(litBad)")
        for f in valFails.prefix(30) { print("  ARG " + f) }
        if valFails.count > 30 { print("  ... (\(valFails.count - 30) más)") }
        // redo/undo (H)
        let h = records.filter { $0.test.group == "H" }
        let hOk = h.filter {
            if case .actions(let s) = $0.plan, s.actions.count == 1,
               s.actions[0].toolName == $0.test.expected { return true }
            return false
        }.count
        print(String(format: "redo/undo (H): %.1f%% (%d/%d)", 100.0 * Double(hOk) / Double(max(h.count, 1)), hOk, h.count))
        // find/select/format (I)
        let ii = records.filter { $0.test.group == "I" }
        var iOk = 0
        for r in ii {
            let exp = r.test.expected.split(separator: "+").map(String.init)
            if case .actions(let s) = r.plan, s.actions.map(\.toolName) == exp { iOk += 1 }
        }
        print(String(format: "find/select/format (I): %.1f%% (%d/%d)", 100.0 * Double(iOk) / Double(max(ii.count, 1)), iOk, ii.count))
        // Multi (F)
        let f = records.filter { $0.test.group == "F" }
        var exact = 0, wrongOrder = 0, missing = 0, extra = 0, wrongAct = 0
        for r in f {
            let exp = r.test.expected.split(separator: "+").map(String.init)
            guard case .actions(let s) = r.plan else { wrongAct += 1; continue }
            let act = s.actions.map(\.toolName)
            if act == exp { exact += 1 }
            else if Set(act) == Set(exp) && act.count == exp.count { wrongOrder += 1 }
            else if exp.allSatisfy(act.contains) && act.count > exp.count { extra += 1 }
            else if act.count < exp.count && act.allSatisfy(exp.contains) { missing += 1 }
            else { wrongAct += 1 }
        }
        print("Multi (F): exact=\(exact) wrongOrder=\(wrongOrder) missing=\(missing) extra=\(extra) wrong=\(wrongAct)")
        // Validator outcomes
        var counts: [String: Int] = [:]
        for r in records {
            guard let p = r.plan else { continue }
            let (v, _) = validate(plan: p, test: r.test)
            counts[v, default: 0] += 1
        }
        print("Validator: \(counts)")
        // Errores de generación
        let errs = records.filter { $0.plan == nil }
        print("Generation errors: \(errs.count)")
        for r in errs { print("  \(r.test.id) [\(r.test.group)] \(r.genError ?? "") | \(r.test.utterance)") }
        // Guardrail: buscar rechazos explícitos en errores
        let guardrail = errs.filter { ($0.genError ?? "").localizedCaseInsensitiveContains("sensitive") || ($0.genError ?? "").localizedCaseInsensitiveContains("unsafe") }
        print("Guardrail rejections: \(guardrail.count)")
        // Latencias
        let lat = records.map(\.latencyMs).sorted()
        func stats(_ xs: [Double]) -> (Double, Double) {
            guard !xs.isEmpty else { return (0, 0) }
            return (xs.reduce(0, +) / Double(xs.count), percentile(xs.sorted(), 0.5))
        }
        let cold = records.first?.latencyMs ?? 0
        let steady = Array(lat.dropFirst())
        let all = stats(steady)
        print(String(format: "Latency cold=%.0f mean=%.0f median=%.0f p95=%.0f (n=%d)", cold, all.0, all.1, percentile(steady, 0.95), records.count))
        for g in ["A", "B", "C", "D", "E", "F", "G", "H", "I"] {
            let xs = records.filter { $0.test.group == g }.map(\.latencyMs)
            let s = stats(xs)
            print(String(format: "  %@ mean=%.0f median=%.0f (n=%d)", g, s.0, s.1, xs.count))
        }
        // Fallos single
        print("Single failures:")
        for r in singles {
            let ok: Bool
            if case .actions(let s) = r.plan, s.actions.count == 1, s.actions[0].toolName == r.test.expected { ok = true }
            else { ok = false }
            if !ok {
                let got: String
                if let p = r.plan {
                    switch p {
                    case .actions(let s): got = s.actions.map(\.toolName).joined(separator: "+")
                    case .unsupported: got = "UNSUPPORTED"
                    case .noAction: got = "NOACTION"
                    }
                } else { got = "ERROR" }
                print("  \(r.test.id) [\(r.test.group)] exp=\(r.test.expected) got=\(got) | \(r.test.utterance)")
            }
        }
    }

    static func runRegression(model: SystemLanguageModel, options: GenerationOptions) async {
        print("\nPHASE5_REGRESSION (diagnóstico, fuera de métrica principal)")
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("data/regression_p5.csv")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            print("sin regression_p5.csv, se omite")
            return
        }
        let clock = ContinuousClock()
        var n = 0, sOk = 0, sTot = 0, unsOk = 0, unsTot = 0, subs = 0
        var naOk = 0, naTot = 0, naFalse = 0, argT = 0, argOk = 0, errs = 0, guardrail = 0
        var want: [String: String] = [:]
        for line in text.components(separatedBy: "\n").dropFirst() {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let p = splitCSV(line)
            guard p.count >= 9 else { continue }
            // id,group,voice,sel,undo,redo,open,expectedTools(|),expectedArgs(k=v;)
            let exp = p[7].split(separator: "|").map(String.init).filter { !$0.isEmpty }
            want = [:]
            for kv in p[8].split(separator: ";") {
                let k2 = kv.split(separator: "=", maxSplits: 1).map(String.init)
                if k2.count == 2 { want[k2[0]] = k2[1] }
            }
            let session = LanguageModelSession(model: model, instructions: instructions)
            let s = clock.now
            do {
                let resp = try await session.respond(
                    to: prompt(hasSel: p[3] == "1", undo: p[4] == "1", redo: p[5] == "1",
                               open: p[6] == "1", voice: p[2]),
                    generating: CommandPlan.self, options: options)
                _ = milliseconds(s, clock.now)
                n += 1
                switch resp.content {
                case .actions(let seq):
                    let act = seq.actions.map(\.toolName)
                    if p[1] == "F" { subs += 1; unsTot += 1 }
                    else if exp.isEmpty { naFalse += 1; naTot += 1 }
                    else { sTot += 1; if act == exp { sOk += 1 } }
                    for a in seq.actions {
                        let (k, v): (String, String?)
                        switch a {
                        case .renameTitle(let x): (k, v) = ("newTitle", x)
                        case .replaceSelection(let x): (k, v) = ("newText", x)
                        case .findText(let x): (k, v) = ("query", x)
                        default: continue
                        }
                        if let w = want[k], !w.isEmpty {
                            argT += 1
                            if normLit(v ?? "") == normLit(w) { argOk += 1 }
                        }
                    }
                case .unsupported:
                    if p[1] == "F" { unsOk += 1; unsTot += 1 }
                    else if !exp.isEmpty { sTot += 1 }
                    else { naTot += 1; naOk += 1 }
                case .noAction:
                    if p[1] == "F" { unsTot += 1 }
                    else if !exp.isEmpty { sTot += 1 }
                    else { naTot += 1; naOk += 1 }
                }
            } catch {
                errs += 1
                if "\(error)".localizedCaseInsensitiveContains("sensitive") { guardrail += 1 }
            }
            print(".", terminator: "")
            fflush(stdout)
        }
        print("\nregression n=\(n) single=\(sOk)/\(sTot) uns=\(unsOk)/\(unsTot) subs=\(subs) na=\(naOk)/\(naTot) naFalse=\(naFalse) args=\(argOk)/\(argT) errs=\(errs) guardrail=\(guardrail)")
    }
}
