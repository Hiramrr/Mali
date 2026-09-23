// Runner: routing explícito, FM solo en COMMAND MODE, métricas de PipelineRecord.
import Foundation
import FoundationModels

struct PipelineRecord: Sendable {
    let test: PipelineTest
    let fmCalled: Bool
    let calls: [RecordedToolCall]
    let latencyMs: Double
    let error: String?
}

let instructions = """
You interpret spoken input directed at a text editor.
Call an editor tool only when the user clearly requests an executable editor action.
The user may also be dictating ordinary document content. Text that talks about editing, titles, deleting, replacing, formatting, or editors is not necessarily an instruction.
Use the current editor state when determining whether an action is applicable.
If the user is dictating text, making an incomplete request, or the intended action is unclear, do not call a tool.
"""

func prompt(_ c: EditorContext, _ voice: String) -> String {
    """
    CURRENT TITLE:
    \(c.currentTitle)

    SELECTED TEXT:
    \(c.selectedText ?? "none")

    CAN UNDO:
    \(c.canUndo)

    CAN REDO:
    \(c.canRedo)

    DOCUMENT OPEN:
    \(c.documentIsOpen)

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

func normalizeArg(_ s: String) -> String {
    var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
        t = String(t.dropFirst().dropLast())
    }
    t = t.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.hasSuffix(".") || t.hasSuffix("!") { t = String(t.dropLast()) }
    return t
}

@main
struct PipelineApp {
    static func main() async {
        let model = SystemLanguageModel.default
        print("Availability: \(model.availability)")
        guard case .available = model.availability else {
            print("Modelo no disponible. Fin sin sustitutos.")
            return
        }
        let clock = ContinuousClock()
        var records: [PipelineRecord] = []
        var fmCalls = 0

        for test in allTests {
            if test.mode == .dictation {
                // Rama explícita: FM no participa. Solo medir el branch.
                let s = clock.now
                let route = "DICTATION_PIPELINE"
                let ms = milliseconds(s, clock.now)
                _ = route
                records.append(PipelineRecord(test: test, fmCalled: false, calls: [], latencyMs: ms, error: nil))
                continue
            }
            let recorder = ToolRecorder()
            let session = LanguageModelSession(
                model: model, tools: makeTools(context: test.context, recorder: recorder),
                instructions: instructions)
            // Tool calling por defecto: el modelo decide libremente.
            let start = clock.now
            do {
                _ = try await session.respond(to: prompt(test.context, test.voice))
                let calls = await recorder.calls
                fmCalls += 1
                records.append(PipelineRecord(test: test, fmCalled: true, calls: calls,
                                              latencyMs: milliseconds(start, clock.now), error: nil))
            } catch {
                records.append(PipelineRecord(test: test, fmCalled: true, calls: [],
                                              latencyMs: milliseconds(start, clock.now), error: "\(error)"))
            }
            print(".", terminator: "")
            fflush(stdout)
        }
        print("\n")
        printSummary(records: records)
        await interactive(model: model)
    }

    static func printSummary(records: [PipelineRecord]) {
        let dict = records.filter { $0.test.mode == .dictation }
        let cmd = records.filter { $0.test.mode == .command }
        let dictFM = dict.filter(\.fmCalled).count
        let dictCalls = dict.map(\.calls.count).reduce(0, +)
        print("========================================")
        print("EXPLICIT COMMAND PIPELINE")
        print("========================================")
        print("Total tests: \(records.count)")
        print("")
        print("ROUTING SAFETY (dictation mode, n=\(dict.count)):")
        print("Foundation invocations: \(dictFM)")
        print("Tool calls: \(dictCalls)")
        print(dictFM == 0 && dictCalls == 0 ? "ROUTING: SAFE (by construction)" : "ARCHITECTURE_SAFETY_FAILURE")
        print("")

        // Single-command accuracy: grupos C (+D semántico)
        let single = records.filter { $0.test.group == "C" }
        var correct = 0, wrong = 0, missed = 0
        var argCases = 0, argOk = 0
        var argLangFails: [String] = []
        for r in single {
            let exp = r.test.expectedTools
            let act = r.calls.map(\.tool)
            if r.error != nil { missed += 1; continue }
            if act.isEmpty { missed += 1; continue }
            if act.count == 1 && act == exp {
                correct += 1
                // args
                if !r.test.expectedArgs.isEmpty {
                    argCases += 1
                    var ok = true
                    let parts = r.calls[0].arguments.split(separator: "|")
                    var actual: [String: String] = [:]
                    for p in parts {
                        let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
                        if kv.count == 2 { actual[kv[0]] = kv[1] }
                    }
                    for (k, v) in r.test.expectedArgs {
                        if normalizeArg(actual[k] ?? "") != normalizeArg(v) { ok = false }
                    }
                    if ok { argOk += 1 }
                    else if r.test.preserveLang { argLangFails.append("\(r.test.id): \(r.calls[0].arguments)") }
                }
            } else { wrong += 1 }
        }
        let total1 = single.count
        print("COMMAND MODE single (C, n=\(total1)): correct=\(correct) wrong=\(wrong) missed=\(missed)")
        print(String(format: "Single-command Tool Accuracy: %.1f%%", 100.0 * Double(correct) / Double(max(total1, 1))))
        print(String(format: "Argument Accuracy: %.1f%% (%d/%d)", argCases > 0 ? 100.0 * Double(argOk) / Double(argCases) : 0, argOk, argCases))
        if !argLangFails.isEmpty {
            print("Argument-language failures:")
            for f in argLangFails { print("  \(f)") }
        }
        print("")

        // D: semántica vs ejecutabilidad
        let d = records.filter { $0.test.group == "D" }
        let dSemOk = d.filter { $0.calls.map(\.tool) == $0.test.expectedTools }.count
        let dBlocked = d.filter { !$0.calls.isEmpty && !$0.calls[0].validation.isValid }.count
        print("GROUP D (n=\(d.count)): semantic correct=\(dSemOk) validator-blocked=\(dBlocked)")
        print("")

        // E: false tool rate
        let e = records.filter { $0.test.group == "E" }
        let eFalse = e.filter { !$0.calls.isEmpty }.count
        print("GROUP E non-command (n=\(e.count)): false tool calls=\(eFalse)")
        print(String(format: "Command-mode False Tool Rate: %.1f%%", 100.0 * Double(eFalse) / Double(max(e.count, 1))))
        print("")

        // F: unsupported
        let f = records.filter { $0.test.group == "F" }
        let fNone = f.filter { $0.calls.isEmpty }.count
        let fWrong = f.filter { !$0.calls.isEmpty }.count
        print("GROUP F unsupported (n=\(f.count)): no-tool=\(fNone) wrong-tool substitutions=\(fWrong)")
        for r in f where !r.calls.isEmpty {
            print("  \(r.test.id) \(r.test.voice) -> \(r.calls.map(\.tool).joined(separator: ","))")
        }
        print("")

        // G: multi-action
        let g = records.filter { $0.test.group == "G" }
        print("GROUP G multi-action (n=\(g.count)):")
        for r in g {
            let act = r.calls.map(\.tool)
            let exp = r.test.expectedTools
            let verdict = act == exp ? "EXACT" : (act.isEmpty ? "MISSING" : "PARTIAL/WRONG")
            print("  \(r.test.id) [\(verdict)] exp=\(exp.joined(separator: "+")) act=\(act.joined(separator: "+"))")
            for c in r.calls { print("      \(c.tool) \(c.arguments) [\(c.validation.label)]") }
        }
        print("")

        // Validator global (command mode con llamadas)
        let proposed = cmd.flatMap(\.calls)
        let valid = proposed.filter { $0.validation.isValid }.count
        print("VALIDATOR (command mode): proposed=\(proposed.count) valid=\(valid) blocked=\(proposed.count - valid)")
        print("")

        // Latencias
        let cmdLat = cmd.map(\.latencyMs)
        let cold = cmdLat.first ?? 0
        let steady = Array(cmdLat.dropFirst()).sorted()
        func stats(_ xs: [Double]) -> (Double, Double) {
            guard !xs.isEmpty else { return (0, 0) }
            return (xs.reduce(0, +) / Double(xs.count), percentile(xs.sorted(), 0.5))
        }
        let all = stats(steady)
        let noTool = stats(steady.enumerated().filter { cmd[$0.offset + 1].calls.isEmpty }.map(\.element))
        let withTool = stats(steady.enumerated().filter { !cmd[$0.offset + 1].calls.isEmpty }.map(\.element))
        let multi = stats(cmd.filter { $0.test.group == "G" }.map(\.latencyMs))
        let dictLat = dict.map(\.latencyMs)
        print("Latency (ms):")
        print(String(format: "Foundation cold start: %.0f", cold))
        print(String(format: "Single mean/med/p95: %.0f/%.0f/%.0f", all.0, all.1, percentile(steady, 0.95)))
        print(String(format: "No-tool: mean %.0f med %.0f | Tool-call: mean %.0f med %.0f", noTool.0, noTool.1, withTool.0, withTool.1))
        print(String(format: "Multi-action: mean %.0f med %.0f", multi.0, multi.1))
        print(String(format: "Dictation routing: max %.3f ms (no FM)", dictLat.max() ?? 0))
        print("")

        // Fallos C (wrong/missed)
        print("C wrong/missed:")
        for r in single where r.calls.map(\.tool) != r.test.expectedTools {
            print("  \(r.test.id) exp=\(r.test.expectedTools.joined(separator: ",")) act=\(r.error ?? r.calls.map(\.tool).joined(separator: ",")) | \(r.test.voice)")
        }
        print("E false calls:")
        for r in e where !r.calls.isEmpty {
            print("  \(r.test.id) -> \(r.calls.map { "\($0.tool)(\($0.arguments))" }.joined(separator: ",")) | \(r.test.voice)")
        }
    }

    static func interactive(model: SystemLanguageModel) async {
        print("\nInteractivo: MODE (dictation|command), luego Selected, Voice. 'exit' sale.")
        let clock = ContinuousClock()
        while true {
            print("MODE:"); guard let m = readLine(), m.lowercased() != "exit" else { break }
            let mode: VoiceInteractionMode = (m.lowercased() == "command") ? .command : .dictation
            print("Selected (vacío=none):"); guard let sel = readLine() else { break }
            print("Voice:"); guard let voice = readLine(), !voice.isEmpty else { continue }
            if voice.lowercased() == "exit" { break }
            let ctx = EditorContext(currentTitle: "Introducción",
                                    selectedText: sel.isEmpty ? nil : sel,
                                    canUndo: false, canRedo: false, documentIsOpen: true)
            if mode == .dictation {
                print("ROUTE: DICTATION_PIPELINE (FM no llamado)")
                continue
            }
            let recorder = ToolRecorder()
            let session = LanguageModelSession(model: model, tools: makeTools(context: ctx, recorder: recorder),
                                               instructions: instructions)
            let s = clock.now
            do {
                _ = try await session.respond(to: prompt(ctx, voice))
                for c in await recorder.calls {
                    print("Tool: \(c.tool) \(c.arguments) [\(c.validation.label)]")
                }
                if await recorder.calls.isEmpty { print("Tool: none") }
                print(String(format: "Latency: %.0f ms", milliseconds(s, clock.now)))
            } catch {
                print("Error: \(error)")
            }
        }
    }
}
