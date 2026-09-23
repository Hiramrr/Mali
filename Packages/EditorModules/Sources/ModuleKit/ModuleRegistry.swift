import Foundation
import Observation

/// Registro de módulos de entrada. Vive en la raíz de composición (App)
/// y se inyecta donde haga falta (toolbar, ajustes).
///
/// Los módulos son targets compilados con la app, no bundles dinámicos:
/// quitar un target deja al editor compilando y funcionando.
@MainActor @Observable
public final class ModuleRegistry {
    public private(set) var modules: [ModuleDescriptor] = []

    public init() {}

    public func register(_ descriptor: ModuleDescriptor) {
        guard !modules.contains(where: { $0.identifier == descriptor.identifier }) else { return }
        modules.append(descriptor)
    }

    public func unregister(identifier: String) {
        modules.removeAll { $0.identifier == identifier }
    }

    public func isRegistered(identifier: String) -> Bool {
        modules.contains { $0.identifier == identifier }
    }
}
