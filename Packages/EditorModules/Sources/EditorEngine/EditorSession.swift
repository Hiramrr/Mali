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
        selectedCharacters = view.selectedRange().length == 0 ? 0 : (view.string as NSString).substring(with: view.selectedRange()).count
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
        case .insertText(let text), .replaceSelection(let text):
            view.insertText(text, replacementRange: view.selectedRange())
        case .selectRange(let range):
            guard let valid = range.validated(in: view.string) else { return }
            view.setSelectedRange(valid)
            view.scrollRangeToVisible(valid)
        case .selectAll: view.selectAll(nil)
        case .deleteBackward: view.deleteBackward(nil)
        case .deleteForward: view.deleteForward(nil)
        case .undo: view.undoManager?.undo()
        case .redo: view.undoManager?.redo()
        case .toggleBold: wrapSelection(in: "**", view: view)
        case .toggleItalic: wrapSelection(in: "*", view: view)
        case .toggleCode: wrapSelection(in: "`", view: view)
        case .heading(let level):
            guard (1...6).contains(level) else { return }
            prefixParagraph(String(repeating: "#", count: level) + " ", view: view)
        case .bulletList: prefixParagraph("- ", view: view)
        case .quote: prefixParagraph("> ", view: view)
        case .insertLink:
            let range = view.selectedRange()
            let selected = (view.string as NSString).substring(with: range)
            let label = selected.isEmpty ? "texto" : selected
            view.insertText("[\(label)](https://)", replacementRange: range)
            view.setSelectedRange(NSRange(location: range.location + label.utf16.count + 3, length: 8))
        case .beginPreview(let range):
            beginPreview(range)
        case .showPreview(let option):
            showPreview(option: option)
        case .commitPreview:
            commitPreview()
        case .cancelPreview:
            cancelPreview()
        }
        view.window?.makeFirstResponder(view)
    }

    private func prefixParagraph(_ prefix: String, view: NSTextView) {
        let text = view.string as NSString
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
