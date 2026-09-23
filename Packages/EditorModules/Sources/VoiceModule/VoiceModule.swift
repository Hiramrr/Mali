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
/// Flujo: micrófono → reconocedor → `VoiceCommandParser` + `DictationCleaner`
/// → `EditorCommand` → `EditorCommandBus` → `EditorSession`.
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
    /// Último parcial del reconocedor, para mostrar mientras se dicta.
    public private(set) var partialTranscript = ""
    /// Nivel de entrada 0…1 para la barra del HUD.
    public private(set) var inputLevel: Float = 0
    /// Último texto insertado (para confirmar sin reabrir el documento).
    public private(set) var lastInsertedText = ""
    /// Qué hizo el último comando ("Guardado", "Título: X"…). Los comandos se
    /// ejecutan al momento; "deshacer" por voz revierte la última acción.
    public private(set) var lastCommandFeedback = ""
    /// Escucha continua: un toque inicia; cada pausa ejecuta y rearma; otro
    /// toque detiene. Sin esto habría que pulsar para terminar cada frase.
    public var continuousListening = true
    /// Pausa (s) sin cambios en el parcial para cerrar el enunciado solo.
    public var autoEndpointSilence: TimeInterval = 1.6
    private var monitorTask: Task<Void, Never>?
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
        stopMonitor()
        await recognizer.cancel()
        context = nil
        state = .idle
        partialTranscript = ""
    }

    // MARK: - Dictado (pulsar para hablar)

    public var isListening: Bool {
        if case .listening = state { return true }
        return false
    }

    /// Alterna dictado: empieza si está en reposo, termina e inserta si escucha.
    public func toggle() async {
        if isListening {
            await finish()
        } else {
            await begin()
        }
    }

    /// Abre el micrófono. Pide permiso de micrófono y voz solo aquí,
    /// nunca al arrancar el editor. Arranca el monitor de cierre automático.
    public func begin() async {
        guard !isListening else { return }
        state = .listening
        partialTranscript = ""
        inputLevel = 0
        recognizer.onPartial = { [weak self] text in
            Task { @MainActor [weak self] in self?.partialTranscript = text }
        }
        recognizer.onLevel = { [weak self] level in
            Task { @MainActor [weak self] in self?.inputLevel = level }
        }
        do {
            try await recognizer.start()
            startMonitor()
        } catch {
            state = .failed(error.localizedDescription)
            logger.error("Voice begin failed")
        }
    }

    /// Cierra el micrófono, procesa el texto y lo envía como comandos.
    /// Uso manual (botón "Insertar ahora" o segundo toque): no rearma.
    public func finish() async {
        await stopAndEmit()
    }

    /// Cierre automático por pausa: para, ejecuta y —en escucha continua—
    /// rearma el micrófono para el siguiente enunciado sin tocar botones.
    private func autoFinish() async {
        await stopAndEmit()
        if continuousListening, state == .idle {
            await begin()
        }
    }

    private func stopAndEmit() async {
        guard isListening else { return }
        state = .processing
        stopMonitor()
        recognizer.onPartial = nil
        recognizer.onLevel = nil
        do {
            let raw = try await recognizer.stop()
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                if recognizer.hasSpeech {
                    state = .idle
                } else {
                    state = .failed("Silencio: revisa el micrófono y vuelve a intentarlo.")
                }
                return
            }
            let intent = process(rawTranscript: raw)
            await emit(intent)
            state = .idle
        } catch {
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
                await self.checkAutoFinish()
            }
        }
    }

    private func stopMonitor() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func checkAutoFinish() {
        guard isListening, continuousListening else { return }
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
        await recognizer.cancel()
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
    /// - rewrite: la IA llega en Fase 12; no se finge (feedback + 0 comandos).
    /// - word: el editor no exporta Word (feedback + 0 comandos).
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
        case .rewriteSelection:
            return []
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
            case .word: return []
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
        case .rewriteSelection: return "La reescritura con IA llega en la Fase 12"
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
            case .word: return "Word no disponible en el editor"
            }
        case .unsupported: return "Ese comando no está disponible"
        case .unknown: return "No entendí el comando"
        case .multipleActions: return "Una acción a la vez, por favor"
        }
    }

    private func emit(_ intent: VoiceIntent) async {
        if intent == .cancel {
            partialTranscript = ""
            return
        }
        guard let bus = context?.commandBus else {
            state = .failed("Voz sin conectar al editor. Reinicia la app.")
            return
        }
        let commands = editorCommands(for: intent)
        switch intent {
        case .dictation(let text):
            lastInsertedText = text
            lastCommandFeedback = ""
        case .command(let cmd):
            lastInsertedText = ""
            lastCommandFeedback = feedback(for: cmd)
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
