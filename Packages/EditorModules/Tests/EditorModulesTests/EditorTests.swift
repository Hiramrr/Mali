import XCTest
import AppKit
@testable import EditorCore
@testable import DocumentKit
@testable import EditorEngine
import DesignSystem

final class EditorTests: XCTestCase {
    func testUTF8RoundTripAndInvalidData() throws {
        for text in ["", "Español, 日本語, 👩🏽‍💻\r\n", String(repeating: "á", count: 100_000), String(repeating: "文", count: 500_000), String(repeating: "x", count: 1_000_000)] {
            XCTAssertEqual(try UTF8Document.decode(UTF8Document.encode(text)), text)
        }
        XCTAssertThrowsError(try UTF8Document.decode(Data([0xFF, 0xFE, 0x80])))
    }

    func testUTF16RangesAndOutline() {
        let text = "🐈\r\n## Cazador\r\nTexto\n```\n# código\n```\n# Fin"
        let headings = DocumentOutline.headings(in: text)
        XCTAssertEqual(headings.map(\.title), ["Cazador", "Fin"])
        XCTAssertEqual(headings.first?.offset, 4)
        XCTAssertNil(TextRange(location: -1, length: 1).validated(in: text))
        XCTAssertNil(TextRange(location: 1, length: 0).validated(in: text))
        XCTAssertNil(TextRange(location: 0, length: Int.max).validated(in: text))
        XCTAssertNotNil(TextRange(location: 0, length: 2).validated(in: text))
    }

    @MainActor func testNativeCommandsUndoAndRedo() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        let view = NSTextView(usingTextLayoutManager: true)
        view.isRichText = false
        view.allowsUndo = true
        window.contentView = view
        window.makeFirstResponder(view)
        let session = EditorSession()
        session.textView = view
        view.undoManager?.groupsByEvent = false
        view.undoManager?.beginUndoGrouping()
        session.send(.insertText("Hola 🐈"))
        view.undoManager?.endUndoGrouping()
        view.breakUndoCoalescing()
        session.send(.selectRange(TextRange(location: 5, length: 2)))
        view.undoManager?.beginUndoGrouping()
        session.send(.replaceSelection("mundo"))
        view.undoManager?.endUndoGrouping()
        view.breakUndoCoalescing()
        XCTAssertEqual(view.string, "Hola mundo")
        session.send(.undo)
        XCTAssertEqual(view.string, "Hola 🐈")
        session.send(.redo)
        XCTAssertEqual(view.string, "Hola mundo")
        session.send(.selectAll)
        view.undoManager?.beginUndoGrouping()
        session.send(.toggleBold)
        view.undoManager?.endUndoGrouping()
        XCTAssertEqual(view.string, "**Hola mundo**")
        session.stop()
        window.orderOut(nil)
    }
}

final class MarkdownExperienceTests: XCTestCase {
    func testFencesUnicodeAndStatistics() {
        let source = "# Café 🐈\r\n\r\n~~~swift\r\n# No es título\r\n```\r\n~~~\r\n## Fin\r\n"
        let document = MarkdownDocument(source)
        XCTAssertEqual(document.headings.map(\.title), ["Café 🐈", "Fin"])
        XCTAssertEqual(document.headings.last?.offset, (source as NSString).range(of: "## Fin").location)
        XCTAssertEqual(document.lines.filter { $0.kind == .fence }.count, 2)
        XCTAssertEqual(document.statistics.characters, source.count)
        XCTAssertGreaterThan(document.statistics.words, 0)
        XCTAssertEqual(MarkdownDocument("").statistics.words, 0)
        XCTAssertEqual(MarkdownDocument("uno dos\n\ntres").statistics.paragraphs, 2)
    }

    @MainActor func testReadingAndDecorationPreserveSource() {
        let source = "# Título\n\n**Negrita** y *cursiva* con 🐈.\n- Elemento\n> Cita\n~~~\n**literal**\n~~~\n[Seguro](https://example.com) [No](file:///tmp/secret)"
        let document = MarkdownDocument(source)
        let storage = NSMutableAttributedString(string: source)
        let style = WritingStyle()
        MarkdownAppearance.decorate(storage, document: document, style: style)
        XCTAssertEqual(storage.string, source)
        let headingFont = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertGreaterThan(headingFont?.pointSize ?? 0, 18)
        let boldRange = (source as NSString).range(of: "Negrita")
        let bold = storage.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(bold.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false)
        let reading = MarkdownAppearance.readingText(source, document: document, style: style)
        XCTAssertTrue(reading.string.hasPrefix("Título\n"))
        XCTAssertTrue(reading.string.contains("Negrita y cursiva con 🐈."))
        XCTAssertTrue(reading.string.contains("• Elemento"))
        XCTAssertTrue(reading.string.contains("**literal**"))
        XCTAssertFalse(reading.string.contains("~~~"))
        let noLink = (reading.string as NSString).range(of: "No")
        XCTAssertNil(reading.attribute(.link, at: noLink.location, effectiveRange: nil))
        let safeLink = (reading.string as NSString).range(of: "Seguro")
        XCTAssertNotNil(reading.attribute(.link, at: safeLink.location, effectiveRange: nil))
        let renderedBold = reading.attribute(.font, at: (reading.string as NSString).range(of: "Negrita").location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(renderedBold.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false, "\(reading.attributes(at: (reading.string as NSString).range(of: "Negrita").location, effectiveRange: nil))")
    }

    @MainActor func testFormatTogglePreservesEmojiAndNativeUndo() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        let view = WritingTextView(usingTextLayoutManager: true)
        window.contentView = view
        view.allowsUndo = true
        view.isRichText = false
        view.string = "Café 👩🏽‍💻"
        let session = EditorSession()
        session.textView = view
        view.undoManager?.groupsByEvent = false
        session.send(.selectAll)
        view.undoManager?.beginUndoGrouping()
        session.send(.toggleBold)
        view.undoManager?.endUndoGrouping()
        let formatted = view.string
        view.applyAnalysis(MarkdownDocument(formatted))
        XCTAssertEqual(view.string, "**Café 👩🏽‍💻**")
        view.undoManager?.beginUndoGrouping()
        session.send(.toggleBold)
        view.undoManager?.endUndoGrouping()
        XCTAssertEqual(view.string, "Café 👩🏽‍💻")
        session.send(.undo)
        XCTAssertEqual(view.string, formatted)
        session.readingMode = true
        session.send(.insertText("No debe escribirse"))
        XCTAssertEqual(view.string, formatted)
        session.stop()
    }
}
