import SwiftUI
import AppKit
import EditorCore
import DesignSystem

public struct MarkdownReader: NSViewRepresentable {
    public let text: String
    public let style: WritingStyle
    public let documentURL: URL?
    public init(text: String, style: WritingStyle, documentURL: URL? = nil) {
        self.text = text
        self.style = style
        self.documentURL = documentURL
    }
    public func makeCoordinator() -> Coordinator { Coordinator() }
    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let view = ReadingTextView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isSelectable = true
        view.usesFindBar = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 28, height: 24)
        view.backgroundColor = style.effectiveBackgroundColor
        view.textColor = style.effectiveTextColor
        view.setAccessibilityLabel("Vista de lectura")
        scroll.documentView = view
        return scroll
    }
    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        view.backgroundColor = style.effectiveBackgroundColor
        view.textColor = style.effectiveTextColor
        view.insertionPointColor = style.effectiveTextColor
        guard context.coordinator.text != text || context.coordinator.style != style || context.coordinator.documentURL != documentURL else { return }
        context.coordinator.text = text
        context.coordinator.style = style
        context.coordinator.documentURL = documentURL
        view.textStorage?.setAttributedString(MarkdownAppearance.readingText(text, document: MarkdownDocument(text), style: style, documentURL: documentURL))
    }
    @MainActor public final class Coordinator {
        var text: String?
        var style: WritingStyle?
        var documentURL: URL?
    }
}

@MainActor private final class ReadingTextView: NSTextView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }
}
