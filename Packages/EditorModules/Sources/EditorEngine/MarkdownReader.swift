import SwiftUI
import AppKit
import EditorCore
import DesignSystem

public struct MarkdownReader: NSViewRepresentable {
    public let text: String
    public let style: WritingStyle
    public init(text: String, style: WritingStyle) {
        self.text = text
        self.style = style
    }
    public func makeCoordinator() -> Coordinator { Coordinator() }
    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let view = NSTextView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isSelectable = true
        view.usesFindBar = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 28, height: 24)
        view.backgroundColor = .textBackgroundColor
        view.setAccessibilityLabel("Vista de lectura")
        scroll.documentView = view
        return scroll
    }
    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView,
              context.coordinator.text != text || context.coordinator.style != style else { return }
        context.coordinator.text = text
        context.coordinator.style = style
        view.textStorage?.setAttributedString(MarkdownAppearance.readingText(text, document: MarkdownDocument(text), style: style))
    }
    @MainActor public final class Coordinator {
        var text: String?
        var style: WritingStyle?
    }
}
