import CommandGrammar
import EditorCore
import Foundation
import ModuleKit
import OSLog

/// Estado visible del dictado. Nunca se registra el texto dictado en el log.
public enum VoiceState: Sendable, Equatable {
    case idle
    case listening
    case processing
    case failed(String)
}

public struct PendingVoiceAction: Equatable, Sendable {
    public let transcript: String
    public let intent: VoiceIntent
    public let preview: String

    public var isDictation: Bool {
        if case .dictation = intent { return true }
        return false
    }
}

// MARK: - Pieza Lego: Voz
//
// Para QUITAR la voz del programa:
//   1. Borra el bloque "Pieza Lego: Voz" de `App/EditorApp.swift`.
//   2. Quita `VoiceModule` (y `ModuleKit` si nada más lo usa) de
//      `EditorFinal.xcodeproj` y de `Package.swift`.
//   3. Listo: `EditorScreen` compila igual con `voicePanel == nil` y muestra
//      "Módulo no disponible" en Ajustes > Voz.
//
// Para PONERLA de nuevo basta revertir esos pasos: el motor de texto no se toca.

/// Dictado local estilo Wispr Flow como pieza extraíble.
///
/// Flujo: micrófono → reconocedor → dictado o comando → propuesta si cambia
/// estado → `EditorCommandBus` → `EditorSession`.
///
/// El módulo nunca toca `NSTextView`: si el editor está en lectura, sus
/// comandos se ignoran solos (`EditorSession.send` no escribe en lectura).
/// Deshacer usa el `UndoManager` del editor: "borra eso" equivale a undo.
@MainActor @Observable
public final class VoiceModule: EditorInputModule {
    public nonisolated let identifier = "voice.dictation"
    public nonisolated let displayName = "Voz"

    public static var descriptor: ModuleDescriptor {
        ModuleDescriptor(identifier: "voice.dictation", displayName: "Voz")
    }

    public private(set) var state: VoiceState = .idle
    public private(set) var microphoneReady = false
    /// Último parcial del reconocedor, para mostrar mientras se dicta.
    public private(set) var partialTranscript = ""
    /// Nivel de entrada 0…1 para la barra del HUD.
    public private(set) var inputLevel: Float = 0
    /// Último texto insertado (para confirmar sin reabrir el documento).
    public private(set) var lastInsertedText = ""
    /// La transcripción cruda acompaña al resultado para detectar errores de voz.
    public private(set) var lastTranscript = ""
    public private(set) var pendingAction: PendingVoiceAction?
    /// El editor aporta la selección y conserva la propuesta hasta decidir.
    public var prepareRewrite: (@MainActor (String) async -> String?)?
    public var acceptRewrite: (@MainActor () -> Bool)?
    public var discardRewrite: (@MainActor () -> Void)?
    public var pendingDictationText: String? {
        guard case .dictation(let text) = pendingAction?.intent else { return nil }
        return text
    }
    /// Qué hizo el último comando ("Guardado", "Título: X"…).
    public private(set) var lastCommandFeedback = ""
    /// Escucha continua: un toque inicia; cada pausa procesa un enunciado y
    /// vuelve a escuchar, incluso si hay una propuesta por confirmar.
    public var continuousListening = true
    public private(set) var handsFreeActive = false
    /// Push-to-talk con `⌥Espacio`: mantener habla, soltar cierra. Comparte el
    /// mismo `process` que el modo por toques, así los comandos
    /// ("guarda", "busca…", "cambia el título a…") siguen funcionando.
    public var pushToTalkEnabled = true {
        didSet {
            UserDefaults.standard.set(pushToTalkEnabled, forKey: Self.pushToTalkDefaultsKey)
            pushToTalk?.isEnabled = pushToTalkEnabled
        }
    }
    /// Hay una pulsación de push-to-talk en curso (para el HUD y para
    /// suspender el cierre automático mientras se mantiene la tecla).
    public private(set) var pushToTalkHeld = false
    private var pushToTalk: VoicePushToTalk?
    private static let pushToTalkDefaultsKey = "voice.pushToTalkEnabled"
    /// Pausa (s) sin cambios en el parcial para cerrar el enunciado solo.
    public var autoEndpointSilence: TimeInterval = 1.6
    private var monitorTask: Task<Void, Never>?
    private var startTask: Task<Void, Error>?
    private var voicePreviewStarted = false
    private var recognitionGeneration = 0
    private var lastSeenPartial = ""
    private var lastPartialChange = Date()
    /// Idioma del dictado (`es-MX`, `es-ES`, `en-US`).
    public var localeIdentifier = "es-MX" {
        didSet {
            if let apple = recognizer as? AppleSpeechRecognizer {
                apple.localeIdentifier = localeIdentifier
            }
        }
    }
    /// Estilo formal: mayúscula inicial y punto final (recomendado en documentos).
    public var formalStyle = true

    private let recognizer: any VoiceSpeechRecognizer
    private let parser = VoiceCommandParser()
    private let cleaner = DictationCleaner()
    private var context: EditorModuleContext?
    private let logger = Logger(subsystem: "com.hiram.EditorFinal", category: "voice")

    /// - Parameter recognizer: en producción se omite (usa el de Apple);
    ///   en pruebas se inyecta un doble sin micrófono.
    public init(recognizer: (any VoiceSpeechRecognizer)? = nil, localeIdentifier: String = "es-MX") {
        self.localeIdentifier = localeIdentifier
        self.pushToTalkEnabled = UserDefaults.standard.object(forKey: Self.pushToTalkDefaultsKey) as? Bool ?? true
        if let recognizer {
            self.recognizer = recognizer
        } else {
            self.recognizer = AppleSpeechRecognizer(localeIdentifier: localeIdentifier)
        }
    }

    // MARK: - EditorInputModule (ciclo de vida)

    public func start(context: EditorModuleContext) async throws {
        self.context = context
    }

    public func stop() async {
        disablePushToTalk()
        stopMonitor()
        recognitionGeneration += 1
        discardRewrite?()
        handsFreeActive = false
        microphoneReady = false
        pushToTalkHeld = false
        recognizer.onPartial = nil
        recognizer.onLevel = nil
        _ = try? await startTask?.value
        stopMonitor()
        await recognizer.cancel()
        await cancelLivePreview()
        context = nil
        state = .idle
        partialTranscript = ""
        pendingAction = nil
    }

    // MARK: - Dictado (pulsar para hablar)

    public var isListening: Bool {
        if case .listening = state { return true }
        return false
    }

    /// Alterna dictado: empieza si está en reposo, termina si escucha.
    public func toggle() async {
        if pendingAction != nil && isListening {
            await cancelDictation()
        } else if isListening {
            await finish()
        } else if state == .processing {
            handsFreeActive = false
        } else {
            handsFreeActive = continuousListening
            await begin()
        }
    }

    /// Abre el micrófono. Pide permiso de micrófono y voz solo aquí,
    /// nunca al arrancar el editor. Arranca el monitor de cierre automático.
    public func begin() async {
        guard state == .idle || isFailed,
              pendingAction == nil || handsFreeActive else { return }
        state = .listening
        microphoneReady = false
        partialTranscript = ""
        inputLevel = 0
        recognitionGeneration += 1
        let generation = recognitionGeneration
        recognizer.onPartial = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self, self.isListening, self.recognitionGeneration == generation else { return }
                self.partialTranscript = text
                if self.voicePreviewStarted {
                    await self.context?.commandBus.send(.showVoicePreview(text))
                }
            }
        }
        recognizer.onLevel = { [weak self] level in
            Task { @MainActor [weak self] in
                guard let self, self.recognitionGeneration == generation else { return }
                self.inputLevel = level
            }
        }
        let bus = context?.commandBus
        let showsPreview = handsFreeActive && pendingAction == nil
        voicePreviewStarted = showsPreview
        let task = Task {
            if showsPreview { await bus?.send(.beginVoicePreview) }
            try await recognizer.start()
        }
        startTask = task
        do {
            try await task.value
            if isListening {
                microphoneReady = true
                startMonitor()
            }
        } catch {
            await cancelLivePreview()
            handsFreeActive = false
            microphoneReady = false
            state = .failed(error.localizedDescription)
            logger.error("Voice begin failed")
        }
        startTask = nil
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    /// Cierra el micrófono y procesa el texto. Una mutación espera confirmación.
    /// Uso manual (botón "Terminar" o segundo toque): no rearma.
    public func finish() async {
        let commitDictation = handsFreeActive
        handsFreeActive = false
        await stopAndEmit(commitDictation: commitDictation)
    }

    /// Cierre automático por pausa. Conserva la escucha para responder a la propuesta.
    func autoFinish() async {
        await stopAndEmit(commitDictation: true)
        if continuousListening, handsFreeActive, state == .idle {
            await begin()
        } else {
            handsFreeActive = false
        }
    }

    /// Escucha la respuesta a una propuesta con o sin Manos libres.
    public func listenForPendingDecision() async {
        guard pendingAction != nil, !isListening else { return }
        handsFreeActive = true
        await begin()
    }

    // MARK: - Push-to-talk (`⌥Espacio`: mantener para hablar, soltar para cerrar)

    /// ¿Puede empezar una pulsación ahora? Síncrono para el monitor de teclas.
    var canBeginPushToTalk: Bool {
        pushToTalkEnabled && !pushToTalkHeld && (state == .idle || isFailed) && pendingAction == nil
    }

    /// Instala el hotkey global/local. La app real lo llama una vez tras
    /// `start`; las pruebas no lo llaman (sin monitores de teclas).
    public func enablePushToTalk() {
        if let existing = pushToTalk {
            existing.isEnabled = pushToTalkEnabled
            return
        }
        let monitor = VoicePushToTalk(
            onPress: { [weak self] in Task { @MainActor [weak self] in _ = self?.handlePushToTalkPress() } },
            onRelease: { [weak self] in Task { @MainActor [weak self] in self?.handlePushToTalkRelease() } }
        )
        monitor.isEnabled = pushToTalkEnabled
        monitor.start()
        pushToTalk = monitor
    }

    public func disablePushToTalk() {
        pushToTalk?.stop()
        pushToTalk = nil
    }

    /// Entrada del hotkey (síncrona): reserva `held` y arranca el micrófono en
    /// segundo plano. Devuelve si se consumió la pulsación.
    @discardableResult
    func handlePushToTalkPress() -> Bool {
        guard canBeginPushToTalk else { return false }
        pushToTalkHeld = true
        Task {
            await self.begin()
            if !self.isListening { self.pushToTalkHeld = false }
        }
        return true
    }

    /// Soltada del hotkey: cierra el enunciado por el camino normal
    /// (`stopAndEmit` → `process`), así dictado y comandos se conservan.
    func handlePushToTalkRelease() {
        guard pushToTalkHeld else { return }
        pushToTalkHeld = false
        Task { await self.finish() }
    }

    /// Atajos async para pruebas y para la UI sin teclas.
    public func beginPushToTalk() async {
        guard canBeginPushToTalk else { return }
        pushToTalkHeld = true
        await begin()
        if !isListening { pushToTalkHeld = false }
    }

    public func endPushToTalk() async {
        guard pushToTalkHeld else { return }
        pushToTalkHeld = false
        await finish()
    }

    private func stopAndEmit(commitDictation: Bool) async {
        guard isListening else { return }
        _ = try? await startTask?.value
        guard isListening else { return }
        state = .processing
        microphoneReady = false
        recognitionGeneration += 1
        let generation = recognitionGeneration
        stopMonitor()
        recognizer.onPartial = nil
        recognizer.onLevel = nil
        do {
            let raw = try await recognizer.stop()
            guard recognitionGeneration == generation else { return }
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await cancelLivePreview()
                if recognizer.hasSpeech {
                    state = .idle
                } else {
                    state = .failed("Silencio: revisa el micrófono y vuelve a intentarlo.")
                }
                return
            }
            if Self.isStopPhrase(raw) {
                await cancelLivePreview()
                handsFreeActive = false
                lastCommandFeedback = "Escucha detenida"
            } else if pendingAction != nil {
                await handlePendingSpeech(raw)
            } else if Self.decision(for: raw) != nil {
                await cancelLivePreview()
                lastCommandFeedback = "No hay propuesta pendiente"
            } else {
                let intent = process(rawTranscript: raw)
                if commitDictation, case .dictation = intent {
                    lastTranscript = raw
                    let hadLivePreview = voicePreviewStarted
                    voicePreviewStarted = false
                    await emit(intent, livePreview: hadLivePreview)
                } else {
                    await cancelLivePreview()
                    await receive(intent, transcript: raw, generation: generation)
                }
            }
            if recognitionGeneration == generation && state == .processing { state = .idle }
        } catch {
            guard recognitionGeneration == generation else { return }
            await cancelLivePreview()
            handsFreeActive = false
            state = .failed(error.localizedDescription)
            logger.error("Voice finish failed")
        }
    }

    // MARK: - Cierre automático por pausa (sin botón de terminar)

    private func startMonitor() {
        stopMonitor()
        lastSeenPartial = ""
        lastPartialChange = Date()
        monitorTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                self.checkAutoFinish()
            }
        }
    }

    private func stopMonitor() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func checkAutoFinish() {
        guard isListening, handsFreeActive, !pushToTalkHeld else { return }
        let current = partialTranscript
        let now = Date()
        if current != lastSeenPartial {
            lastSeenPartial = current
            lastPartialChange = now
            return
        }
        guard Self.endpointReached(partial: current,
                                   unchangedFor: now.timeIntervalSince(lastPartialChange),
                                   timeout: autoEndpointSilence) else { return }
        Task { await self.autoFinish() }
    }

    /// Decisión pura del endpoint: parcial no vacío y estable por `timeout`.
    /// El silencio total (parcial vacío) nunca cierra solo: el usuario detiene.
    nonisolated static func endpointReached(partial: String, unchangedFor: TimeInterval, timeout: TimeInterval) -> Bool {
        !partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && unchangedFor >= timeout
    }

    /// Descarta la grabación sin insertar nada. "Cancelar" por voz hace lo mismo.
    public func cancelDictation() async {
        stopMonitor()
        recognitionGeneration += 1
        handsFreeActive = false
        microphoneReady = false
        recognizer.onPartial = nil
        recognizer.onLevel = nil
        _ = try? await startTask?.value
        stopMonitor()
        await recognizer.cancel()
        await cancelLivePreview()
        state = .idle
        partialTranscript = ""
    }

    // MARK: - Intención → comandos

    /// Convierte una transcripción cruda en su intención final.
    /// Orden: legacy (frases exactas cortas) → gramática completa probada →
    /// dictado. Lo no accionable (unsupported/unknown/múltiple) cae a dictado,
    /// jamás se inserta como comando.
    func process(rawTranscript raw: String) -> VoiceIntent {
        if let legacy = parser.parse(raw) {
            return legacy
        }
        if let cmd = fullCommand(raw) {
            return .command(cmd)
        }
        let cleaned = cleaner.clean(raw, formal: formalStyle)
        guard !cleaned.isEmpty else { return .cancel }
        return .dictation(cleaned)
    }

    /// Gramática probada (`CommandGrammar`, fuente única). Si el raw no da una
    /// acción, se reintenta con la adaptación "cambia el título de X" → "a X"
    /// (el STT confunde a/de); `Grammar.swift` no se toca.
    func fullCommand(_ raw: String) -> ParsedCommand? {
        let first = parseCommand(raw: raw)
        if Self.isActionable(first) { return first }
        if let adapted = Self.adaptTitleDe(raw) {
            let second = parseCommand(raw: adapted)
            if Self.isActionable(second) { return second }
        }
        return nil
    }

    static func isActionable(_ cmd: ParsedCommand) -> Bool {        switch cmd {
        case .unsupported, .unknown, .multipleActions: return false
        default: return true
        }
    }

    /// "Cambia el título de X" → "Cambia el título a X" (mismo largo en
    /// caracteres: el folding no expande estos prefijos). Solo para parsear;
    /// el dictado usa siempre el raw original.
    static func adaptTitleDe(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = trimmed.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX"))
        let prefix = "cambia el titulo de "
        guard folded.hasPrefix(prefix), folded.count > prefix.count else { return nil }
        return "Cambia el título a " + String(trimmed.dropFirst(prefix.count))
    }

    /// Traduce una intención a comandos del editor.
    /// `deleteLastInsertion` es undo: borra la última inserción del editor.
    func editorCommands(for intent: VoiceIntent) -> [EditorCommand] {
        switch intent {
        case .dictation(let text):
            return text.isEmpty ? [] : [.insertText(text)]
        case .newline:
            return [.insertText("\n")]
        case .paragraph:
            return [.insertText("\n\n")]
        case .undo, .deleteLastInsertion:
            return [.undo]
        case .command(let cmd):
            return editorCommands(for: cmd)
        case .cancel:
            return []
        }
    }

    /// Gramática probada → `EditorCommand`. Reglas:
    /// - find/select: inmediatos, solo mueven selección (la sesión no muta).
    /// - delete sin selección: no-op en sesión (nunca inserta ni borra de más).
    /// - rewrite: la sesión genera antes de confirmar; la aceptación aplica el texto visible.
    /// - unsupported/unknown/múltiple: 0 comandos (el dictado ya los cubrió
    ///   como fallback en `process`; aquí nunca llegan, pero se blindan).
    func editorCommands(for command: ParsedCommand) -> [EditorCommand] {
        switch command {
        case .renameTitle(let t):
            return t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [.renameTitle(t)]
        case .deleteSelection:
            return [.replaceSelection("")]
        case .replaceSelection(let t):
            return [.replaceSelection(t)]
        case .rewriteSelection(let instruction):
            return instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? [] : [.rewriteSelection(instruction)]
        case .formatSelection(let style):
            switch style {
            case .bold: return [.toggleBold]
            case .italic: return [.toggleItalic]
            case .underline: return [.toggleUnderline]
            }
        case .undo:
            return [.undo]
        case .redo:
            return [.redo]
        case .selectText(let q):
            return q.isEmpty ? [] : [.selectText(q)]
        case .findText(let q):
            return q.isEmpty ? [] : [.findText(q)]
        case .saveDocument:
            return [.saveDocument]
        case .openDocument(let name):
            return [.openDocument(name)]
        case .exportDocument(let format):
            switch format {
            case .pdf: return [.exportDocument("pdf")]
            case .plainText: return [.exportDocument("txt")]
            case .richText: return [.exportDocument("rtf")]
            case .word: return [.exportDocument("word")]
            }
        case .unsupported, .unknown, .multipleActions:
            return []
        }
    }

    /// Texto del HUD tras ejecutar ("Guardado", "Título: X"…). Sin esto los
    /// comandos automáticos serían invisibles.
    func feedback(for command: ParsedCommand) -> String {
        switch command {
        case .renameTitle(let t): return "Título: \(t)"
        case .deleteSelection: return "Selección eliminada — «deshacer» revierte"
        case .replaceSelection(let t): return "Reemplazado por «\(t)» — «deshacer» revierte"
        case .rewriteSelection: return "Reescribí la selección. «Deshacer» revierte el cambio."
        case .formatSelection(let s):
            let name: String
            switch s {
            case .bold: name = "negritas"
            case .italic: name = "cursiva"
            case .underline: name = "subrayado"
            }
            return "Formato: \(name) — «deshacer» revierte"
        case .undo: return "Deshecho"
        case .redo: return "Rehecho"
        case .selectText(let q): return "Seleccionado: «\(q)»"
        case .findText(let q): return "Buscado: «\(q)»"
        case .saveDocument: return "Documento guardado"
        case .openDocument: return "Abriendo documento…"
        case .exportDocument(let f):
            switch f {
            case .pdf: return "Exportando PDF…"
            case .plainText: return "Exportando texto…"
            case .richText: return "Exportando RTF…"
            case .word: return "Exportando Word…"
            }
        case .unsupported: return "Ese comando no está disponible"
        case .unknown: return "No entendí el comando"
        case .multipleActions: return "Una acción a la vez, por favor"
        }
    }

    private func receive(_ intent: VoiceIntent, transcript: String, generation: Int) async {
        lastTranscript = transcript
        if intent == .cancel {
            partialTranscript = ""
            return
        }
        let commands = editorCommands(for: intent)
        guard !commands.isEmpty else {
            if case .command(let command) = intent { lastCommandFeedback = feedback(for: command) }
            partialTranscript = ""
            return
        }
        if case .command(.rewriteSelection(let instruction)) = intent {
            let proposal = await prepareRewrite?(instruction)
            guard recognitionGeneration == generation, context != nil else {
                discardRewrite?()
                return
            }
            guard let proposal else {
                lastCommandFeedback = "No se pudo generar la propuesta. Selecciona texto y comprueba que Apple Intelligence esté disponible."
                partialTranscript = ""
                return
            }
            pendingAction = PendingVoiceAction(
                transcript: transcript, intent: intent,
                preview: "Reescribir selección: «\(instruction)»\n\nPropuesta:\n\(proposal)"
            )
            lastCommandFeedback = ""
            partialTranscript = ""
        } else if case .command(.findText) = intent {
            await emit(intent)
        } else if case .command(.selectText) = intent {
            await emit(intent)
        } else {
            pendingAction = PendingVoiceAction(transcript: transcript, intent: intent, preview: preview(for: intent))
            lastCommandFeedback = ""
            partialTranscript = ""
        }
    }

    private func handlePendingSpeech(_ raw: String) async {
        switch Self.decision(for: raw) {
        case .confirm:
            await confirmPending()
        case .discard:
            cancelPending()
        case .repeatAction:
            discardRewrite?()
            pendingAction = nil
            lastCommandFeedback = "Repite la frase"
        case .asText:
            usePendingAsDictation()
        default:
            lastCommandFeedback = "Di confirmar, descartar o repetir"
        }
        partialTranscript = ""
    }

    private static func spokenAction(_ raw: String) -> String {
        raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_MX"))
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func isStopPhrase(_ raw: String) -> Bool {
        ["detener voz", "deten la voz", "apaga el microfono", "termina el dictado"]
            .contains(spokenAction(raw))
    }

    private func cancelLivePreview() async {
        guard voicePreviewStarted else { return }
        voicePreviewStarted = false
        await context?.commandBus.send(.cancelVoicePreview)
    }

    private enum SpokenDecision { case confirm, discard, repeatAction, asText }

    private static func decision(for raw: String) -> SpokenDecision? {
        switch spokenAction(raw) {
        case "confirmar", "confirma", "aceptar", "acepta", "confirmar la propuesta": return .confirm
        case "descartar", "descarta", "cancelar", "cancela": return .discard
        case "repetir", "repite", "intentar de nuevo": return .repeatAction
        case "usar como texto": return .asText
        default: return nil
        }
    }

    private func preview(for intent: VoiceIntent) -> String {
        switch intent {
        case .dictation(let text): return "Insertar: \"\(text)\""
        case .newline: return "Insertar salto de línea"
        case .paragraph: return "Insertar párrafo"
        case .undo, .deleteLastInsertion: return "Deshacer último cambio"
        case .command(let command):
            switch command {
            case .renameTitle(let title): return "Cambiar título a: \"\(title)\""
            case .replaceSelection(let text): return "Reemplazar selección por: \"\(text)\""
            case .rewriteSelection(let instruction): return "Reescribir selección: «\(instruction)»"
            case .deleteSelection: return "Eliminar selección"
            case .formatSelection(let style): return "Aplicar formato: \(style.rawValue)"
            case .undo: return "Deshacer último cambio"
            case .redo: return "Rehacer último cambio"
            case .saveDocument: return "Guardar documento"
            case .openDocument(let name): return "Abrir: \(name ?? "elegir documento")"
            case .exportDocument(let format): return "Exportar: \(format.rawValue)"
            default: return feedback(for: command)
            }
        case .cancel: return ""
        }
    }

    public func confirmPending() async {
        guard let action = pendingAction else { return }
        if case .dictation(let text) = action.intent,
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        pendingAction = nil
        if isListening && !continuousListening { await cancelDictation() }
        if case .command(.rewriteSelection) = action.intent {
            lastCommandFeedback = acceptRewrite?() == true
                ? "Selección reescrita — «deshacer» revierte"
                : "La propuesta caducó porque cambió la selección o el documento."
            return
        }
        await emit(action.intent)
    }

    public func updatePendingDictation(_ text: String) {
        guard let action = pendingAction, action.isDictation else { return }
        let intent = VoiceIntent.dictation(text)
        pendingAction = PendingVoiceAction(transcript: action.transcript, intent: intent, preview: preview(for: intent))
    }

    public func cancelPending() {
        guard pendingAction != nil else { return }
        discardRewrite?()
        pendingAction = nil
        lastCommandFeedback = "Propuesta descartada"
    }

    /// Si una frase era dictado, conserva el transcript y cambia la propuesta.
    public func usePendingAsDictation() {
        guard let action = pendingAction else { return }
        if case .dictation = action.intent { return }
        let text = cleaner.clean(action.transcript, formal: formalStyle)
        guard !text.isEmpty else { return }
        discardRewrite?()
        let intent = VoiceIntent.dictation(text)
        pendingAction = PendingVoiceAction(transcript: action.transcript, intent: intent, preview: preview(for: intent))
    }

    public func repeatPending() async {
        guard pendingAction != nil else { return }
        discardRewrite?()
        pendingAction = nil
        lastCommandFeedback = ""
        if isListening && !continuousListening { await cancelDictation() }
        await begin()
    }

    private func emit(_ intent: VoiceIntent, livePreview: Bool = false) async {
        guard let bus = context?.commandBus else {
            state = .failed("Voz sin conectar al editor. Reinicia la app.")
            return
        }
        let commands: [EditorCommand]
        if livePreview, case .dictation(let text) = intent {
            commands = [.commitVoicePreview(text)]
        } else {
            commands = editorCommands(for: intent)
        }
        switch intent {
        case .dictation(let text):
            lastInsertedText = text
            lastCommandFeedback = ""
        case .command(let cmd):
            lastInsertedText = ""
            lastCommandFeedback = feedback(for: cmd)
        case .undo, .deleteLastInsertion:
            lastInsertedText = ""
            lastCommandFeedback = "Deshecho"
        case .newline, .paragraph:
            lastInsertedText = ""
            lastCommandFeedback = "Insertado"
        default:
            lastInsertedText = ""
            lastCommandFeedback = ""
        }
        for command in commands {
            await bus.send(command)
        }
        partialTranscript = ""
    }
}
