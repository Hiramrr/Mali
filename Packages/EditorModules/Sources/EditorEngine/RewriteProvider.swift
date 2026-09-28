import Foundation
import FoundationModels

/// Fuente de reescritura para el comando de voz ("hazlo más breve").
///
/// La IA vive en este Mac (Apple Intelligence on-device). Sin modelo
/// disponible o ante cualquier fallo devuelve nil y la sesión no toca el
/// texto: nunca se finge una reescritura.
public protocol RewriteProvider: Sendable {
    /// ¿Puede reescribir ahora mismo?
    var isAvailable: Bool { get }
    /// Motivo legible si no está disponible (nil si lo está).
    var availabilityReason: String? { get }
    /// Texto reescrito según la instrucción, o nil si no se pudo generar.
    /// Nunca lanza: ante cualquier fallo devuelve nil y se conserva el original.
    func rewrite(_ text: String, instruction: String) async -> String?
}

/// Reescritura real con Apple Foundation Models (on-device).
/// Sin modelo disponible devuelve nil: la sesión conserva el original.
public struct FoundationModelsRewriteProvider: RewriteProvider {
    private static let instructions = "Eres editor de textos en español. Reescribes solo el texto dado según la instrucción, conservando hechos, nombres, cifras y sentido del original. No inventes datos ni agregues información externa."

    public init() {}

    public var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    public var availabilityReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "Este Mac no es compatible con Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Activa Apple Intelligence en Ajustes del Sistema para reescribir con IA."
            case .modelNotReady:
                return "El modelo de IA se está descargando; reintenta en unos minutos."
            @unknown default:
                return "Modelo de IA no disponible ahora mismo."
            }
        }
    }

    public func rewrite(_ text: String, instruction: String) async -> String? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let order = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !order.isEmpty, isAvailable, !Task.isCancelled else { return nil }
        do {
            return try await withThrowingTaskGroup(of: String?.self) { group in
                group.addTask {
                    let session = LanguageModelSession(instructions: Self.instructions)
                    let response = try await session.respond(
                        to: """
                        Instrucción: \(order)

                        Texto: \(clean)
                        """,
                        generating: RewriteOutput.self
                    )
                    let out = response.content.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return Self.preservingBoundaryWhitespace(out, from: text)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(20))
                    return nil
                }
                let first = try await group.next()
                group.cancelAll()
                return first ?? nil
            }
        } catch {
            return nil
        }
    }

    static func preservingBoundaryWhitespace(_ rewritten: String, from original: String) -> String? {
        let content = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = rewritten.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !replacement.isEmpty,
              let range = original.range(of: content) else { return nil }
        return String(original[..<range.lowerBound]) + replacement + String(original[range.upperBound...])
    }
}

/// Respuesta estructurada (Guided Generation): solo el texto, sin comentarios.
@Generable
struct RewriteOutput {
    @Guide(description: "El texto reescrito, sin comillas ni comentarios")
    var text: String
}
