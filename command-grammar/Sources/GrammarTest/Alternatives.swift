// Fase Alternatives+Confidence: CUSTOM LM + alternatives + confidence.
// NO toca Grammar/Types/contextualStrings/LM/weight/preset/locale/audios/protocolo.
// Config: mismo preset .phrase + custom hint + .alternativeTranscriptions
// + .transcriptionConfidence, mismo AnalysisContext, mismos 180 WAVs.
import Foundation
import Speech
import AVFoundation

struct AlternativeHypothesis {
    let transcript: String
    let confidence: Double?
}

struct AlternativesResult {
    let top1: String
    let top1Confidence: Double?
    let alternatives: [AlternativeHypothesis] // en orden de Speech, SIN reordenar
    let sttMs: Double
}

/// Confidence de un AttributedString: media de los runs con atributo
/// transcriptionConfidence, si existe; nil si la API no lo proporciona.
func confidenceOf(_ s: AttributedString) -> Double? {
    var vals: [Double] = []
    for run in s.runs {
        if let c = run.transcriptionConfidence {
            vals.append(c)
        }
    }
    guard !vals.isEmpty else { return nil }
    return vals.reduce(0, +) / Double(vals.count)
}

func transcribeFileAlternatives(_ url: URL, locale: Locale, lmConfig: SFSpeechLanguageModel.Configuration) async throws -> AlternativesResult {
    let t0 = ContinuousClock().now
    var preset = DictationTranscriber.Preset.phrase
    preset.contentHints.insert(.customizedLanguage(modelConfiguration: lmConfig))
    preset.reportingOptions.insert(.alternativeTranscriptions)
    preset.attributeOptions.insert(.transcriptionConfidence)
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
    let collectTask = Task { () -> (AttributedString, [AttributedString]) in
        var lastTop = AttributedString("")
        var lastAlts: [AttributedString] = []
        do {
            for try await r in await transcriber.results {
                lastTop = r.text
                lastAlts = r.alternatives
            }
        } catch {
            print("DBG alternatives stream error: \(error)")
        }
        return (lastTop, lastAlts)
    }
    try await analyzer.finalizeAndFinishThroughEndOfInput()
    let (lastTop, lastAlts) = await collectTask.value
    let end = ContinuousClock().now
    let comps = (end - t0).components
    let msD = Double(comps.seconds) * 1000.0 + Double(comps.attoseconds) / 1e15
    let top1Str = NSAttributedString(lastTop).string
    let top1Conf = confidenceOf(lastTop)
    let alts = lastAlts.map { a in
        AlternativeHypothesis(transcript: NSAttributedString(a).string, confidence: confidenceOf(a))
    }
    return AlternativesResult(top1: top1Str, top1Confidence: top1Conf, alternatives: alts, sttMs: msD)
}

/// Transcriber custom Fase 8 SIN flags extra (para diagnóstico comparativo).
func makeCustomTranscriberNoFlags() async throws -> DictationTranscriber {
    let cfg = try loadCustomLMConfiguration()
    let locale = Locale(identifier: "es_MX")
    var preset = DictationTranscriber.Preset.phrase
    preset.contentHints.insert(.customizedLanguage(modelConfiguration: cfg))
    return DictationTranscriber(
        locale: locale,
        contentHints: preset.contentHints,
        transcriptionOptions: preset.transcriptionOptions,
        reportingOptions: preset.reportingOptions,
        attributeOptions: preset.attributeOptions
    )
}

// MARK: - Smoke (un archivo, imprime top1 + alternativas con confidence y parse)

func runAltsSmoke(path: String) async {
    let url = URL(fileURLWithPath: path)
    let locale = Locale(identifier: "es_MX")
    do {
        let cfg = try loadCustomLMConfiguration()
        // Diagnóstico: todos los segmentos del stream
        var preset = DictationTranscriber.Preset.phrase
        preset.contentHints.insert(.customizedLanguage(modelConfiguration: cfg))
        preset.reportingOptions.insert(.alternativeTranscriptions)
        preset.attributeOptions.insert(.transcriptionConfidence)
        let tr = DictationTranscriber(
            locale: locale,
            contentHints: preset.contentHints,
            transcriptionOptions: preset.transcriptionOptions,
            reportingOptions: preset.reportingOptions,
            attributeOptions: preset.attributeOptions
        )
        let file = try AVAudioFile(forReading: url)
        let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [tr],
                                                analysisContext: commandContext())
        let collectTask = Task { () -> [(String, [String], String)] in
            var segs: [(String, [String], String)] = []
            do {
                for try await r in await tr.results {
                    segs.append((NSAttributedString(r.text).string,
                                 r.alternatives.map { NSAttributedString($0).string },
                                 "\(r.range) fin=\(r.resultsFinalizationTime)"))
                }
            } catch {
                print("DBG smoke stream error: \(error)")
            }
            return segs
        }
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let segs = await collectTask.value
        print("segments=\(segs.count)")
        for (i, s) in segs.enumerated() {
            print("SEG\(i): top=[\(s.0)] alts=\(s.1) range=\(s.2)")
        }
        // Comparación: misma config Fase 8 (custom, sin flags extra)
        let tr2 = try await makeCustomTranscriberNoFlags()
        let file2 = try AVAudioFile(forReading: url)
        let analyzer2 = try await SpeechAnalyzer(inputAudioFile: file2, modules: [tr2],
                                                 analysisContext: commandContext())
        let collect2 = Task { () -> [String] in
            var ss: [String] = []
            do {
                for try await r in await tr2.results {
                    ss.append(NSAttributedString(r.text).string)
                }
            } catch {
                print("DBG smoke2 error: \(error)")
            }
            return ss
        }
        try await analyzer2.finalizeAndFinishThroughEndOfInput()
        let segs2 = await collect2.value
        print("fase8-config segments=\(segs2.count)")
        for (i, s) in segs2.enumerated() { print("F8-SEG\(i): [\(s)]") }
        let r = try await transcribeFileAlternatives(url, locale: locale, lmConfig: cfg)
        print("TOP1: [\(r.top1)] conf=\(r.top1Confidence.map { String(format: "%.3f", $0) } ?? "nil") -> \(parseCommand(raw: r.top1)) (\(String(format: "%.0f", r.sttMs)) ms)")
        print("alternatives count=\(r.alternatives.count)")
        for (i, a) in r.alternatives.enumerated() {
            print("ALT\(i + 1): [\(a.transcript)] conf=\(a.confidence.map { String(format: "%.3f", $0) } ?? "nil") -> \(parseCommand(raw: a.transcript))")
        }
    } catch {
        print("alts-smoke error: \(error)")
    }
}
