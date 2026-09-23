// Prueba aislada de Foundation Models como clasificador de intención.
// DICTATION / COMMAND / AMBIGUOUS con guided generation (@Generable).
// Sin heurísticas de strings, sin tool calling, sin modificar documentos.

import Foundation
import FoundationModels

// MARK: - Salida estructurada (guided generation, sin parseo de strings)

@Generable
enum Intent {
    case dictation
    case command
    case ambiguous
}

@Generable
struct IntentResult {
    var intent: Intent
}

extension Intent {
    var label: String {
        switch self {
        case .dictation: "DICTATION"
        case .command: "COMMAND"
        case .ambiguous: "AMBIGUOUS"
        }
    }
}

// MARK: - Contexto del editor

struct EditorContext: Sendable {
    let currentTitle: String
    let selectedText: String?
}

// MARK: - Casos de prueba

struct IntentTest: Sendable {
    let id: Int
    let group: String
    let context: EditorContext
    let voice: String
    let expected: Intent
}

let title = "Introducción"
func ctx(_ selected: String? = nil) -> EditorContext {
    EditorContext(currentTitle: title, selectedText: selected)
}

let selectionTDHA = "Las personas con TDAH tienen problemas para escribir."

let tests: [IntentTest] = [
    // Grupo A — Dictado evidente
    IntentTest(id: 1, group: "A", context: ctx(), voice: "La interacción humano computadora estudia la relación entre las personas y los sistemas interactivos.", expected: .dictation),
    IntentTest(id: 2, group: "A", context: ctx(), voice: "Durante los últimos años se han desarrollado nuevas interfaces multimodales.", expected: .dictation),
    IntentTest(id: 3, group: "A", context: ctx(), voice: "Mi proyecto busca diseñar un editor de texto para personas con TDAH.", expected: .dictation),
    IntentTest(id: 4, group: "A", context: ctx(), voice: "Las personas pueden experimentar dificultades durante tareas prolongadas de escritura.", expected: .dictation),

    // Grupo B — Dictado con vocabulario de comandos
    IntentTest(id: 5, group: "B", context: ctx(), voice: "El editor permite cambiar el título del documento.", expected: .dictation),
    IntentTest(id: 6, group: "B", context: ctx(), voice: "La función deshacer permite recuperar el contenido anterior.", expected: .dictation),
    IntentTest(id: 7, group: "B", context: ctx(), voice: "El usuario puede borrar una oración utilizando el teclado.", expected: .dictation),
    IntentTest(id: 8, group: "B", context: ctx(), voice: "Una interfaz accesible permite seleccionar diferentes elementos.", expected: .dictation),
    IntentTest(id: 9, group: "B", context: ctx(), voice: "El sistema puede reemplazar automáticamente algunas palabras.", expected: .dictation),
    IntentTest(id: 10, group: "B", context: ctx(), voice: "En la siguiente sección se explica cómo cambiar el formato del texto.", expected: .dictation),
    IntentTest(id: 11, group: "B", context: ctx(), voice: "Los usuarios pueden poner palabras en negritas para resaltarlas.", expected: .dictation),
    IntentTest(id: 12, group: "B", context: ctx(), voice: "El comando borrar elimina el contenido seleccionado.", expected: .dictation),

    // Grupo C — Comandos explícitos sin selección
    IntentTest(id: 13, group: "C", context: ctx(), voice: "Cambia el título a Metodología.", expected: .command),
    IntentTest(id: 14, group: "C", context: ctx(), voice: "Pon como título Arquitectura del sistema.", expected: .command),
    IntentTest(id: 15, group: "C", context: ctx(), voice: "Deshaz el último cambio.", expected: .command),
    IntentTest(id: 16, group: "C", context: ctx(), voice: "Rehaz el cambio anterior.", expected: .command),

    // Grupo C — Comandos explícitos con selección
    IntentTest(id: 17, group: "C", context: ctx(selectionTDHA), voice: "Borra esto.", expected: .command),
    IntentTest(id: 18, group: "C", context: ctx(selectionTDHA), voice: "Ponlo en negritas.", expected: .command),
    IntentTest(id: 19, group: "C", context: ctx(selectionTDHA), voice: "Hazlo menos absoluto.", expected: .command),
    IntentTest(id: 20, group: "C", context: ctx(selectionTDHA), voice: "Hazlo más corto.", expected: .command),
    IntentTest(id: 21, group: "C", context: ctx("problemas"), voice: "Cambia esta palabra por dificultades.", expected: .command),

    // Grupo D — Dependencia del contexto
    IntentTest(id: 22, group: "D", context: ctx("Esta oración es demasiado larga y contiene información innecesaria."), voice: "Hazlo más corto.", expected: .command),
    IntentTest(id: 23, group: "D", context: ctx(), voice: "Hazlo más corto.", expected: .ambiguous),
    IntentTest(id: 24, group: "D", context: ctx("texto seleccionado"), voice: "Pon esto en negritas.", expected: .command),
    IntentTest(id: 25, group: "D", context: ctx(), voice: "Pon esto en negritas.", expected: .ambiguous),
    IntentTest(id: 26, group: "D", context: ctx("texto seleccionado"), voice: "Borra esto.", expected: .command),
    IntentTest(id: 27, group: "D", context: ctx(), voice: "Borra esto.", expected: .ambiguous),

    // Grupo E — Ambigüedad real (sin contexto suficiente)
    IntentTest(id: 28, group: "E", context: ctx(), voice: "Cámbialo.", expected: .ambiguous),
    IntentTest(id: 29, group: "E", context: ctx(), voice: "Pon eso.", expected: .ambiguous),
    IntentTest(id: 30, group: "E", context: ctx(), voice: "Eso no.", expected: .ambiguous),
    IntentTest(id: 31, group: "E", context: ctx(), voice: "Mejor.", expected: .ambiguous),
    IntentTest(id: 32, group: "E", context: ctx(), voice: "Hazlo diferente.", expected: .ambiguous),
    IntentTest(id: 33, group: "E", context: ctx(), voice: "Cambia esa parte.", expected: .ambiguous),
    IntentTest(id: 34, group: "E", context: ctx(), voice: "No me gusta.", expected: .ambiguous),
    IntentTest(id: 35, group: "E", context: ctx(), voice: "Ese.", expected: .ambiguous),

    // Grupo F — Adversariales
    IntentTest(id: 36, group: "F", context: ctx(), voice: "Es importante cambiar la manera en que diseñamos interfaces.", expected: .dictation),
    IntentTest(id: 37, group: "F", context: ctx(), voice: "Borrar información accidentalmente puede afectar la experiencia del usuario.", expected: .dictation),
    IntentTest(id: 38, group: "F", context: ctx(), voice: "El título debe comunicar claramente el objetivo del proyecto.", expected: .dictation),
    IntentTest(id: 39, group: "F", context: ctx(), voice: "Seleccionar correctamente los participantes es importante para el estudio.", expected: .dictation),
    IntentTest(id: 40, group: "F", context: ctx(), voice: "Deshacer una acción debería ser sencillo para el usuario.", expected: .dictation),
    IntentTest(id: 41, group: "F", context: ctx(), voice: "Ahora cambia el título a Resultados.", expected: .command),
    IntentTest(id: 42, group: "F", context: ctx(selectionTDHA), voice: "Ahora borra el texto seleccionado.", expected: .command),
    IntentTest(id: 43, group: "F", context: ctx(), voice: "Quiero escribir que el editor puede cambiar automáticamente el título.", expected: .dictation),
]

// Instrucciones: breves, neutrales, categorías explicadas una sola vez.
// Estrategia anti-contaminación: una LanguageModelSession nueva por caso.
let sessionInstructions = """
Clasifica lo que dice el usuario en un editor de texto. Responde con una de estas tres intenciones.
DICTATION: el usuario está dictando contenido para escribirlo en el documento, no pide ninguna acción.
COMMAND: el usuario pide una acción explícita y ejecutable con el contexto disponible del editor, sin necesidad de adivinar nada.
AMBIGUOUS: hay una posible intención de editar, pero falta información esencial para ejecutar una acción con seguridad.
"""

func userPrompt(context: EditorContext, voice: String) -> String {
    """
    CURRENT TITLE:
    \(context.currentTitle)

    SELECTED TEXT:
    \(context.selectedText ?? "none")

    USER SAID:
    \(voice)
    """
}

// MARK: - Medición

func milliseconds(_ start: ContinuousClock.Instant, _ end: ContinuousClock.Instant) -> Double {
    let d = end - start
    let c = d.components
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

// MARK: - Resultado de un caso

struct CaseOutcome: Sendable {
    let test: IntentTest
    let predicted: Intent?
    let latencyMs: Double
    let error: String?
}

// MARK: - App

@main
struct FMIntentTest {
    static func main() async {
        let model = SystemLanguageModel.default

        await printModelInfo(model: model)

        switch model.availability {
        case .available:
            print("Availability: available")
        case .unavailable(let reason):
            print("Availability: unavailable (\(reason))")
            print("La prueba se detiene: el modelo no está disponible y no se sustituirá por otro.")
            return
        }
        print("")

        var outcomes: [CaseOutcome] = []
        let clock = ContinuousClock()

        for test in tests {
            // Sesión nueva por caso: ninguna prueba influye en la siguiente.
            let session = LanguageModelSession(model: model, instructions: sessionInstructions)
            let prompt = userPrompt(context: test.context, voice: test.voice)
            let start = clock.now
            do {
                let response = try await session.respond(to: prompt, generating: IntentResult.self)
                let end = clock.now
                let ms = milliseconds(start, end)
                let predicted = response.content.intent
                let ok = predicted.label == test.expected.label
                outcomes.append(CaseOutcome(test: test, predicted: predicted, latencyMs: ms, error: nil))
                printCase(test: test, predicted: predicted.label, latencyMs: ms, ok: ok, error: nil)
            } catch {
                let end = clock.now
                let ms = milliseconds(start, end)
                outcomes.append(CaseOutcome(test: test, predicted: nil, latencyMs: ms, error: "\(error)"))
                printCase(test: test, predicted: "ERROR", latencyMs: ms, ok: false, error: "\(error)")
            }
        }

        printSummary(outcomes: outcomes)
        await runInteractive(model: model)
    }

    static func printModelInfo(model: SystemLanguageModel) async {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "unknown"
        #endif
        let locale = Locale.current
        print("Foundation Models availability: \(model.availability)")
        print("OS version: \(os)")
        print("Architecture: \(arch)")
        print("Locale: \(locale.identifier)")
        let langs = model.supportedLanguages.map(\.minimalIdentifier).sorted()
        print("Supported languages (\(langs.count)): \(langs.joined(separator: ", "))")
        let spanishSupported = model.supportedLanguages.contains {
            $0.minimalIdentifier.hasPrefix("es")
        }
        print("Spanish supported: \(spanishSupported)")
        for code in ["es", "es-MX", "es-ES"] {
            let ok = model.supportsLocale(Locale(identifier: code))
            print("supportsLocale(\(code)): \(ok)")
        }
    }

    static func printCase(test: IntentTest, predicted: String, latencyMs: Double, ok: Bool, error: String?) {
        print("--------------------------------------------------")
        print("TEST \(test.id) [grupo \(test.group)]")
        print("")
        print("SELECTED TEXT:")
        print(test.context.selectedText ?? "none")
        print("")
        print("VOICE:")
        print(test.voice)
        print("")
        print("EXPECTED:")
        print(test.expected.label)
        print("")
        print("PREDICTED:")
        print(predicted)
        if let error {
            print("ERROR: \(error)")
        }
        print("")
        print("LATENCY:")
        print(String(format: "%.0f ms", latencyMs))
        print("")
        print(ok ? "✓ CORRECT" : "✗ INCORRECT")
        print("--------------------------------------------------")
    }

    static func printSummary(outcomes: [CaseOutcome]) {
        let total = outcomes.count
        let correct = outcomes.filter { $0.predicted?.label == $0.test.expected.label }.count

        func rate(expected: Intent) -> (ok: Int, n: Int) {
            let subset = outcomes.filter { $0.test.expected.label == expected.label }
            let ok = subset.filter { $0.predicted?.label == expected.label }.count
            return (ok, subset.count)
        }
        let d = rate(expected: .dictation)
        let c = rate(expected: .command)
        let a = rate(expected: .ambiguous)

        let falseCommands = outcomes.filter {
            $0.test.expected.label != Intent.command.label && $0.predicted?.label == Intent.command.label
        }
        let nonCommands = outcomes.filter { $0.test.expected.label != Intent.command.label }.count
        let missedCommands = outcomes.filter {
            $0.test.expected.label == Intent.command.label && $0.predicted?.label != Intent.command.label
        }
        let totalCommands = outcomes.filter { $0.test.expected.label == Intent.command.label }.count

        // Cold start = primera inferencia; estadísticas sobre el resto.
        let latencies = outcomes.map(\.latencyMs)
        let coldStart = latencies.first ?? 0
        let steady = Array(latencies.dropFirst()).sorted()
        let mean = steady.isEmpty ? 0 : steady.reduce(0, +) / Double(steady.count)
        let median = steady.isEmpty ? 0 : percentile(steady, 0.5)

        print("")
        print("========================================")
        print("FOUNDATION MODELS INTENT TEST")
        print("========================================")
        print("")
        print(String(format: "Total:                 %d", total))
        print(String(format: "Correct:               %d", correct))
        print(String(format: "Accuracy:              %.1f%%", total > 0 ? 100.0 * Double(correct) / Double(total) : 0))
        print("")
        print(String(format: "DICTATION:             %d/%d", d.ok, d.n))
        print(String(format: "COMMAND:               %d/%d", c.ok, c.n))
        print(String(format: "AMBIGUOUS:             %d/%d", a.ok, a.n))
        print("")
        print(String(format: "False commands:         %d", falseCommands.count))
        print(String(format: "False Command Rate:   %.1f%%", nonCommands > 0 ? 100.0 * Double(falseCommands.count) / Double(nonCommands) : 0))
        print("")
        print(String(format: "Missed commands:        %d", missedCommands.count))
        print(String(format: "Missed Command Rate:  %.1f%%", totalCommands > 0 ? 100.0 * Double(missedCommands.count) / Double(totalCommands) : 0))
        print("")
        print("Latency")
        print(String(format: "Cold start:           %.0f ms", coldStart))
        print(String(format: "Mean:                 %.0f ms", mean))
        print(String(format: "Median:               %.0f ms", median))
        print(String(format: "P95:                  %.0f ms", steady.isEmpty ? 0 : percentile(steady, 0.95)))
        print(String(format: "Min:                   %.0f ms", steady.first ?? 0))
        print(String(format: "Max:                   %.0f ms", steady.last ?? 0))
        print("")

        // Matriz de confusión: filas = esperado, columnas = predicho.
        let labels: [Intent] = [.dictation, .command, .ambiguous]
        print("Confusion matrix (rows=expected, cols=predicted D/C/A/err)")
        for exp in labels {
            var row: [String] = []
            for pred in labels {
                let n = outcomes.filter {
                    $0.test.expected.label == exp.label && $0.predicted?.label == pred.label
                }.count
                row.append("\(n)")
            }
            let errs = outcomes.filter { $0.test.expected.label == exp.label && $0.predicted == nil }.count
            print("\(exp.label): " + row.joined(separator: " / ") + " / \(errs)")
        }
        print("")

        let failures = outcomes.filter { $0.predicted?.label != $0.test.expected.label }
        if failures.isEmpty {
            print("Fallos: ninguno")
        } else {
            print("Fallos (\(failures.count)):")
            for f in failures {
                print("--- TEST \(f.test.id) [grupo \(f.test.group)]")
                print("input: \(f.test.voice)")
                print("context: title=\(f.test.context.currentTitle) selected=\(f.test.context.selectedText ?? "none")")
                print("expected: \(f.test.expected.label)")
                print("predicted: \(f.predicted?.label ?? "ERROR \(f.error ?? "")")")
            }
        }
    }

    static func runInteractive(model: SystemLanguageModel) async {
        print("")
        print("Prueba interactiva. Escribe 'exit' en Voice para salir.")
        let clock = ContinuousClock()
        while true {
            print("")
            print("Selected text (vacío = none):")
            guard let sel = readLine() else { break }
            print("Voice:")
            guard let voice = readLine(), !voice.isEmpty else { continue }
            if voice.lowercased() == "exit" { break }
            let context = EditorContext(
                currentTitle: title,
                selectedText: sel.isEmpty ? nil : sel
            )
            let session = LanguageModelSession(model: model, instructions: sessionInstructions)
            let start = clock.now
            do {
                let response = try await session.respond(
                    to: userPrompt(context: context, voice: voice),
                    generating: IntentResult.self
                )
                let ms = milliseconds(start, clock.now)
                print("")
                print("Intent: \(response.content.intent.label)")
                print(String(format: "Latency: %.0f ms", ms))
            } catch {
                print("Error: \(error)")
            }
        }
    }
}
