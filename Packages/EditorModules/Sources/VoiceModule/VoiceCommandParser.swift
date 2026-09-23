import Foundation

/// Detección determinista de comandos por voz. Se ejecuta antes de limpiar
/// el texto: un comando solo vale como frase completa y corta, nunca
/// mezclado dentro de un dictado largo.
///
/// Lógica portada de `RuleBasedIntentParser` de LocalFlow
/// (`MiyuWisp/LocalFlow/LocalFlow/Intelligence/RuleBasedIntentParser.swift`).
/// Allí vive la versión completa con más sinónimos; aquí solo lo necesario
/// para el editor, en un archivo fácil de ampliar.
public struct VoiceCommandParser: Sendable {
    public init() {}

    public func parse(_ transcript: String) -> VoiceIntent? {
        let text = transcript
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text == "cancelar" || text == "cancela" || text == "cancel" || text == "olvídalo" || text == "olvidalo" {
            return .cancel
        }
        let deletePhrases = [
            "borra lo que acabo de escribir",
            "borra lo último que escribiste",
            "borra lo ultimo que escribiste",
            "borra lo último",
            "borra lo ultimo",
            "borra eso",
            "elimina lo que acabo de escribir",
            "deshaz eso",
            "deshaz lo último",
            "deshaz lo ultimo",
        ]
        if deletePhrases.contains(text), text.count < 80 {
            return .deleteLastInsertion
        }
        if text == "deshacer" || text == "deshaz" || text == "undo" {
            return .undo
        }
        if text.count < 40 {
            if text == "nueva línea" || text == "nueva linea" || text == "salto de línea" || text == "salto de linea" || text == "newline" {
                return .newline
            }
            if text == "nuevo párrafo" || text == "nuevo parrafo" || text == "nuevo parágrafo" || text == "paragraph" || text == "párrafo nuevo" || text == "parrafo nuevo" {
                return .paragraph
            }
        }
        return nil
    }
}
