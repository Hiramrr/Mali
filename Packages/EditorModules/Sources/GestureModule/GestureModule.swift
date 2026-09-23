import EditorCore
import Foundation
import ModuleKit
import Observation

/// Sesión de pinza sobre una palabra: pinzar abre las opciones,
/// mover cambia el preview en el documento, soltar confirma.
///
/// Todo el cómputo es local. El preview no toca undo ni el guardado
/// hasta confirmar (entonces queda un único undo, como escribir).
struct PinchSession: Sendable {
    let id: UUID
    let word: String
    let location: Int
    var alternatives: [String]
    var currentIndex: Int
    var referenceX: Double

    var option: String { alternatives[currentIndex] }
}

/// Sesión a dos manos sobre un párrafo: mostrar ambas manos abre las
/// versiones de longitud, acercar/separar cambia el preview en el
/// documento, retirar una mano confirma.
///
/// Las versiones son locales ([corta, original, original]): sin IA en este
/// programa, la lista local es final y la tarjeta lo indica. Navegar entre
/// ellas nunca espera a nada.
struct LengthSession: Sendable {
    let id: UUID
    let originalText: String
    let originalLocation: Int
    /// Orden fijo: [corta, media (= original), larga (= original)].
    var alternatives: [String]
    var currentIndex: Int
    var referenceSpan: Double

    var option: String { alternatives[currentIndex] }
}

/// Entrada por gestos con la cámara local, como pieza extraíble.
///
/// - Mano abierta + mover a los lados → la selección camina palabra por palabra.
/// - Pinza sobre una palabra → muestra sinónimos locales; mover elige, soltar confirma.
/// - Abrir la pinza o perder la mano → cancela y restaura la palabra.
/// - Pinza + barrido lateral amplio → deshacer/rehacer (una vez por pinza).
/// - Dos manos + acercar/separar → cambia la longitud del párrafo
///   (corto/medio/largo locales); retirar UNA mano confirma, perder AMBAS
///   restaura (nunca se confirma a ciegas).
///
/// El módulo nunca toca `NSTextView` ni el motor de texto:
/// - Navegación y deshacer/rehacer viajan como `EditorCommand` por el bus
///   (en orden FIFO; la sesión los valida contra el texto vigente).
/// - Las previews viajan como comandos atómicos
///   (`beginPreview`/`showPreview`/`commitPreview`/`cancelPreview`) que
///   `EditorSession` aplica sin ensuciar undo ni guardado.
/// - El documento llega por `updateDocument(text:selection:)` (instantánea
///   de valores, sin referencias a vistas). Si el texto cambia por fuera
///   durante una sesión, se cancela, no se aplica a ciegas.
@MainActor @Observable
public final class GestureModule: EditorInputModule {
    public nonisolated let identifier = "gestures.hand"
    public nonisolated let displayName = "Gestos"

    public static var descriptor: ModuleDescriptor {
        ModuleDescriptor(identifier: "gestures.hand", displayName: "Gestos")
    }

    public var running = false
    public var starting = false
    public var message = "Cámara apagada"
    public var state = GestureState()

    private var commandBus: EditorCommandBus?
    /// Mejora de sinónimos con IA (on-device). Por defecto Foundation Models
    /// con fallback local; en pruebas se inyecta un doble sin modelo.
    private let synonymProvider: any SynonymProvider

    // @Observable no admite `lazy`: inicialización explícita a demanda.
    // La cámara solo existe si el usuario la activa: sin la pieza (o sin
    // activarla) el programa jamás pide permiso de cámara.
    private var _camera: CameraManager?
    public var camera: CameraManager {
        if let _camera { return _camera }
        let manager = CameraManager { [weak self] message in
            Task { @MainActor [weak self] in
                self?.cameraDidFail(message)
            }
        }
        _camera = manager
        return manager
    }

    private var task: Task<Void, Never>?

    // Instantánea del documento (la empuja la app, sin vistas de por medio).
    private var cachedText = ""
    private var cachedSelection = NSRange(location: 0, length: 0)
    private var rangedText = ""
    private var cachedWordRanges: [NSRange] = []
    private var navigationX: Double?

    // Sesión de pinza. Interna para pruebas (@testable): simulan el avance
    // del preview sin cámara.
    var pinchSession: PinchSession?
    private var sessionLastHandX = 0.0
    /// Ancla del barrido deshacer/rehacer: posición X al cerrar la pinza.
    /// Si la mano barre más de `undoSwipeDistance` antes de que abra la
    /// sesión de sinónimos, el gesto es deshacer/rehacer (una vez por pinza).
    private var undoSwipeAnchor: Double?
    private var undoSwipeFired = false
    /// Pinza sostenida: la sesión abre tras varios frames (evita roces).
    private var pinchStreak = 0
    /// Pinza del frame anterior: la pinza efectiva exige 2 frames seguidos
    /// (un parpadeo aislado no interrumpe la navegación ni abre sesiones).
    private var lastRawPinch = false
    private var requiresRelease = false
    private var trackingLostAt: TimeInterval?
    /// Frames válidos seguidos con la mano abierta y sesión activa.
    /// Confirma al llegar a 3: el evento .ended aislado se pierde con parpadeos.
    private var openStreak = 0
    /// Desplazamiento actual respecto a la referencia (para guiar en la UI).
    public private(set) var sessionDelta = 0.0
    /// La lista actual ya incluye sinónimos de IA (si no, locales).
    public private(set) var sessionUpgraded = false
    private var upgradeTask: Task<Void, Never>?
    /// Estado de la IA para la UI (panel y ajustes).
    public var synonymProviderAvailable: Bool { synonymProvider.isAvailable }
    public var synonymProviderReason: String? { synonymProvider.availabilityReason }

    /// Sesión iniciada desde un botón (sin cámara): solo la tarjeta la mueve.
    private var pinchManualControl = false
    public var isPinchManual: Bool { pinchManualControl }

    /// Calibración guiada a la mano del usuario.
    public private(set) var calibration: GestureCalibrationRun?
    public private(set) var calibrationMessage: String?
    public private(set) var openMedian: Double?
    public private(set) var pinchMedian: Double?

    /// Lecturas para la tarjeta de opciones (observadas por SwiftUI).
    public var hasPinchSession: Bool { pinchSession != nil }
    public var sessionOptions: [String] { pinchSession?.alternatives ?? [] }
    public var sessionIndex: Int { pinchSession?.currentIndex ?? 0 }
    /// Offset de la palabra en sesión.
    public var sessionLocation: Int? { pinchSession?.location }

    // MARK: - Sesión a dos manos (longitud del párrafo)

    private var lengthSession: LengthSession?
    private var lengthLastSpan = 0.0
    /// Separación suavizada (media móvil exponencial). Congelada durante
    /// pérdidas de seguimiento: al volver, el re-anclaje excluye el salto.
    private var lengthSmoothedSpan: Double?
    /// Momentos (uptime) de detecciones recientes con dos manos.
    /// Abrir exige varias dentro de una ventana corta: tolera parpadeos.
    private var lengthTwoHandHits: [TimeInterval] = []
    /// Frames seguidos con una sola mano y sesión activa (confirma).
    private var lengthOpenStreak = 0
    /// Tras confirmar/cancelar hay que separar las manos para otra sesión.
    private var lengthRequiresRelease = false
    /// Sesión iniciada desde el botón (sin cámara): solo la tarjeta la mueve.
    private var lengthManualControl = false
    private var lengthTrackingLostAt: TimeInterval?
    /// Desplazamiento actual de la separación (para guiar en la UI).
    public private(set) var lengthSessionDelta = 0.0

    /// Lecturas para la tarjeta de longitud (observadas por SwiftUI).
    public var hasLengthSession: Bool { lengthSession != nil }
    public var lengthOptions: [String] { lengthSession?.alternatives ?? [] }
    public var lengthIndex: Int { lengthSession?.currentIndex ?? LengthLevel.medio.rawValue }
    public var lengthLabels: [String] { LengthLevel.allCases.map(\.label) }
    public var isLengthManual: Bool { lengthManualControl }
    /// Texto original del párrafo en sesión (para marcar filas idénticas).
    public var lengthOriginalText: String { lengthSession?.originalText ?? "" }
    /// Confirmación visible tras aplicar un nivel, con Deshacer en un clic.
    public private(set) var lengthToast: String?
    /// Si el toast confirma un cambio real (con "Sin cambios" no hay nada que deshacer).
    public private(set) var lengthToastCanUndo = true

    public init(synonymProvider: (any SynonymProvider)? = nil) {
        // Sin inyección (producción): IA on-device si hay modelo, locales si no.
        self.synonymProvider = synonymProvider ?? FoundationModelsSynonymProvider()
    }

    // MARK: - EditorInputModule

    public func start(context: EditorModuleContext) async throws {
        commandBus = context.commandBus
    }

    public func stop() async {
        deactivateCamera()
        commandBus = nil
    }

    // MARK: - Instantánea del documento

    /// La app empuja texto+selección (valores, sin vistas). Barato: los rangos
    /// de palabra se recalculan bajo demanda, no en cada pulsación.
    public func updateDocument(text: String, selection: NSRange) {
        cachedText = text
        cachedSelection = selection
        guard commandBus != nil else { return }
        reconcileSessions(with: text)
    }

    private func currentWordRanges() -> [NSRange] {
        if cachedText != rangedText {
            rangedText = cachedText
            cachedWordRanges = Self.wordRanges(in: cachedText)
            navigationX = nil
        }
        return cachedWordRanges
    }

    private static func wordRanges(in text: String) -> [NSRange] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        var out: [NSRange] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { _, range, _, _ in
            out.append(range)
        }
        return out
    }

    /// Si el texto cambió por fuera durante una sesión, se cancela la sesión
    /// (nunca se confirma a ciegas). Durante la propia preview el binding no
    /// cambia, así que la base sigue intacta y no hay cancelaciones falsas.
    /// Si algún eco de la preview llegara igual, se acepta la opción actual
    /// como intacta: solo lo ajeno a palabra Y opción cancela.
    private func reconcileSessions(with text: String) {
        let ns = text as NSString
        if let s = pinchSession {
            if !spanMatches(s.location, length: (s.word as NSString).length, text: s.word, in: ns)
                && !spanMatches(s.location, length: (s.option as NSString).length, text: s.option, in: ns) {
                cancelPinchSession()
            }
        }
        if let s = lengthSession {
            if !spanMatches(s.originalLocation, length: (s.originalText as NSString).length, text: s.originalText, in: ns)
                && !spanMatches(s.originalLocation, length: (s.option as NSString).length, text: s.option, in: ns) {
                cancelLengthSession()
            }
        }
    }

    private func spanMatches(_ location: Int, length: Int, text: String, in ns: NSString) -> Bool {
        let span = NSRange(location: location, length: length)
        return NSMaxRange(span) <= ns.length && ns.substring(with: span) == text
    }

    private func send(_ command: EditorCommand) async {
        await commandBus?.send(command)
    }

    // MARK: - Cámara

    /// Abre la cámara. Pide permiso de cámara solo aquí, nunca al arrancar.
    public func activateCamera() async {
        guard !starting, !running else { return }
        starting = true
        defer { starting = false }
        do {
            _ = try await camera.start()
            running = true
            navigationX = nil
            trackingLostAt = nil
            lastRawPinch = false
            message = "Muestra tu mano: moverla elige palabra, la pinza muestra sinónimos."
            // Un único consumidor del AsyncStream durante toda la vida del
            // objeto: crearlo por arranque dividía la entrega de frames.
            ensureConsumer()
        } catch {
            message = error.localizedDescription
        }
    }

    public func deactivateCamera() {
        // No se cancela el consumidor: aparcado sin frames, se reutiliza
        // al arrancar de nuevo.
        cancelPinchSession()
        _camera?.stop()
        running = false
        navigationX = nil
        trackingLostAt = nil
        lengthTrackingLostAt = nil
        lengthTwoHandHits = []
        lengthSmoothedSpan = nil
        lengthToast = nil
        lengthOpenStreak = 0
        lengthRequiresRelease = false
        lengthManualControl = false
        lengthSessionDelta = 0
        openStreak = 0
        pinchStreak = 0
        lastRawPinch = false
        undoSwipeAnchor = nil
        undoSwipeFired = false
        sessionDelta = 0
        calibration = nil
        calibrationMessage = nil
        state = GestureState()
        message = "Cámara apagada"
    }

    private func ensureConsumer() {
        guard task == nil else { return }
        let frames = camera.frames
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let detector = HandPoseDetector()
            var recognizer = GestureRecognizer()
            for await frame in frames {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard ProcessInfo.processInfo.systemUptime - frame.uptime
                        < GestureTuning.staleFrameTimeout else { continue }
                do {
                    let detection = try await detector.detect(frame)
                    let next = recognizer.update(handDetected: detection.handDetected,
                                                 landmarks: detection.landmarks,
                                                 secondaryLandmarks: detection.secondaryLandmarks)
                    await self.handleVision(next, at: frame.uptime)
                } catch {
                    await self.handleVisionError(error.localizedDescription)
                }
            }
        }
    }

    private func cameraDidFail(_ message: String) {
        self.message = message
        deactivateCamera()
    }

    // MARK: - Calibración

    /// Muestrea una fase durante ~3 s. Congela la interacción mientras tanto
    /// para no abrir sesiones accidentales con la pinza de muestra.
    public func startCalibration(phase: GestureCalibrationPhase) {
        guard running else {
            message = "Activa la cámara primero."
            return
        }
        // Ronda nueva: las medianas anteriores no se mezclan.
        openMedian = nil
        pinchMedian = nil
        calibration = GestureCalibrationRun(
            phase: phase,
            endsAt: ProcessInfo.processInfo.systemUptime + GestureCalibrationMath.window)
        calibrationMessage = "\(phase.instruction)…"
    }

    public func cancelCalibration() {
        calibration = nil
        calibrationMessage = nil
        message = "Calibración cancelada."
    }

    private func sampleCalibration(_ vision: GestureState, at uptime: TimeInterval) {
        guard var run = calibration else { return }
        if uptime >= run.endsAt {
            finishCalibration(run)
            return
        }
        if let d = vision.distance {
            run.samples.append(d)
            calibration = run
        }
    }

    private func finishCalibration(_ run: GestureCalibrationRun) {
        calibration = nil
        calibrationMessage = nil
        guard let med = GestureCalibrationMath.median(run.samples),
              run.samples.count >= GestureCalibrationMath.minimumSamples else {
            message = "Muy pocas muestras. Mejora la luz y reintenta."
            return
        }
        switch run.phase {
        case .openHand:
            openMedian = med
            message = String(format: "Abierta: %.3f. Ahora muestrea la pinza (botón 2).", med)
        case .pinch:
            pinchMedian = med
            guard let open = openMedian else {
                message = String(format: "Pinza: %.3f. Primero muestrea la mano abierta (botón 1).", med)
                return
            }
            applyCalibration(open: open, pinch: med)
        }
    }

    private func applyCalibration(open: Double, pinch: Double) {
        guard let suggested = GestureCalibrationMath.suggestedThreshold(open: open, pinch: pinch) else {
            message = "Las muestras se solapan: repite abriendo bien la mano y cerrando bien la pinza."
            return
        }
        GestureThresholds.activation = suggested.value
        message = String(format: "Umbral ajustado a %.3f (abierta %.3f · pinza %.3f).%@",
                         suggested.value, open, pinch,
                         suggested.gapWarning ? " Poca separación: acerca la mano a la cámara." : "")
    }

    // MARK: - Visión (MainActor)

    private func handleVision(_ vision: GestureState, at uptime: TimeInterval) async {
        guard running else { return }
        state = vision
        // Calibrando: solo muestrear (la interacción queda congelada).
        if calibration != nil {
            sampleCalibration(vision, at: uptime)
            return
        }
        // Sesión manual (botón): la cámara solo decora, no decide.
        // La tarjeta confirma con clic y cancela con ✕.
        if pinchManualControl {
            return
        }
        // Dos manos: el gesto de longitud tiene prioridad y suspende
        // la navegación y la pinza de una mano mientras está activo.
        if lengthSession != nil || vision.hasTwoDistinctHands {
            await handleLengthVision(vision, at: uptime)
            return
        }
        // Sin dos manos: rearmar el gesto (las detecciones viejas caducan solas).
        lengthRequiresRelease = false
        guard vision.landmarksValid else {
            await handleTrackingGap(at: uptime)
            return
        }
        resolveTrackingGap(vision)
        // Antirrebote: la pinza efectiva exige 2 frames seguidos.
        // Solo retrasa el cierre (40 ms); la apertura sigue instantánea.
        let rawPinch = vision.pinch
        let effectivePinch = rawPinch && lastRawPinch
        lastRawPinch = rawPinch
        if effectivePinch {
            openStreak = 0
            navigationX = nil
            pinchStreak += 1
            if pinchSession == nil {
                // Pinza + barrido lateral amplio = deshacer/rehacer.
                // Se evalúa antes de abrir sinónimos: pinza quieta abre la
                // tarjeta, pinza que barre ejecuta (una vez por pinza; abrir
                // los dedos rearma, como en el prototipo).
                if !undoSwipeFired, !requiresRelease,
                   let x = vision.x, x.isFinite {
                    if undoSwipeAnchor == nil {
                        undoSwipeAnchor = x
                    } else if abs(x - undoSwipeAnchor!) > GestureTuning.undoSwipeDistance {
                        if x < undoSwipeAnchor! {
                            await send(.undo)
                            message = "Deshacer"
                        } else {
                            await send(.redo)
                            message = "Rehacer"
                        }
                        undoSwipeFired = true
                        requiresRelease = true
                        pinchStreak = 0
                    }
                }
                // La sesión abre tras varios frames sostenidos: un roce
                // no abre la tarjeta y el ancla excluye el gesto de cierre.
                if pinchStreak >= GestureTuning.pinchStartFrames {
                    await tryStartSession(vision)
                }
            } else {
                await updateSession(vision)
            }
        } else if !rawPinch {
            // Apertura verificada (el frame de transición se ignora).
            pinchStreak = 0
            requiresRelease = false
            undoSwipeAnchor = nil
            undoSwipeFired = false
            if pinchSession != nil {
                // Soltar confirma: al instante si es decidido, o tras
                // 3 frames sostenidos (un parpadeo no confirma solo).
                let clearRelease = vision.event == .ended
                    && (vision.distance ?? 0) > GestureThresholds.commit
                openStreak += 1
                if clearRelease || openStreak >= 3 { await commitSession() }
            } else {
                await navigateWords(vision)
            }
        }
    }

    private func handleVisionError(_ text: String) async {
        guard running else { return }
        message = text
    }

    // MARK: - Pérdida breve de seguimiento (0.3 s de gracia)

    private func handleTrackingGap(at uptime: TimeInterval) async {
        // Sin mano verificable no hay pinza verificable: cuenta como
        // dedos abiertos para no bloquear futuros pinch.
        requiresRelease = false
        navigationX = nil
        lastRawPinch = false
        undoSwipeAnchor = nil
        undoSwipeFired = false
        guard pinchSession != nil else { return }
        if trackingLostAt == nil {
            trackingLostAt = uptime
            message = "Sin seguimiento. Mantén la mano visible."
        } else if uptime - trackingLostAt! >= GestureTuning.trackingLossGrace {
            await cancelSession(reason: "Se perdió la mano")
        }
    }

    private func resolveTrackingGap(_ vision: GestureState) {
        guard trackingLostAt != nil else { return }
        defer { trackingLostAt = nil }
        // Vuelve con pinza: conserva lo avanzado pero excluye el salto no visto.
        if vision.pinch, let x = vision.x, var s = pinchSession {
            s.referenceX += x - sessionLastHandX
            pinchSession = s
            sessionLastHandX = x
            message = "Preview: \(s.option). Mueve para elegir, suelta para confirmar."
        }
    }

    // MARK: - Sesión de sinónimos

    private func wordAtSelection() -> (word: String, range: NSRange)? {
        let full = cachedText
        guard !full.isEmpty else { return nil }
        let sel = cachedSelection
        let ranges = currentWordRanges()
        guard !ranges.isEmpty else { return nil }
        var target: NSRange?
        if sel.length > 0 {
            target = ranges.first(where: { $0 == sel })
                ?? ranges.first(where: { NSLocationInRange(sel.location, $0) })
        } else {
            target = ranges.first(where: { NSLocationInRange(sel.location, $0) })
        }
        // Sin coincidencia (caret en un espacio): la palabra más cercana.
        if target == nil {
            var bestDist = Int.max
            for r in ranges {
                let d = abs((r.location + r.length / 2) - sel.location)
                if d < bestDist { bestDist = d; target = r }
            }
            if bestDist > 20 { target = nil }
        }
        guard let r = target, let swiftRange = Range(r, in: full) else { return nil }
        let word = String(full[swiftRange])
        guard !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return (word, r)
    }

    private func tryStartSession(_ vision: GestureState) async {
        guard !requiresRelease, let x = vision.x, x.isFinite else { return }
        guard let (word, range) = wordAtSelection() else {
            // Aviso una sola vez por pinza (al abrir la ventana de inicio).
            if pinchStreak == GestureTuning.pinchStartFrames {
                message = "Selecciona una palabra con la mano abierta y haz pinza."
            }
            return
        }
        let starter = PinchStep.starterOptions(word: word, local: GestureSynonyms.alternatives(for: word))
        // Sin locales solo se abre si la IA puede generar: son justo las
        // palabras que más la necesitan. Sin IA que las genere, decirlo en
        // vez de abrir una tarjeta con la palabra sola (control falso).
        guard starter.count > 1 || synonymProvider.isAvailable else {
            let reason = synonymProvider.availabilityReason.map { " \($0)" } ?? ""
            if pinchStreak == GestureTuning.pinchStartFrames {
                message = "Sin sinónimos locales para “\(word)”. Prueba con otra palabra.\(reason)"
            }
            return
        }
        await send(.beginPreview(TextRange(location: range.location, length: range.length)))
        // La palabra objetivo queda seleccionada: se ve qué va a cambiar.
        await send(.selectRange(TextRange(location: range.location, length: range.length)))
        pinchSession = PinchSession(id: UUID(), word: word, location: range.location,
                                    alternatives: starter,
                                    currentIndex: starter.firstIndex(of: word) ?? 0,
                                    referenceX: x)
        sessionLastHandX = x
        sessionDelta = 0
        sessionUpgraded = false
        openStreak = 0
        message = starter.count > 1
            ? "Pinza: mueve para elegir, suelta para confirmar."
            : "Buscando sinónimos con IA… mantén la pinza."
        fetchUpgrade(sessionId: pinchSession!.id, word: word)
    }

    private func updateSession(_ vision: GestureState) async {
        guard var s = pinchSession, vision.event == .changed,
              let x = vision.x, x.isFinite else { return }
        sessionLastHandX = x
        let delta = x - s.referenceX
        sessionDelta = delta
        guard let out = PinchStep.advance(current: s.currentIndex, count: s.alternatives.count,
                                          delta: delta, reference: s.referenceX) else { return }
        s.referenceX = out.reference
        if out.index != s.currentIndex {
            s.currentIndex = out.index
            pinchSession = s
            await send(.showPreview(s.option))
            message = "Preview: \(s.option)"
        } else {
            pinchSession = s
            message = out.index == 0
                ? "Primera opción. Mueve a la derecha para avanzar."
                : "Última opción. Mueve a la izquierda para volver."
        }
    }

    private func commitSession() async {
        guard let s = pinchSession else { return }
        pinchSession = nil
        pinchManualControl = false
        trackingLostAt = nil
        openStreak = 0
        sessionDelta = 0
        upgradeTask?.cancel()
        upgradeTask = nil
        // Tras confirmar hay que reabrir los dedos para otra sesión
        // (evita que un clic en la tarjeta reabra la pinza sostenida).
        requiresRelease = true
        await send(.commitPreview)
        message = (s.option == s.word) ? "Sin cambios" : "Confirmado: \(s.option)"
    }

    /// Confirma directamente una opción de la tarjeta (clic).
    public func commitPinchSession(at index: Int) async {
        guard var s = pinchSession, s.alternatives.indices.contains(index) else { return }
        s.currentIndex = index
        pinchSession = s
        await send(.showPreview(s.option))
        await commitSession()
    }

    private func cancelSession(reason: String) async {
        pinchSession = nil
        pinchManualControl = false
        trackingLostAt = nil
        openStreak = 0
        sessionDelta = 0
        upgradeTask?.cancel()
        upgradeTask = nil
        requiresRelease = true
        await send(.cancelPreview)
        message = "Cancelado: \(reason). Abre los dedos antes de otro pinch."
    }

    /// Cancela la sesión (cambio de documento, cámara detenida).
    public func cancelPinchSession() {
        if pinchSession != nil {
            let pinch = pinchSession
            pinchSession = nil
            pinchManualControl = false
            trackingLostAt = nil
            openStreak = 0
            sessionDelta = 0
            upgradeTask?.cancel()
            upgradeTask = nil
            requiresRelease = true
            Task { await send(.cancelPreview) }
            _ = pinch
        }
        cancelLengthSession()
        lengthToast = nil
    }

    /// Abre la sesión de sinónimos sin cámara (botón o menú).
    /// Sirve para probar la lista aislando el gesto, y como
    /// alternativa accesible a la pinza. La tarjeta la dirige:
    /// clic confirma, ✕ cancela.
    public func startPinchSessionManually() async {
        guard pinchSession == nil, lengthSession == nil else {
            message = "Ya hay una sesión de gesto activa."
            return
        }
        guard let (word, range) = wordAtSelection() else {
            message = "Coloca el cursor en una palabra primero."
            return
        }
        let starter = PinchStep.starterOptions(word: word, local: GestureSynonyms.alternatives(for: word))
        guard starter.count > 1 || synonymProvider.isAvailable else {
            let reason = synonymProvider.availabilityReason.map { " \($0)" } ?? ""
            message = "Sin sinónimos locales para “\(word)”. Prueba con otra palabra.\(reason)"
            return
        }
        await send(.beginPreview(TextRange(location: range.location, length: range.length)))
        await send(.selectRange(TextRange(location: range.location, length: range.length)))
        pinchSession = PinchSession(id: UUID(), word: word, location: range.location,
                                    alternatives: starter,
                                    currentIndex: starter.firstIndex(of: word) ?? 0,
                                    referenceX: 0)
        sessionLastHandX = 0
        sessionDelta = 0
        sessionUpgraded = false
        openStreak = 0
        pinchStreak = 0
        pinchManualControl = true
        message = starter.count > 1
            ? "Elige un sinónimo en la tarjeta para confirmar, o ✕ para cancelar."
            : "Buscando sinónimos con IA…"
        fetchUpgrade(sessionId: pinchSession!.id, word: word)
    }

    /// Sinónimos reales (IA on-device) que mejoran la lista local si llegan
    /// a tiempo. Sin modelo disponible el proveedor devuelve vacío y la
    /// tarjeta conserva los locales diciendo que son locales.
    private func fetchUpgrade(sessionId: UUID, word: String) {
        upgradeTask?.cancel()
        upgradeTask = Task { [weak self] in
            let fresh = await self?.synonymProvider.synonyms(for: word) ?? []
            await self?.applyUpgrade(fresh, sessionId: sessionId, word: word)
        }
    }

    /// Mejora con sinónimos frescos: se aplica aunque el usuario ya se
    /// moviera (se conserva su elección si sigue en la lista). Si la sesión
    /// ya cerró, se descarta en silencio. Si no llegó mejora y la lista era
    /// solo la palabra, se cierra con mensaje (con la pinza aún cerrada el
    /// `requiresRelease` evita que se reabra sola).
    private func applyUpgrade(_ fresh: [String], sessionId: UUID, word: String) async {
        guard var s = pinchSession, s.id == sessionId else { return }
        if fresh.isEmpty {
            if s.alternatives.count <= 1 {
                await cancelSession(reason: "La IA no devolvió sinónimos para “\(word)”")
            }
            return
        }
        let merged = PinchStep.mergedOptions(word: word, fresh: fresh)
        guard merged != s.alternatives else { return }
        let currentOption = s.option
        s.alternatives = merged
        s.currentIndex = merged.firstIndex(of: currentOption) ?? 0
        pinchSession = s
        sessionUpgraded = true
        Task { await send(.showPreview(s.option)) }
        message = "Sinónimos listos. Mueve para elegir, suelta para confirmar."
    }

    // MARK: - Sesión a dos manos (longitud del párrafo)

    /// Suavizado exponencial de la separación entre manos.
    /// Con la señal congelada (sin medida nueva) devuelve el último valor:
    /// durante pérdidas de seguimiento no se hereda ningún brinco.
    private func smoothedLengthSpan(raw: Double?) -> Double? {
        guard let raw, raw.isFinite else { return lengthSmoothedSpan }
        if let prev = lengthSmoothedSpan {
            lengthSmoothedSpan = prev + GestureTuning.lengthSmoothing * (raw - prev)
        } else {
            lengthSmoothedSpan = raw
        }
        return lengthSmoothedSpan
    }

    /// Puerta del gesto doble: exige varias detecciones con ambas manos
    /// dentro de una ventana corta (un cruce aislado o un parpadeo no abren
    /// ni reinician la cuenta). Mientras hay sesión, retirar UNA mano
    /// confirma; perder AMBAS manos restaura el párrafo (nunca confirma
    /// a ciegas: lo no visto no se aplica).
    /// Interna para pruebas (@testable): simulan detecciones sin cámara.
    func handleLengthVision(_ vision: GestureState, at uptime: TimeInterval) async {
        // Sesión manual (botón): la cámara solo decora, no decide.
        guard !lengthManualControl else { return }
        guard vision.landmarksValid else {
            await handleLengthTrackingGap(at: uptime)
            return
        }
        // Suavizar una sola vez por frame válido.
        let span = smoothedLengthSpan(raw: vision.handSpan)
        if lengthTrackingLostAt != nil {
            // Vuelve tras perder frames: conserva lo avanzado pero excluye
            // el salto no observado (igual que la pinza de una mano).
            lengthTrackingLostAt = nil
            if var s = lengthSession, let span {
                s.referenceSpan += span - lengthLastSpan
                lengthSession = s
                lengthLastSpan = span
            }
        }
        if vision.hasTwoDistinctHands {
            lengthTwoHandHits.append(uptime)
            lengthTwoHandHits.removeAll { uptime - $0 > GestureTuning.twoHandWindow }
            lengthOpenStreak = 0
        } else if lengthSession != nil {
            // Sesión activa y solo una mano: contar hacia confirmar.
            lengthOpenStreak += 1
            if lengthOpenStreak >= GestureTuning.lengthCommitFrames {
                await commitLengthSession()
            } else {
                message = "Retira una mano para confirmar (las dos cancela)."
            }
            return
        } else {
            return
        }
        let hits = min(lengthTwoHandHits.count, GestureTuning.twoHandStartFrames)
        let ready = lengthSession != nil
            || (!lengthRequiresRelease && pinchSession == nil
                && lengthTwoHandHits.count >= GestureTuning.twoHandStartFrames)
        guard ready else {
            if pinchSession != nil {
                message = "Termina la pinza de una mano primero (suelta para confirmar)."
            } else if lengthRequiresRelease {
                message = "Separa las manos antes de otro gesto de longitud."
            } else {
                message = "Dos manos \(hits)/\(GestureTuning.twoHandStartFrames)… mantén la posición."
            }
            return
        }
        if lengthSession == nil {
            // Un gesto cada vez: la sesión de palabra sigue intacta.
            guard pinchSession == nil else { return }
            guard let span else { return }
            await tryStartLengthSession(span: span)
        } else {
            guard let span else { return }
            await updateLengthSession(span: span)
        }
    }

    private func handleLengthTrackingGap(at uptime: TimeInterval) async {
        lengthRequiresRelease = false
        lastRawPinch = false
        guard lengthSession != nil else { return }
        if lengthTrackingLostAt == nil {
            lengthTrackingLostAt = uptime
            message = "Sin seguimiento. Mantén ambas manos visibles."
        } else if uptime - lengthTrackingLostAt! >= GestureTuning.trackingLossGrace {
            // Manos perdidas del todo: se restaura el párrafo original.
            // Solo confirma lo que se ve: retirar UNA mano.
            await cancelLengthSession(reason: "Se perdieron las manos; párrafo restaurado")
        }
    }

    private func paragraphForLength() -> (text: String, range: NSRange)? {
        let full = cachedText as NSString
        guard full.length > 0 else { return nil }
        let caret = min(max(cachedSelection.location, 0), full.length - 1)
        var para = full.paragraphRange(for: NSRange(location: caret, length: 0))
        while para.length > 0, NSMaxRange(para) <= full.length,
              full.character(at: NSMaxRange(para) - 1) == 10 {
            para.length -= 1
        }
        let text = full.substring(with: para).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return (full.substring(with: para), para)
    }

    private func tryStartLengthSession(span: Double) async {
        guard !lengthRequiresRelease, span.isFinite else { return }
        guard let (text, range) = paragraphForLength() else {
            message = "Coloca el cursor en un párrafo y muestra las dos manos."
            return
        }
        // Alternativa local inmediata (la media es el original exacto).
        let starter = GestureSynonyms.lengthVariants(for: text)
        guard starter.count == 3 else { return }
        await send(.beginPreview(TextRange(location: range.location, length: range.length)))
        await send(.selectRange(TextRange(location: range.location, length: range.length)))
        lengthSession = LengthSession(id: UUID(), originalText: text, originalLocation: range.location,
                                      alternatives: starter,
                                      currentIndex: LengthLevel.medio.rawValue,
                                      referenceSpan: span)
        lengthLastSpan = span
        lengthSessionDelta = 0
        lengthOpenStreak = 0
        lengthManualControl = false
        // La pinza de una mano queda desarmada: al volver a una mano se
        // confirma la longitud en vez de abrir sinónimos por accidente.
        pinchStreak = 0
        openStreak = 0
        lastRawPinch = false
        navigationX = nil
        lengthToast = nil
        message = "Longitud · medio. Acerca para acortar, separa para ampliar. Retira UNA mano para confirmar."
    }

    private func updateLengthSession(span: Double) async {
        guard var s = lengthSession, span.isFinite else { return }
        lengthLastSpan = span
        let delta = span - s.referenceSpan
        lengthSessionDelta = delta
        guard let out = LengthSpanStep.advance(current: s.currentIndex, count: s.alternatives.count,
                                               delta: delta, reference: s.referenceSpan,
                                               maxSteps: 1) else { return }
        s.referenceSpan = out.reference
        if out.index != s.currentIndex {
            s.currentIndex = out.index
            lengthSession = s
            await send(.showPreview(s.option))
            let level = LengthLevel(rawValue: out.index)?.label ?? ""
            message = "Longitud · \(level). Retira UNA mano para confirmar."
        } else {
            lengthSession = s
            message = out.index == 0
                ? "Versión más corta. Separa las manos para ampliar."
                : "Versión más larga. Acerca las manos para acortar."
        }
    }

    private func commitLengthSession() async {
        guard let s = lengthSession else { return }
        lengthSession = nil
        lengthTrackingLostAt = nil
        lengthTwoHandHits = []
        lengthSmoothedSpan = nil
        lengthOpenStreak = 0
        lengthSessionDelta = 0
        lengthManualControl = false
        // Tras confirmar hay que separar las manos para otra sesión.
        lengthRequiresRelease = true
        pinchStreak = 0
        lastRawPinch = false
        // La mano restante puede seguir en pinza: no debe abrir sinónimos.
        requiresRelease = true
        await send(.commitPreview)
        if s.option != s.originalText {
            let level = LengthLevel(rawValue: s.currentIndex)?.label ?? ""
            message = "Confirmado · \(level). ⌘Z para deshacer."
            lengthToast = "Párrafo en versión \(level)"
            lengthToastCanUndo = true
        } else {
            message = "Sin cambios"
            let words = s.option.split(whereSeparator: \.isWhitespace).count
            let origWords = s.originalText.split(whereSeparator: \.isWhitespace).count
            lengthToast = "Sin cambios: \(LengthLevel(rawValue: s.currentIndex)?.label ?? "esa versión") tiene \(words) pal., igual que tu texto (\(origWords))"
            lengthToastCanUndo = false
        }
    }

    /// Confirma directamente un nivel de la tarjeta (clic).
    /// Sin silencios: si no se puede aplicar, se dice en voz alta (toast).
    public func commitLengthSession(at index: Int) async {
        guard var s = lengthSession else {
            lengthToast = "La sesión ya no está activa; vuelve a abrirla"
            lengthToastCanUndo = false
            return
        }
        guard s.alternatives.indices.contains(index) else { return }
        s.currentIndex = index
        lengthSession = s
        await send(.showPreview(s.option))
        await commitLengthSession()
    }

    private func cancelLengthSession(reason: String) async {
        lengthSession = nil
        lengthTrackingLostAt = nil
        lengthOpenStreak = 0
        lengthTwoHandHits = []
        lengthSmoothedSpan = nil
        lengthSessionDelta = 0
        lengthManualControl = false
        lengthToast = nil
        lengthRequiresRelease = true
        requiresRelease = true
        await send(.cancelPreview)
        message = "Cancelado: \(reason). Separa las manos antes de otro gesto."
    }

    /// Cancela la sesión de longitud (cambio de documento, cámara detenida).
    public func cancelLengthSession() {
        if lengthSession != nil {
            lengthSession = nil
            lengthTrackingLostAt = nil
            lengthOpenStreak = 0
            lengthTwoHandHits = []
            lengthSmoothedSpan = nil
            lengthSessionDelta = 0
            lengthManualControl = false
            lengthRequiresRelease = true
            requiresRelease = true
            Task { await send(.cancelPreview) }
        }
    }

    /// Abre la sesión de longitud sin cámara (botón del panel).
    /// Sirve para probar la generación aislando el gesto, y como
    /// alternativa accesible al gesto a dos manos.
    public func startLengthSessionManually() async {
        guard lengthSession == nil, pinchSession == nil else {
            message = "Ya hay una sesión de gesto activa."
            return
        }
        guard let (text, range) = paragraphForLength() else {
            message = "Coloca el cursor en un párrafo primero."
            return
        }
        let starter = GestureSynonyms.lengthVariants(for: text)
        guard starter.count == 3 else { return }
        await send(.beginPreview(TextRange(location: range.location, length: range.length)))
        await send(.selectRange(TextRange(location: range.location, length: range.length)))
        lengthSession = LengthSession(id: UUID(), originalText: text, originalLocation: range.location,
                                      alternatives: starter,
                                      currentIndex: LengthLevel.medio.rawValue,
                                      referenceSpan: state.handSpan ?? 0)
        lengthManualControl = true
        lengthSessionDelta = 0
        lengthSmoothedSpan = nil
        lengthToast = nil
        navigationX = nil
        message = "Elige un nivel en la tarjeta para confirmar, o ✕ para cancelar."
    }

    /// Cierra el aviso de longitud confirmada (sin tocar el texto).
    public func dismissLengthToast() { lengthToast = nil }

    /// Revierte el último cambio de longitud confirmado con el gesto.
    public func undoLengthCommit() async {
        await send(.undo)
        lengthToast = nil
    }

    // MARK: - Selección de palabra con mano abierta

    private func navigateWords(_ vision: GestureState) async {
        // Sin puerta de distancia: si el estado dice "no pinza", se navega.
        // La histéresis del reconocedor ya evita el aleteo en la frontera.
        guard vision.event != .ended,
              let hand = vision.landmarks, hand.isValid,
              let x = vision.x, x.isFinite, (0...1).contains(x) else {
            navigationX = nil
            return
        }
        let ranges = currentWordRanges()
        guard !ranges.isEmpty else {
            navigationX = nil
            return
        }
        let selection = cachedSelection
        guard let out = WordNavigator.update(
            ranges: ranges, selection: selection,
            referenceX: navigationX, handX: x
        ) else { return }
        navigationX = out.referenceX
        cachedSelection = out.select
        await send(.selectRange(TextRange(location: out.select.location, length: out.select.length)))
    }
}
