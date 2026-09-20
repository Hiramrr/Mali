import SwiftUI
import AppKit
import EditorCore
import DesignSystem

public struct NativeTextEditor: NSViewRepresentable {
    @Binding private var text: String
    private let session: EditorSession
    private let style: WritingStyle

    public init(text: Binding<String>, session: EditorSession, style: WritingStyle = WritingStyle()) {
        _text = text
        self.session = session
        self.style = style
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
        view.font = style.font
        view.defaultParagraphStyle = style.attributes[.paragraphStyle] as? NSParagraphStyle
        view.textColor = .textColor
        view.backgroundColor = .textBackgroundColor
        view.string = text
        view.setAccessibilityLabel("Contenido del documento")
        view.delegate = context.coordinator
        scroll.documentView = view
        session.textView = view
        session.refreshOutline(text)
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? WritingTextView else { return }
        if view.string != text {
            let selection = view.selectedRange()
            view.string = text
            view.setSelectedRange(NSRange(location: min(selection.location, text.utf16.count), length: 0))
            session.refreshOutline(text)
        }
        if view.style != style {
            view.style = style
            view.applyAnalysis(MarkdownDocument(view.string))
        }
        if view.paragraphFocus != session.paragraphFocus {
            view.paragraphFocus = session.paragraphFocus
            view.updateParagraphHighlight()
        }
        if view.typewriterMode != session.typewriterMode {
            view.typewriterMode = session.typewriterMode
            view.updateInsets()
            if view.typewriterMode { view.centerInsertionPoint() }
        }
        view.isEditable = !session.readingMode
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
            parent.text = view.string
            parent.session.refreshOutline(view.string)
            view.typingAttributes = parent.style.attributes
            if view.typewriterMode && !view.hasMarkedText() { view.centerInsertionPoint() }
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            parent.session.selectionChanged()
        }
    }
}

@MainActor final class WritingTextView: NSTextView {
    var style = WritingStyle()
    var paragraphFocus = false
    var typewriterMode = false
    private var paragraphRect = NSRect.zero

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
        // Presentation attributes do not replace text or participate in its undo history.
        storage.beginEditing()
        MarkdownAppearance.decorate(storage, document: document, style: style)
        storage.endEditing()
        typingAttributes = style.attributes
        updateParagraphHighlight()
    }

    func updateInsets() {
        let height = typewriterMode ? max(24, (enclosingScrollView?.contentSize.height ?? 0) * 0.42) : 24
        let inset = NSSize(width: 28, height: height)
        if textContainerInset != inset { textContainerInset = inset }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
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
        NSColor.controlAccentColor.withAlphaComponent(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.17 : 0.06).setFill()
        NSBezierPath(roundedRect: paragraphRect, xRadius: 4, yRadius: 4).fill()
    }
}
