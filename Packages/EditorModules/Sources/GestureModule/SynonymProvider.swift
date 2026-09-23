import Foundation
import FoundationModels

/// Fuente de sinónimos para la sesión de pinza.
///
/// La lista local es instantánea y siempre está; la IA (si hay modelo en el
/// Mac) mejora la lista en segundo plano. Sin modelo no se finge nada: la
/// tarjeta dice "locales" y el panel explica el motivo.
public protocol SynonymProvider: Sendable {
    /// ¿Puede mejorar la lista local ahora mismo?
    var isAvailable: Bool { get }
    /// Motivo legible si no está disponible (nil si lo está).
    var availabilityReason: String? { get }
    /// Sinónimos frescos (máximo 3 útiles) o vacío si no hay mejora.
    /// Nunca lanza: ante cualquier fallo devuelve vacío y el módulo
    /// conserva la lista local.
    func synonyms(for word: String) async -> [String]
}

/// Lista local inmediata. Siempre disponible como base, pero nunca mejora:
/// `isAvailable` es falso para que el módulo sepa que no hay de dónde
/// generar más allá del diccionario.
public struct LocalSynonymProvider: SynonymProvider {
    public init() {}
    public var isAvailable: Bool { false }
    public var availabilityReason: String? { "Mejora con IA desactivada: solo listas locales." }
    public func synonyms(for word: String) async -> [String] {
        GestureSynonyms.alternatives(for: word)
    }
}

/// Sinónimos reales con Apple Foundation Models (on-device).
/// Sin modelo disponible devuelve vacío: el módulo conserva los locales.
public struct FoundationModelsSynonymProvider: SynonymProvider {
    private static let instructions = "Eres un asistente de escritura en español. Respondes solo con el resultado pedido, sin preámbulos."

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
                return "Activa Apple Intelligence en Ajustes del Sistema para sinónimos con IA."
            case .modelNotReady:
                return "El modelo de IA se está descargando; reintenta en unos minutos."
            @unknown default:
                return "Modelo de IA no disponible ahora mismo."
            }
        }
    }

    public func synonyms(for word: String) async -> [String] {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, isAvailable else { return [] }
        // Un intento + un reintento ante fallos transitorios.
        if let top = await attempt(clean) { return top }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return [] }
        return await attempt(clean) ?? []
    }

    private func attempt(_ clean: String) async -> [String]? {
        guard !Task.isCancelled else { return nil }
        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let response = try await withResponseTimeout(seconds: 15) {
                try await session.respond(
                    to: """
                    Dame exactamente 3 sinónimos breves para la palabra "\(clean)".
                    Responde SIEMPRE en el mismo idioma de la palabra (español por defecto).
                    Ejemplo: para "rápido" responde veloz, pronto, ágil.
                    Devuelve solo los sinónimos, sin explicaciones ni numeración extra.
                    """,
                    generating: SynonymList.self
                )
            }
            // Solo sustitutos reales: distintos, breves y sin duplicados.
            let maxWords = clean.split(separator: " ").count + 1
            var seen = Set<String>()
            let alts = response.content.synonyms
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.lowercased() != clean.lowercased() }
                .filter { $0.split(separator: " ").count <= maxWords }
                .filter { seen.insert($0.lowercased()).inserted }
            let top = Array(alts.prefix(3))
            return top.isEmpty ? nil : top
        } catch {
            return nil
        }
    }

    private struct TimeoutError: Error {}

    /// Tope de tiempo: si el modelo se queda colgado, se falla rápido en vez
    /// de dejar la tarjeta esperando para siempre.
    private func withResponseTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TimeoutError()
            }
            guard let result = try await group.next() else { throw TimeoutError() }
            group.cancelAll()
            return result
        }
    }
}

/// Respuesta estructurada (Guided Generation): directa, sin preámbulos.
@Generable
struct SynonymList {
    @Guide(description: "Tres sinónimos breves en español, sin explicaciones")
    var synonyms: [String]
}
