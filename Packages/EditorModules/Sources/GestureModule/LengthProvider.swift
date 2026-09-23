import Foundation
import FoundationModels

public protocol LengthProvider: Sendable {
    var isAvailable: Bool { get }
    var availabilityReason: String? { get }
    /// Devuelve [corta, larga], o vacío si no pudo crear ambas versiones.
    func variants(for paragraph: String) async -> [String]
}

public struct FoundationModelsLengthProvider: LengthProvider {
    public init() {}

    public var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    public var availabilityReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: "Este Mac no es compatible con Apple Intelligence."
            case .appleIntelligenceNotEnabled: "Activa Apple Intelligence en Ajustes del Sistema."
            case .modelNotReady: "El modelo de IA se está descargando; reintenta en unos minutos."
            @unknown default: "Modelo de IA no disponible ahora mismo."
            }
        }
    }

    public func variants(for paragraph: String) async -> [String] {
        guard isAvailable, !Task.isCancelled else { return [] }
        do {
            return try await withThrowingTaskGroup(of: [String].self) { group in
                group.addTask {
                    let session = LanguageModelSession(instructions: "Eres editor de textos en español. Conserva los hechos, nombres, cifras y sentido del original. No inventes datos ni agregues información externa. Devuelve párrafos completos, sin puntos suspensivos ni comentarios.")
                    let response = try await session.respond(
                        to: """
                        Reescribe este párrafo en dos versiones.
                        Corta: expresa su idea principal en una oración completa, con menos del 70 % de las palabras. No cortes una frase a la mitad.
                        Larga: explica con mayor claridad las ideas que ya están en el párrafo, con al menos 10 % más palabras. No agregues hechos nuevos ni repitas frases para rellenar.

                        Párrafo: \(paragraph)
                        """,
                        generating: LengthVariants.self
                    )
                    return [response.content.short, response.content.long]
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(20))
                    return []
                }
                let result = try await group.next() ?? []
                group.cancelAll()
                guard result.count == 2 else { return [] }
                let short = result[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let long = result[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard GestureSynonyms.isValidShort(short, original: paragraph),
                      GestureSynonyms.isValidLong(long, original: paragraph) else { return [] }
                return [short, long]
            }
        } catch {
            return []
        }
    }
}

@Generable
struct LengthVariants {
    @Guide(description: "Una versión breve y completa del párrafo")
    var short: String
    @Guide(description: "Una versión más extensa que aclara sin inventar hechos")
    var long: String
}
