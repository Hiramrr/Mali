import AppKit
import Foundation

/// Hotkey de push-to-talk para voz: mantener `⌥Espacio` habla, soltar cierra.
///
/// Sin permisos extra: el monitor local funciona cuando la app está al frente
/// y consume la pulsación para no insertar un espacio inseparable en el texto.
/// El monitor global es oportunista (requiere Accesibilidad para teclas fuera
/// de la app); si el sistema no lo autoriza, simplemente no dispara y el modo
/// local sigue funcionando. Ambos comparten un solo `pressed` para no
/// disparar dos veces cuando la app está activa.
///
/// El filtrado del evento es síncrono (el monitor local debe devolver `nil` o
/// el evento de inmediato); la decisión de negocio (¿puede empezar?) vive en
/// `VoiceModule` y es idempotente, así que un doble disparo es inofensivo.
final class VoicePushToTalk: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var localMonitor: Any?
    private nonisolated(unsafe) var globalMonitor: Any?
    private nonisolated(unsafe) var resignObserver: Any?
    private var _pressed = false
    private var _enabled = true

    var isEnabled: Bool {
        get { lock.withLock { _enabled } }
        set { lock.withLock { _enabled = newValue } }
    }

    private let onPress: (@Sendable () -> Void)
    private let onRelease: (@Sendable () -> Void)

    init(onPress: @escaping (@Sendable () -> Void), onRelease: @escaping (@Sendable () -> Void)) {
        self.onPress = onPress
        self.onRelease = onRelease
    }

    /// Instala los monitores. Llamar desde el hilo principal una sola vez.
    func start() {
        lock.withLock {
            guard localMonitor == nil else { return }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self else { return event }
                return self.handleLocal(event) ?? event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                self?.handleGlobal(event)
            }
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, self.takePressed() else { return }
                self.onRelease()
            }
        }
    }

    func stop() {
        lock.withLock {
            if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
            if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
            if let observer = resignObserver { NotificationCenter.default.removeObserver(observer) }
            localMonitor = nil
            globalMonitor = nil
            resignObserver = nil
            _pressed = false
        }
    }

    deinit {
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let observer = resignObserver { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Detección pura (probable sin UI)

    /// `⌥Espacio` a la baja: espacio (keyCode 49) con opción y sin
    /// comando ni control. No se exige ausencia de shift para no fallar con
    /// teclados que lo reportan junto a opción.
    nonisolated static func isHotkeyDown(_ event: NSEvent) -> Bool {
        event.type == .keyDown
            && event.keyCode == 49
            && event.modifierFlags.contains(.option)
            && !event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.control)
    }

    // MARK: - Manejo interno

    /// Devuelve `nil` para consumir el evento, o el evento para dejarlo pasar.
    private func handleLocal(_ event: NSEvent) -> NSEvent? {
        guard isEnabled else { return event }
        if event.type == .keyDown {
            guard Self.isHotkeyDown(event) else { return event }
            if event.isARepeat {
                return lock.withLock { _pressed } ? nil : event
            }
            guard trySetPressed() else { return nil }
            onPress()
            return nil
        }
        if event.type == .keyUp, event.keyCode == 49 {
            guard takePressed() else { return event }
            onRelease()
            return nil
        }
        return event
    }

    private func handleGlobal(_ event: NSEvent) {
        guard isEnabled else { return }
        if event.type == .keyDown {
            guard Self.isHotkeyDown(event), !event.isARepeat else { return }
            guard trySetPressed() else { return }
            onPress()
        } else if event.type == .keyUp, event.keyCode == 49 {
            guard takePressed() else { return }
            onRelease()
        }
    }

    private func trySetPressed() -> Bool {
        lock.withLock {
            guard !_pressed else { return false }
            _pressed = true
            return true
        }
    }

    private func takePressed() -> Bool {
        lock.withLock {
            guard _pressed else { return false }
            _pressed = false
            return true
        }
    }
}
