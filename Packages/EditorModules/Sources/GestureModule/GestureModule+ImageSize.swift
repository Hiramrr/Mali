import EditorCore
import Foundation

extension GestureModule {
    // MARK: - Ancho de imagen (mismo gesto a dos manos sobre una imagen)

    func imageAtSelection() -> (MarkdownImage, NSRange)? {
        let full = cachedText as NSString
        guard full.length > 0 else { return nil }
        let caret = min(max(cachedSelection.location, 0), full.length - 1)
        var range = full.paragraphRange(for: NSRange(location: caret, length: 0))
        if range.length > 0, full.character(at: NSMaxRange(range) - 1) == 10 { range.length -= 1 }
        guard caret < NSMaxRange(range),
              let image = MarkdownImage(line: full.substring(with: range)) else { return nil }
        return (image, range)
    }

    func imageAtRange(_ range: NSRange) -> (MarkdownImage, NSRange)? {
        let full = cachedText as NSString
        guard range.location >= 0, NSMaxRange(range) <= full.length,
              let image = MarkdownImage(line: full.substring(with: range)) else { return nil }
        return (image, range)
    }

    /// ¿La palabra candidata está dentro del párrafo de una imagen?
    /// Evita que `![alt](ruta "width=..")` se trate como texto con sinónimos:
    /// cualquier fragmento (alt, ruta, width, align) rompería el markdown al confirmar.
    func wordIsInsideImage(_ wordRange: NSRange) -> Bool {
        let full = cachedText as NSString
        guard wordRange.location >= 0, NSMaxRange(wordRange) <= full.length else { return false }
        var para = full.paragraphRange(for: wordRange)
        if para.length > 0, NSMaxRange(para) <= full.length,
           full.character(at: NSMaxRange(para) - 1) == 10 {
            para.length -= 1
        }
        guard para.length > 0, NSMaxRange(para) <= full.length else { return false }
        return MarkdownImage(line: full.substring(with: para)) != nil
    }

    func startImageSizeSession(image: MarkdownImage, range: NSRange,
                                       span: Double, manual: Bool) async {
        await send(.beginPreview(TextRange(location: range.location, length: range.length)))
        await send(.selectRange(TextRange(location: range.location, length: range.length)))
        imageSizeSession = ImageSizeSession(original: image,
                                             originalText: (cachedText as NSString).substring(with: range),
                                             location: range.location,
                                             width: image.width, referenceSpan: span)
        imageManualControl = manual
        lengthLastSpan = span
        lengthOpenStreak = 0
        lengthSessionDelta = 0
        lengthToast = nil
        pinchStreak = 0
        lastRawPinch = false
        navigationX = nil
        message = "Imagen · ancho \(image.width). Acerca para reducir, separa para ampliar."
    }

    func updateImageSizeSession(span: Double) async {
        guard var s = imageSizeSession, span.isFinite else { return }
        lengthLastSpan = span
        let delta = span - s.referenceSpan
        lengthSessionDelta = delta
        let steps = min(2, max(-2, Int(delta / (GestureTuning.lengthSpanStep / 2))))
        guard steps != 0 else { return }
        s.referenceSpan += Double(steps) * GestureTuning.lengthSpanStep / 2
        imageSizeSession = s
        await setImageWidth(s.width + steps * 40)
    }

    public func setImageWidth(_ width: Int) async {
        guard var s = imageSizeSession else { return }
        let next = min(1200, max(80, width))
        guard next != s.width else { return }
        s.width = next
        imageSizeSession = s
        await send(.showPreview(s.markdown))
        message = "Imagen · ancho \(next). Retira una mano para confirmar."
    }

    func commitImageSizeSession() async {
        await finishImageSizeSession(commit: true)
    }

    public func confirmImageSizeSession() async {
        guard imageSizeSession != nil else { return }
        await commitImageSizeSession()
    }

    func finishImageSizeSession(commit: Bool) async {
        guard let s = imageSizeSession else { return }
        imageSizeSession = nil
        imageManualControl = false
        lengthTrackingLostAt = nil
        lengthTwoHandHits = []
        lengthSmoothedSpan = nil
        lengthOpenStreak = 0
        lengthSessionDelta = 0
        lengthRequiresRelease = true
        requiresRelease = true
        await send(commit ? .commitPreview : .cancelPreview)
        message = commit ? "Imagen · ancho \(s.width) confirmado. ⌘Z para deshacer."
                         : "Tamaño de imagen cancelado."
        if commit {
            lengthToast = s.width == s.original.width ? "Imagen sin cambios" : "Imagen · ancho \(s.width)"
            lengthToastCanUndo = s.width != s.original.width
        }
    }

    public func cancelImageSizeSession() {
        guard imageSizeSession != nil else { return }
        imageSizeSession = nil
        imageManualControl = false
        lengthTrackingLostAt = nil
        lengthTwoHandHits = []
        lengthSmoothedSpan = nil
        lengthOpenStreak = 0
        lengthSessionDelta = 0
        lengthRequiresRelease = true
        requiresRelease = true
        Task { await send(.cancelPreview) }
    }

    public func startImageSizeSessionManually() async {
        guard imageSizeSession == nil, lengthSession == nil, pinchSession == nil else {
            message = "Ya hay una sesión de gesto activa."
            return
        }
        guard let (image, range) = imageAtSelection() else {
            message = "Coloca el cursor en una imagen primero."
            return
        }
        await startImageSizeSession(image: image, range: range,
                                    span: state.handSpan ?? 0, manual: true)
    }
}
