import AppKit
import Observation
import EditorCore
import DesignSystem

@MainActor @Observable
public final class EditorSession {
    public var focusMode = false
    public var paragraphFocus = false
    public var typewriterMode = false
    public var readingMode = false
    public private(set) var headings: [DocumentHeading] = []
    public private(set) var statistics = DocumentStatistics()
    public private(set) var selectedCharacters = 0
    public private(set) var selectedWords = 0
    public private(set) var cursorOffset = 0
    public private(set) var analysisRevision = 0
    @ObservationIgnored public weak var textView: NSTextView?
    @ObservationIgnored public private(set) var analysis = MarkdownDocument("")
    @ObservationIgnored private var outlineTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    // Previsualización atómica (gestos). Mientras está activa, el texto del
    // NSTextView muestra una opción provisional: el binding, el autosave y el
    // índice la ignoran (ver NativeTextEditor), y el undo no se ensucia.
    // `onPreviewCommitted` sincroniza el binding al terminar.
    @ObservationIgnored public private(set) var isPreviewing = false
    @ObservationIgnored public var onPreviewCommitted: ((String) -> Void)?
    @ObservationIgnored private var previewLocation = 0
    @ObservationIgnored private var previewOriginal = ""
    @ObservationIgnored private var previewCurrent = ""
    @ObservationIgnored private var previewLength = 0

    public init() {}

    public func refreshOutline(_ text: String) {
        generation += 1
        let revision = generation
        outlineTask?.cancel()
        outlineTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            let analysis = await Self.analyze(text)
            guard !Task.isCancelled, let self, self.generation == revision,
                  !self.isPreviewing, self.textView?.string == text else { return }
            self.analysis = analysis
            self.headings = analysis.headings
            self.statistics = analysis.statistics
            self.analysisRevision += 1
            (self.textView as? WritingTextView)?.applyAnalysis(analysis)
        }
    }

    private nonisolated static func analyze(_ text: String) async -> MarkdownDocument {
        MarkdownDocument(text)
    }

    public func selectionChanged() {
        guard let view = textView else { return }
        cursorOffset = view.selectedRange().location
        let range = view.selectedRange()
        let selectedText = range.length == 0 ? "" : (view.string as NSString).substring(with: range)
        selectedCharacters = selectedText.count
        var words = 0
        selectedText.enumerateSubstrings(in: selectedText.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            words += 1
        }
        selectedWords = words
        (view as? WritingTextView)?.updateParagraphHighlight()
    }

    public func stop() {
        if isPreviewing { endPreview() }
        onPreviewCommitted = nil
        outlineTask?.cancel()
        outlineTask = nil
        textView = nil
    }

    public func send(_ command: EditorCommand) {
        guard !readingMode, let view = textView else { return }
        switch command {
        case .insertText(let text):
            edit(view) { $0.insertText(text, replacementRange: $0.selectedRange()) }
        case .replaceSelection(let text):
            // Solo con selección real: sin ella sería una inserción fantasma.
            guard view.selectedRange().length > 0 else { return }
            edit(view) { $0.insertText(text, replacementRange: $0.selectedRange()) }
        case .selectRange(let range):
            guard let valid = range.validated(in: view.string) else { return }
            view.setSelectedRange(valid)
            view.scrollRangeToVisible(valid)
        case .selectAll: view.selectAll(nil)
        case .deleteBackward: view.deleteBackward(nil)
        case .deleteForward: view.deleteForward(nil)
        case .undo: view.undoManager?.undo()
        case .redo: view.undoManager?.redo()
        case .toggleBold: edit(view) { wrapSelection(in: "**", view: $0) }
        case .toggleItalic: edit(view) { wrapSelection(in: "*", view: $0) }
        case .toggleCode: edit(view) { wrapSelection(in: "`", view: $0) }
        case .toggleUnderline: edit(view) { toggleUnderline(view: $0) }
        case .heading(let level):
            guard (1...6).contains(level) else { return }
            edit(view) { prefixParagraph(String(repeating: "#", count: level) + " ", view: $0) }
        case .bulletList: edit(view) { prefixParagraph("- ", view: $0) }
        case .quote: edit(view) { prefixParagraph("> ", view: $0) }
        case .insertLink:
            edit(view) { v in
                let range = v.selectedRange()
                let selected = (v.string as NSString).substring(with: range)
                let label = selected.isEmpty ? "texto" : selected
                v.insertText("[\(label)](https://)", replacementRange: range)
                v.setSelectedRange(NSRange(location: range.location + label.utf16.count + 3, length: 8))
            }
        case .beginPreview(let range):
            beginPreview(range)
        case .showPreview(let option):
            showPreview(option: option)
        case .commitPreview:
            commitPreview()
        case .cancelPreview:
            cancelPreview()
        case .renameTitle:
            // Lo aplica EditorScreen (dueño del documento). Ver el caso en
            // EditorCommand: ignorar aquí evita el bug de insertar el título
            // como texto si algún consumidor reenvía al session.send.
            break
        case .findText(let query):
            findInText(query, view: view)
        case .selectText(let query):
            findInText(query, view: view)
        case .saveDocument, .openDocument, .exportDocument:
            // Los aplica EditorScreen (documento y paneles). Ignorar aquí.
            break
        }
        view.window?.makeFirstResponder(view)
    }

    /// Una sola operación de Undo por comando de voz: aísla la mutación del
    /// tecleo adyacente (funciona con groupsByEvent true o false).
    private func edit(_ view: NSTextView, _ body: (NSTextView) -> Void) {
        view.breakUndoCoalescing()
        view.undoManager?.beginUndoGrouping()
        body(view)
        view.undoManager?.endUndoGrouping()
        view.breakUndoCoalescing()
    }

    private func prefixParagraph(_ prefix: String, view: NSTextView) {        let text = view.string as NSString
        let range = text.paragraphRange(for: view.selectedRange())
        let paragraph = text.substring(with: range)
        let replacement = paragraph.hasPrefix(prefix) ? String(paragraph.dropFirst(prefix.count)) : prefix + paragraph
        view.insertText(replacement, replacementRange: range)
    }

    private func wrapSelection(in marker: String, view: NSTextView) {
        let text = view.string as NSString
        let range = view.selectedRange()
        let selected = text.substring(with: range)
        let width = marker.utf16.count
        let hasOuterMarkers = range.location >= width && NSMaxRange(range) + width <= text.length
            && text.substring(with: NSRange(location: range.location - width, length: width)) == marker
            && text.substring(with: NSRange(location: NSMaxRange(range), length: width)) == marker
        // A second press removes the markers around the still-selected content.
        if hasOuterMarkers {
            view.insertText(selected, replacementRange: NSRange(location: range.location - width, length: range.length + width * 2))
            view.setSelectedRange(NSRange(location: range.location - width, length: range.length))
            return
        }
        let unwrap = selected.count >= marker.count * 2 && selected.hasPrefix(marker) && selected.hasSuffix(marker)
        let replacement = unwrap ? String(selected.dropFirst(marker.count).dropLast(marker.count)) : marker + selected + marker
        view.insertText(replacement, replacementRange: range)
        view.setSelectedRange(NSRange(location: range.location + (unwrap ? 0 : width), length: unwrap ? replacement.utf16.count : range.length))
    }

    /// Subrayado con `<u>…</u>` (HTML inline válido en Markdown; el motor no
    /// tiene toggleUnderline nativo). Misma semántica de conmutación que
    /// `wrapSelection`: segunda aplicación lo retira.
    private func toggleUnderline(view: NSTextView) {
        let text = view.string as NSString
        let range = view.selectedRange()
        guard range.length > 0, NSMaxRange(range) <= text.length else { return }
        let selected = text.substring(with: range)
        let open = "<u>", close = "</u>"
        let ow = (open as NSString).length, cw = (close as NSString).length
        if range.location >= ow && NSMaxRange(range) + cw <= text.length
            && text.substring(with: NSRange(location: range.location - ow, length: ow)) == open
            && text.substring(with: NSRange(location: NSMaxRange(range), length: cw)) == close {
            view.insertText(selected, replacementRange: NSRange(location: range.location - ow, length: range.length + ow + cw))
            view.setSelectedRange(NSRange(location: range.location - ow, length: range.length))
            return
        }
        if selected.hasPrefix(open) && selected.hasSuffix(close) && selected.count >= open.count + close.count {
            let inner = String(selected.dropFirst(open.count).dropLast(close.count))
            view.insertText(inner, replacementRange: range)
            view.setSelectedRange(NSRange(location: range.location, length: (inner as NSString).length))
            return
        }
        view.insertText(open + selected + close, replacementRange: range)
        view.setSelectedRange(NSRange(location: range.location + ow, length: range.length))
    }

    /// Buscar por voz: coincidencia literal exacta primero, luego normalizada
    /// (insensible a mayúsculas y acentos). Sin fuzzy. Duplicados: primera
    /// coincidencia en o después del cursor, con wrap al inicio. Solo mueve
    /// selección/cursor; jamás modifica contenido. Sin coincidencia no toca nada.
    private func findInText(_ query: String, view: NSTextView) {
        guard !query.isEmpty else { return }
        let text = view.string
        let ns = text as NSString
        for options in [NSString.CompareOptions(), [.caseInsensitive, .diacriticInsensitive]] {
            var found: [NSRange] = []
            var at = NSRange(location: 0, length: ns.length)
            while at.location < ns.length {
                let r = ns.range(of: query, options: options, range: at)
                guard r.location != NSNotFound else { break }
                if Range(r, in: text) != nil { found.append(r) }
                let next = r.location + max(r.length, 1)
                if next >= ns.length { break }
                at = NSRange(location: next, length: ns.length - next)
            }
            if let match = found.first(where: { $0.location >= min(view.selectedRange().location, ns.length) }) ?? found.first {
                view.setSelectedRange(match)
                view.scrollRangeToVisible(match)
                return
            }
        }
    }

    // MARK: - Previsualización atómica (gestos)

    /// Congela el undo y marca el span provisional. Vale para palabra y para
    /// párrafo: solo importa el rango afectado.
    private func beginPreview(_ range: EditorCore.TextRange) {
        guard !isPreviewing, !readingMode, let view = textView else { return }
        let ns = view.string as NSString
        let span = NSRange(location: range.location, length: range.length)
        guard range.location >= 0, range.length > 0, NSMaxRange(span) <= ns.length else { return }
        previewLocation = span.location
        previewOriginal = ns.substring(with: span)
        previewCurrent = previewOriginal
        previewLength = span.length
        view.undoManager?.disableUndoRegistration()
        isPreviewing = true
        view.setSelectedRange(span)
        view.scrollRangeToVisible(span)
    }

    /// Muestra una opción reemplazando solo el span. Si el span ya no contiene
    /// lo esperado (el usuario tecleó durante la preview), cancela en vez de
    /// aplicar a ciegas.
    private func showPreview(option: String) {
        guard isPreviewing, let view = textView else { return }
        let ns = view.string as NSString
        let span = NSRange(location: previewLocation, length: previewLength)
        guard NSMaxRange(span) <= ns.length,
              ns.substring(with: span) == previewCurrent else {
            cancelPreview()
            return
        }
        applyPreviewSpan(option)
        let sel = NSRange(location: previewLocation, length: previewLength)
        view.setSelectedRange(sel)
        view.scrollRangeToVisible(sel)
    }

    /// Confirma con un único undo (o ninguno si el texto no cambió).
    /// Si el documento cambió por fuera, libera sin tocar nada.
    private func commitPreview() {
        guard isPreviewing, let view = textView else { return }
        let ns = view.string as NSString
        let span = NSRange(location: previewLocation, length: previewLength)
        guard NSMaxRange(span) <= ns.length,
              ns.substring(with: span) == previewCurrent else {
            endPreview()
            onPreviewCommitted?(view.string)
            return
        }
        let changed = previewCurrent != previewOriginal
        let committedRange = span
        let originalRange = NSRange(location: previewLocation, length: (previewOriginal as NSString).length)
        endPreview()
        view.setSelectedRange(committedRange)
        if changed, let um = view.undoManager {
            registerPreviewSwap(range: committedRange, newText: previewOriginal, newSelect: originalRange,
                                backRange: originalRange, backText: previewCurrent, backSelect: committedRange,
                                undoManager: um)
        }
        onPreviewCommitted?(view.string)
    }

    /// Cancela y restaura el original. Si el span está obsoleto (edición
    /// externa), libera la sesión sin tocar nada: el texto del usuario manda.
    private func cancelPreview() {
        guard isPreviewing, let view = textView else { return }
        let ns = view.string as NSString
        let span = NSRange(location: previewLocation, length: previewLength)
        if NSMaxRange(span) <= ns.length, ns.substring(with: span) == previewCurrent {
            applyPreviewSpan(previewOriginal)
        }
        endPreview()
        let full = NSRange(location: 0, length: (view.string as NSString).length)
        let sel = NSIntersectionRange(
            NSRange(location: previewLocation, length: (previewOriginal as NSString).length), full)
        view.setSelectedRange(sel.length > 0 ? sel : NSRange(location: min(previewLocation, full.length), length: 0))
        onPreviewCommitted?(view.string)
    }

    private func endPreview() {
        isPreviewing = false
        textView?.undoManager?.enableUndoRegistration()
    }

    /// Reemplazo crudo del span, sin undo ni sincronización (la hace quien llama).
    private func applyPreviewSpan(_ option: String) {
        guard let view = textView else { return }
        let span = NSRange(location: previewLocation, length: previewLength)
        view.shouldChangeText(in: span, replacementString: option)
        view.replaceCharacters(in: span, with: option)
        view.didChangeText() // El Coordinator lo ignora mientras isPreviewing.
        previewCurrent = option
        previewLength = (option as NSString).length
    }

    /// Ping-pong undo/redo simétrico para el cambio confirmado.
    private func registerPreviewSwap(range: NSRange, newText: String, newSelect: NSRange,
                                     backRange: NSRange, backText: String, backSelect: NSRange,
                                     undoManager um: UndoManager) {
        guard let view = textView else { return }
        um.registerUndo(withTarget: view) { [weak self] target in
            self?.applyPreviewSwap(in: target, range: range, text: newText, select: newSelect)
            self?.registerPreviewSwap(range: backRange, newText: backText, newSelect: backSelect,
                                      backRange: newSelect, backText: newText, backSelect: newSelect,
                                      undoManager: um)
        }
    }

    private func applyPreviewSwap(in view: NSTextView, range: NSRange, text: String, select: NSRange) {
        guard NSMaxRange(range) <= (view.string as NSString).length else { return }
        view.shouldChangeText(in: range, replacementString: text)
        view.replaceCharacters(in: range, with: text)
        view.didChangeText()
        view.setSelectedRange(select)
    }
}
