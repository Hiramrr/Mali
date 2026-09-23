import XCTest
import AppKit
import CommandGrammar
import EditorCore
import EditorEngine
@testable import ModuleKit
@testable import VoiceModule

/// Doble sin micrófono: devuelve texto fijo en `stop()`.
final class MockSpeechRecognizer: VoiceSpeechRecognizer, @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var _started = false
    var nextTranscript = ""
    var didStart: Bool { lock.withLock { _started } }

    var onPartial: (@Sendable (String) -> Void)?
    var onLevel: (@Sendable (Float) -> Void)?
    // Sin voz real si el texto es vacío o solo espacios (como el VAD de energía).
    var hasSpeech: Bool { !nextTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var liveTranscript: String { nextTranscript }

    func start() async throws {
        lock.withLock { _started = true }
    }

    func stop() async throws -> String { nextTranscript }
    func cancel() async { lock.withLock { _started = false } }
}

final class VoiceCommandParserTests: XCTestCase {
    func testCommands() {
        let parser = VoiceCommandParser()
        XCTAssertEqual(parser.parse("cancelar"), .cancel)
        XCTAssertEqual(parser.parse("Borra eso."), .deleteLastInsertion)
        XCTAssertEqual(parser.parse("deshacer"), .undo)
        XCTAssertEqual(parser.parse("nueva línea"), .newline)
        XCTAssertEqual(parser.parse("nuevo párrafo"), .paragraph)
    }

    func testDictationIsNotACommand() {
        let parser = VoiceCommandParser()
        XCTAssertNil(parser.parse("hola mundo"))
        // Comando mezclado en frase larga: no dispara.
        XCTAssertNil(parser.parse("quiero decir que borra eso por favor y sigue escribiendo mucho más"))
        XCTAssertNil(parser.parse(""))
    }

    @MainActor func testRenameTitleViaGrammar() {
        // El rename ahora lo resuelve la gramática probada (fuente única),
        // no el parser legacy: mismo resultado, bestemado en 447 tests.
        let module = VoiceModule(recognizer: MockSpeechRecognizer())
        XCTAssertEqual(module.process(rawTranscript: "Cambia el título a prueba."), .command(.renameTitle("prueba")))
        XCTAssertEqual(module.process(rawTranscript: "Cambia el titulo a Metodología"), .command(.renameTitle("Metodología")))
        XCTAssertEqual(module.process(rawTranscript: "Pon como título IHC 2026."), .command(.renameTitle("IHC 2026")))
        XCTAssertEqual(module.process(rawTranscript: "Ponle de título TDAH"), .command(.renameTitle("TDAH")))
        XCTAssertEqual(module.process(rawTranscript: "Titula Informe final"), .command(.renameTitle("Informe final")))
        XCTAssertEqual(module.process(rawTranscript: "Renombra a Borrador 2"), .command(.renameTitle("Borrador 2")))
        // El argumento va verbatim: si el STT confunde ("de usabilidad" por
        // ", sensibilidad"), el título refleja el transcript tal cual.
        XCTAssertEqual(
            module.process(rawTranscript: "Cambia el titulo a prueba, sensibilidad."),
            .command(.renameTitle("prueba, sensibilidad"))
        )
    }

    func testRenameTitleGuards() {
        let parser = VoiceCommandParser()
        // Sin argumento, vacío efectivo o frase larga: no es comando (dictado).
        XCTAssertNil(parser.parse("Cambia el título a."))
        XCTAssertNil(parser.parse("Cambia el título a "))
        XCTAssertNil(parser.parse("Titula"))
        XCTAssertNil(parser.parse("quiero que cambies el título a otro porque este no me gusta nada"))
        XCTAssertNil(parser.parse("hola mundo"))
    }

    @MainActor func testFullGrammarCommands() {
        // La gramática probada (fuente única) resuelve los 12 comandos.
        let module = VoiceModule(recognizer: MockSpeechRecognizer())
        XCTAssertEqual(module.process(rawTranscript: "Cambia el título a prueba."), .command(.renameTitle("prueba")))
        XCTAssertEqual(module.process(rawTranscript: "Busca TDAH."), .command(.findText("TDAH")))
        XCTAssertEqual(module.process(rawTranscript: "Selecciona IHC."), .command(.selectText("IHC")))
        XCTAssertEqual(module.process(rawTranscript: "Ponlo en negritas."), .command(.formatSelection(.bold)))
        XCTAssertEqual(module.process(rawTranscript: "Borra la selección."), .command(.deleteSelection))
        XCTAssertEqual(module.process(rawTranscript: "Sustituye esto por diseño."), .command(.replaceSelection("diseño")))
        XCTAssertEqual(module.process(rawTranscript: "Deshaz el cambio."), .command(.undo))
        XCTAssertEqual(module.process(rawTranscript: "Rehaz el cambio."), .command(.redo))
        XCTAssertEqual(module.process(rawTranscript: "Guarda el documento."), .command(.saveDocument))
        XCTAssertEqual(module.process(rawTranscript: "Exporta a pdf."), .command(.exportDocument(.pdf)))
        XCTAssertEqual(module.process(rawTranscript: "Hazlo más breve."), .command(.rewriteSelection("más breve")))
    }

    @MainActor func testTitleDeAdaptation() {
        // El STT confunde a/de: segundo intento con "a", sin tocar Grammar.
        let module = VoiceModule(recognizer: MockSpeechRecognizer())
        XCTAssertEqual(module.process(rawTranscript: "Cambia el título de prueba."), .command(.renameTitle("prueba")))
        XCTAssertEqual(VoiceModule.adaptTitleDe("Cambia el título de prueba."), "Cambia el título a prueba.")
        XCTAssertNil(VoiceModule.adaptTitleDe("Cambia el título a prueba."))
        XCTAssertNil(VoiceModule.adaptTitleDe("hola mundo"))
    }

    @MainActor func testLegacyWinsAndFallbackIsDictation() {
        let module = VoiceModule(recognizer: MockSpeechRecognizer())
        // "Borra eso" sigue siendo undo (legacy), no deleteSelection.
        XCTAssertEqual(module.process(rawTranscript: "borra eso"), .deleteLastInsertion)
        // Lo no accionable (unsupported/unknown/múltiple) cae a dictado.
        if case .dictation = module.process(rawTranscript: "Imprime el documento.") { } else {
            XCTFail("unsupported debe caer a dictado")
        }
        if case .dictation = module.process(rawTranscript: "klmn xyz wq") { } else {
            XCTFail("unknown debe caer a dictado")
        }
        if case .dictation = module.process(rawTranscript: "hola coma mundo") { } else {
            XCTFail("dictado normal intacto")
        }
    }

    @MainActor func testCommandMapping() {
        let module = VoiceModule(recognizer: MockSpeechRecognizer())
        XCTAssertEqual(module.editorCommands(for: .renameTitle("X")), [.renameTitle("X")])
        XCTAssertEqual(module.editorCommands(for: .deleteSelection), [.replaceSelection("")])
        XCTAssertEqual(module.editorCommands(for: .replaceSelection("diseño")), [.replaceSelection("diseño")])
        XCTAssertEqual(module.editorCommands(for: .formatSelection(.bold)), [.toggleBold])
        XCTAssertEqual(module.editorCommands(for: .formatSelection(.italic)), [.toggleItalic])
        XCTAssertEqual(module.editorCommands(for: .formatSelection(.underline)), [.toggleUnderline])
        XCTAssertEqual(module.editorCommands(for: VoiceIntent.undo), [.undo])
        XCTAssertEqual(module.editorCommands(for: .redo), [.redo])
        XCTAssertEqual(module.editorCommands(for: .findText("a")), [.findText("a")])
        XCTAssertEqual(module.editorCommands(for: .selectText("b")), [.selectText("b")])
        XCTAssertEqual(module.editorCommands(for: .saveDocument), [.saveDocument])
        XCTAssertEqual(module.editorCommands(for: .openDocument("x")), [.openDocument("x")])
        XCTAssertEqual(module.editorCommands(for: .exportDocument(.pdf)), [.exportDocument("pdf")])
        XCTAssertEqual(module.editorCommands(for: .exportDocument(.plainText)), [.exportDocument("txt")])
        XCTAssertEqual(module.editorCommands(for: .exportDocument(.richText)), [.exportDocument("rtf")])
        // Sin fingir: rewrite y word no emiten comandos.
        XCTAssertEqual(module.editorCommands(for: .rewriteSelection("x")), [])
        XCTAssertEqual(module.editorCommands(for: .exportDocument(.word)), [])
        XCTAssertEqual(module.editorCommands(for: .unsupported("z")), [])
        XCTAssertEqual(module.editorCommands(for: .unknown), [])
        XCTAssertEqual(module.editorCommands(for: .multipleActions), [])
    }

    @MainActor func testCommandFeedback() {
        let module = VoiceModule(recognizer: MockSpeechRecognizer())
        XCTAssertFalse(module.feedback(for: .saveDocument).isEmpty)
        XCTAssertFalse(module.feedback(for: .renameTitle("X")).isEmpty)
        XCTAssertTrue(module.feedback(for: .exportDocument(.word)).contains("Word"))
        XCTAssertTrue(module.feedback(for: .rewriteSelection("x")).contains("Fase 12"))
    }

    func testEndpointReached() {
        XCTAssertTrue(VoiceModule.endpointReached(partial: "hola", unchangedFor: 2.0, timeout: 1.6))
        XCTAssertFalse(VoiceModule.endpointReached(partial: "hola", unchangedFor: 0.5, timeout: 1.6))
        XCTAssertFalse(VoiceModule.endpointReached(partial: "   ", unchangedFor: 9.0, timeout: 1.6))
        XCTAssertFalse(VoiceModule.endpointReached(partial: "", unchangedFor: 9.0, timeout: 1.6))
    }
}

final class DictationCleanerTests: XCTestCase {
    func testFillersAndPunctuation() {
        let cleaner = DictationCleaner()
        // "eh" fuera, "coma" a signo, formal con punto final.
        XCTAssertEqual(cleaner.clean("eh hola coma mundo"), "Hola, mundo.")
    }

    func testLocutionsArePreserved() {
        let cleaner = DictationCleaner()
        XCTAssertEqual(cleaner.clean("punto de encuentro", formal: false), "punto de encuentro")
    }

    func testCustomCorrectionsWin() {
        let cleaner = DictationCleaner()
        let out = cleaner.clean("miyu wisp es bueno", formal: false, customCorrections: [(from: "miyu wisp", to: "MiyuWisp")])
        XCTAssertEqual(out, "MiyuWisp es bueno")
    }
}

final class VoiceBusRegistryTests: XCTestCase {
    func testBusDeliversCommand() async {
        let bus = EditorCommandBus()
        let stream = await bus.commands()
        await bus.send(.insertText("hola"))
        var received: EditorCommand?
        for await command in stream {
            received = command
            break
        }
        XCTAssertEqual(received, .insertText("hola"))
        await bus.finish()
    }

    @MainActor func testRegistry() {
        let registry = ModuleRegistry()
        XCTAssertFalse(registry.isRegistered(identifier: "voice.dictation"))
        registry.register(VoiceModule.descriptor)
        XCTAssertTrue(registry.isRegistered(identifier: "voice.dictation"))
        registry.unregister(identifier: "voice.dictation")
        XCTAssertFalse(registry.isRegistered(identifier: "voice.dictation"))
    }
}

final class VoiceModuleTests: XCTestCase {
    @MainActor func testIntentMapping() {
        let module = VoiceModule(recognizer: MockSpeechRecognizer())
        XCTAssertEqual(module.editorCommands(for: .dictation("Hola.")), [.insertText("Hola.")])
        XCTAssertEqual(module.editorCommands(for: .newline), [.insertText("\n")])
        XCTAssertEqual(module.editorCommands(for: .paragraph), [.insertText("\n\n")])
        XCTAssertEqual(module.editorCommands(for: VoiceIntent.undo), [.undo])
        // "Borra eso" usa el UndoManager del editor: equivale a undo.
        XCTAssertEqual(module.editorCommands(for: .deleteLastInsertion), [.undo])
        XCTAssertEqual(module.editorCommands(for: .cancel), [])
        XCTAssertEqual(module.editorCommands(for: .dictation("")), [])
    }

    @MainActor func testProcessPrefersCommands() {
        let module = VoiceModule(recognizer: MockSpeechRecognizer())
        XCTAssertEqual(module.process(rawTranscript: "borra eso"), .deleteLastInsertion)
        if case .dictation(let text) = module.process(rawTranscript: "hola coma mundo") {
            XCTAssertEqual(text, "Hola, mundo.")
        } else {
            XCTFail("Se esperaba dictado limpio")
        }
    }

    @MainActor func testToggleInsertsThroughBus() async throws {
        let bus = EditorCommandBus()
        let mock = MockSpeechRecognizer()
        mock.nextTranscript = "hola coma mundo"
        let module = VoiceModule(recognizer: mock)
        try await module.start(context: EditorModuleContext(commandBus: bus))
        let stream = await bus.commands()
        await module.begin()
        XCTAssertTrue(mock.didStart)
        await module.finish()
        var received: EditorCommand?
        for await command in stream {
            received = command
            break
        }
        XCTAssertEqual(received, .insertText("Hola, mundo."))
        await bus.finish()
    }

    @MainActor func testVoiceCommandTravelsAsUndo() async throws {
        let bus = EditorCommandBus()
        let mock = MockSpeechRecognizer()
        mock.nextTranscript = "deshacer"
        let module = VoiceModule(recognizer: mock)
        try await module.start(context: EditorModuleContext(commandBus: bus))
        let stream = await bus.commands()
        await module.begin()
        await module.finish()
        var received: EditorCommand?
        for await command in stream {
            received = command
            break
        }
        XCTAssertEqual(received, .undo)
        await bus.finish()
    }

    @MainActor func testRenameTitleTravelsAsRenameNotInsert() async throws {
        // Regresión del reporte: "Cambia el título a prueba." insertaba texto.
        let bus = EditorCommandBus()
        let mock = MockSpeechRecognizer()
        mock.nextTranscript = "Cambia el título a prueba."
        let module = VoiceModule(recognizer: mock)
        try await module.start(context: EditorModuleContext(commandBus: bus))
        let stream = await bus.commands()
        await module.begin()
        await module.finish()
        var received: EditorCommand?
        for await command in stream {
            received = command
            break
        }
        XCTAssertEqual(received, .renameTitle("prueba"))
        await bus.finish()
    }

    @MainActor func testSilenceDoesNotInsert() async throws {
        let bus = EditorCommandBus()
        let mock = MockSpeechRecognizer()
        mock.nextTranscript = "   "
        let module = VoiceModule(recognizer: mock)
        try await module.start(context: EditorModuleContext(commandBus: bus))
        await module.begin()
        await module.finish()
        if case .failed(let message) = module.state {
            XCTAssertTrue(message.lowercased().contains("silencio"))
        } else {
            XCTFail("Se esperaba estado de silencio, fue \(module.state)")
        }
        await bus.finish()
    }

    @MainActor func testSessionNeverInsertsTitleAsText() {
        // texto, la selección y el historial quedan intactos.
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let view = NSTextView(usingTextLayoutManager: true)
        view.isRichText = false
        view.allowsUndo = true
        window.contentView = view
        window.makeFirstResponder(view)
        view.string = "texto intacto"
        view.undoManager?.removeAllActions()
        let session = EditorSession()
        session.textView = view
        session.send(.renameTitle("prueba"))
        XCTAssertEqual(view.string, "texto intacto")
        XCTAssertFalse(view.undoManager?.canUndo ?? true)
        window.orderOut(nil)
    }

    @MainActor func testSessionFindSelect() {
        let (window, view, session) = voiceTestSession(text: "TDAH y accesibilidad con 🧠 y metodología.")
        session.send(.findText("metodologia"))
        XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "metodología")
        let before = view.string
        session.send(.selectText("🧠"))
        XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "🧠")
        XCTAssertEqual(view.string, before, "find/select jamás mutan contenido")
        XCTAssertFalse(view.undoManager?.canUndo ?? true, "navegación no toca historial")
        session.send(.findText("zzz-sin-match"))
        XCTAssertEqual(view.string, before)
        window.orderOut(nil)
    }

    @MainActor func testSessionUnderline() {
        let (window, view, session) = voiceTestSession(text: "texto claro aquí")
        voiceTestSelect(view, "claro")
        let before = view.string
        session.send(.toggleUnderline)
        XCTAssertTrue(view.string.contains("<u>claro</u>"))
        view.undoManager?.undo()
        XCTAssertEqual(view.string, before)
        window.orderOut(nil)
    }

    @MainActor func testSessionReplaceDeleteGuards() {
        let (window, view, session) = voiceTestSession(text: "borra esto por favor")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        session.send(.replaceSelection("X"))
        XCTAssertEqual(view.string, "borra esto por favor", "replace sin selección no inserta")
        voiceTestSelect(view, "esto")
        session.send(.replaceSelection(""))
        XCTAssertEqual(view.string, "borra  por favor", "delete = replace vacío con selección")
        view.undoManager?.undo()
        XCTAssertEqual(view.string, "borra esto por favor", "un undo restaura")
        window.orderOut(nil)
    }
}

@MainActor private func voiceTestSession(text: String) -> (NSWindow, NSTextView, EditorSession) {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let view = NSTextView(usingTextLayoutManager: true)
    view.isRichText = false
    view.allowsUndo = true
    window.contentView = view
    window.makeFirstResponder(view)
    view.undoManager?.groupsByEvent = false
    view.string = text
    view.breakUndoCoalescing()
    view.undoManager?.removeAllActions()
    let session = EditorSession()
    session.textView = view
    return (window, view, session)
}

@MainActor private func voiceTestSelect(_ view: NSTextView, _ query: String) {
    let r = (view.string as NSString).range(of: query)
    guard r.location != NSNotFound else { return }
    view.setSelectedRange(r)
}
