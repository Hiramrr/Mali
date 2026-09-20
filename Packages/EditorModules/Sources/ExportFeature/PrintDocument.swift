import AppKit
import EditorCore
import DesignSystem

@MainActor public enum PrintDocument {
    public static func run(text: String, title: String, window: NSWindow?) {
        let info = NSPrintInfo()
        info.topMargin = 48
        info.bottomMargin = 48
        info.leftMargin = 54
        info.rightMargin = 54
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.isEditable = false
        view.isVerticallyResizable = true
        view.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        let source = "# \(title)\n\n" + text
        let rendered = MarkdownAppearance.readingText(source, document: MarkdownDocument(source), style: WritingStyle(size: 12, family: "serif", spacing: 4), forPrint: true)
        view.textStorage?.setAttributedString(rendered)
        view.sizeToFit()
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = title
        // The native PDF menu handles destination access and overwrite confirmation.
        if let window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else { operation.run() }
    }
}
