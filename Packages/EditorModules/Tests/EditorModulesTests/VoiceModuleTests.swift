import XCTest
import AppKit
import CommandGrammar
import EditorCore
import EditorEngine
@testable import EditorUI
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

private final class DelayedSpeechRecognizer: VoiceSpeechRecognizer, @unchecked Sendable {
    private let lock = NSLock()
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var started = false
    private var stoppedBeforeStart = false
    var onStart: (@Sendable () -> Void)?
    var onPartial: (@Sendable (String) -> Void)?
    var onLevel: (@Sendable (Float) -> Void)?
    var hasSpeech: Bool { true }
    var liveTranscript: String { "hola" }
    var didStopBeforeStart: Bool { lock.withLock { stoppedBeforeStart } }

    func start() async throws {
        await withCheckedContinuation { continuation in
            lock.withLock { startContinuation = continuation }
            onStart?()
        }
        lock.withLock { started = true }
    }

    func completeStart() {
        lock.withLock {
            startContinuation?.resume()
            startContinuation = nil
        }
    }

    func stop() async throws -> String {
        lock.withLock { stoppedBeforeStart = !started }
        return "hola"
    }

    func cancel() async {}
}

final class VoiceCommandParserTests: XCTestCase {
    func testCommands() {
        let parser = VoiceCommandParser()
        XCTAssertEqual(parser.parse("cancelar"), .cancel)
        XCTAssertEqual(parser.parse("Borra eso."), .deleteLastInsertion)
        XCTAssertEqual(parser.parse("deshacer"), .undo)
        XCTAssertEqual(parser.parse("corrige eso"), .undo)
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
        // Rewrite y word emiten comandos reales (IA on-device y .docx).
        XCTAssertEqual(module.editorCommands(for: .rewriteSelection("x")), [.rewriteSelection("x")])
        XCTAssertEqual(module.editorCommands(for: .rewriteSelection("  ")), [])
        XCTAssertEqual(module.editorCommands(for: .exportDocument(.word)), [.exportDocument("word")])
        XCTAssertEqual(module.editorCommands(for: .unsupported("z")), [])
        XCTAssertEqual(module.editorCommands(for: .unknown), [])
        XCTAssertEqual(module.editorCommands(for: .multipleActions), [])
    }

    @MainActor func testCommandFeedback() {
        let module = VoiceModule(recognizer: MockSpeechRecognizer())
        XCTAssertFalse(module.feedback(for: .saveDocument).isEmpty)
        XCTAssertFalse(module.feedback(for: .renameTitle("X")).isEmpty)
        XCTAssertTrue(module.feedback(for: .exportDocument(.word)).contains("Word"))
        XCTAssertTrue(module.feedback(for: .rewriteSelection("x")).contains("Reescrib"))
    }

    func testEndpointReached() {
        XCTAssertTrue(VoiceModule.endpointReached(partial: "hola", unchangedFor: 2.0, timeout: 1.6))
        XCTAssertFalse(VoiceModule.endpointReached(partial: "hola", unchangedFor: 0.5, timeout: 1.6))
        XCTAssertFalse(VoiceModule.endpointReached(partial: "   ", unchangedFor: 9.0, timeout: 1.6))
        XCTAssertFalse(VoiceModule.endpointReached(partial: "", unchangedFor: 9.0, timeout: 1.6))
    }

    func testPushToTalkHotkeyDetection() {
        func keyEvent(type: NSEvent.EventType, flags: NSEvent.ModifierFlags, keyCode: UInt16, repeat repeatFlag: Bool = false) -> NSEvent? {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: repeatFlag, keyCode: keyCode)
        }
        XCTAssertNotNil(keyEvent(type: .keyDown, flags: .option, keyCode: 49))
        if let down = keyEvent(type: .keyDown, flags: .option, keyCode: 49) {
            XCTAssertTrue(VoicePushToTalk.isHotkeyDown(down))
        }
        // Con comando o control ya no es el hotkey de voz.
        if let cmd = keyEvent(type: .keyDown, flags: [.option, .command], keyCode: 49) {
            XCTAssertFalse(VoicePushToTalk.isHotkeyDown(cmd))
        }
        if let ctrl = keyEvent(type: .keyDown, flags: [.option, .control], keyCode: 49) {
            XCTAssertFalse(VoicePushToTalk.isHotkeyDown(ctrl))
        }
        // Otra tecla con opción no dispara.
        if let other = keyEvent(type: .keyDown, flags: .option, keyCode: 8) {
            XCTAssertFalse(VoicePushToTalk.isHotkeyDown(other))
        }
        // KeyUp nunca es "down".
        if let up = keyEvent(type: .keyUp, flags: .option, keyCode: 49) {
            XCTAssertFalse(VoicePushToTalk.isHotkeyDown(up))
        }
    }
}

final class VoicePushToTalkTests: XCTestCase {
    @MainActor func testReleaseWaitsForMicrophoneStartup() async throws {
        let recognizer = DelayedSpeechRecognizer()
        let started = expectation(description: "El micrófono empezó a prepararse")
        recognizer.onStart = { started.fulfill() }
        let module = VoiceModule(recognizer: recognizer)
        module.pushToTalkEnabled = true
        let press = Task { await module.beginPushToTalk() }
        await fulfillment(of: [started], timeout: 2)
        let release = Task { await module.endPushToTalk() }
        await Task.yield()
        XCTAssertFalse(recognizer.didStopBeforeStart)
        recognizer.completeStart()
        await press.value
        await release.value
        XCTAssertFalse(recognizer.didStopBeforeStart)
        XCTAssertEqual(module.pendingDictationText, "Hola.")
    }

    @MainActor func testPushToTalkDictationFlow() async throws {
        let bus = EditorCommandBus()
        let mock = MockSpeechRecognizer()
        mock.nextTranscript = "hola coma mundo"
        let module = VoiceModule(recognizer: mock)
        module.pushToTalkEnabled = true
        try await module.start(context: EditorModuleContext(commandBus: bus))
        XCTAssertTrue(module.canBeginPushToTalk)
        let stream = await bus.commands()
        await module.beginPushToTalk()
        XCTAssertTrue(module.pushToTalkHeld)
        XCTAssertTrue(module.isListening)
        // Segunda pulsación mientras se mantiene: no hace nada.
        XCTAssertFalse(module.canBeginPushToTalk)
        await module.endPushToTalk()
        XCTAssertFalse(module.pushToTalkHeld)
        XCTAssertFalse(module.isListening)
        XCTAssertEqual(module.pendingAction?.preview, "Insertar: \"Hola, mundo.\"")
        await module.confirmPending()
        await bus.finish()
        var received: [EditorCommand] = []
        for await command in stream { received.append(command) }
        XCTAssertEqual(received, [.insertText("Hola, mundo.")])
    }

    @MainActor func testPushToTalkKeepsCommandMode() async throws {
        let bus = EditorCommandBus()
        let mock = MockSpeechRecognizer()
        mock.nextTranscript = "Guarda el documento"
        let module = VoiceModule(recognizer: mock)
        module.pushToTalkEnabled = true
        try await module.start(context: EditorModuleContext(commandBus: bus))
        let stream = await bus.commands()
        await module.beginPushToTalk()
        await module.endPushToTalk()
        // El comando pasa por propuesta (igual que por toques), no se inserta texto.
        XCTAssertEqual(module.pendingAction?.intent, .command(.saveDocument))
        await module.confirmPending()
        await bus.finish()
        var received: [EditorCommand] = []
        for await command in stream { received.append(command) }
        XCTAssertEqual(received, [.saveDocument])
    }

    @MainActor func testPushToTalkImmediateCommand() async throws {
        let bus = EditorCommandBus()
        let mock = MockSpeechRecognizer()
        mock.nextTranscript = "Busca TDAH"
        let module = VoiceModule(recognizer: mock)
        module.pushToTalkEnabled = true
        try await module.start(context: EditorModuleContext(commandBus: bus))
        let stream = await bus.commands()
        await module.beginPushToTalk()
        await module.endPushToTalk()
        XCTAssertNil(module.pendingAction)
        await bus.finish()
        var received: [EditorCommand] = []
        for await command in stream { received.append(command) }
        XCTAssertEqual(received, [.findText("TDAH")])
    }

    @MainActor func testPushToTalkBlockedWhilePending() async throws {
        let bus = EditorCommandBus()
        let mock = MockSpeechRecognizer()
        mock.nextTranscript = "hola"
        let module = VoiceModule(recognizer: mock)
        module.pushToTalkEnabled = true
        try await module.start(context: EditorModuleContext(commandBus: bus))
        await module.beginPushToTalk()
        await module.endPushToTalk()
        XCTAssertNotNil(module.pendingAction)
        XCTAssertFalse(module.canBeginPushToTalk)
        await module.beginPushToTalk()
        XCTAssertFalse(module.pushToTalkHeld, "con propuesta pendiente no se rearma")
        XCTAssertFalse(module.isListening)
        module.cancelPending()
        await bus.finish()
    }

    @MainActor func testPushToTalkDisabledNeverStarts() async throws {
        let bus = EditorCommandBus()
        let module = VoiceModule(recognizer: MockSpeechRecognizer())
        module.pushToTalkEnabled = false
        try await module.start(context: EditorModuleContext(commandBus: bus))
        XCTAssertFalse(module.canBeginPushToTalk)
        await module.beginPushToTalk()
        XCTAssertFalse(module.pushToTalkHeld)
        XCTAssertFalse(module.isListening)
        module.pushToTalkEnabled = true
        await bus.finish()
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
    @MainActor func testHandsFreeShowsDictationAndAcceptsNextCommandByVoice() async throws {
        let (window, view, session) = voiceTestSession(text: "base ")
        defer { session.stop(); window.orderOut(nil) }
        view.setSelectedRange(NSRange(location: 5, length: 0))
        let bus = EditorCommandBus()
        let mock = MockSpeechRecognizer()
        let module = VoiceModule(recognizer: mock)
        try await module.start(context: EditorModuleContext(commandBus: bus))
        let consumer = Task { @MainActor in
            for await command in await bus.commands() { session.send(command) }
        }
        defer { consumer.cancel() }
        for _ in 0..<50 { await Task.yield() }

        await module.toggle()
        mock.onPartial?("probando")
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(view.string, "base probando")
        XCTAssertTrue(session.isPreviewing)

        mock.nextTranscript = "hola"
        await module.autoFinish()
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(view.string, "base Hola.")
        XCTAssertTrue(session.isPreviewing, "la siguiente frase ya está preparada")
        XCTAssertTrue(module.isListening)

        mock.nextTranscript = "deshacer"
        await module.autoFinish()
        XCTAssertNotNil(module.pendingAction)
        XCTAssertTrue(module.isListening)
        mock.nextTranscript = "confirmar"
        await module.autoFinish()
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(view.string, "base ")
        XCTAssertNil(module.pendingAction)
        XCTAssertTrue(module.isListening)

        mock.onPartial?("provisional")
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(view.string, "base provisional")
        mock.nextTranscript = "detener voz"
        await module.autoFinish()
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(view.string, "base ")
        XCTAssertFalse(session.isPreviewing)
        XCTAssertFalse(module.isListening)
        await module.stop()
        await bus.finish()
    }

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
        XCTAssertEqual(module.pendingAction?.transcript, "hola coma mundo")
        XCTAssertEqual(module.pendingAction?.preview, "Insertar: \"Hola, mundo.\"")
        await module.confirmPending()
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
        XCTAssertNotNil(module.pendingAction)
        await module.confirmPending()
        var received: EditorCommand?
        for await command in stream {
            received = command
            break
        }
        XCTAssertEqual(received, .undo)
        await bus.finish()
    }

    @MainActor func testCorrectedDictationIsInsertedOnce() async throws {
        let bus = EditorCommandBus()
        let mock = MockSpeechRecognizer()
        mock.nextTranscript = "ola mundo"
        let module = VoiceModule(recognizer: mock)
        try await module.start(context: EditorModuleContext(commandBus: bus))
        let stream = await bus.commands()
        await module.begin()
        await module.finish()
        module.updatePendingDictation("Hola mundo.")
        XCTAssertEqual(module.pendingAction?.transcript, "ola mundo")
        XCTAssertEqual(module.pendingDictationText, "Hola mundo.")
        module.updatePendingDictation("   ")
        await module.confirmPending()
        XCTAssertNotNil(module.pendingAction)
        module.updatePendingDictation("Hola mundo.")
        await module.confirmPending()
        await module.confirmPending()
        await bus.finish()
        var received: [EditorCommand] = []
        for await command in stream { received.append(command) }
        XCTAssertEqual(received, [.insertText("Hola mundo.")])
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
        XCTAssertEqual(module.pendingAction?.transcript, "Cambia el título a prueba.")
        XCTAssertEqual(module.lastTranscript, "Cambia el título a prueba.")
        await module.confirmPending()
        await module.confirmPending()
        await bus.finish()
        var received: [EditorCommand] = []
        for await command in stream { received.append(command) }
        XCTAssertEqual(received, [.renameTitle("prueba")])
    }

    @MainActor func testCancelNeverEmits() async throws {
        for spoken in ["Titula bien tus ideas", "Cambia el título a prueba"] {
            let bus = EditorCommandBus()
            let mock = MockSpeechRecognizer()
            mock.nextTranscript = spoken
            let module = VoiceModule(recognizer: mock)
            try await module.start(context: EditorModuleContext(commandBus: bus))
            let stream = await bus.commands()
            await module.begin()
            await module.finish()
            XCTAssertNotNil(module.pendingAction)
            module.cancelPending()
            await bus.finish()
            var received: [EditorCommand] = []
            for await command in stream { received.append(command) }
            XCTAssertTrue(received.isEmpty, "\(spoken) se envió antes de confirmar")
        }
    }

    @MainActor func testAmbiguousCommandCanBeUsedAsDictation() async throws {
        let bus = EditorCommandBus()
        let mock = MockSpeechRecognizer()
        mock.nextTranscript = "Titula bien tus ideas"
        let module = VoiceModule(recognizer: mock)
        try await module.start(context: EditorModuleContext(commandBus: bus))
        let stream = await bus.commands()
        await module.begin()
        await module.finish()
        XCTAssertEqual(module.pendingAction?.intent, .command(.renameTitle("bien tus ideas")))
        module.usePendingAsDictation()
        XCTAssertEqual(module.pendingAction?.intent, .dictation("Titula bien tus ideas."))
        await module.confirmPending()
        await bus.finish()
        var received: [EditorCommand] = []
        for await command in stream { received.append(command) }
        XCTAssertEqual(received, [.insertText("Titula bien tus ideas.")])
    }

    @MainActor func testNavigationIsImmediate() async throws {
        let bus = EditorCommandBus()
        let mock = MockSpeechRecognizer()
        mock.nextTranscript = "Busca TDAH"
        let module = VoiceModule(recognizer: mock)
        try await module.start(context: EditorModuleContext(commandBus: bus))
        let stream = await bus.commands()
        await module.begin()
        await module.finish()
        XCTAssertNil(module.pendingAction)
        await bus.finish()
        var received: [EditorCommand] = []
        for await command in stream { received.append(command) }
        XCTAssertEqual(received, [.findText("TDAH")])
    }

    @MainActor func testRepeatDropsProposalAndListensAgain() async throws {
        let bus = EditorCommandBus()
        let mock = MockSpeechRecognizer()
        mock.nextTranscript = "Guarda el documento"
        let module = VoiceModule(recognizer: mock)
        try await module.start(context: EditorModuleContext(commandBus: bus))
        let stream = await bus.commands()
        await module.begin()
        await module.finish()
        XCTAssertNotNil(module.pendingAction)
        await module.repeatPending()
        XCTAssertNil(module.pendingAction)
        XCTAssertTrue(module.isListening)
        await module.cancelDictation()
        await bus.finish()
        var received: [EditorCommand] = []
        for await command in stream { received.append(command) }
        XCTAssertTrue(received.isEmpty)
    }

    @MainActor func testOpenByNameRequiresUniqueMatch() {
        let acta = URL(fileURLWithPath: "/tmp/acta vieja.md")
        let other = URL(fileURLWithPath: "/tmp/notas.md")
        XCTAssertEqual(EditorScreen.matchVoiceDocument("el acta vieja", in: [acta, other]), acta)
        XCTAssertNil(EditorScreen.matchVoiceDocument("acta", in: [acta, URL(fileURLWithPath: "/tmp/acta nueva.md")]))
        XCTAssertNil(EditorScreen.matchVoiceDocument("desconocido", in: [acta, other]))
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

    @MainActor func testRewriteTravelsAsRewriteCommand() async throws {
        let bus = EditorCommandBus()
        let mock = MockSpeechRecognizer()
        mock.nextTranscript = "Hazlo más breve."
        let module = VoiceModule(recognizer: mock)
        try await module.start(context: EditorModuleContext(commandBus: bus))
        let stream = await bus.commands()
        await module.begin()
        await module.finish()
        XCTAssertEqual(module.pendingAction?.intent, .command(.rewriteSelection("más breve")))
        XCTAssertTrue(module.pendingAction?.preview.contains("más breve") == true)
        await module.confirmPending()
        await bus.finish()
        var received: [EditorCommand] = []
        for await command in stream { received.append(command) }
        XCTAssertEqual(received, [.rewriteSelection("más breve")])
    }

    @MainActor func testWordTravelsAsWordExport() async throws {
        let bus = EditorCommandBus()
        let mock = MockSpeechRecognizer()
        mock.nextTranscript = "Exporta a Word."
        let module = VoiceModule(recognizer: mock)
        try await module.start(context: EditorModuleContext(commandBus: bus))
        let stream = await bus.commands()
        await module.begin()
        await module.finish()
        XCTAssertNotNil(module.pendingAction, "word requiere confirmación")
        await module.confirmPending()
        await bus.finish()
        var received: [EditorCommand] = []
        for await command in stream { received.append(command) }
        XCTAssertEqual(received, [.exportDocument("word")])
    }

    @MainActor func testSessionRewriteApplies() async {
        let (window, view, session) = voiceTestSession(
            text: "texto original aquí",
            rewrite: MockRewriteProvider(result: "nuevo"))
        voiceTestSelect(view, "original")
        session.send(.rewriteSelection("más breve"))
        // La IA es asíncrona: el texto no cambia antes de generarse.
        XCTAssertEqual(view.string, "texto original aquí")
        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(view.string, "texto nuevo aquí")
        view.undoManager?.undo()
        XCTAssertEqual(view.string, "texto original aquí", "un undo restaura")
        window.orderOut(nil)
    }

    @MainActor func testSessionRewriteRequiresSelection() async {
        let (window, view, session) = voiceTestSession(
            text: "texto intacto",
            rewrite: MockRewriteProvider(result: "X"))
        view.setSelectedRange(NSRange(location: 0, length: 0))
        session.send(.rewriteSelection("más breve"))
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(view.string, "texto intacto", "sin selección no reescribe")
        window.orderOut(nil)
    }

    @MainActor func testSessionRewriteFailureKeepsText() async {
        let (window, view, session) = voiceTestSession(
            text: "texto intacto",
            rewrite: MockRewriteProvider(result: nil))
        voiceTestSelect(view, "intacto")
        session.send(.rewriteSelection("más breve"))
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(view.string, "texto intacto", "si la IA falla no toca nada")
        window.orderOut(nil)
    }

    @MainActor func testSessionRewriteStaleDoesNotApplyBlindly() async {
        let (window, view, session) = voiceTestSession(
            text: "texto original aquí",
            rewrite: MockRewriteProvider(result: "TARDÍO", delay: .milliseconds(200)))
        voiceTestSelect(view, "original")
        session.send(.rewriteSelection("más breve"))
        // El usuario edita mientras la IA genera: el span queda obsoleto.
        view.setSelectedRange(NSRange(location: 0, length: 0))
        session.send(.insertText("¡Hola! "))
        try? await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(view.string.hasPrefix("¡Hola! "), "la edición del usuario manda")
        XCTAssertFalse(view.string.contains("TARDÍO"), "nunca aplica a ciegas")
        window.orderOut(nil)
    }
}

private struct MockRewriteProvider: RewriteProvider {
    var result: String?
    var delay: Duration = .zero
    var isAvailable: Bool { true }
    var availabilityReason: String? { nil }
    func rewrite(_ text: String, instruction: String) async -> String? {
        if delay > .zero { try? await Task.sleep(for: delay) }
        return result
    }
}

@MainActor private func voiceTestSession(text: String, rewrite: (any RewriteProvider)? = nil) -> (NSWindow, NSTextView, EditorSession) {
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
    let session = EditorSession(rewriteProvider: rewrite)
    session.textView = view
    return (window, view, session)
}

@MainActor private func voiceTestSelect(_ view: NSTextView, _ query: String) {
    let r = (view.string as NSString).range(of: query)
    guard r.location != NSNotFound else { return }
    view.setSelectedRange(r)
}
