import Foundation

/// Micrófono + reconocimiento local detrás de la pieza de voz.
///
/// El `VoiceModule` solo habla con este protocolo: en producción se inyecta
/// `AppleSpeechRecognizer`; en pruebas, un doble que devuelve texto fijo
/// sin pedir micrófono ni permisos.
public protocol VoiceSpeechRecognizer: AnyObject, Sendable {
    /// Transcripción parcial para mostrar mientras se dicta.
    var onPartial: (@Sendable (String) -> Void)? { get set }
    /// Nivel de entrada 0…1 para la barra del HUD.
    var onLevel: (@Sendable (Float) -> Void)? { get set }
    /// ¿Detectó voz real en la sesión actual? (energía, no texto).
    var hasSpeech: Bool { get }
    /// Texto final acumulado hasta ahora (solo lectura).
    var liveTranscript: String { get }

    /// Pide permisos y abre el micrófono. Lanza con mensaje legible si falla.
    func start() async throws
    /// Cierra el micrófono y devuelve la transcripción final.
    func stop() async throws -> String
    /// Descarta la sesión sin devolver texto.
    func cancel() async
}
