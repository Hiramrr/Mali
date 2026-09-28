import EditorCore
import Foundation

extension GestureModule {
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
        guard !lengthManualControl, !imageManualControl else { return }
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
            if let span {
                if var s = lengthSession {
                    s.referenceSpan += span - lengthLastSpan
                    lengthSession = s
                } else if var s = imageSizeSession {
                    s.referenceSpan += span - lengthLastSpan
                    imageSizeSession = s
                }
                lengthLastSpan = span
            }
        }
        if vision.hasTwoDistinctHands {
            lengthTwoHandHits.append(uptime)
            lengthTwoHandHits.removeAll { uptime - $0 > GestureTuning.twoHandWindow }
            lengthOpenStreak = 0
        } else if lengthSession != nil || imageSizeSession != nil {
            // Sesión activa y solo una mano: contar hacia confirmar.
            lengthOpenStreak += 1
            if lengthOpenStreak >= GestureTuning.lengthCommitFrames {
                if imageSizeSession != nil { await commitImageSizeSession() }
                else { await commitLengthSession() }
            } else {
                message = "Retira una mano para confirmar (las dos cancela)."
            }
            return
        } else {
            return
        }
        let hits = min(lengthTwoHandHits.count, GestureTuning.twoHandStartFrames)
        let ready = lengthSession != nil || imageSizeSession != nil
            || (!lengthRequiresRelease && pinchSession == nil
                && lengthTwoHandHits.count >= GestureTuning.twoHandStartFrames)
        guard ready else {
            if pinchSession != nil {
                message = "Termina la pinza de una mano primero (suelta para confirmar)."
            } else if lengthRequiresRelease {
                message = "Separa las manos antes de otro gesto de dos manos."
            } else {
                message = "Dos manos \(hits)/\(GestureTuning.twoHandStartFrames)… mantén la posición."
            }
            return
        }
        if lengthSession == nil && imageSizeSession == nil {
            // Un gesto cada vez: la sesión de palabra sigue intacta.
            guard pinchSession == nil else { return }
            guard let span else { return }
            if let (image, range) = pointedImageRange.flatMap(imageAtRange) ?? imageAtSelection() {
                await startImageSizeSession(image: image, range: range, span: span, manual: false)
            } else {
                await tryStartLengthSession(span: span)
            }
        } else if imageSizeSession != nil {
            guard let span else { return }
            await updateImageSizeSession(span: span)
        } else {
            guard let span else { return }
            await updateLengthSession(span: span)
        }
    }

    private func handleLengthTrackingGap(at uptime: TimeInterval) async {
        lengthRequiresRelease = false
        lastRawPinch = false
        guard lengthSession != nil || imageSizeSession != nil else { return }
        // Mientras genera no se cancela por perder las manos: la IA sigue
        // en segundo plano y al volver la sesión sigue viva.
        if lengthLoading, lengthSession != nil {
            message = "Generando versiones… mantén ambas manos visibles, medio ya disponible."
            return
        }
        if lengthTrackingLostAt == nil {
            lengthTrackingLostAt = uptime
            message = "Sin seguimiento. Mantén ambas manos visibles."
        } else if uptime - lengthTrackingLostAt! >= GestureTuning.trackingLossGrace {
            // Manos perdidas del todo: se restaura el párrafo original.
            // Solo confirma lo que se ve: retirar UNA mano.
            if imageSizeSession != nil {
                await finishImageSizeSession(commit: false)
                message = "Se perdieron las manos; imagen restaurada."
            } else {
                await cancelLengthSession(reason: "Se perdieron las manos; párrafo restaurado")
            }
        }
    }

    private func paragraphForLength() -> (text: String, range: NSRange)? {
        guard imageAtSelection() == nil else { return nil }
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
        guard lengthProvider.isAvailable else {
            message = "No se puede cambiar la longitud. \(lengthProvider.availabilityReason ?? "Modelo de IA no disponible.")"
            lengthToast = message
            lengthToastCanUndo = false
            lengthRequiresRelease = true
            return
        }
        await send(.beginPreview(TextRange(location: range.location, length: range.length)))
        await send(.selectRange(TextRange(location: range.location, length: range.length)))
        lengthSession = LengthSession(id: UUID(), originalText: text, originalLocation: range.location,
                                      alternatives: [text, text, text],
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
        // Reuso instantáneo: el mismo párrafo no regenera.
        if let cached = lengthCache[text], cached.count == 2,
           GestureSynonyms.isValidShort(cached[0], original: text),
           GestureSynonyms.isValidLong(cached[1], original: text) {
            lengthSession?.alternatives = [cached[0], text, cached[1]]
            lengthLoading = false
            message = "Versiones listas (reusadas). Acerca para acortar, separa para ampliar. Retira una mano para confirmar."
            return
        }
        lengthLoading = true
        message = "Preparando versiones corta y larga… Puedes quedarte en medio mientras tanto."
        fetchLengthVariants(sessionId: lengthSession!.id, text: text)
    }

    private func fetchLengthVariants(sessionId: UUID, text: String) {
        lengthTask?.cancel()
        lengthTask = Task { [weak self] in
            guard let self else { return }
            let variants = await lengthProvider.variants(for: text)
            await applyLengthVariants(variants, sessionId: sessionId)
        }
    }

    private func applyLengthVariants(_ variants: [String], sessionId: UUID) async {
        guard var s = lengthSession, s.id == sessionId else { return }
        guard variants.count == 2,
              GestureSynonyms.isValidShort(variants[0], original: s.originalText),
              GestureSynonyms.isValidLong(variants[1], original: s.originalText) else {
            await cancelLengthSession(reason: "no se pudieron crear versiones útiles; prueba con otro párrafo")
            lengthToast = "No se pudieron crear versiones útiles. Prueba con otro párrafo."
            lengthToastCanUndo = false
            return
        }
        s.alternatives = [variants[0], s.originalText, variants[1]]
        // Guarda para reuso: reabrir el mismo párrafo es instantáneo.
        lengthCache[s.originalText] = [variants[0], variants[1]]
        if lengthCache.count > 30 {
            lengthCache.removeValue(forKey: lengthCache.keys.first ?? "")
        }
        // Si el usuario ya se movió a un extremo mientras cargaba, conserva
        // su posición y previsualízala; si no, queda en medio.
        let keptIndex = s.currentIndex
        lengthSession = s
        lengthLoading = false
        if keptIndex != LengthLevel.medio.rawValue {
            lengthSession?.currentIndex = keptIndex
            await send(.showPreview(s.alternatives[keptIndex]))
        }
        message = "Versiones listas. Acerca para acortar, separa para ampliar. Retira una mano para confirmar."
    }

    private func updateLengthSession(span: Double) async {
        guard var s = lengthSession, span.isFinite else { return }
        lengthLastSpan = span
        let delta = span - s.referenceSpan
        lengthSessionDelta = delta
        guard let out = LengthSpanStep.advance(current: s.currentIndex, count: s.alternatives.count,
                                               delta: delta, reference: s.referenceSpan,
                                               maxSteps: 1) else { return }
        // Mientras carga solo se puede volver al medio (original): los
        // extremos aún no existen y no se previsualiza texto a medias.
        if lengthLoading, out.index != LengthLevel.medio.rawValue { return }
        s.referenceSpan = out.reference
        if out.index != s.currentIndex {
            s.currentIndex = out.index
            lengthSession = s
            await send(.showPreview(s.option))
            let level = LengthLevel(rawValue: out.index)?.label ?? ""
            message = lengthLoading
                ? "Longitud · \(level) (tu texto) mientras se generan las versiones."
                : "Longitud · \(level). Retira UNA mano para confirmar."
        } else {
            lengthSession = s
            message = out.index == 0
                ? "Versión más corta. Separa las manos para ampliar."
                : "Versión más larga. Acerca las manos para acortar."
        }
    }

    private func commitLengthSession() async {
        guard let s = lengthSession else { return }
        if lengthLoading {
            // Confirmar el medio (original) no necesita esperar: no hay
            // cambio que generar. Otro nivel sí debe esperar.
            guard s.currentIndex == LengthLevel.medio.rawValue else {
                message = "Aún generando versiones… espera o elige medio para salir sin cambios."
                return
            }
        }
        lengthSession = nil
        lengthTask?.cancel()
        lengthTask = nil
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
    /// El medio (original) confirma incluso mientras carga: no hay espera.
    public func commitLengthSession(at index: Int) async {
        guard var s = lengthSession else {
            lengthToast = "La sesión ya no está activa; vuelve a abrirla"
            lengthToastCanUndo = false
            return
        }
        guard s.alternatives.indices.contains(index) else { return }
        if lengthLoading, index != LengthLevel.medio.rawValue { return }
        s.currentIndex = index
        lengthSession = s
        await send(.showPreview(s.option))
        await commitLengthSession()
    }

    /// Previsualiza un nivel sin confirmar: el usuario puede comparar
    /// corto/medio/largo antes de decidir. Confirmar es explícito
    /// (botón Confirmar o retirar una mano). No cierra la sesión.
    public func previewLengthOption(at index: Int) async {
        guard var s = lengthSession, s.alternatives.indices.contains(index) else { return }
        if lengthLoading, index != LengthLevel.medio.rawValue { return }
        guard index != s.currentIndex else { return }
        s.currentIndex = index
        lengthSession = s
        await send(.showPreview(s.option))
        let level = LengthLevel(rawValue: index)?.label ?? ""
        message = "Longitud · \(level) en vista previa. Confirma o sigue comparando."
    }

    /// Confirmación explícita del nivel previsualizado (botón Confirmar).
    public func confirmLengthSession() async {
        await commitLengthSession()
    }

    func cancelLengthSession(reason: String) async {
        lengthSession = nil
        lengthTask?.cancel()
        lengthTask = nil
        lengthLoading = false
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
            lengthTask?.cancel()
            lengthTask = nil
            lengthLoading = false
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
        guard lengthSession == nil, pinchSession == nil, imageSizeSession == nil else {
            message = "Ya hay una sesión de gesto activa."
            return
        }
        guard let (text, range) = paragraphForLength() else {
            message = "Coloca el cursor en un párrafo primero."
            return
        }
        guard lengthProvider.isAvailable else {
            message = "No se puede cambiar la longitud. \(lengthProvider.availabilityReason ?? "Modelo de IA no disponible.")"
            lengthToast = message
            lengthToastCanUndo = false
            return
        }
        await send(.beginPreview(TextRange(location: range.location, length: range.length)))
        await send(.selectRange(TextRange(location: range.location, length: range.length)))
        lengthSession = LengthSession(id: UUID(), originalText: text, originalLocation: range.location,
                                      alternatives: [text, text, text],
                                      currentIndex: LengthLevel.medio.rawValue,
                                      referenceSpan: state.handSpan ?? 0)
        lengthManualControl = true
        lengthSessionDelta = 0
        lengthSmoothedSpan = nil
        lengthToast = nil
        navigationX = nil
        if let cached = lengthCache[text], cached.count == 2,
           GestureSynonyms.isValidShort(cached[0], original: text),
           GestureSynonyms.isValidLong(cached[1], original: text) {
            lengthSession?.alternatives = [cached[0], text, cached[1]]
            lengthLoading = false
            message = "Versiones listas (reusadas). Compara y confirma."
            return
        }
        lengthLoading = true
        message = "Preparando versiones corta y larga… Puedes ver tu texto en medio mientras tanto."
        fetchLengthVariants(sessionId: lengthSession!.id, text: text)
    }

    /// Cierra el aviso de longitud confirmada (sin tocar el texto).
    public func dismissLengthToast() { lengthToast = nil }

    /// Revierte el último cambio de longitud confirmado con el gesto.
    public func undoLengthCommit() async {
        await send(.undo)
        lengthToast = nil
    }
}
