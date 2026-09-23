import XCTest
import AppKit
@testable import EditorCore
@testable import EditorEngine

/// La preview atómica no toca el binding (lo sincroniza `onPreviewCommitted`),
/// no ensucia el undo y confirma con un único undo. Cancelar restaura.
final class PreviewTests: XCTestCase {
    @MainActor
    private func makeSession(text: String) -> (EditorSession, NSWindow, NSTextView, [String]) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let view = NSTextView(usingTextLayoutManager: true)
        view.isRichText = false
        view.allowsUndo = true
        view.string = text
        window.contentView = view
        window.makeFirstResponder(view)
        let session = EditorSession()
        session.textView = view
        var synced: [String] = []
        session.onPreviewCommitted = { synced.append($0) }
        return (session, window, view, synced)
    }

    @MainActor func testCommitRegistersSingleUndo() {
        let (session, window, view, _) = makeSession(text: "hola mundo")
        session.send(.beginPreview(TextRange(location: 0, length: 4)))
        XCTAssertTrue(session.isPreviewing)
        session.send(.showPreview("adiós"))
        XCTAssertEqual(view.string, "hola mundo".replacingOccurrences(of: "hola", with: "adiós"))
        session.send(.commitPreview)
        XCTAssertFalse(session.isPreviewing)
        XCTAssertEqual(view.string, "adiós mundo")
        session.send(.undo)
        XCTAssertEqual(view.string, "hola mundo")
        session.send(.redo)
        XCTAssertEqual(view.string, "adiós mundo")
        session.stop()
        window.orderOut(nil)
    }

    @MainActor func testCommitWithoutChangesRegistersNothing() {
        let (session, window, view, _) = makeSession(text: "hola mundo")
        view.undoManager?.removeAllActions()
        session.send(.beginPreview(TextRange(location: 0, length: 4)))
        session.send(.showPreview("hola"))
        session.send(.commitPreview)
        XCTAssertEqual(view.string, "hola mundo")
        XCTAssertFalse(view.undoManager?.canUndo ?? true)
        session.stop()
        window.orderOut(nil)
    }

    @MainActor func testCancelRestoresOriginal() {
        let (session, window, view, _) = makeSession(text: "hola mundo")
        session.send(.beginPreview(TextRange(location: 5, length: 5)))
        session.send(.showPreview("planeta"))
        XCTAssertEqual(view.string, "hola planeta")
        session.send(.cancelPreview)
        XCTAssertFalse(session.isPreviewing)
        XCTAssertEqual(view.string, "hola mundo")
        XCTAssertFalse(view.undoManager?.canUndo ?? true)
        session.stop()
        window.orderOut(nil)
    }

    @MainActor func testExternalEditCancelsInsteadOfApplyingBlindly() {
        let (session, window, view, _) = makeSession(text: "hola mundo")
        session.send(.beginPreview(TextRange(location: 0, length: 4)))
        // Edición externa directa dentro del span (teclear durante la preview).
        view.setSelectedRange(NSRange(location: 1, length: 0))
        view.insertText("X", replacementRange: view.selectedRange())
        // El siguiente show detecta el span obsoleto y cancela.
        session.send(.showPreview("adiós"))
        XCTAssertFalse(session.isPreviewing)
        session.stop()
        window.orderOut(nil)
    }

    @MainActor func testPreviewBlockedInReadingMode() {
        let (session, window, view, _) = makeSession(text: "hola mundo")
        session.readingMode = true
        session.send(.beginPreview(TextRange(location: 0, length: 4)))
        XCTAssertFalse(session.isPreviewing)
        XCTAssertEqual(view.string, "hola mundo")
        session.stop()
        window.orderOut(nil)
    }
}
