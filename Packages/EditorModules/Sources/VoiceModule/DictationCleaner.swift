import Foundation

/// Limpieza local del dictado, sin red ni modelos externos.
///
/// Orden: muletillas fuera, puntuación dictada (`coma` → `,`), correcciones
/// del usuario y estilo formal opcional (mayúscula inicial y punto final,
/// como en documentos y correo).
///
/// Versión recortada de `DictationNormalizer` de LocalFlow
/// (`MiyuWisp/LocalFlow/LocalFlow/Intelligence/DictationNormalizer.swift`).
/// Allí quedan backtrack, listas dictadas y vocabulario técnico; aquí solo
/// lo que el editor necesita para dictar prosa. Conservadora por diseño:
/// ante la duda, conserva el texto tal cual.
public struct DictationCleaner: Sendable {
    public init() {}

    /// Limpia un dictado.
    /// - Parameters:
    ///   - raw: transcripción tal cual la entrega el reconocedor.
    ///   - formal: mayúscula inicial y punto final.
    ///   - customCorrections: pares `(lo que oigo, lo que quiero)`; ganan a las reglas.
    public func clean(
        _ raw: String,
        formal: Bool = true,
        customCorrections: [(from: String, to: String)] = []
    ) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: #"[^\S\r\n]+"#, with: " ", options: .regularExpression)
        text = removingFillers(text)
        text = applyingSpokenPunctuation(text)
        for correction in customCorrections where !correction.from.isEmpty && !correction.to.isEmpty {
            text = replacingWord(text, variant: correction.from, canonical: correction.to)
        }
        if formal {
            text = applyingFormalStyle(text)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Muletillas

    /// Quita relleno (`eh`, `um`, `ah`) y tartamudeos cortos (`yo yo`).
    /// Conserva palabras con significado (`este`, `pues`) y énfasis (`muy muy`).
    private func removingFillers(_ text: String) -> String {
        var out = text
        for filler in ["eh", "uh", "um", "ah", "mmm", "mm", "euh"] {
            let pattern = #"(?i)(?<![\p{L}\p{N}_])"# + filler + #"\b,?"#
            out = out.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        out = out.replacingOccurrences(of: #"(?i)\b([\p{L}]{1,2})\s+\1\b"#, with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: #"[^\S\r\n]+"#, with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\s+([,.;:?!…])"#, with: "$1", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Puntuación dictada

    /// Convierte palabras de puntuación en signos. `punto` no se toca dentro
    /// de locuciones (`punto de encuentro`, `punto final`).
    private func applyingSpokenPunctuation(_ text: String) -> String {
        var out = text
        let phrases: [(pattern: String, replacement: String)] = [
            (#"(?i)\bpunto y coma\b"#, ";"),
            (#"(?i)\bdos puntos\b"#, ":"),
            (#"(?i)\bpuntos suspensivos\b"#, "…"),
            (#"(?i)\bsigno de interrogaci[óo]n\b"#, "?"),
            (#"(?i)\bsigno de exclamaci[óo]n\b"#, "!"),
            (#"(?i)\bpor ciento\b"#, "%"),
            (#"(?i)\barroba\b"#, "@"),
            (#"(?i)\bcoma\b"#, ","),
            (#"(?i)\bpunto\b(?!\s+de\b|\s+del\b|\s+final\b|\s+muerto\b)"#, "."),
        ]
        for (pattern, replacement) in phrases {
            out = out.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        out = out.replacingOccurrences(of: #"\s+([,.;:?!…%])"#, with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\s*@\s*"#, with: "@", options: .regularExpression)
        out = out.replacingOccurrences(of: #"[^\S\r\n]+"#, with: " ", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Estilo

    private func applyingFormalStyle(_ text: String) -> String {
        var out = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { return text }
        if let first = out.first {
            out.replaceSubrange(out.startIndex...out.startIndex, with: String(first).uppercased())
        }
        var chars = Array(out)
        var i = 0
        while i < chars.count {
            if ".?!…".contains(chars[i]) {
                var j = i + 1
                while j < chars.count && chars[j].isWhitespace && chars[j] != "\n" { j += 1 }
                if j < chars.count && chars[j].isLetter {
                    chars[j] = Character(String(chars[j]).uppercased())
                }
                i = j
            }
            i += 1
        }
        out = String(chars)
        if let last = out.last, last.isLetter || last.isNumber {
            out.append(".")
        }
        return out
    }

    private func replacingWord(_ text: String, variant: String, canonical: String) -> String {
        let pattern = #"(?i)(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for: variant) + #"(?![\p{L}\p{N}_])"#
        return text.replacingOccurrences(of: pattern, with: canonical, options: .regularExpression)
    }
}
