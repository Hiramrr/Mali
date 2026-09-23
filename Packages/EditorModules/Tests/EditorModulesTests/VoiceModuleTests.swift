import XCTest
import EditorCore
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
        XCTAssertEqual(module.editorCommands(for: .undo), [.undo])
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
}
