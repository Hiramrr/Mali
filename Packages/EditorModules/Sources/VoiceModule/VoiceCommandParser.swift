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
        if let title = Self.renameTitle(in: transcript), text.count < 120 {
            return .renameTitle(title)
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

    /// "Cambia el título a X" → `X` verbatim (con tildes y mayúsculas del
    /// hablante). Solo frase completa: el comando debe abrir la frase, el
    /// argumento no va vacío y no contiene saltos de línea. Sin fuzzy: lo que
    /// no calza exacto sigue siendo dictado.
    private static func renameTitle(in transcript: String) -> String? {
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.contains("\n") else { return nil }
        let folded = raw.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX"))
        let prefixes = [
            "cambia el titulo a ",
            "pon como titulo ",
            "ponle de titulo ",
            "titula ",
            "renombra a ",
            "renombra como ",
        ]
        for prefix in prefixes {
            guard folded.hasPrefix(prefix), folded.count > prefix.count else { continue }
            // El folding no altera el número de caracteres de estos prefijos:
            // el argumento se recorta del raw por posición.
            let arg = String(raw.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !arg.isEmpty, arg.count <= 60, !arg.contains("\n") else { return nil }
            return arg
        }
        return nil
    }
}
