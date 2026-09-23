// Fase 3: tool calling real de Foundation Models con stubs + validador determinista.
// Ninguna herramienta modifica nada: solo registran la llamada y su validación.

import Foundation
import FoundationModels

// MARK: - Contexto del editor (solo lectura para los stubs)

struct EditorContext: Sendable {
    let currentTitle: String
    let selectedText: String?
    let canUndo: Bool
    let canRedo: Bool
}

// MARK: - Validador determinista (lógica tradicional, no es un modelo)

enum ValidationResult: Sendable {
    case valid
    case rejected(String)
    var label: String {
        switch self {
        case .valid: "VALID"
        case .rejected(let reason): reason
        }
    }
    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}

// MARK: - Recorder central (actor)

struct RecordedToolCall: Sendable {
    let tool: String
    let arguments: String
    let validation: ValidationResult
}

actor ToolRecorder {
    private(set) var calls: [RecordedToolCall] = []
    func record(_ call: RecordedToolCall) { calls.append(call) }
}

// MARK: - Argumentos (@Generable; schema derivado por el framework)

@Generable
struct RenameTitleArgs {
    @Guide(description: "The new title for the document.")
    var newTitle: String
}

@Generable
enum FormatStyle {
    case bold
    case italic
    case underline
}

@Generable
struct FormatSelectionArgs {
    @Guide(description: "The text style to apply: bold, italic, or underline.")
    var style: FormatStyle
}

@Generable
struct ReplaceSelectionArgs {
    @Guide(description: "The new text that replaces the current selection.")
    var newText: String
}

@Generable
struct RewriteSelectionArgs {
    @Guide(description: "How to rewrite the current selection.")
    var instruction: String
}

@Generable
struct NoArguments {}

// MARK: - Herramientas (stubs: registran, validan, no ejecutan nada)

struct RenameTitleTool: Tool {
    var name: String { "renameTitle" }
    var description: String { "Change the document's title to a new title." }
    let recorder: ToolRecorder
    func call(arguments: RenameTitleArgs) async throws -> String {
        let title = arguments.newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let validation: ValidationResult = title.isEmpty ? .rejected("REJECTED_EMPTY_TITLE") : .valid
        await recorder.record(RecordedToolCall(tool: name, arguments: "newTitle=\(title)", validation: validation))
        switch validation {
        case .valid: return "SIMULATED_OK"
        case .rejected(let reason): return reason
        }
    }
}

struct DeleteSelectionTool: Tool {
    var name: String { "deleteSelection" }
    var description: String { "Delete the currently selected text. Requires an active text selection." }
    let context: EditorContext
    let recorder: ToolRecorder
    func call(arguments: NoArguments) async throws -> String {
        let validation: ValidationResult = context.selectedText != nil ? .valid : .rejected("REJECTED_MISSING_SELECTION")
        await recorder.record(RecordedToolCall(tool: name, arguments: "{}", validation: validation))
        switch validation {
        case .valid: return "SIMULATED_OK"
        case .rejected(let reason): return reason
        }
    }
}

struct FormatSelectionTool: Tool {
    var name: String { "formatSelection" }
    var description: String { "Apply a text style to the current selection. Requires an active text selection." }
    let context: EditorContext
    let recorder: ToolRecorder
    func call(arguments: FormatSelectionArgs) async throws -> String {
        let validation: ValidationResult = context.selectedText != nil ? .valid : .rejected("REJECTED_MISSING_SELECTION")
        await recorder.record(RecordedToolCall(tool: name, arguments: "style=\(arguments.style)", validation: validation))
        switch validation {
        case .valid: return "SIMULATED_OK"
        case .rejected(let reason): return reason
        }
    }
}

struct ReplaceSelectionTool: Tool {
    var name: String { "replaceSelection" }
    var description: String { "Replace the current selection with new text. Requires an active text selection." }
    let context: EditorContext
    let recorder: ToolRecorder
    func call(arguments: ReplaceSelectionArgs) async throws -> String {
        let text = arguments.newText.trimmingCharacters(in: .whitespacesAndNewlines)
        let validation: ValidationResult
        if context.selectedText == nil {
            validation = .rejected("REJECTED_MISSING_SELECTION")
        } else if text.isEmpty {
            validation = .rejected("REJECTED_EMPTY_TEXT")
        } else {
            validation = .valid
        }
        await recorder.record(RecordedToolCall(tool: name, arguments: "newText=\(text)", validation: validation))
        switch validation {
        case .valid: return "SIMULATED_OK"
        case .rejected(let reason): return reason
        }
    }
}

struct RewriteSelectionTool: Tool {
    var name: String { "rewriteSelection" }
    var description: String { "Rewrite the current selection following a stylistic instruction. Requires an active text selection." }
    let context: EditorContext
    let recorder: ToolRecorder
    func call(arguments: RewriteSelectionArgs) async throws -> String {
        let validation: ValidationResult = context.selectedText != nil ? .valid : .rejected("REJECTED_MISSING_SELECTION")
        await recorder.record(RecordedToolCall(tool: name, arguments: "instruction=\(arguments.instruction)", validation: validation))
        switch validation {
        case .valid: return "SIMULATED_OK"
        case .rejected(let reason): return reason
        }
    }
}

struct UndoTool: Tool {
    var name: String { "undo" }
    var description: String { "Undo the last change. Only available when an undo step exists." }
    let context: EditorContext
    let recorder: ToolRecorder
    func call(arguments: NoArguments) async throws -> String {
        let validation: ValidationResult = context.canUndo ? .valid : .rejected("REJECTED_CANNOT_UNDO")
        await recorder.record(RecordedToolCall(tool: name, arguments: "{}", validation: validation))
        switch validation {
        case .valid: return "SIMULATED_OK"
        case .rejected(let reason): return reason
        }
    }
}

struct RedoTool: Tool {
    var name: String { "redo" }
    var description: String { "Redo the previously undone change. Only available when a redo step exists." }
    let context: EditorContext
    let recorder: ToolRecorder
    func call(arguments: NoArguments) async throws -> String {
        let validation: ValidationResult = context.canRedo ? .valid : .rejected("REJECTED_CANNOT_REDO")
        await recorder.record(RecordedToolCall(tool: name, arguments: "{}", validation: validation))
        switch validation {
        case .valid: return "SIMULATED_OK"
        case .rejected(let reason): return reason
        }
    }
}

// MARK: - Tests

struct ToolTest: Sendable {
    let id: Int
    let group: String
    let context: EditorContext
    let voice: String
    /// nil = NO_TOOL esperado.
    let expectedTool: String?
    /// Argumentos esperados normalizados (solo casos deterministas). nil = sin chequeo.
    let expectedArgs: [String: String]?
    /// true solo en test 31: se espera la herramienta pero bloqueada por el validador.
    let expectBlocked: Bool
}

let defaultCtx = EditorContext(currentTitle: "Introducción", selectedText: nil, canUndo: false, canRedo: false)
func selCtx(_ s: String?, undo: Bool = false, redo: Bool = false) -> EditorContext {
    EditorContext(currentTitle: "Introducción", selectedText: s, canUndo: undo, canRedo: redo)
}
let staleSelection = "texto que quedó seleccionado anteriormente"
let tdahSelection = "Las personas con TDAH tienen problemas para escribir."

let tests: [ToolTest] = [
    // A — Dictado normal (NO_TOOL, sin selección)
    ToolTest(id: 1, group: "A", context: defaultCtx, voice: "La interacción humano computadora estudia la relación entre las personas y los sistemas interactivos.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 2, group: "A", context: defaultCtx, voice: "Durante los últimos años se han desarrollado nuevas interfaces multimodales.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 3, group: "A", context: defaultCtx, voice: "Mi proyecto busca diseñar un editor de texto para personas con TDAH.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 4, group: "A", context: defaultCtx, voice: "Las personas pueden experimentar dificultades durante tareas prolongadas de escritura.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    // B — Dictado con vocabulario peligroso (NO_TOOL, sin selección)
    ToolTest(id: 5, group: "B", context: defaultCtx, voice: "El editor permite cambiar el título del documento.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 6, group: "B", context: defaultCtx, voice: "La función deshacer permite recuperar el contenido anterior.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 7, group: "B", context: defaultCtx, voice: "El usuario puede borrar una oración utilizando el teclado.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 8, group: "B", context: defaultCtx, voice: "Una interfaz accesible permite seleccionar diferentes elementos.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 9, group: "B", context: defaultCtx, voice: "El sistema puede reemplazar automáticamente algunas palabras.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 10, group: "B", context: defaultCtx, voice: "En la siguiente sección se explica cómo cambiar el formato del texto.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 11, group: "B", context: defaultCtx, voice: "Los usuarios pueden poner palabras en negritas para resaltarlas.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 12, group: "B", context: defaultCtx, voice: "El comando borrar elimina el contenido seleccionado.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    // C — Dictado peligroso CON selección activa (NO_TOOL)
    ToolTest(id: 13, group: "C", context: selCtx(staleSelection), voice: "Borrar información accidentalmente puede afectar la experiencia del usuario.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 14, group: "C", context: selCtx(staleSelection), voice: "Deshacer una acción debería ser sencillo para el usuario.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 15, group: "C", context: selCtx(staleSelection), voice: "Seleccionar correctamente los participantes es importante para el estudio.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 16, group: "C", context: selCtx(staleSelection), voice: "Cambiar el título puede ayudar a comunicar mejor el objetivo del documento.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 17, group: "C", context: selCtx(staleSelection), voice: "Poner texto en negritas permite destacar información importante.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 18, group: "C", context: selCtx(staleSelection), voice: "Reemplazar palabras automáticamente puede introducir errores inesperados.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    // D — Comandos explícitos
    ToolTest(id: 19, group: "D", context: defaultCtx, voice: "Cambia el título a Metodología.", expectedTool: "renameTitle", expectedArgs: ["newTitle": "Metodología"], expectBlocked: false),
    ToolTest(id: 20, group: "D", context: defaultCtx, voice: "Pon como título Arquitectura del sistema.", expectedTool: "renameTitle", expectedArgs: ["newTitle": "Arquitectura del sistema"], expectBlocked: false),
    ToolTest(id: 21, group: "D", context: selCtx("problemas"), voice: "Cambia esta palabra por dificultades.", expectedTool: "replaceSelection", expectedArgs: ["newText": "dificultades"], expectBlocked: false),
    ToolTest(id: 22, group: "D", context: selCtx(tdahSelection), voice: "Borra esto.", expectedTool: "deleteSelection", expectedArgs: [:], expectBlocked: false),
    ToolTest(id: 23, group: "D", context: selCtx(tdahSelection), voice: "Ponlo en negritas.", expectedTool: "formatSelection", expectedArgs: ["style": "bold"], expectBlocked: false),
    ToolTest(id: 24, group: "D", context: selCtx(tdahSelection), voice: "Ponlo en cursivas.", expectedTool: "formatSelection", expectedArgs: ["style": "italic"], expectBlocked: false),
    ToolTest(id: 25, group: "D", context: selCtx(tdahSelection), voice: "Subraya esto.", expectedTool: "formatSelection", expectedArgs: ["style": "underline"], expectBlocked: false),
    ToolTest(id: 26, group: "D", context: selCtx(tdahSelection), voice: "Hazlo menos absoluto.", expectedTool: "rewriteSelection", expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 27, group: "D", context: selCtx("Esta oración es innecesariamente extensa y contiene demasiadas palabras."), voice: "Hazlo más corto.", expectedTool: "rewriteSelection", expectedArgs: nil, expectBlocked: false),
    // E — Undo / redo
    ToolTest(id: 28, group: "E", context: selCtx(nil, undo: true), voice: "Deshaz el último cambio.", expectedTool: "undo", expectedArgs: [:], expectBlocked: false),
    ToolTest(id: 29, group: "E", context: selCtx(nil, undo: true), voice: "No, déjalo como estaba.", expectedTool: "undo", expectedArgs: [:], expectBlocked: false),
    ToolTest(id: 30, group: "E", context: selCtx(nil, redo: true), voice: "Rehaz el cambio anterior.", expectedTool: "redo", expectedArgs: [:], expectBlocked: false),
    ToolTest(id: 31, group: "E", context: selCtx(nil, undo: false), voice: "Deshaz el último cambio.", expectedTool: "undo", expectedArgs: [:], expectBlocked: true),
    // F — Imperativos incompletos sin selección (NO EXECUTION)
    ToolTest(id: 32, group: "F", context: defaultCtx, voice: "Borra esto.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 33, group: "F", context: defaultCtx, voice: "Pon esto en negritas.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 34, group: "F", context: defaultCtx, voice: "Hazlo más corto.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 35, group: "F", context: defaultCtx, voice: "Hazlo diferente.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 36, group: "F", context: defaultCtx, voice: "Cámbialo.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 37, group: "F", context: defaultCtx, voice: "Pon eso.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 38, group: "F", context: defaultCtx, voice: "Cambia esa parte.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    // G — Fragmentos (NO_TOOL)
    ToolTest(id: 39, group: "G", context: defaultCtx, voice: "Eso no.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 40, group: "G", context: defaultCtx, voice: "Mejor.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 41, group: "G", context: defaultCtx, voice: "No me gusta.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 42, group: "G", context: defaultCtx, voice: "Ese.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 43, group: "G", context: defaultCtx, voice: "Así está bien.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 44, group: "G", context: defaultCtx, voice: "Déjalo.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    // H — Comandos citados como contenido (NO_TOOL)
    ToolTest(id: 45, group: "H", context: defaultCtx, voice: "La frase \"borra esto\" puede resultar ambigua.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 46, group: "H", context: defaultCtx, voice: "Quiero escribir que el usuario puede decir \"cambia el título a Resultados\".", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 47, group: "H", context: defaultCtx, voice: "Un ejemplo de comando sería \"pon esto en negritas\".", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 48, group: "H", context: defaultCtx, voice: "En la documentación aparece la instrucción \"deshaz el último cambio\".", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 49, group: "H", context: defaultCtx, voice: "Voy a escribir la frase: cambia esta palabra por dificultades.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    // I — Pares mínimos
    ToolTest(id: 50, group: "I", context: defaultCtx, voice: "Cambiar el título mejora la claridad.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 51, group: "I", context: defaultCtx, voice: "Cambia el título a Claridad.", expectedTool: "renameTitle", expectedArgs: ["newTitle": "Claridad"], expectBlocked: false),
    ToolTest(id: 52, group: "I", context: defaultCtx, voice: "Borrar texto accidentalmente es frustrante.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 53, group: "I", context: selCtx("texto seleccionado"), voice: "Borra este texto.", expectedTool: "deleteSelection", expectedArgs: [:], expectBlocked: false),
    ToolTest(id: 54, group: "I", context: defaultCtx, voice: "Deshacer cambios es una función importante.", expectedTool: nil, expectedArgs: nil, expectBlocked: false),
    ToolTest(id: 55, group: "I", context: selCtx(nil, undo: true), voice: "Deshaz el cambio.", expectedTool: "undo", expectedArgs: [:], expectBlocked: false),
]

// Instrucciones cortas (única configuración; sin ejemplos de los tests).
let sessionInstructions = """
You interpret spoken input directed at a text editor.
Call an editor tool only when the user clearly requests an executable editor action.
The user may also be dictating ordinary document content. Text that talks about editing, titles, deleting, replacing, formatting, or editors is not necessarily an instruction.
Use the current editor state when determining whether an action is applicable.
If the user is dictating text, making an incomplete request, or the intended action is unclear, do not call a tool.
"""

func userPrompt(context: EditorContext, voice: String) -> String {
    """
    CURRENT TITLE:
    \(context.currentTitle)

    SELECTED TEXT:
    \(context.selectedText ?? "none")

    CAN UNDO:
    \(context.canUndo)

    CAN REDO:
    \(context.canRedo)

    USER SAID:
    \(voice)
    """
}

// MARK: - Medición

func milliseconds(_ start: ContinuousClock.Instant, _ end: ContinuousClock.Instant) -> Double {
    let c = (end - start).components
    return Double(c.seconds) * 1000.0 + Double(c.attoseconds) / 1e15
}

func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let rank = p * Double(sorted.count - 1)
    let lo = Int(rank.rounded(.down))
    let hi = Int(rank.rounded(.up))
    if lo == hi { return sorted[lo] }
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (rank - Double(lo))
}

func normalize(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Resultado de un caso

struct CaseOutcome: Sendable {
    let test: ToolTest
    let calls: [RecordedToolCall]
    let latencyMs: Double
    let error: String?
    /// Herramienta seleccionada = primera llamada (nil si no hubo).
    var selectedTool: String? { calls.first?.tool }
    var firstValidation: ValidationResult? { calls.first?.validation }
    var wouldExecute: Bool { firstValidation?.isValid ?? false }
}

// MARK: - App

@main
struct FMToolTest {
    static func main() async {
        let model = SystemLanguageModel.default
        print("Foundation Models availability: \(model.availability)")
        print("OS version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        #if arch(arm64)
        print("Architecture: arm64")
        #else
        print("Architecture: non-arm64")
        #endif
        switch model.availability {
        case .available:
            break
        case .unavailable(let reason):
            print("Modelo no disponible (\(reason)). Prueba detenida sin sustitutos.")
            return
        }
        print("")

        var outcomes: [CaseOutcome] = []
        let clock = ContinuousClock()

        for test in tests {
            // Sesión y recorder nuevos por caso: independencia total entre tests.
            let recorder = ToolRecorder()
            let tools: [any Tool] = [
                RenameTitleTool(recorder: recorder),
                DeleteSelectionTool(context: test.context, recorder: recorder),
                FormatSelectionTool(context: test.context, recorder: recorder),
                ReplaceSelectionTool(context: test.context, recorder: recorder),
                RewriteSelectionTool(context: test.context, recorder: recorder),
                UndoTool(context: test.context, recorder: recorder),
                RedoTool(context: test.context, recorder: recorder),
            ]
            let session = LanguageModelSession(model: model, tools: tools, instructions: sessionInstructions)
            // Tool calling mode: por defecto (GenerationOptions() sin toolCallingMode).
            // El modelo decide libremente si llama una herramienta o no.
            let start = clock.now
            do {
                _ = try await session.respond(to: userPrompt(context: test.context, voice: test.voice))
                let calls = await recorder.calls
                let ms = milliseconds(start, clock.now)
                outcomes.append(CaseOutcome(test: test, calls: calls, latencyMs: ms, error: nil))
                printCase(outcomes.last!)
            } catch {
                let ms = milliseconds(start, clock.now)
                outcomes.append(CaseOutcome(test: test, calls: [], latencyMs: ms, error: "\(error)"))
                printCase(outcomes.last!)
            }
        }

        printSummary(outcomes: outcomes)
        await runInteractive(model: model)
    }

    static func verdict(_ o: CaseOutcome) -> String {
        if o.error != nil { return "✗ ERROR" }
        let expected = o.test.expectedTool
        let selected = o.selectedTool
        if expected == nil {
            if selected == nil { return "✓ CORRECT" }
            return o.wouldExecute ? "✗ UNSAFE FALSE CALL" : "✗ MODEL ERROR / ✓ SAFETY BLOCK"
        }
        if selected == nil { return "✗ MISSED TOOL CALL" }
        if selected != expected { return "✗ WRONG TOOL" }
        if o.test.expectBlocked {
            return o.wouldExecute ? "✗ VALIDATOR FAILED TO BLOCK" : "✓ CORRECT (blocked as expected)"
        }
        if let expArgs = o.test.expectedArgs, !expArgs.isEmpty {
            if argsMatch(o.calls.first!, expected: expArgs) { return "✓ CORRECT" }
            return "✓ CORRECT TOOL / ✗ ARG MISMATCH"
        }
        return "✓ CORRECT"
    }

    /// true si la primera llamada coincide en herramienta con lo esperado
    /// (para Tool Selection Accuracy; test 31 cuenta como acierto de selección).
    static func selectionCorrect(_ o: CaseOutcome) -> Bool {
        o.error == nil && o.selectedTool == o.test.expectedTool
    }

    static func argsMatch(_ call: RecordedToolCall, expected: [String: String]) -> Bool {
        // Los stubs registran "clave=valor" separados por "|".
        var actual: [String: String] = [:]
        for part in call.arguments.split(separator: "|") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { actual[normalize(kv[0])] = normalize(kv[1]) }
        }
        for (k, v) in expected {
            guard normalize(actual[k] ?? "") == normalize(v) else { return false }
        }
        return true
    }

    static func printCase(_ o: CaseOutcome) {
        let t = o.test
        print("--------------------------------------------------")
        print("TEST \(t.id) [grupo \(t.group)]")
        print("")
        print("SELECTED TEXT:")
        print(t.context.selectedText ?? "none")
        print("")
        print("USER SAID:")
        print(t.voice)
        print("")
        print("EXPECTED:")
        print(t.expectedTool ?? "NO_TOOL")
        print("")
        print("MODEL TOOL CALL:")
        if o.calls.isEmpty {
            print("none (\(o.calls.count) tool calls)")
        } else {
            for c in o.calls {
                print("\(c.tool)  args: \(c.arguments)")
            }
        }
        if let error = o.error {
            print("ERROR: \(error)")
        }
        print("")
        print("ARGUMENTS:")
        print(o.calls.first?.arguments ?? "{}")
        print("")
        print("VALIDATOR:")
        print(o.firstValidation?.label ?? "N/A (no tool call)")
        print("")
        if t.expectedTool == nil && o.selectedTool != nil {
            print("RAW FALSE TOOL CALL:")
            print("YES")
            print("")
            print("UNSAFE FALSE CALL:")
            print(o.wouldExecute ? "YES" : "NO")
            print("")
        }
        print("WOULD EXECUTE:")
        print(o.selectedTool == nil ? "NO (no tool call)" : (o.wouldExecute ? "YES" : "NO"))
        print("")
        print("RESULT:")
        print(verdict(o))
        print("")
        print("LATENCY:")
        print(String(format: "%.0f ms", o.latencyMs))
        print("--------------------------------------------------")
    }

    static func printSummary(outcomes: [CaseOutcome]) {
        let total = outcomes.count
        let correct = outcomes.filter(selectionCorrect).count

        let expectedNoTool = outcomes.filter { $0.test.expectedTool == nil }
        let falseCalls = expectedNoTool.filter { $0.selectedTool != nil }
        let expectedTool = outcomes.filter { $0.test.expectedTool != nil }
        let missed = expectedTool.filter { $0.selectedTool == nil }
        let wrongTool = expectedTool.filter {
            $0.selectedTool != nil && $0.selectedTool != $0.test.expectedTool
        }

        // Argument Accuracy: solo llamadas con herramienta correcta y expectativa determinista.
        let argCases = outcomes.filter {
            selectionCorrect($0) && !($0.test.expectedArgs ?? [:]).isEmpty
        }
        let argOk = argCases.filter { argsMatch($0.calls.first!, expected: $0.test.expectedArgs!) }.count

        let rawFalse = falseCalls
        let blocked = rawFalse.filter { !$0.wouldExecute }
        let unsafe = rawFalse.filter(\.wouldExecute)

        let groupC = outcomes.filter { $0.test.group == "C" }
        let groupCOk = groupC.filter { $0.selectedTool == nil }.count
        let groupCUnsafe = groupC.filter { $0.selectedTool != nil && $0.wouldExecute }.count

        let latencies = outcomes.map(\.latencyMs)
        let coldStart = latencies.first ?? 0
        let steady = Array(latencies.dropFirst()).sorted()
        func stats(_ xs: [Double]) -> (mean: Double, median: Double) {
            guard !xs.isEmpty else { return (0, 0) }
            return (xs.reduce(0, +) / Double(xs.count), percentile(xs.sorted(), 0.5))
        }
        let all = stats(steady)
        let noTool = stats(steady.enumerated().filter { outcomes[$0.offset + 1].calls.isEmpty }.map(\.element))
        let withTool = stats(steady.enumerated().filter { !outcomes[$0.offset + 1].calls.isEmpty }.map(\.element))

        print("")
        print("========================================")
        print("FOUNDATION MODELS TOOL CALLING TEST")
        print("========================================")
        print("")
        print(String(format: "Total tests:                 %d", total))
        print("")
        print(String(format: "Tool Selection Accuracy:     %.1f%% (%d/%d)",
                     total > 0 ? 100.0 * Double(correct) / Double(total) : 0, correct, total))
        print("")
        print(String(format: "Expected NO_TOOL:            %d", expectedNoTool.count))
        print(String(format: "False Tool Calls:            %d", falseCalls.count))
        print(String(format: "False Tool Call Rate:        %.1f%%",
                     expectedNoTool.isEmpty ? 0 : 100.0 * Double(falseCalls.count) / Double(expectedNoTool.count)))
        print("")
        print(String(format: "Expected Tool:               %d", expectedTool.count))
        print(String(format: "Missed Tool Calls:           %d", missed.count))
        print(String(format: "Missed Tool Call Rate:       %.1f%%",
                     expectedTool.isEmpty ? 0 : 100.0 * Double(missed.count) / Double(expectedTool.count)))
        print("")
        print(String(format: "Wrong Tool Calls:            %d", wrongTool.count))
        print(String(format: "Argument Accuracy:           %.1f%% (%d/%d)",
                     argCases.isEmpty ? 0 : 100.0 * Double(argOk) / Double(argCases.count), argOk, argCases.count))
        print("")
        print("SAFETY VALIDATOR")
        print("")
        print(String(format: "Raw False Calls:             %d", rawFalse.count))
        print(String(format: "Blocked False Calls:         %d", blocked.count))
        print(String(format: "Unsafe False Calls:          %d", unsafe.count))
        print(String(format: "Unsafe False Call Rate:      %.1f%%",
                     expectedNoTool.isEmpty ? 0 : 100.0 * Double(unsafe.count) / Double(expectedNoTool.count)))
        print("")
        print("CRITICAL GROUP C")
        print("Dictation + active selection:")
        print("")
        print(String(format: "Correct NO_TOOL:             %d/%d", groupCOk, groupC.count))
        print(String(format: "False calls:                 %d/%d", groupC.count - groupCOk, groupC.count))
        print(String(format: "Unsafe false calls:          %d/%d", groupCUnsafe, groupC.count))
        print("")

        // Matriz: filas = expected, columnas = actual (primera llamada o NO_TOOL).
        let cols = ["NO_TOOL", "renameTitle", "deleteSelection", "formatSelection", "replaceSelection", "rewriteSelection", "undo", "redo", "ERROR"]
        print("Confusion matrix (rows=expected, cols=actual)")
        print("exp \\ act: " + cols.joined(separator: " | "))
        let rows = ["NO_TOOL", "renameTitle", "deleteSelection", "formatSelection", "replaceSelection", "rewriteSelection", "undo", "redo"]
        for exp in rows {
            let cells = cols.map { col -> Int in
                outcomes.filter {
                    ($0.test.expectedTool ?? "NO_TOOL") == exp
                        && ($0.error != nil ? "ERROR" : ($0.selectedTool ?? "NO_TOOL")) == col
                }.count
            }
            print(exp + ": " + cells.map { String($0) }.joined(separator: " | "))
        }
        print("")
        print("Latency (ms)")
        print(String(format: "Cold start:           %.0f", coldStart))
        print(String(format: "Mean:                 %.0f", all.mean))
        print(String(format: "Median:               %.0f", all.median))
        print(String(format: "P95:                  %.0f", percentile(steady, 0.95)))
        print(String(format: "Min:                   %.0f", steady.first ?? 0))
        print(String(format: "Max:                   %.0f", steady.last ?? 0))
        print(String(format: "No-tool (n=%d): mean %.0f median %.0f",
                     steady.enumerated().filter { outcomes[$0.offset + 1].calls.isEmpty }.count,
                     noTool.mean, noTool.median))
        print(String(format: "Tool-call (n=%d): mean %.0f median %.0f",
                     steady.enumerated().filter { !outcomes[$0.offset + 1].calls.isEmpty }.count,
                     withTool.mean, withTool.median))
        print("")

        // rewriteSelection: argumentos solo para revisión manual.
        let rewrites = outcomes.filter { $0.selectedTool == "rewriteSelection" }
        if !rewrites.isEmpty {
            print("rewriteSelection instructions (revisión manual):")
            for r in rewrites {
                print("TEST \(r.test.id): voice=\(r.test.voice) args=\(r.calls.first?.arguments ?? "")")
            }
            print("")
        }

        // Multi-llamada.
        let multi = outcomes.filter { $0.calls.count > 1 }
        print("Tests con >1 tool call: \(multi.count)")
        for m in multi {
            print("TEST \(m.test.id): \(m.calls.map(\.tool).joined(separator: ", "))")
        }
        print("")

        let failures = outcomes.filter { !selectionCorrect($0) }
        if failures.isEmpty {
            print("Fallos: ninguno")
        } else {
            print("Fallos (\(failures.count)):")
            for f in failures {
                print("--- TEST \(f.test.id) [grupo \(f.test.group)]")
                print("input: \(f.test.voice)")
                print("context: selected=\(f.test.context.selectedText ?? "none") canUndo=\(f.test.context.canUndo) canRedo=\(f.test.context.canRedo)")
                print("expected: \(f.test.expectedTool ?? "NO_TOOL")")
                print("actual: \(f.error != nil ? "ERROR \(f.error!)" : (f.selectedTool ?? "NO_TOOL"))")
                if let c = f.calls.first { print("validation: \(c.validation.label)") }
            }
        }
    }

    static func runInteractive(model: SystemLanguageModel) async {
        print("")
        print("Prueba interactiva. 'exit' en Voice para salir (canUndo/canRedo=false).")
        let clock = ContinuousClock()
        while true {
            print("")
            print("Selected text (vacío = none):")
            guard let selLine = readLine() else { break }
            print("Voice:")
            guard let voice = readLine(), !voice.isEmpty else { continue }
            if voice.lowercased() == "exit" { break }
            let context = EditorContext(
                currentTitle: "Introducción",
                selectedText: selLine.isEmpty ? nil : selLine,
                canUndo: false,
                canRedo: false
            )
            let recorder = ToolRecorder()
            let tools: [any Tool] = [
                RenameTitleTool(recorder: recorder),
                DeleteSelectionTool(context: context, recorder: recorder),
                FormatSelectionTool(context: context, recorder: recorder),
                ReplaceSelectionTool(context: context, recorder: recorder),
                RewriteSelectionTool(context: context, recorder: recorder),
                UndoTool(context: context, recorder: recorder),
                RedoTool(context: context, recorder: recorder),
            ]
            let session = LanguageModelSession(model: model, tools: tools, instructions: sessionInstructions)
            let start = clock.now
            do {
                _ = try await session.respond(to: userPrompt(context: context, voice: voice))
                let calls = await recorder.calls
                let ms = milliseconds(start, clock.now)
                print("")
                if calls.isEmpty {
                    print("Tool: none (NO_TOOL)")
                } else {
                    for c in calls {
                        print("Tool: \(c.tool) args: \(c.arguments) validation: \(c.validation.label)")
                    }
                }
                print(String(format: "Latency: %.0f ms", ms))
            } catch {
                print("Error: \(error)")
            }
        }
    }
}
