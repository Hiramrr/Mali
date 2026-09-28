import AppKit
import EditorCore
import DesignSystem
import EditorEngine

@MainActor public enum PrintDocument {
    public static func run(text: String, title: String, window: NSWindow?, documentURL: URL? = nil) {
        let operation = makeOperation(text: text, title: title, documentURL: documentURL)
        // The native PDF menu handles destination access and overwrite confirmation.
        if let window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else { operation.run() }
    }

    static func makeOperation(text: String, title: String, documentURL: URL? = nil) -> NSPrintOperation {
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
        let view = PrintableTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.isEditable = false
        view.isVerticallyResizable = true
        view.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        let source = "# \(title)\n\n" + text
        let rendered = MarkdownAppearance.readingText(source, document: MarkdownDocument(source), style: WritingStyle(size: 12, family: "serif", spacing: 4), forPrint: true, documentURL: documentURL)
        view.textStorage?.setAttributedString(rendered)
        view.sizeToFit()
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = title
        return operation
    }
}


@MainActor private final class PrintableTextView: NSTextView {
    override func adjustPageHeightNew(_ newBottom: UnsafeMutablePointer<CGFloat>, top oldTop: CGFloat, bottom oldBottom: CGFloat, limit bottomLimit: CGFloat) {
        super.adjustPageHeightNew(newBottom, top: oldTop, bottom: oldBottom, limit: bottomLimit)
        guard let layoutManager, let textContainer, let storage = textStorage else { return }
        let origin = textContainerOrigin
        let visible = NSRect(x: 0, y: oldTop - origin.y, width: bounds.width, height: max(0, newBottom.pointee - oldTop - 0.5))
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)
        guard glyphs.length > 0 else { return }
        // Una imagen o un diagrama no se corta entre páginas: pasa entero a la siguiente.
        var attachmentTop: CGFloat?
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        storage.enumerateAttribute(.attachment, in: characters) { value, range, stop in
            guard value != nil else { return }
            let line = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: range.location), effectiveRange: nil)
            let top = line.minY + origin.y - 0.5
            if top > oldTop + 1, line.maxY + origin.y > newBottom.pointee {
                attachmentTop = top
                stop.pointee = true
            }
        }
        if let attachmentTop {
            newBottom.pointee = attachmentTop
            return
        }
        let source = string as NSString
        var index = layoutManager.characterIndexForGlyph(at: NSMaxRange(glyphs) - 1)
        while index > 0 {
            let range = source.paragraphRange(for: NSRange(location: index, length: 0))
            if !source.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let paragraph = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
                      paragraph.headerLevel > 0 else { return }
                let headingGlyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let headingTop = layoutManager.lineFragmentRect(forGlyphAt: headingGlyphs.location, effectiveRange: nil).minY + origin.y - 0.5
                if headingTop > oldTop + 1 { newBottom.pointee = headingTop }
                return
            }
            guard range.location > 0 else { return }
            index = range.location - 1
        }
    }
}
