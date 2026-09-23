import Foundation
import EditorCore

/// Bus asíncrono entre módulos de entrada y el editor.
///
/// Los productores (voz, gestos, …) envían `EditorCommand` sin conocer el
/// motor de texto. La app consume el stream y lo aplica a la sesión activa.
///
/// - Múltiples productores y múltiples consumidores (difusión).
/// - Sin pérdidas: el buffer no descarta comandos (un deshacer jamás se tira).
/// - Cancelación segura: si un consumidor se cancela, se desregistra solo.
/// - `finish()` cierra el bus (p. ej. al desmontar el último documento).
public actor EditorCommandBus {
    private var continuations: [UUID: AsyncStream<EditorCommand>.Continuation] = [:]
    private var finished = false

    public init() {}

    /// Nuevo consumidor. Cada llamada devuelve un stream independiente que
    /// recibe todo lo enviado desde su creación hasta `finish()` o su
    /// cancelación.
    public func commands() -> AsyncStream<EditorCommand> {
        let (stream, continuation) = AsyncStream<EditorCommand>.makeStream()
        guard !finished else {
            continuation.finish()
            return stream
        }
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.remove(id: id) }
        }
        return stream
    }

    /// Difunde un comando a todos los consumidores activos.
    public func send(_ command: EditorCommand) {
        guard !finished else { return }
        for continuation in continuations.values {
            continuation.yield(command)
        }
    }

    /// Cierra el bus. Los consumidores pendientes terminan su iteración.
    public func finish() {
        guard !finished else { return }
        finished = true
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    private func remove(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
