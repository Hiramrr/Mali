// Fase 11 — Tests del executor + adaptador real (NSTextView, UndoManager real).
// Cobertura: navegación, delete, replace, format, undo/redo, Unicode, stale,
// preview C20, invariante de confirmación, rewrite simulado, save/open/export,
// rangos, política. Cada método es un test nuevo (total al final del archivo).
import XCTest
import AppKit
@testable import EditorEngine

@MainActor private func makeRealTarget(
    text: String = VoiceFixtureText.real,
    select selectQuery: String? = nil,
    title: String = "Proyecto"
) -> (NSWindow, NSTextView, RealEditorTarget, EditorCommandExecutor, VoiceDocumentStore) {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let view = NSTextView(usingTextLayoutManager: true)
    view.isRichText = false
    view.allowsUndo = true
    window.contentView = view
    window.makeFirstResponder(view)
    view.undoManager?.groupsByEvent = false
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("voice11-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = VoiceDocumentStore(baseDirectory: dir)
    view.string = text
    view.breakUndoCoalescing()
    // Limpia el historial del setup para que canUndo refleje solo acciones de voz.
    view.undoManager?.removeAllActions()
    let target = RealEditorTarget(view: view, title: title, store: store)
    let executor = EditorCommandExecutor(target: target)
    if let q = selectQuery, let r = (text as NSString).range(of: q) as NSRange?,
       r.location != NSNotFound, UnicodeRanges.validated(r, in: text) != nil {
        view.setSelectedRange(r)
    }
    return (window, view, target, executor, store)
}

@MainActor private func confirm(_ e: EditorCommandExecutor, _ cmd: VoiceCommand) -> EditorCommandResult {
    let out = e.receive(cmd)
    guard case .needsConfirm(let p) = out else {
        XCTFail("se esperaba needsConfirm para \(cmd), fue \(out)")
        return .failure(.unsupportedCommand("test"))
    }
    return e.confirm(p)
}

final class VoiceRealEditorTests: XCTestCase {

    // MARK: - Navegación (find/select inmediatos, sin mutar contenido)

    @MainActor func testNav01FindExactMovesSelection() {
        let (w, v, t, _, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let before = v.string
        let r = t.findText("Metodología")
        guard case .success(.found(let range)) = r else { return XCTFail("find falló: \(r)") }
        XCTAssertEqual((before as NSString).substring(with: range), "Metodología")
        XCTAssertEqual(v.string, before, "find no debe mutar contenido")
    }

    @MainActor func testNav02FindNoMatch() {
        let (w, _, t, _, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let beforeText = t.currentText
        let beforeSel = t.selectedNSRange
        let r = t.findText("inexistente-zz-qq")
        guard case .noMatch = r else { return XCTFail("debió ser noMatch: \(r)") }
        XCTAssertEqual(t.currentText, beforeText)
        XCTAssertEqual(t.selectedNSRange.location, beforeSel.location)
    }

    @MainActor func testNav03FindAcentos() {
        let (w, v, t, _, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let r = t.findText("evaluación")
        guard case .success(.found(let range)) = r else { return XCTFail("find acentos: \(r)") }
        XCTAssertEqual((v.string as NSString).substring(with: range), "evaluación")
        XCTAssertEqual(v.string, VoiceFixtureText.real)
    }

    @MainActor func testNav04FindEmoji() {
        let (w, v, t, _, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let r = t.findText("🧠")
        guard case .success(.found(let range)) = r else { return XCTFail("find emoji: \(r)") }
        XCTAssertEqual((v.string as NSString).substring(with: range), "🧠")
        XCTAssertEqual(range.length, ("🧠" as NSString).length)
    }

    @MainActor func testNav05FindJapanese() {
        let (w, v, t, _, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let r = t.findText("ユーザー")
        guard case .success(.found(let range)) = r else { return XCTFail("find japonés: \(r)") }
        XCTAssertEqual((v.string as NSString).substring(with: range), "ユーザー")
    }

    @MainActor func testNav06FindAfterCursorRule() {
        let (w, v, t, _, _) = makeRealTarget(text: VoiceFixtureText.withDuplicates); defer { w.orderOut(nil) }
        let ns = v.string as NSString
        let first = ns.range(of: "Metodología")
        XCTAssertNotEqual(first.location, NSNotFound)
        v.setSelectedRange(NSRange(location: first.location + first.length, length: 0))
        let r = t.findText("Metodología")
        guard case .success(.found(let range)) = r else { return XCTFail("find: \(r)") }
        XCTAssertGreaterThan(range.location, first.location, "regla: primera coincidencia después del cursor")
    }

    @MainActor func testNav07FindNormalizedFallback() {
        let (w, v, t, _, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let r = t.findText("metodologia") // sin acento ni mayúscula
        guard case .success(.found(let range)) = r else { return XCTFail("fallback normalizado: \(r)") }
        XCTAssertEqual((v.string as NSString).substring(with: range), "Metodología")
    }

    @MainActor func testNav08SelectExact() {
        let (w, v, t, _, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let before = v.string
        let r = t.selectText("María-José")
        guard case .success(.selected(let range)) = r else { return XCTFail("select: \(r)") }
        XCTAssertEqual((before as NSString).substring(with: range), "María-José")
        XCTAssertEqual(v.selectedRange(), range)
        XCTAssertEqual(v.string, before)
    }

    @MainActor func testNav09SelectNoMatch() {
        let (w, _, t, _, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let before = t.currentText
        XCTAssertEqual(t.selectText("zzz-sin-match"), .noMatch("zzz-sin-match"))
        XCTAssertEqual(t.currentText, before)
    }

    @MainActor func testNav10SelectDuplicateFirstAfterCursor() {
        let (w, v, t, _, _) = makeRealTarget(text: VoiceFixtureText.withDuplicates); defer { w.orderOut(nil) }
        v.setSelectedRange(NSRange(location: 0, length: 0))
        let r = t.selectText("TDAH")
        guard case .success(.selected(let range)) = r else { return XCTFail("select dup: \(r)") }
        let expected = (v.string as NSString).range(of: "TDAH")
        XCTAssertEqual(range, expected, "duplicados: primera coincidencia después del cursor")
    }

    @MainActor func testNav11NavigationPreservesHistory() {
        let (w, _, t, _, _) = makeRealTarget(); defer { w.orderOut(nil) }
        XCTAssertFalse(t.canUndo)
        _ = t.findText("TDAH")
        _ = t.selectText("IHC")
        XCTAssertFalse(t.canUndo, "navegación no debe tocar historial")
        XCTAssertFalse(t.canRedo)
    }

    @MainActor func testNav12ExecutorImmediate() {
        let (w, _, _, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let out = e.receive(.findText("IHC"))
        guard case .executed(.success(.found)) = out else { return XCTFail("find debe ser inmediato: \(out)") }
        let out2 = e.receive(.selectText("TDAH"))
        guard case .executed(.success(.selected)) = out2 else { return XCTFail("select inmediato: \(out2)") }
        XCTAssertTrue(e.autoLog.count >= 2)
    }

    // MARK: - Delete

    @MainActor func testDel01ProposalNoMutation() {
        let (w, _, t, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let before = t.currentText
        let out = e.receive(.deleteSelection)
        guard case .needsConfirm = out else { return XCTFail("delete requiere confirm: \(out)") }
        XCTAssertEqual(t.currentText, before, "antes de Enter: 0 mutación")
    }

    @MainActor func testDel02ConfirmDeletes() {
        let (w, v, _, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let r = confirm(e, .deleteSelection)
        guard case .success(.deleted(_, let removed)) = r else { return XCTFail("delete: \(r)") }
        XCTAssertEqual(removed, "TDAH")
        XCTAssertFalse(v.string.contains("TDAH") && v.string.contains("TDAH y accesibilidad"))
        XCTAssertFalse(v.string.contains("TDAH y accesibilidad cognitiva."))
    }

    @MainActor func testDel03UndoRestores() {
        let (w, v, t, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let before = v.string
        _ = confirm(e, .deleteSelection)
        let r = confirm(e, .undo)
        guard case .success(.undone) = r else { return XCTFail("undo: \(r)") }
        XCTAssertEqual(v.string, before)
        _ = t
    }

    @MainActor func testDel04RedoReDeletes() {
        let (w, v, _, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        _ = confirm(e, .deleteSelection)
        let afterDelete = v.string
        _ = confirm(e, .undo)
        _ = confirm(e, .redo)
        XCTAssertEqual(v.string, afterDelete)
    }

    @MainActor func testDel05RequiresSelection() {
        let (w, _, _, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let out = e.receive(.deleteSelection)
        guard case .invalid(.noSelection) = out else { return XCTFail("sin selección debe ser inválido: \(out)") }
    }

    @MainActor func testDel06PreviewShowsSelectedText() {
        let (w, _, t, e, _) = makeRealTarget(select: "IHC"); defer { w.orderOut(nil) }
        let out = e.receive(.deleteSelection)
        guard case .needsConfirm(let p) = out else { return XCTFail() }
        XCTAssertTrue(p.preview.contains("IHC"), "preview debe mostrar selectedText actual: \(p.preview)")
        XCTAssertFalse(p.preview.contains("Borra"), "preview no reconstruye desde transcript")
        _ = t
    }

    @MainActor func testDel07UnicodeEmojiSingleOp() {
        let (w, v, _, e, _) = makeRealTarget(select: "🧠"); defer { w.orderOut(nil) }
        let before = v.string
        _ = confirm(e, .deleteSelection)
        XCTAssertFalse(v.string.contains("🧠"))
        _ = confirm(e, .undo)
        XCTAssertEqual(v.string, before, "un solo undo restaura el emoji completo")
    }

    @MainActor func testDel08RegistersUndo() {
        let (w, _, t, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        XCTAssertFalse(t.canUndo)
        _ = confirm(e, .deleteSelection)
        XCTAssertTrue(t.canUndo, "delete debe registrarse en UndoManager")
    }

    // MARK: - Replace

    @MainActor func testRep01ProposalNoMutation() {
        let (w, _, t, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let before = t.currentText
        let out = e.receive(.replaceSelection("atención"))
        guard case .needsConfirm = out else { return XCTFail() }
        XCTAssertEqual(t.currentText, before)
    }

    @MainActor func testRep02ConfirmReplaces() {
        let (w, v, _, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let r = confirm(e, .replaceSelection("atención"))
        guard case .success(.replaced(_, let old, let new)) = r else { return XCTFail("replace: \(r)") }
        XCTAssertEqual(old, "TDAH")
        XCTAssertEqual(new, "atención")
        XCTAssertTrue(v.string.contains("atención"))
    }

    @MainActor func testRep03UndoRestoresOriginal() {
        let (w, v, _, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let before = v.string
        _ = confirm(e, .replaceSelection("atención"))
        _ = confirm(e, .undo)
        XCTAssertEqual(v.string, before)
    }

    @MainActor func testRep04RedoReapplies() {
        let (w, v, _, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        _ = confirm(e, .replaceSelection("atención"))
        let replaced = v.string
        _ = confirm(e, .undo)
        _ = confirm(e, .redo)
        XCTAssertEqual(v.string, replaced)
    }

    @MainActor func testRep05RequiresSelection() {
        let (w, _, _, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let out = e.receive(.replaceSelection("x"))
        guard case .invalid(.noSelection) = out else { return XCTFail("requiere selección: \(out)") }
    }

    @MainActor func testRep06PreviewOldToNew() {
        let (w, _, _, e, _) = makeRealTarget(select: "IHC"); defer { w.orderOut(nil) }
        let out = e.receive(.replaceSelection("diseño"))
        guard case .needsConfirm(let p) = out else { return XCTFail() }
        XCTAssertTrue(p.preview.contains("IHC") && p.preview.contains("diseño") && p.preview.contains("→"))
    }

    @MainActor func testRep07JapaneseSingleUndo() {
        let (w, v, _, e, _) = makeRealTarget(select: "ユーザー"); defer { w.orderOut(nil) }
        let before = v.string
        _ = confirm(e, .replaceSelection("interfaz"))
        XCTAssertTrue(v.string.contains("interfaz"))
        _ = confirm(e, .undo)
        XCTAssertEqual(v.string, before)
    }

    @MainActor func testRep08AccentedArg() {
        let (w, v, _, e, _) = makeRealTarget(select: "IHC"); defer { w.orderOut(nil) }
        _ = confirm(e, .replaceSelection("Interacción Humano-Computadora"))
        XCTAssertTrue(v.string.contains("Interacción Humano-Computadora"))
    }

    // MARK: - Format

    @MainActor func testFmt01BoldMarkers() {
        let (w, v, _, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let r = confirm(e, .formatSelection(.bold))
        guard case .success(.formatted(.bold, _)) = r else { return XCTFail("bold: \(r)") }
        XCTAssertTrue(v.string.contains("**TDAH**"))
    }

    @MainActor func testFmt02BoldUndo() {
        let (w, v, _, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let before = v.string
        _ = confirm(e, .formatSelection(.bold))
        _ = confirm(e, .undo)
        XCTAssertEqual(v.string, before)
    }

    @MainActor func testFmt03ItalicMarkers() {
        let (w, v, _, e, _) = makeRealTarget(select: "IHC"); defer { w.orderOut(nil) }
        _ = confirm(e, .formatSelection(.italic))
        XCTAssertTrue(v.string.contains("*IHC*"))
    }

    @MainActor func testFmt04ItalicUndo() {
        let (w, v, _, e, _) = makeRealTarget(select: "IHC"); defer { w.orderOut(nil) }
        let before = v.string
        _ = confirm(e, .formatSelection(.italic))
        _ = confirm(e, .undo)
        XCTAssertEqual(v.string, before)
    }

    @MainActor func testFmt05UnderlineMarkers() {
        let (w, v, _, e, _) = makeRealTarget(select: "IHC"); defer { w.orderOut(nil) }
        _ = confirm(e, .formatSelection(.underline))
        XCTAssertTrue(v.string.contains("<u>IHC</u>"), "underline persiste como <u>: \(v.string)")
    }

    @MainActor func testFmt06UnderlineUndo() {
        let (w, v, _, e, _) = makeRealTarget(select: "IHC"); defer { w.orderOut(nil) }
        let before = v.string
        _ = confirm(e, .formatSelection(.underline))
        _ = confirm(e, .undo)
        XCTAssertEqual(v.string, before)
    }

    @MainActor func testFmt07RequiresSelection() {
        let (w, _, _, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let out = e.receive(.formatSelection(.bold))
        guard case .invalid(.noSelection) = out else { return XCTFail("formato requiere selección: \(out)") }
    }

    @MainActor func testFmt08BeforeEnterUnchanged() {
        let (w, _, t, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let before = t.currentText
        let out = e.receive(.formatSelection(.bold))
        guard case .needsConfirm = out else { return XCTFail() }
        XCTAssertEqual(t.currentText, before)
    }

    @MainActor func testFmt09ToggleUnwraps() {
        let (w, v, _, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let before = v.string
        _ = confirm(e, .formatSelection(.bold))
        XCTAssertTrue(v.string.contains("**TDAH**"))
        // Segunda aplicación conmuta (unwrap) como EditorSession.
        v.setSelectedRange((v.string as NSString).range(of: "TDAH"))
        _ = confirm(e, .formatSelection(.bold))
        XCTAssertEqual(v.string, before)
    }

    @MainActor func testFmt10AccentedSelection() {
        let (w, v, _, e, _) = makeRealTarget(select: "María-José"); defer { w.orderOut(nil) }
        _ = confirm(e, .formatSelection(.bold))
        XCTAssertTrue(v.string.contains("**María-José**"))
        _ = confirm(e, .undo)
        XCTAssertEqual(v.string, VoiceFixtureText.real)
    }

    @MainActor func testFmt11PreviewShowsSelected() {
        let (w, _, _, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let out = e.receive(.formatSelection(.italic))
        guard case .needsConfirm(let p) = out else { return XCTFail() }
        XCTAssertTrue(p.preview.contains("TDAH") && p.preview.contains("cursiva"))
    }

    @MainActor func testFmt12SingleUndoOp() {
        let (w, v, t, e, _) = makeRealTarget(select: "evaluación"); defer { w.orderOut(nil) }
        let before = v.string
        _ = confirm(e, .formatSelection(.bold))
        XCTAssertTrue(t.canUndo)
        _ = confirm(e, .undo)
        XCTAssertEqual(v.string, before, "formato = una sola operación de Undo")
    }

    // MARK: - Undo/Redo + C20

    @MainActor func testUR01UndoUsesRealManager() {
        let (w, _, t, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        _ = confirm(e, .deleteSelection)
        XCTAssertTrue(t.canUndo)
    }

    @MainActor func testUR02UndoBeforeConfirmZeroMutation() {
        let (w, _, t, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        _ = confirm(e, .deleteSelection)
        let before = t.currentText
        let out = e.receive(.undo)
        guard case .needsConfirm = out else { return XCTFail("undo requiere confirm") }
        XCTAssertEqual(t.currentText, before, "antes de Enter: 0 mutación")
    }

    @MainActor func testUR03UndoEmptyInvalid() {
        let (w, _, _, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let out = e.receive(.undo)
        guard case .invalid(.cannotUndo) = out else { return XCTFail("undo vacío: \(out)") }
    }

    @MainActor func testUR04RedoEmptyInvalid() {
        let (w, _, _, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let out = e.receive(.redo)
        guard case .invalid(.cannotRedo) = out else { return XCTFail("redo vacío: \(out)") }
    }

    @MainActor func testUR05UndoPreviewUnequivocal() {
        let (w, _, _, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        _ = confirm(e, .deleteSelection)
        let out = e.receive(.undo)
        guard case .needsConfirm(let p) = out else { return XCTFail() }
        XCTAssertTrue(p.preview.hasPrefix("↶"), "undo debe empezar con ↶: \(p.preview)")
        XCTAssertTrue(p.preview.contains("Deshacer"))
        XCTAssertFalse(p.preview.contains("↷"))
    }

    @MainActor func testUR06RedoPreviewUnequivocal() {
        let (w, _, _, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        _ = confirm(e, .deleteSelection)
        _ = confirm(e, .undo)
        let out = e.receive(.redo)
        guard case .needsConfirm(let p) = out else { return XCTFail() }
        XCTAssertTrue(p.preview.hasPrefix("↷"), "redo debe empezar con ↷: \(p.preview)")
        XCTAssertTrue(p.preview.contains("Rehacer"))
        XCTAssertFalse(p.preview.contains("↶"))
    }

    @MainActor func testUR07UndoPreviewWithManagerLabel() {
        let (w, _, _, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        _ = confirm(e, .renameTitle("Metodología"))
        let out = e.receive(.undo)
        guard case .needsConfirm(let p) = out else { return XCTFail() }
        XCTAssertEqual(p.preview, "↶ Deshacer: Renombrar título", "C20: etiqueta real de UndoManager: \(p.preview)")
    }

    @MainActor func testUR08RedoPreviewWithManagerLabel() {
        let (w, _, _, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        _ = confirm(e, .renameTitle("Metodología"))
        _ = confirm(e, .undo)
        let out = e.receive(.redo)
        guard case .needsConfirm(let p) = out else { return XCTFail() }
        XCTAssertTrue(p.preview.hasPrefix("↷ Rehacer"), "C20 redo: \(p.preview)")
    }

    @MainActor func testUR09UndoRedoRequireConfirm() {
        XCTAssertEqual(voicePolicyForCommand(.undo), .confirm)
        XCTAssertEqual(voicePolicyForCommand(.redo), .confirm)
        XCTAssertEqual(voicePolicyForCommand(.formatSelection(.bold)), .confirm)
    }

    @MainActor func testUR10UndoRedoCycle() {
        let (w, v, _, e, _) = makeRealTarget(select: "IHC"); defer { w.orderOut(nil) }
        let before = v.string
        _ = confirm(e, .replaceSelection("diseño"))
        _ = confirm(e, .undo)
        XCTAssertEqual(v.string, before)
        _ = confirm(e, .redo)
        XCTAssertTrue(v.string.contains("diseño"))
        _ = confirm(e, .undo)
        XCTAssertEqual(v.string, before)
    }

    // MARK: - Stale proposal

    @MainActor func testStale01SelectionChangeBlocksDelete() {
        let (w, v, t, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let before = v.string
        let out = e.receive(.deleteSelection)
        guard case .needsConfirm(let p) = out else { return XCTFail() }
        v.setSelectedRange((v.string as NSString).range(of: "IHC")) // usuario cambia selección
        let r = e.confirm(p)
        XCTAssertEqual(r, .failure(.staleProposal))
        XCTAssertEqual(v.string, before, "STALE: 0 mutación")
        _ = t
    }

    @MainActor func testStale02TextChangeBlocksReplace() {
        let (w, v, _, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let before = v.string
        let out = e.receive(.replaceSelection("x"))
        guard case .needsConfirm(let p) = out else { return XCTFail() }
        v.undoManager?.beginUndoGrouping()
        v.insertText("!", replacementRange: NSRange(location: 0, length: 0)) // edición externa
        v.undoManager?.endUndoGrouping()
        let r = e.confirm(p)
        XCTAssertEqual(r, .failure(.staleProposal))
        XCTAssertTrue(v.string.contains("TDAH"), "STALE no debe reemplazar otro estado")
        XCTAssertNotEqual(v.string, before.replacingOccurrences(of: "TDAH", with: "x"))
    }

    @MainActor func testStale03TitleChangeBlocksRename() {
        let (w, _, t, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let out = e.receive(.renameTitle("A"))
        guard case .needsConfirm(let p) = out else { return XCTFail() }
        _ = t.renameTitle(to: "Externo") // cambio intermedio
        let r = e.confirm(p)
        XCTAssertEqual(r, .failure(.staleProposal))
        XCTAssertEqual(t.documentTitle, "Externo")
    }

    @MainActor func testStale04UnknownProposalRejected() {
        let (w, _, _, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let out = e.receive(.deleteSelection)
        guard case .needsConfirm(let p) = out else { return XCTFail() }
        e.cancel()
        let r = e.confirm(p)
        XCTAssertEqual(r, .failure(.staleProposal), "proposal cancelada no debe ejecutar")
    }

    @MainActor func testStale05SelectionRemovedRevalidates() {
        let (w, v, _, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let before = v.string
        let out = e.receive(.deleteSelection)
        guard case .needsConfirm(let p) = out else { return XCTFail() }
        v.setSelectedRange(NSRange(location: 0, length: 0)) // selección desaparece
        let r = e.confirm(p)
        XCTAssertEqual(r, .invalidContext(.noSelection), "revalidación antes de ejecutar")
        XCTAssertEqual(v.string, before)
    }

    @MainActor func testStale06PendingClearedAfterStale() {
        let (w, v, _, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let out = e.receive(.deleteSelection)
        guard case .needsConfirm(let p) = out else { return XCTFail() }
        v.setSelectedRange(NSRange(location: 0, length: 0))
        _ = e.confirm(p)
        XCTAssertNil(e.pending)
    }

    // MARK: - Invariante de confirmación (todo lo que muta: 0 cambios antes de Enter)

    @MainActor func testConf01UndoInvariant() {
        let (w, _, t, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        _ = confirm(e, .deleteSelection)
        let beforeText = t.currentText
        let beforeTitle = t.documentTitle
        _ = e.receive(.undo)
        XCTAssertEqual(t.currentText, beforeText)
        XCTAssertEqual(t.documentTitle, beforeTitle)
    }

    @MainActor func testConf02RedoInvariant() {
        let (w, _, t, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        _ = confirm(e, .deleteSelection)
        _ = confirm(e, .undo)
        let beforeText = t.currentText
        let beforeTitle = t.documentTitle
        _ = e.receive(.redo)
        XCTAssertEqual(t.currentText, beforeText)
        XCTAssertEqual(t.documentTitle, beforeTitle)
    }

    @MainActor func testConf03FormatInvariant() {
        let (w, _, t, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let before = t.currentText
        _ = e.receive(.formatSelection(.bold))
        XCTAssertEqual(t.currentText, before)
    }

    @MainActor func testConf04DeleteInvariant() {
        let (w, _, t, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let before = t.currentText
        _ = e.receive(.deleteSelection)
        XCTAssertEqual(t.currentText, before)
    }

    @MainActor func testConf05ReplaceInvariant() {
        let (w, _, t, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let before = t.currentText
        _ = e.receive(.replaceSelection("x"))
        XCTAssertEqual(t.currentText, before)
    }

    @MainActor func testConf06RenameInvariant() {
        let (w, _, t, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        _ = e.receive(.renameTitle("X"))
        XCTAssertEqual(t.documentTitle, "Proyecto")
    }

    @MainActor func testConf07RewriteInvariant() {
        let (w, _, t, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let beforeText = t.currentText
        let beforeTitle = t.documentTitle
        let beforeUndo = t.canUndo
        _ = e.receive(.rewriteSelection("más breve"))
        XCTAssertEqual(t.currentText, beforeText)
        XCTAssertEqual(t.documentTitle, beforeTitle)
        XCTAssertEqual(t.canUndo, beforeUndo)
    }

    @MainActor func testConf08SaveInvariant() {
        let (w, v, _, e, s) = makeRealTarget(); defer { w.orderOut(nil) }
        let out = e.receive(.saveDocument)
        guard case .needsConfirm(let p) = out else { return XCTFail("save requiere confirm") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.url(for: "fixture", extension: "md")!.path),
                       "save no debe escribir antes de Enter")
        _ = e.confirm(p)
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.url(for: "fixture", extension: "md")!.path))
        _ = v
    }

    @MainActor func testConf09OpenInvariant() {
        let (w, v, _, e, s) = makeRealTarget(); defer { w.orderOut(nil) }
        try? s.write(text: "otro", name: "acta", extension: "md")
        let before = v.string
        let out = e.receive(.openDocument("acta"))
        guard case .needsConfirm = out else { return XCTFail("open requiere confirm") }
        XCTAssertEqual(v.string, before, "open no debe cargar antes de Enter")
    }

    @MainActor func testConf10ExportInvariant() {
        let (w, _, _, e, s) = makeRealTarget(); defer { w.orderOut(nil) }
        let out = e.receive(.exportDocument(.plainText))
        guard case .needsConfirm(let p) = out else { return XCTFail("export requiere confirm") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.url(for: "fixture", extension: "txt")!.path))
        _ = e.confirm(p)
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.url(for: "fixture", extension: "txt")!.path))
    }

    @MainActor func testConf11NavNeedsNoConfirm() {
        let (w, _, _, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        if case .needsConfirm = e.receive(.findText("TDAH")) { XCTFail("find no lleva preview") }
        if case .needsConfirm = e.receive(.selectText("TDAH")) { XCTFail("select no lleva preview") }
    }

    // MARK: - Rewrite simulado (sin Foundation Models)

    @MainActor func testRew01CapturesAll() {
        let (w, v, t, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let sel = v.selectedRange()
        let out = e.receive(.rewriteSelection("más breve"))
        guard case .needsConfirm(let p) = out else { return XCTFail() }
        let r = e.confirm(p)
        guard case .simulated(let req) = r else { return XCTFail("rewrite debe ser simulated: \(r)") }
        XCTAssertEqual(req.selectedText, "TDAH")
        XCTAssertEqual(req.instruction, "más breve")
        XCTAssertEqual(req.range, sel)
        XCTAssertEqual(t.simulatedRewrites, [req])
    }

    @MainActor func testRew02DocumentUnchanged() {
        let (w, v, _, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let before = v.string
        let out = e.receive(.rewriteSelection("más formal"))
        guard case .needsConfirm(let p) = out else { return XCTFail() }
        _ = e.confirm(p)
        XCTAssertEqual(v.string, before)
    }

    @MainActor func testRew03UndoUntouched() {
        let (w, v, t, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        v.undoManager?.beginUndoGrouping()
        v.insertText("!", replacementRange: NSRange(location: 0, length: 0))
        v.undoManager?.endUndoGrouping()
        let before = v.string
        XCTAssertTrue(t.canUndo)
        let out = e.receive(.rewriteSelection("hazlo"))
        guard case .needsConfirm(let p) = out else { return XCTFail() }
        _ = e.confirm(p)
        XCTAssertTrue(t.canUndo, "rewrite no debe limpiar ni añadir historial")
        _ = confirm(e, .undo) // deshace la edición "!", no el rewrite
        XCTAssertEqual(v.string, before.replacingOccurrences(of: "!", with: ""))
    }

    @MainActor func testRew04PreviewHasInstruction() {
        let (w, _, _, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let out = e.receive(.rewriteSelection("más breve"))
        guard case .needsConfirm(let p) = out else { return XCTFail() }
        XCTAssertTrue(p.preview.contains("más breve") && p.preview.contains("TDAH"))
    }

    @MainActor func testRew05RequiresSelection() {
        let (w, _, _, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let out = e.receive(.rewriteSelection("x"))
        guard case .invalid(.noSelection) = out else { return XCTFail() }
    }

    // MARK: - Rename

    @MainActor func testRen01PreviewOldToNew() {
        let (w, _, _, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let out = e.receive(.renameTitle("Metodología"))
        guard case .needsConfirm(let p) = out else { return XCTFail() }
        XCTAssertTrue(p.preview.contains("Proyecto") && p.preview.contains("Metodología") && p.preview.contains("→"))
    }

    @MainActor func testRen02ConfirmChangesTitle() {
        let (w, _, t, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let r = confirm(e, .renameTitle("Metodología"))
        guard case .success(.titleChanged(let old, let new)) = r else { return XCTFail("rename: \(r)") }
        XCTAssertEqual(old, "Proyecto")
        XCTAssertEqual(new, "Metodología")
        XCTAssertEqual(t.documentTitle, "Metodología")
    }

    @MainActor func testRen03UndoRestoresTitle() {
        let (w, _, t, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        _ = confirm(e, .renameTitle("Metodología"))
        _ = confirm(e, .undo)
        XCTAssertEqual(t.documentTitle, "Proyecto")
    }

    @MainActor func testRen04RedoReappliesTitle() {
        let (w, _, t, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        _ = confirm(e, .renameTitle("Metodología"))
        _ = confirm(e, .undo)
        _ = confirm(e, .redo)
        XCTAssertEqual(t.documentTitle, "Metodología")
    }

    @MainActor func testRen05TitleChangeDoesNotTouchText() {
        let (w, v, _, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let before = v.string
        _ = confirm(e, .renameTitle("IHC 2026"))
        XCTAssertEqual(v.string, before)
    }

    // MARK: - Save/Open/Export

    @MainActor func testDoc01SaveWritesTempMD() throws {
        let (w, v, _, e, s) = makeRealTarget(); defer { w.orderOut(nil) }
        let r = confirm(e, .saveDocument)
        guard case .success(.saved(let url)) = r else { return XCTFail("save: \(r)") }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), v.string)
        XCTAssertTrue(url.path.hasPrefix(s.baseDirectory.path))
    }

    @MainActor func testDoc02OpenLoadsFixture() throws {
        let (w, v, _, e, s) = makeRealTarget(); defer { w.orderOut(nil) }
        try s.write(text: "contenido del acta", name: "acta-1", extension: "md")
        v.string = "borrador distinto"
        let r = confirm(e, .openDocument("acta-1"))
        guard case .success(.opened(let name, _)) = r else { return XCTFail("open: \(r)") }
        XCTAssertEqual(name, "acta-1")
        XCTAssertEqual(v.string, "contenido del acta")
    }

    @MainActor func testDoc03OpenNilReopensLast() throws {
        let (w, v, _, e, s) = makeRealTarget(); defer { w.orderOut(nil) }
        try s.write(text: "uno", name: "doc-a", extension: "md")
        _ = confirm(e, .openDocument("doc-a"))
        v.string = "modificado"
        _ = confirm(e, .openDocument(nil))
        XCTAssertEqual(v.string, "uno", "open nil reabre el último documento")
    }

    @MainActor func testDoc04OpenMissingIsIOError() {
        let (w, v, _, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let before = v.string
        let r = confirm(e, .openDocument("no-existe-xyz"))
        guard case .failure(.ioError) = r else { return XCTFail("open inexistente: \(r)") }
        XCTAssertEqual(v.string, before, "open fallido no muta")
    }

    @MainActor func testDoc05ExportTxt() throws {
        let (w, v, _, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let r = confirm(e, .exportDocument(.plainText))
        guard case .success(.exported(.plainText, let url)) = r else { return XCTFail("export txt: \(r)") }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), v.string)
        XCTAssertEqual(url.pathExtension, "txt")
    }

    @MainActor func testDoc06ExportRtf() {
        let (w, _, _, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let r = confirm(e, .exportDocument(.richText))
        guard case .success(.exported(.richText, let url)) = r else { return XCTFail("export rtf: \(r)") }
        let data = try? Data(contentsOf: url)
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 0)
    }

    @MainActor func testDoc07ExportPdf() {
        let (w, v, _, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let r = confirm(e, .exportDocument(.pdf))
        guard case .success(.exported(.pdf, let url)) = r else { return XCTFail("export pdf: \(r)") }
        XCTAssertEqual(url.pathExtension, "pdf")
        let data = try? Data(contentsOf: url)
        XCTAssertGreaterThan(data?.count ?? 0, 0)
        _ = v
    }

    @MainActor func testDoc08ExportWord() {
        let (w, _, _, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let r = confirm(e, .exportDocument(.word))
        guard case .success(.exported(.word, let url)) = r else { return XCTFail("export word: \(r)") }
        XCTAssertEqual(url.pathExtension, "docx")
        let data = try? Data(contentsOf: url)
        XCTAssertGreaterThan(data?.count ?? 0, 0)
        // Office Open XML es un zip: empieza con "PK".
        XCTAssertEqual(data?.prefix(2).map { $0 }, [0x50, 0x4B])
    }

    @MainActor func testDoc09StoreNeverEscapesBase() {
        let (w, _, _, _, s) = makeRealTarget(); defer { w.orderOut(nil) }
        let evil = s.url(for: "../evil", extension: "md")!
        XCTAssertTrue(evil.standardizedFileURL.path.hasPrefix(s.baseDirectory.standardizedFileURL.path),
                      "path traversal contenido: \(evil.path)")
    }

    @MainActor func testDoc10UndoAfterOpen() throws {
        let (w, v, _, e, s) = makeRealTarget(); defer { w.orderOut(nil) }
        let before = v.string
        try s.write(text: "nuevo contenido", name: "otro", extension: "md")
        _ = confirm(e, .openDocument("otro"))
        XCTAssertEqual(v.string, "nuevo contenido")
        _ = confirm(e, .undo)
        XCTAssertEqual(v.string, before, "open es deshacible")
    }

    // MARK: - Rangos y Unicode

    @MainActor func testUni01ValidatedAcceptsASCII() {
        XCTAssertNotNil(UnicodeRanges.validated(NSRange(location: 0, length: 5), in: "hello world"))
    }

    @MainActor func testUni02ValidatedRejectsNegative() {
        XCTAssertNil(UnicodeRanges.validated(NSRange(location: -1, length: 1), in: "hola"))
    }

    @MainActor func testUni03ValidatedRejectsOverflow() {
        XCTAssertNil(UnicodeRanges.validated(NSRange(location: 0, length: 99), in: "hola"))
        XCTAssertNil(UnicodeRanges.validated(NSRange(location: 4, length: 1), in: "hola"))
    }

    @MainActor func testUni04PartialEmojiRejected() {
        let text = "a🧠b" // 🧠 = 2 unidades UTF-16
        XCTAssertNil(UnicodeRanges.validated(NSRange(location: 1, length: 1), in: text),
                     "partir un grafema debe ser inválido")
    }

    @MainActor func testUni05FullEmojiAccepted() {
        let text = "a🧠b"
        XCTAssertNotNil(UnicodeRanges.validated(NSRange(location: 1, length: 2), in: text))
    }

    @MainActor func testUni06PartialZWJRejected() {
        let text = "x👩🏽‍💻y"
        let full = (text as NSString).range(of: "👩🏽‍💻")
        XCTAssertGreaterThan(full.length, 1)
        XCTAssertNil(UnicodeRanges.validated(NSRange(location: full.location, length: 1), in: text))
        XCTAssertNotNil(UnicodeRanges.validated(full, in: text))
    }

    @MainActor func testUni07AccentedRangeValid() {
        let text = "evaluación"
        let r = (text as NSString).range(of: "evaluación")
        XCTAssertNotNil(UnicodeRanges.validated(r, in: text))
    }

    @MainActor func testUni08JapaneseRangeValid() {
        let text = "ユーザーインターフェース"
        let r = (text as NSString).range(of: "ユーザー")
        XCTAssertNotNil(UnicodeRanges.validated(r, in: text))
    }

    @MainActor func testUni09ClampCursor() {
        XCTAssertEqual(UnicodeRanges.clampCursor(NSRange(location: 99, length: 0), in: "hola"),
                       NSRange(location: 4, length: 0))
    }

    @MainActor func testUni10FindNeverPartialGrapheme() {
        let (w, _, t, _, _) = makeRealTarget(text: "a🧠b"); defer { w.orderOut(nil) }
        // Query que solo coincidiría con medio surrogate no debe seleccionar nada válido.
        let r = t.selectText("🧠")
        guard case .success(.selected(let range)) = r else { return XCTFail("select emoji: \(r)") }
        XCTAssertEqual(range.length, ("🧠" as NSString).length)
    }

    @MainActor func testUni11DeleteNeverCorruptsSurrogates() {
        let (w, v, _, e, _) = makeRealTarget(text: "a🧠b"); defer { w.orderOut(nil) }
        // Intento de selección a medio grafema: AppKit la coacciona o el target la rechaza.
        v.setSelectedRange(NSRange(location: 1, length: 1))
        let before = v.string
        let out = e.receive(.deleteSelection)
        switch out {
        case .invalid(.noSelection):
            XCTAssertEqual(v.string, before)
        case .needsConfirm(let p):
            _ = e.confirm(p)
            let delta = before.utf16.count - v.string.utf16.count
            XCTAssertTrue(delta == 0 || delta == 2, "nunca medio surrogate: delta=\(delta)")
            XCTAssertNotNil(Range(NSRange(location: 0, length: v.string.utf16.count), in: v.string))
        default:
            XCTFail("resultado inesperado: \(out)")
        }
    }

    @MainActor func testUni12SelectNWithTilde() {
        let (w, v, t, _, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let r = t.selectText("María-José Pérez")
        guard case .success(.selected(let range)) = r else { return XCTFail("select ñ/acentos: \(r)") }
        XCTAssertEqual((v.string as NSString).substring(with: range), "María-José Pérez")
    }

    // MARK: - Política, rechazos y sesión

    @MainActor func testPol01ImmediateOnlyNav() {
        let nav: [VoiceCommand] = [.findText("a"), .selectText("b")]
        for c in nav { XCTAssertEqual(voicePolicyForCommand(c), .immediate, "\(c)") }
        let mut: [VoiceCommand] = [.renameTitle("x"), .deleteSelection, .replaceSelection("x"),
            .rewriteSelection("x"), .formatSelection(.bold), .undo, .redo,
            .saveDocument, .openDocument("x"), .exportDocument(.pdf)]
        for c in mut { XCTAssertEqual(voicePolicyForCommand(c), .confirm, "\(c)") }
    }

    @MainActor func testPol02RiskMapping() {
        XCTAssertEqual(voiceRiskOf(.findText("a")), .navigation)
        XCTAssertEqual(voiceRiskOf(.selectText("a")), .navigation)
        XCTAssertEqual(voiceRiskOf(.undo), .reversible)
        XCTAssertEqual(voiceRiskOf(.redo), .reversible)
        XCTAssertEqual(voiceRiskOf(.formatSelection(.italic)), .reversible)
        XCTAssertEqual(voiceRiskOf(.deleteSelection), .contentChanging)
        XCTAssertEqual(voiceRiskOf(.saveDocument), .externalSideEffect)
    }

    @MainActor func testPol03UnsupportedRejected() {
        let (w, _, t, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let before = t.currentText
        let out = e.receive(.unsupported("imprime"))
        guard case .rejected = out else { return XCTFail("unsupported: \(out)") }
        XCTAssertEqual(t.currentText, before)
    }

    @MainActor func testPol04UnknownRejected() {
        let (w, _, t, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let before = t.currentText
        let out = e.receive(.unknown)
        guard case .rejected = out else { return XCTFail("unknown: \(out)") }
        XCTAssertEqual(t.currentText, before)
    }

    @MainActor func testPol05MultiRejected() {
        let (w, _, t, e, _) = makeRealTarget(); defer { w.orderOut(nil) }
        let before = t.currentText
        let out = e.receive(.multipleActions)
        guard case .rejected = out else { return XCTFail("multi: \(out)") }
        XCTAssertEqual(t.currentText, before)
    }

    @MainActor func testPol06CancelNoMutation() {
        let (w, _, t, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let before = t.currentText
        _ = e.receive(.deleteSelection)
        e.cancel()
        XCTAssertNil(e.pending)
        XCTAssertEqual(t.currentText, before)
    }

    @MainActor func testPol07RepeatClearsPending() {
        let (w, _, t, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let before = t.currentText
        _ = e.receive(.deleteSelection)
        XCTAssertNotNil(e.pending)
        e.requestRepeat()
        XCTAssertNil(e.pending)
        XCTAssertEqual(t.currentText, before)
    }

    @MainActor func testPol08DoubleConfirmNoOp() {
        let (w, v, _, e, _) = makeRealTarget(select: "TDAH"); defer { w.orderOut(nil) }
        let out = e.receive(.deleteSelection)
        guard case .needsConfirm(let p) = out else { return XCTFail() }
        _ = e.confirm(p)
        let afterFirst = v.string
        let second = e.confirm(p)
        XCTAssertEqual(second, .failure(.staleProposal))
        XCTAssertEqual(v.string, afterFirst, "segunda confirmación no duplica efectos")
    }

    @MainActor func testPol09FixtureTextComplete() {
        let f = VoiceFixtureText.real
        for required in ["TDAH", "Metodología", "María-José Pérez", "IHC 2026", "7.5%",
                         "🧠", "interacción", "evaluación", "metodología",
                         "ユーザーインターフェース", "Texto normal en español."] {
            XCTAssertTrue(f.contains(required), "fixture debe incluir: \(required)")
        }
    }

    @MainActor func testPol10HarnessRunsFlow() {
        let (w, v, _, _, s) = makeRealTarget(); defer { w.orderOut(nil) }
        let harness = RealEditorCommandTestHarness(store: s, view: v)
        let step = harness.run("Borra esto", .deleteSelection, decision: "esc")
        XCTAssertTrue(step.outcome.contains("cancel") || step.outcome.contains("invalid"),
                      "harness esc sin selección: \(step.outcome)")
        XCTAssertEqual(v.string, VoiceFixtureText.real)
    }
}
