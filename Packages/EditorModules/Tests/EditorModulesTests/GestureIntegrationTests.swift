import XCTest
import AppKit
@testable import EditorCore
@testable import EditorEngine
@testable import ModuleKit
@testable import GestureModule

/// Flujo completo gesto → bus → sesión, sin cámara.
final class GestureIntegrationTests: XCTestCase {
    @MainActor
    private func makeHarness(text: String, lengthProvider: (any LengthProvider)? = nil) -> (GestureModule, EditorSession, NSTextView, NSWindow, EditorCommandBus) {
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
        session.onPreviewCommitted = { _ in }
        let bus = EditorCommandBus()
        let module = GestureModule(lengthProvider: lengthProvider)
        return (module, session, view, window, bus)
    }

    @MainActor
    private func pump(times: Int = 50) async {
        for _ in 0..<times {
            await Task.yield()
        }
    }

    @MainActor func testManualSynonymSessionEndToEnd() async throws {
        let (module, session, view, window, bus) = makeHarness(text: "hola mundo importante")
        defer { session.stop(); window.orderOut(nil) }
        try await module.start(context: EditorModuleContext(commandBus: bus))
        // Consumidor como el de EditorScreen.
        let consumer = Task { @MainActor in
            for await command in await bus.commands() {
                session.send(command)
            }
        }
        defer { consumer.cancel() }
        // Dejar que el consumidor registre su continuación antes de enviar.
        await pump()
        module.updateDocument(text: "hola mundo importante",
                              selection: NSRange(location: 18, length: 0))
        await module.startPinchSessionManually()
        await pump()
        XCTAssertTrue(module.hasPinchSession, "mensaje: \(module.message)")
        XCTAssertGreaterThan(module.sessionOptions.count, 1)
        // La palabra objetivo queda seleccionada.
        XCTAssertEqual(view.selectedRange().length, ("importante" as NSString).length)
        // Confirmar la segunda opción la aplica con un solo undo.
        await module.commitPinchSession(at: 1)
        await pump()
        XCTAssertFalse(module.hasPinchSession)
        XCTAssertFalse(session.isPreviewing)
        let applied = view.string
        XCTAssertNotEqual(applied, "hola mundo importante")
        XCTAssertTrue(applied.hasPrefix("hola mundo "))
        // Un solo undo revierte lo confirmado.
        session.send(.undo)
        XCTAssertEqual(view.string, "hola mundo importante")
        session.send(.redo)
        XCTAssertEqual(view.string, applied)
    }

    @MainActor func testBeginPreviewDirectlyThroughBus() async throws {
        let (module, session, view, window, bus) = makeHarness(text: "hola mundo importante")
        defer { session.stop(); window.orderOut(nil) }
        try await module.start(context: EditorModuleContext(commandBus: bus))
        let consumer = Task { @MainActor in
            for await command in await bus.commands() {
                session.send(command)
            }
        }
        defer { consumer.cancel() }
        // Dejar que el consumidor registre su continuación antes de enviar.
        await pump()
        await bus.send(.beginPreview(TextRange(location: 11, length: 10)))
        await pump()
        XCTAssertTrue(session.isPreviewing)
        await bus.send(.showPreview("relevante"))
        await pump()
        XCTAssertEqual(view.string, "hola mundo relevante")
        await bus.send(.commitPreview)
        await pump()
        XCTAssertFalse(session.isPreviewing)
        XCTAssertEqual(view.string, "hola mundo relevante")
    }

    @MainActor func testManualLengthSessionEndToEnd() async throws {
        let paragraph = "Primera oración completa. Segunda oración con desarrollo importante y metodología clara."
        let (module, session, view, window, bus) = makeHarness(text: paragraph, lengthProvider: StubLengthProvider())
        defer { session.stop(); window.orderOut(nil) }
        try await module.start(context: EditorModuleContext(commandBus: bus))
        let consumer = Task { @MainActor in
            for await command in await bus.commands() {
                session.send(command)
            }
        }
        defer { consumer.cancel() }
        // Dejar que el consumidor registre su continuación antes de enviar.
        await pump()
        module.updateDocument(text: paragraph, selection: NSRange(location: 5, length: 0))
        await module.startLengthSessionManually()
        await pump()
        XCTAssertTrue(module.hasLengthSession, "mensaje: \(module.message)")
        XCTAssertEqual(module.lengthOptions.count, 3)
        await module.commitLengthSession(at: 2)
        await pump()
        XCTAssertFalse(module.hasLengthSession)
        XCTAssertEqual(view.string, StubLengthProvider().results[1])
        XCTAssertNotNil(module.lengthToast)
    }

    @MainActor func testFailedLengthGenerationKeepsParagraph() async throws {
        let paragraph = "Primera oración completa. Segunda oración con desarrollo importante y metodología clara."
        let (module, session, view, window, bus) = makeHarness(text: paragraph, lengthProvider: StubLengthProvider(results: []))
        defer { session.stop(); window.orderOut(nil) }
        try await module.start(context: EditorModuleContext(commandBus: bus))
        let consumer = Task { @MainActor in
            for await command in await bus.commands() { session.send(command) }
        }
        defer { consumer.cancel() }
        await pump()
        module.updateDocument(text: paragraph, selection: NSRange(location: 5, length: 0))
        await module.startLengthSessionManually()
        await pump()
        XCTAssertFalse(module.hasLengthSession)
        XCTAssertEqual(view.string, paragraph)
        XCTAssertFalse(module.lengthToastCanUndo)
    }

    @MainActor func testUnknownWordOpensNoSession() async {
        // Sin sinónimos locales y sin IA que genere: no se abre tarjeta con
        // la palabra sola (el proveedor local nunca mejora).
        let module = GestureModule(synonymProvider: LocalSynonymProvider())
        module.updateDocument(text: "hola zxq", selection: NSRange(location: 6, length: 0))
        await module.startPinchSessionManually()
        XCTAssertFalse(module.hasPinchSession)
        XCTAssertTrue(module.message.contains("zxq"))
    }

    @MainActor func testKnownWordOpensSession() async {
        let module = GestureModule(synonymProvider: LocalSynonymProvider())
        module.updateDocument(text: "hola mundo", selection: NSRange(location: 6, length: 0))
        await module.startPinchSessionManually()
        XCTAssertTrue(module.hasPinchSession)
        XCTAssertGreaterThan(module.sessionOptions.count, 1)
        XCTAssertEqual(module.sessionOptions.first, "mundo")
    }

    @MainActor func testPinchOnImageOpensNoSynonyms() async {
        // El markdown de imagen no son palabras: pinzar sobre `![...]` no debe
        // abrir sinónimos (antes ofrecía "foto"/"width"/"align" y al confirmar rompía la imagen).
        let image = "![foto](images/foto.png \"width=320;align=center\")"
        for location in [4, 15, 30, 40] {
            let module = GestureModule(synonymProvider: LocalSynonymProvider())
            module.updateDocument(text: image, selection: NSRange(location: location, length: 0))
            await module.startPinchSessionManually()
            XCTAssertFalse(module.hasPinchSession, "loc \(location) abrió sinónimos en imagen")
            XCTAssertTrue(module.message.lowercased().contains("imagen"), "loc \(location): \(module.message)")
        }
    }

    // MARK: - Gesto a dos manos (detecciones sintéticas, sin cámara)

    private func validLandmarks(x: Double) -> HandLandmarks {
        HandLandmarks(wrist: CGPoint(x: x, y: 0.2), thumb: CGPoint(x: x, y: 0.5),
                      index: CGPoint(x: x + 0.02, y: 0.5), imageSize: CGSize(width: 640, height: 480))
    }

    private func twoHands(span: Double) -> GestureState {
        var state = GestureState()
        state.handDetected = true
        state.landmarks = validLandmarks(x: 0.6)
        state.secondaryLandmarks = validLandmarks(x: 0.3)
        state.handSpan = span
        state.pinch = false
        return state
    }

    private func oneHand() -> GestureState {
        var state = GestureState()
        state.handDetected = true
        state.landmarks = validLandmarks(x: 0.5)
        state.pinch = false
        return state
    }

    @MainActor func testTwoHandLengthFlow() async throws {
        let paragraph = "Primera oración completa. Segunda oración con desarrollo importante y metodología clara."
        let short = StubLengthProvider().results[0]
        XCTAssertNotEqual(short, paragraph)
        let (module, session, view, window, bus) = makeHarness(text: paragraph, lengthProvider: StubLengthProvider())
        defer { session.stop(); window.orderOut(nil) }
        try await module.start(context: EditorModuleContext(commandBus: bus))
        let consumer = Task { @MainActor in
            for await command in await bus.commands() {
                session.send(command)
            }
        }
        defer { consumer.cancel() }
        await pump()
        module.updateDocument(text: paragraph, selection: NSRange(location: 5, length: 0))
        // Tres detecciones con dos manos abren la sesión en nivel medio.
        await module.handleLengthVision(twoHands(span: 0.40), at: 0.0)
        await module.handleLengthVision(twoHands(span: 0.41), at: 0.05)
        await module.handleLengthVision(twoHands(span: 0.42), at: 0.10)
        await pump()
        XCTAssertTrue(module.hasLengthSession, "mensaje: \(module.message)")
        XCTAssertEqual(module.lengthIndex, LengthLevel.medio.rawValue)
        // Separar las manos amplía un nivel por frame.
        await module.handleLengthVision(twoHands(span: 0.75), at: 0.15)
        await pump()
        XCTAssertEqual(module.lengthIndex, LengthLevel.largo.rawValue)
        XCTAssertEqual(view.string, StubLengthProvider().results[1])
        // Acercar reduce un nivel por frame hasta la versión corta, que previsualiza.
        await module.handleLengthVision(twoHands(span: 0.30), at: 0.20)
        await module.handleLengthVision(twoHands(span: 0.22), at: 0.25)
        await module.handleLengthVision(twoHands(span: 0.15), at: 0.30)
        await pump()
        XCTAssertEqual(module.lengthIndex, LengthLevel.corto.rawValue)
        XCTAssertEqual(view.string, short)
        // Retirar una mano confirma con aviso y Deshacer.
        await module.handleLengthVision(oneHand(), at: 0.35)
        await module.handleLengthVision(oneHand(), at: 0.40)
        await module.handleLengthVision(oneHand(), at: 0.45)
        await module.handleLengthVision(oneHand(), at: 0.50)
        await module.handleLengthVision(oneHand(), at: 0.55)
        await pump()
        XCTAssertFalse(module.hasLengthSession)
        XCTAssertEqual(view.string, short)
        XCTAssertNotNil(module.lengthToast)
        XCTAssertTrue(module.lengthToastCanUndo)
        session.send(.undo)
        XCTAssertEqual(view.string, paragraph)
    }

    @MainActor func testTwoHandImageSizeAndUndo() async throws {
        let image = "![foto](images/foto.png \"width=320;align=center\")"
        let (module, session, view, window, bus) = makeHarness(text: image)
        defer { session.stop(); window.orderOut(nil) }
        try await module.start(context: EditorModuleContext(commandBus: bus))
        let consumer = Task { @MainActor in
            for await command in await bus.commands() { session.send(command) }
        }
        defer { consumer.cancel() }
        await pump()
        module.updateDocument(text: image, selection: NSRange(location: 4, length: 0))
        await module.handleLengthVision(twoHands(span: 0.40), at: 0)
        await module.handleLengthVision(twoHands(span: 0.41), at: 0.05)
        await module.handleLengthVision(twoHands(span: 0.42), at: 0.10)
        XCTAssertTrue(module.hasImageSizeSession)
        XCTAssertFalse(module.hasLengthSession)
        await module.handleLengthVision(twoHands(span: 0.75), at: 0.15)
        await pump()
        XCTAssertGreaterThan(module.imageWidth, 320)
        XCTAssertEqual(MarkdownImage(line: view.string)?.width, module.imageWidth)
        for step in 0..<GestureTuning.lengthCommitFrames {
            await module.handleLengthVision(oneHand(), at: 0.20 + Double(step) * 0.05)
        }
        await pump()
        XCTAssertFalse(module.hasImageSizeSession)
        XCTAssertGreaterThan(MarkdownImage(line: view.string)?.width ?? 0, 320)
        XCTAssertTrue(module.lengthToastCanUndo)
        session.send(.undo)
        XCTAssertEqual(view.string, image)
    }

    @MainActor func testFingerTargetsImageWithoutTextCursor() async throws {
        let image = "![foto](images/foto.png \"width=320;align=center\")"
        let text = "Texto\n" + image
        let imageRange = (text as NSString).range(of: image)
        let (module, session, view, window, bus) = makeHarness(text: text)
        defer { session.stop(); window.orderOut(nil) }
        try await module.start(context: EditorModuleContext(commandBus: bus))
        let consumer = Task { @MainActor in
            for await command in await bus.commands() { session.send(command) }
        }
        defer { consumer.cancel() }
        await pump()
        module.updateDocument(text: text, selection: NSRange(location: 2, length: 0))
        module.imageHitTest = { point in
            guard let point, (0.35...0.45).contains(point.x), (0.45...0.55).contains(point.y) else { return nil }
            return imageRange
        }
        module.running = true
        await module.handleVision(twoHands(span: 0.40), at: 0)
        await module.handleVision(twoHands(span: 0.41), at: 0.05)
        await module.handleVision(twoHands(span: 0.42), at: 0.10)
        await pump()
        XCTAssertTrue(module.isPointingAtImage)
        XCTAssertNotNil(module.cursorPoint)
        XCTAssertTrue(module.hasImageSizeSession)
        XCTAssertEqual(view.selectedRange(), imageRange)
    }

    @MainActor func testManualImageSizeCancelRestoresOriginal() async throws {
        let image = "![foto](images/foto.png)"
        let (module, session, view, window, bus) = makeHarness(text: image)
        defer { session.stop(); window.orderOut(nil) }
        try await module.start(context: EditorModuleContext(commandBus: bus))
        let consumer = Task { @MainActor in
            for await command in await bus.commands() { session.send(command) }
        }
        defer { consumer.cancel() }
        await pump()
        module.updateDocument(text: image, selection: NSRange(location: 4, length: 0))
        await module.startImageSizeSessionManually()
        await module.setImageWidth(240)
        await pump()
        XCTAssertEqual(MarkdownImage(line: view.string)?.width, 240)
        module.cancelImageSizeSession()
        await pump()
        XCTAssertEqual(view.string, image)
    }
}

private struct StubLengthProvider: LengthProvider {
    let results: [String]
    init(results: [String] = [
        "Primera oración completa.",
        "Primera oración completa. La segunda oración desarrolla la idea con una metodología clara e importante."
    ]) { self.results = results }
    var isAvailable: Bool { true }
    var availabilityReason: String? { nil }
    func variants(for paragraph: String) async -> [String] { results }
}

/// Doble sin modelo: devuelve lista fija sin Apple Intelligence.
struct StubSynonymProvider: SynonymProvider {
    let fresh: [String]
    var isAvailable: Bool { true }
    var availabilityReason: String? { nil }
    func synonyms(for word: String) async -> [String] { fresh }
}

final class SynonymUpgradeTests: XCTestCase {
    @MainActor
    private func pump(times: Int = 50) async {
        for _ in 0..<times {
            await Task.yield()
        }
    }

    @MainActor func testUpgradeMergesFreshSynonyms() async {
        let module = GestureModule(synonymProvider: StubSynonymProvider(fresh: ["trascendental", "clave"]))
        module.updateDocument(text: "dato importante", selection: NSRange(location: 7, length: 0))
        await module.startPinchSessionManually()
        await pump()
        XCTAssertTrue(module.hasPinchSession)
        XCTAssertTrue(module.sessionUpgraded)
        // La palabra sigue primera; los frescos entran después.
        XCTAssertEqual(module.sessionOptions.first, "importante")
        XCTAssertTrue(module.sessionOptions.contains("trascendental"))
        XCTAssertTrue(module.sessionOptions.contains("clave"))
    }

    @MainActor func testEmptyUpgradeKeepsLocal() async {
        let module = GestureModule(synonymProvider: StubSynonymProvider(fresh: []))
        module.updateDocument(text: "dato importante", selection: NSRange(location: 7, length: 0))
        await module.startPinchSessionManually()
        await pump()
        XCTAssertTrue(module.hasPinchSession)
        XCTAssertFalse(module.sessionUpgraded)
        XCTAssertEqual(module.sessionOptions.first, "importante")
    }

    @MainActor func testStaleUpgradeDiscarded() async {
        let module = GestureModule(synonymProvider: StubSynonymProvider(fresh: ["trascendental"]))
        module.updateDocument(text: "dato importante", selection: NSRange(location: 7, length: 0))
        await module.startPinchSessionManually()
        // Cierra antes de que llegue la mejora: no debe reabrir ni aplicar nada.
        module.cancelPinchSession()
        await pump()
        XCTAssertFalse(module.hasPinchSession)
        XCTAssertFalse(module.sessionUpgraded)
    }

    @MainActor func testSingleOptionOpensWhenIAAvailable() async {
        // Sin locales pero con IA: la sesión abre con la palabra y mejora al llegar.
        let module = GestureModule(synonymProvider: StubSynonymProvider(fresh: ["extraño", "raro"]))
        module.updateDocument(text: "hola zxq", selection: NSRange(location: 6, length: 0))
        await module.startPinchSessionManually()
        XCTAssertTrue(module.hasPinchSession)
        XCTAssertEqual(module.sessionOptions, ["zxq"])
        await pump()
        XCTAssertTrue(module.sessionUpgraded)
        XCTAssertEqual(module.sessionOptions.first, "zxq")
        XCTAssertTrue(module.sessionOptions.contains("extraño"))
    }

    @MainActor func testSingleOptionClosesWhenIAFails() async {
        // Sin locales y la IA sin respuesta: se cierra con mensaje, sin tarjeta vacía.
        let module = GestureModule(synonymProvider: StubSynonymProvider(fresh: []))
        module.updateDocument(text: "hola zxq", selection: NSRange(location: 6, length: 0))
        await module.startPinchSessionManually()
        XCTAssertTrue(module.hasPinchSession)
        await pump()
        XCTAssertFalse(module.hasPinchSession)
        XCTAssertTrue(module.message.contains("zxq"))
    }
}
