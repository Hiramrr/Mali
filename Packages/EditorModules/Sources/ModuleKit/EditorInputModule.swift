import Foundation

/// Contexto que recibe un módulo de entrada al arrancar.
///
/// Solo expone el bus de comandos: el módulo puede producir intenciones
/// (`await context.commandBus.send(.undo)`) pero nunca accede a
/// `NSTextView`, `NSWindow`, vistas del editor ni internos del documento.
public struct EditorModuleContext: Sendable {
    public let commandBus: EditorCommandBus

    public init(commandBus: EditorCommandBus) {
        self.commandBus = commandBus
    }
}

/// Contrato para módulos multimodales (voz, gestos, …).
///
/// Las implementaciones viven en targets separados y se registran en
/// `ModuleRegistry`. Quitar el target del módulo no rompe la compilación
/// del editor: la integración se reduce a `registry.register(...)` más el
/// bloque de cableado en `App/EditorApp.swift` (marcado "Pieza Lego").
///
/// Los métodos son `@MainActor` porque los módulos reales tocan cámara,
/// micrófono o UI al arrancar y al detenerse.
public protocol EditorInputModule: Sendable {
    var identifier: String { get }
    var displayName: String { get }

    @MainActor func start(context: EditorModuleContext) async throws
    @MainActor func stop() async
}

/// Descriptor registrable. La app instancia el módulo y lo arranca con
/// `start(context:)`; el registro solo anuncia disponibilidad (p. ej. para
/// la pestaña Multimodalidad de Ajustes).
public struct ModuleDescriptor: Sendable, Equatable {
    public let identifier: String
    public let displayName: String

    public init(identifier: String, displayName: String) {
        self.identifier = identifier
        self.displayName = displayName
    }
}
