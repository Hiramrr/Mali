// Fase B: micrófono → wav → SpeechAnalyzer → parseCommand. Sin executor.
import Foundation
import Speech
import AVFoundation

struct LiveResult {
    let expectedSpoken: String
    let raw: String
    let normalized: String
    let parsed: ParsedCommand
    let sttMs: Double
    let parseMs: Double
}

func commandContext() -> AnalysisContext {
    var ac = AnalysisContext()
    ac.contextualStrings = [.general: [
        "borra", "elimina", "quita", "suprime", "tacha", "corta", "descarta",
        "reemplaza", "sustituye", "cambia", "troca", "escribe",
        "reescribe", "reformula", "hazlo", "haz",
        "negritas", "negrita", "cursivas", "cursiva", "subraya", "subrayado",
        "título", "titulo", "encabezado", "nombre", "portada",
        "deshaz", "rehaz", "anula", "cancela", "revierte", "restaura",
        "vuelve", "regresa", "repite", "reaplica",
        "selecciona", "marca", "elige", "toma", "aparta", "señala",
        "busca", "encuentra", "localiza", "halla", "rastrea",
        "guarda", "guardalo", "archiva", "consigna", "abre", "ábrelo",
        "exporta", "saca", "genera", "convierte", "produce",
        "párrafo", "palabra", "frase", "oración", "selección", "documento",
        "Metodología", "TDAH", "IHC", "accesibilidad", "Claridad",
        "pdf", "Word", "texto plano", "cursivas", "negritas",
        "esto", "eso", "ponlo", "hazlo", "cámbialo",
    ]]
    return ac
}

func transcribeFile(_ url: URL, locale: Locale) async throws -> (String, Double) {
    let t0 = ContinuousClock().now
    let transcriber = DictationTranscriber(locale: locale, preset: .phrase)
    let file = try AVAudioFile(forReading: url)
    let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [transcriber],
                                        analysisContext: commandContext())
    let collectTask = Task { () -> String in
        var last = ""
        var n = 0
        do {
            for try await r in await transcriber.results {
                n += 1
                last = NSAttributedString(r.text).string
            }
        } catch {
            print("DBG stream error: \(error)")
        }
        _ = n
        return last
    }
    try await analyzer.finalizeAndFinishThroughEndOfInput()
    let text = await collectTask.value
    let end = ContinuousClock().now
    let comps = (end - t0).components
    let msD = Double(comps.seconds) * 1000.0 + Double(comps.attoseconds) / 1e15
    return (text, msD)
}

func recordMic(to url: URL) async throws {
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    input.installTap(onBus: 0, bufferSize: 4096, format: format) { buf, _ in
        try? file.write(from: buf)
    }
    try engine.start()
    print("Hablando... (Enter para terminar)")
    _ = readLine()
    engine.stop()
    input.removeTap(onBus: 0)
}
