import SwiftUI
import AppKit
import EditorCore
import DesignSystem

public struct NativeTextEditor: NSViewRepresentable {
    @Binding private var text: String
    private let session: EditorSession
    private let style: WritingStyle
    private let isOpeningDocument: Bool
    /// Pieza Lego (gestos): informa texto+selección para instantáneas del
    /// documento. `nil` sin la pieza; el editor funciona igual.
    private let onTextActivity: ((String, NSRange) -> Void)?

    public init(text: Binding<String>, session: EditorSession, style: WritingStyle = WritingStyle(), isOpeningDocument: Bool = false, onTextActivity: ((String, NSRange) -> Void)? = nil) {
        _text = text
        self.session = session
        self.style = style
        self.isOpeningDocument = isOpeningDocument
        self.onTextActivity = onTextActivity
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        let view = WritingTextView(usingTextLayoutManager: true)
        view.isRichText = false
        view.allowsUndo = true
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.isContinuousSpellCheckingEnabled = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 28, height: 24)
        view.style = style
        view.isEditable = !session.readingMode && !isOpeningDocument
        view.isSelectable = !session.readingMode && !isOpeningDocument
        WritingTextView.apply(style: style, to: view)
        view.string = text
        view.setAccessibilityLabel("Contenido del documento")
        view.delegate = context.coordinator
        scroll.documentView = view
        session.textView = view
        session.refreshOutline(text)
        session.onPreviewCommitted = { [weak coordinator = context.coordinator] committed in
            coordinator?.syncPreview(committed)
        }
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? WritingTextView else { return }
        // Durante la preview el NSTextView manda: reescribirlo borraría la
        // opción provisional. Al terminar, syncPreview ya actualizó el binding.
        if !session.isPreviewing, view.string != text {
            let selection = view.selectedRange()
            view.string = text
            view.setSelectedRange(NSRange(location: min(selection.location, text.utf16.count), length: 0))
            session.refreshOutline(text)
        }
        if view.style != style {
            view.style = style
            WritingTextView.apply(style: style, to: view)
            session.refreshOutline(view.string)
        }
        if view.paragraphFocus != session.paragraphFocus {
            view.paragraphFocus = session.paragraphFocus
            view.updateParagraphHighlight()
        }
        if view.typewriterMode != session.typewriterMode {
            view.typewriterMode = session.typewriterMode
            view.updateInsets()
            if view.typewriterMode { view.centerInsertionPoint() }
            view.updateParagraphHighlight()
        }
        let wasHidden = scroll.isHidden
        scroll.isHidden = session.readingMode
        view.isEditable = !session.readingMode && !isOpeningDocument
        view.isSelectable = !session.readingMode && !isOpeningDocument
        if wasHidden && !scroll.isHidden { view.window?.makeFirstResponder(view) }
    }

    public static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        (scroll.documentView as? NSTextView)?.delegate = nil
        coordinator.parent.session.stop()
    }

    @MainActor public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeTextEditor
        init(_ parent: NativeTextEditor) { self.parent = parent }

        public func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? WritingTextView else { return }
            // La preview no toca el binding ni el índice: es provisional hasta
            // confirmar o cancelar (entonces syncPreview sincroniza).
            guard !parent.session.isPreviewing else { return }
            parent.text = view.string
            parent.session.refreshOutline(view.string)
            parent.onTextActivity?(view.string, view.selectedRange())
            view.typingAttributes = parent.style.attributes
            if view.typewriterMode && !view.hasMarkedText() { view.centerInsertionPoint() }
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            parent.session.selectionChanged()
            // Durante la preview el texto es provisional: empujarlo haría que
            // el módulo lo confundiera con una edición externa y cancelara la
            // sesión al primer movimiento. Al terminar, syncPreview empuja.
            if !parent.session.isPreviewing, let view = notification.object as? WritingTextView {
                parent.onTextActivity?(view.string, view.selectedRange())
            }
        }

        /// Sincroniza el binding tras confirmar o cancelar una preview.
        func syncPreview(_ committed: String) {
            parent.text = committed
            parent.session.refreshOutline(committed)
            if let view = parent.session.textView {
                parent.onTextActivity?(committed, view.selectedRange())
            }
        }
    }
}

@MainActor final class WritingTextView: NSTextView, @MainActor NSTextStorageDelegate {
    var style = WritingStyle()
    var paragraphFocus = false
    var typewriterMode = false
    private var paragraphRect = NSRect.zero
    private var decoratedLines: [MarkdownLine] = []
    private var decoratedStyle: WritingStyle?
    private var changedRange: NSRange?

    static func apply(style: WritingStyle, to view: NSTextView) {
        view.font = style.font
        view.defaultParagraphStyle = style.attributes[.paragraphStyle] as? NSParagraphStyle
        view.typingAttributes = style.attributes
        view.textColor = style.effectiveTextColor
        view.backgroundColor = style.effectiveBackgroundColor
        view.insertionPointColor = style.accentHex == "auto" ? style.effectiveTextColor : style.effectiveAccentColor
        view.selectedTextAttributes = [
            .backgroundColor: style.effectiveAccentColor.withAlphaComponent(0.28),
            .foregroundColor: style.effectiveTextColor,
        ]
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    func applyAnalysis(_ document: MarkdownDocument) {
        guard !hasMarkedText(), let storage = textStorage else { return }
        var first = 0
        var last = document.lines.count
        if decoratedStyle == style {
            let dirty = changedRange ?? NSRange(location: storage.length, length: 0)
            while first < min(last, decoratedLines.count),
                  NSMaxRange(document.lines[first].range) < dirty.location,
                  document.lines[first] == decoratedLines[first] {
                first += 1
            }
            var oldLast = decoratedLines.count
            while last > first, oldLast > first {
                let line = document.lines[last - 1]
                let previous = decoratedLines[oldLast - 1]
                guard line.range.location > NSMaxRange(dirty),
                      line.range.length == previous.range.length,
                      line.content == previous.content, line.kind == previous.kind,
                      line.prefixLength == previous.prefixLength,
                      line.trailingLength == previous.trailingLength else { break }
                last -= 1
                oldLast -= 1
            }
        }
        // Presentation attributes do not replace text or participate in its undo history.
        storage.beginEditing()
        MarkdownAppearance.decorate(storage, document: document, style: style, lines: first..<last)
        storage.endEditing()
        decoratedLines = document.lines
        decoratedStyle = style
        changedRange = nil
        storage.delegate = self
        typingAttributes = style.attributes
        updateParagraphHighlight()
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        if let previous = changedRange {
            // El rango anterior sigue a las inserciones y borrados antes de él.
            let start = min(previous.location, editedRange.location)
            let end = max(NSMaxRange(editedRange), NSMaxRange(previous) + delta)
            changedRange = NSRange(location: start, length: end - start)
        } else {
            changedRange = editedRange
        }
    }

    func updateInsets() {
        let height = typewriterMode ? max(24, (enclosingScrollView?.contentSize.height ?? 0) * 0.42) : 24
        let inset = NSSize(width: 28, height: height)
        if textContainerInset != inset { textContainerInset = inset }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changedWidth = frame.width != newSize.width
        super.setFrameSize(newSize)
        updateInsets()
        if changedWidth && paragraphFocus {
            Task { @MainActor [weak self] in self?.updateParagraphHighlight() }
        }
    }

    func centerInsertionPoint() {
        guard let scroll = enclosingScrollView, let window else { return }
        let screen = firstRect(forCharacterRange: NSRange(location: selectedRange().location, length: 0), actualRange: nil)
        guard !screen.isEmpty else { return }
        let local = convert(window.convertFromScreen(screen), from: nil)
        let y = max(0, min(frame.height - scroll.contentSize.height, local.midY - scroll.contentSize.height * 0.42))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func updateParagraphHighlight() {
        paragraphRect = .zero
        defer { needsDisplay = true }
        guard paragraphFocus, let window, !string.isEmpty else { return }
        let text = string as NSString
        let range = text.paragraphRange(for: NSRange(location: min(selectedRange().location, text.length), length: 0))
        let first = firstRect(forCharacterRange: NSRange(location: range.location, length: 0), actualRange: nil)
        let last = firstRect(forCharacterRange: NSRange(location: max(range.location, NSMaxRange(range) - 1), length: 0), actualRange: nil)
        let a = convert(window.convertFromScreen(first), from: nil)
        let b = convert(window.convertFromScreen(last), from: nil)
        paragraphRect = NSRect(x: 16, y: min(a.minY, b.minY) - 4, width: max(0, bounds.width - 32), height: max(a.maxY, b.maxY) - min(a.minY, b.minY) + 8)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard paragraphFocus, !paragraphRect.isEmpty else { return }
        let base = style.accentHex == "auto" ? NSColor.controlAccentColor : style.effectiveAccentColor
        base.withAlphaComponent(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.17 : 0.06).setFill()
        NSBezierPath(roundedRect: paragraphRect, xRadius: 4, yRadius: 4).fill()
    }
}
