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
    /// nunca al arrancar el editor.
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
        } catch {
            state = .failed(error.localizedDescription)
            logger.error("Voice begin failed")
        }
    }

    /// Cierra el micrófono, limpia el texto y lo envía como comandos.
    public func finish() async {
        guard isListening else { return }
        state = .processing
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

    /// Descarta la grabación sin insertar nada. "Cancelar" por voz hace lo mismo.
    public func cancelDictation() async {
        await recognizer.cancel()
        state = .idle
        partialTranscript = ""
    }

    // MARK: - Intención → comandos

    /// Convierte una transcripción cruda en su intención final.
    /// Los comandos ganan al dictado; el dictado pasa por la limpieza local.
    func process(rawTranscript raw: String) -> VoiceIntent {
        if let command = parser.parse(raw) {
            return command
        }
        let cleaned = cleaner.clean(raw, formal: formalStyle)
        guard !cleaned.isEmpty else { return .cancel }
        return .dictation(cleaned)
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
        case .renameTitle(let title):
            return title.isEmpty ? [] : [.renameTitle(title)]
        case .cancel:
            return []
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
        if case .dictation(let text) = intent {
            lastInsertedText = text
        } else {
            lastInsertedText = ""
        }
        for command in commands {
            await bus.send(command)
        }
        partialTranscript = ""
    }
}
