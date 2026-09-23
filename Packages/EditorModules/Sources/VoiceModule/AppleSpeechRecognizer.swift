import AVFoundation
import CoreMedia
import Foundation
import Speech

/// Reconocimiento local con `SpeechAnalyzer` + `DictationTranscriber`
/// (macOS 26+). Todo el audio se procesa en el dispositivo; Apple documenta
/// que el transcriptor de dictado solo admite modelos locales.
///
/// Adaptado de `SpeechRecognitionService` de LocalFlow
/// (`MiyuWisp/LocalFlow/LocalFlow/Speech/SpeechRecognitionService.swift`).
/// Recorte aplicado: sin WhisperKit, sin historial, sin atajos globales ni
/// inserción por Accesibilidad (el editor inserta vía `EditorCommand`).
/// Los parciales llegan por `onPartial`; el nivel por `onLevel`.
public final class AppleSpeechRecognizer: VoiceSpeechRecognizer, @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var _onPartial: (@Sendable (String) -> Void)?
    private nonisolated(unsafe) var _onLevel: (@Sendable (Float) -> Void)?
    private nonisolated(unsafe) var _finalSegments: [(start: Double, text: String)] = []
    private nonisolated(unsafe) var _volatileText = ""
    private nonisolated(unsafe) var _recognitionError: (any Error)?
    private nonisolated(unsafe) var _speechFrames = 0
    private nonisolated(unsafe) var _peakLevel: Float = 0

    /// Umbral de energía para considerar que hay voz (modo susurro lo baja).
    public var voiceThreshold: Float = 0.08
    /// Idioma del dictado, p. ej. `es-MX`.
    public var localeIdentifier: String = "es-MX"

    public var onPartial: (@Sendable (String) -> Void)? {
        get { lock.withLock { _onPartial } }
        set { lock.withLock { _onPartial = newValue } }
    }

    public var onLevel: (@Sendable (Float) -> Void)? {
        get { lock.withLock { _onLevel } }
        set { lock.withLock { _onLevel = newValue } }
    }

    public var hasSpeech: Bool {
        lock.withLock { _speechFrames > 0 }
    }

    public var liveTranscript: String {
        lock.withLock { Self.combined(finalSegments: _finalSegments, volatile: _volatileText) }
    }

    // La sesión se toca desde el tap del micrófono y desde stop/cancel;
    // AppState serializa los cambios, el tap se retira antes de soltar objetos.
    private final class SessionHolder: @unchecked Sendable {
        var engine: AVAudioEngine?
        var analyzer: SpeechAnalyzer?
        var transcriber: DictationTranscriber?
        var streamContinuation: AsyncStream<AnalyzerInput>.Continuation?
        var resultsTask: Task<Void, Never>?
        var converter: AVAudioConverter?
        var targetFormat: AVAudioFormat?
    }

    private let session = SessionHolder()
    private let sessionLock = NSLock()

    public init(localeIdentifier: String = "es-MX") {
        self.localeIdentifier = localeIdentifier
    }

    // MARK: - Permisos y recursos

    private func failure(_ message: String) -> NSError {
        NSError(domain: "EditorFinal.Voice", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func requestMicrophone() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
    }

    private func requestSpeech() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    @available(macOS 26, *)
    private func supportedLocale() async -> Locale? {
        await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeIdentifier))
    }

    @available(macOS 26, *)
    private func ensureAssets() async throws {
        guard let locale = await supportedLocale() else {
            throw failure("El idioma seleccionado no tiene un modelo local compatible.")
        }
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        for reserved in await AssetInventory.reservedLocales where reserved != locale {
            _ = await AssetInventory.release(reservedLocale: reserved)
        }
        _ = try await AssetInventory.reserve(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw failure("El modelo local no está instalado. Conecta internet para descargarlo y vuelve a intentar.")
        }
    }

    // MARK: - Start / Stop

    public func start() async throws {
        if #available(macOS 26, *) {
            guard await requestMicrophone() else {
                throw failure("Autoriza el micrófono en Ajustes del Sistema > Privacidad y seguridad > Micrófono.")
            }
            guard await requestSpeech() else {
                throw failure("Autoriza Reconocimiento de voz en Ajustes del Sistema > Privacidad y seguridad.")
            }
            do {
                try await start26()
            } catch {
                await cancel()
                throw error
            }
        } else {
            throw failure("El dictado por voz requiere macOS 26 o posterior.")
        }
    }

    @available(macOS 26, *)
    private func start26() async throws {
        stopSessionObjects()
        lock.withLock {
            _finalSegments = []
            _volatileText = ""
            _recognitionError = nil
            _speechFrames = 0
            _peakLevel = 0
        }
        _ = try await ensureAssets()
        guard let locale = await supportedLocale() else { throw failure("Idioma no compatible.") }
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        sessionLock.withLock { session.transcriber = transcriber }

        let bestFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw failure("No hay un micrófono disponible. Revisa la entrada de sonido de macOS.")
        }
        let tapFormat: AVAudioFormat = bestFormat ?? inputFormat
        sessionLock.withLock {
            session.engine = engine
            session.targetFormat = tapFormat
            if let best = bestFormat, best != inputFormat {
                session.converter = AVAudioConverter(from: inputFormat, to: best)
            } else {
                session.converter = nil
            }
        }
        if tapFormat != inputFormat && session.converter == nil {
            throw failure("No se pudo convertir el formato del micrófono.")
        }

        var contRef: AsyncStream<AnalyzerInput>.Continuation!
        // Cola acotada: si el reconocimiento se atrasa, avisa en vez de perder voz en silencio.
        let stream = AsyncStream<AnalyzerInput>(bufferingPolicy: .bufferingOldest(128)) { c in contRef = c }
        sessionLock.withLock { session.streamContinuation = contRef }

        let analyzer = SpeechAnalyzer(inputSequence: stream, modules: [transcriber])
        sessionLock.withLock { session.analyzer = analyzer }

        let resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    let isFinal = result.isFinal
                    let text = String(result.text.characters)
                    let startSec: Double = {
                        let seconds = result.range.start.seconds
                        return seconds.isFinite ? seconds : 0
                    }()
                    self.lock.withLock {
                        if isFinal {
                            _finalSegments.removeAll { abs($0.start - startSec) < 0.05 }
                            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                _finalSegments.append((startSec, text))
                            }
                            _volatileText = ""
                        } else {
                            _volatileText = text
                        }
                    }
                    let display = self.liveTranscript
                    let callback = self.lock.withLock { self._onPartial }
                    callback?(display)
                }
            } catch {
                self.lock.withLock { self._recognitionError = error }
            }
        }
        sessionLock.withLock { session.resultsTask = resultsTask }

        let holder = session
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let level = Self.rmsLevel(from: buffer)
            let threshold = self.lock.withLock { self.voiceThreshold }
            self.lock.withLock {
                if level > threshold { self._speechFrames += 1 }
                self._peakLevel = max(self._peakLevel, level)
            }
            let levelCallback = self.lock.withLock { self._onLevel }
            levelCallback?(level)
            guard let continuation = holder.streamContinuation, let target = holder.targetFormat else { return }
            do {
                let output = try Self.prepareBuffer(buffer, converter: holder.converter, format: target)
                guard output.frameLength > 0 else { return }
                if case .dropped = continuation.yield(AnalyzerInput(buffer: output)) {
                    throw self.failure("El reconocimiento no pudo seguir el ritmo del audio. Intenta un dictado más corto.")
                }
            } catch {
                self.lock.withLock { self._recognitionError = error }
                continuation.finish()
            }
        }
        engine.prepare()
        try engine.start()
    }

    /// Nivel 0…1 a partir de un buffer PCM. La voz normal queda a mitad de
    /// barra y el silencio cerca de 0.
    static func rmsLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return 0 }
        var sum: Double = 0
        var count: Double = 0
        for ch in 0..<channelCount {
            let data = channels[ch]
            for i in 0..<frames {
                let sample = Double(data[i])
                sum += sample * sample
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        let rms = sqrt(sum / count)
        guard rms > 0.00001 else { return 0 }
        let decibels = 20 * log10(rms)
        return Float(min(1, max(0, (decibels + 60) / 60)))
    }

    /// Copia propia de las muestras: AVAudioEngine reutiliza los buffers del tap.
    static func prepareBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter?, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw NSError(domain: "EditorFinal.Voice", code: 2, userInfo: [NSLocalizedDescriptionKey: "No se pudo reservar memoria para el audio."])
        }
        if let converter {
            var supplied = false
            var convertError: NSError?
            let status = converter.convert(to: output, error: &convertError) { _, inputStatus in
                guard !supplied else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                supplied = true
                inputStatus.pointee = .haveData
                return buffer
            }
            if let convertError { throw convertError }
            if status == .error {
                throw NSError(domain: "EditorFinal.Voice", code: 3, userInfo: [NSLocalizedDescriptionKey: "Falló la conversión del audio del micrófono."])
            }
        } else {
            output.frameLength = buffer.frameLength
            let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let destination = UnsafeMutableAudioBufferListPointer(output.mutableAudioBufferList)
            for (src, dst) in zip(source, destination) {
                if let from = src.mData, let to = dst.mData {
                    memcpy(to, from, Int(src.mDataByteSize))
                }
            }
        }
        return output
    }

    public func stop() async throws -> String {
        if #available(macOS 26, *) {
            return try await stop26()
        }
        return liveTranscript
    }

    @available(macOS 26, *)
    private func stop26() async throws -> String {
        sessionLock.withLock { session.engine?.stop() }
        sessionLock.withLock { session.engine?.inputNode.removeTap(onBus: 0) }
        // Terminar la entrada antes de finalizar: el analizador espera el fin.
        sessionLock.withLock { session.streamContinuation?.finish() }
        if let analyzer = sessionLock.withLock({ session.analyzer }) {
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                await analyzer.cancelAndFinishNow()
                let task = sessionLock.withLock { session.resultsTask }
                await task?.value
                stopSessionObjects()
                throw error
            }
        }
        let task = sessionLock.withLock { session.resultsTask }
        _ = await task?.value
        // Se conserva la transcripción para quien la pidió; solo se sueltan motores.
        sessionLock.withLock {
            session.engine = nil
            session.analyzer = nil
            session.transcriber = nil
            session.streamContinuation = nil
            session.resultsTask = nil
            session.converter = nil
        }
        if let error = lock.withLock({ _recognitionError }) { throw error }
        return liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func cancel() async {
        sessionLock.withLock { session.engine?.stop() }
        sessionLock.withLock { session.engine?.inputNode.removeTap(onBus: 0) }
        sessionLock.withLock { session.streamContinuation?.finish() }
        if let analyzer = sessionLock.withLock({ session.analyzer }) {
            await analyzer.cancelAndFinishNow()
        }
        let task = sessionLock.withLock { session.resultsTask }
        task?.cancel()
        await task?.value
        stopSessionObjects()
        lock.withLock {
            _finalSegments = []
            _volatileText = ""
            _recognitionError = nil
        }
    }

    private func stopSessionObjects() {
        sessionLock.withLock {
            session.engine?.stop()
            session.engine?.inputNode.removeTap(onBus: 0)
            session.engine = nil
            session.analyzer = nil
            session.transcriber = nil
            session.streamContinuation?.finish()
            session.streamContinuation = nil
            session.resultsTask?.cancel()
            session.resultsTask = nil
            session.converter = nil
        }
    }

    private static func combined(finalSegments: [(start: Double, text: String)], volatile: String) -> String {
        let final = finalSegments.sorted { $0.start < $1.start }.map(\.text).joined(separator: " ")
        if volatile.isEmpty { return final }
        return final.isEmpty ? volatile : final + " " + volatile
    }
}
