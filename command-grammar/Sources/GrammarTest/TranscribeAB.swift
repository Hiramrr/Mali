import CommandGrammar
// Transcripción A/B sobre los MISMOS WAV. Todo idéntico excepto custom LM.
// A: DictationTranscriber(locale: es_MX, preset: .phrase) + commandContext()
// B: mismo preset + mismos contextualStrings + ContentHint.customizedLanguage
import Foundation
import Speech
import AVFoundation

/// Baseline exacta Fase 7B (no tocar comportamiento).
func transcribeFileBaseline(_ url: URL, locale: Locale) async throws -> (String, Double) {
    try await transcribeFile(url, locale: locale)
}

/// Custom LM: mismo preset .phrase + hint adicional, mismo AnalysisContext.
func transcribeFileCustom(_ url: URL, locale: Locale, lmConfig: SFSpeechLanguageModel.Configuration) async throws -> (String, Double) {
    let t0 = ContinuousClock().now
    var preset = DictationTranscriber.Preset.phrase
    preset.contentHints.insert(.customizedLanguage(modelConfiguration: lmConfig))
    let transcriber = DictationTranscriber(
        locale: locale,
        contentHints: preset.contentHints,
        transcriptionOptions: preset.transcriptionOptions,
        reportingOptions: preset.reportingOptions,
        attributeOptions: preset.attributeOptions
    )
    let file = try AVAudioFile(forReading: url)
    let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [transcriber],
                                            analysisContext: commandContext())
    let collectTask = Task { () -> String in
        var last = ""
        do {
            for try await r in await transcriber.results {
                last = NSAttributedString(r.text).string
            }
        } catch {
            print("DBG stream error (custom): \(error)")
        }
        return last
    }
    try await analyzer.finalizeAndFinishThroughEndOfInput()
    let text = await collectTask.value
    let end = ContinuousClock().now
    let comps = (end - t0).components
    let msD = Double(comps.seconds) * 1000.0 + Double(comps.attoseconds) / 1e15
    return (text, msD)
}
