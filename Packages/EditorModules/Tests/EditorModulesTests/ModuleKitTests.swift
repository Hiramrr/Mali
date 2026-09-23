import XCTest
import EditorCore
@testable import ModuleKit

final class EditorCommandBusTests: XCTestCase {
    func testDeliversInOrder() async {
        let bus = EditorCommandBus()
        let stream = await bus.commands()
        await bus.send(.undo)
        await bus.send(.redo)
        await bus.send(.insertText("hola"))
        await bus.finish()
        var received: [EditorCommand] = []
        for await command in stream {
            received.append(command)
        }
        XCTAssertEqual(received, [.undo, .redo, .insertText("hola")])
    }

    func testBroadcastsToEveryConsumer() async {
        let bus = EditorCommandBus()
        let first = await bus.commands()
        let second = await bus.commands()
        await bus.send(.undo)
        await bus.finish()
        var a: [EditorCommand] = []
        var b: [EditorCommand] = []
        for await command in first { a.append(command) }
        for await command in second { b.append(command) }
        XCTAssertEqual(a, [.undo])
        XCTAssertEqual(b, [.undo])
    }

    func testFinishClosesLateConsumers() async {
        let bus = EditorCommandBus()
        await bus.finish()
        // Sin comandos pendientes el stream termina de inmediato.
        await bus.send(.undo)
        var received: [EditorCommand] = []
        for await command in await bus.commands() {
            received.append(command)
        }
        XCTAssertTrue(received.isEmpty)
    }
}

final class ModuleRegistryTests: XCTestCase {
    @MainActor func testRegisterDedupAndUnregister() {
        let registry = ModuleRegistry()
        XCTAssertFalse(registry.isRegistered(identifier: "gestures.hand"))
        registry.register(GestureDescriptorForTest.gestures)
        registry.register(GestureDescriptorForTest.gestures)
        XCTAssertTrue(registry.isRegistered(identifier: "gestures.hand"))
        XCTAssertEqual(registry.modules.count, 1)
        registry.unregister(identifier: "gestures.hand")
        XCTAssertFalse(registry.isRegistered(identifier: "gestures.hand"))
    }

    @MainActor func testModuleLifecycleThroughContext() async throws {
        let bus = EditorCommandBus()
        let module = RecordingModule()
        try await module.start(context: EditorModuleContext(commandBus: bus))
        XCTAssertTrue(module.started)
        await module.stop()
        XCTAssertTrue(module.stopped)
    }

    @MainActor func testModuleSendsThroughBus() async {
        let bus = EditorCommandBus()
        let stream = await bus.commands()
        let module = RecordingModule()
        try? await module.start(context: EditorModuleContext(commandBus: bus))
        await module.emitUndo()
        await bus.finish()
        var received: [EditorCommand] = []
        for await command in stream {
            received.append(command)
        }
        XCTAssertEqual(received, [.undo])
    }
}

private enum GestureDescriptorForTest {
    static var gestures: ModuleDescriptor {
        ModuleDescriptor(identifier: "gestures.hand", displayName: "Gestos")
    }
}

@MainActor
private final class RecordingModule: EditorInputModule {
    let identifier = "test.recorder"
    let displayName = "Grabadora"
    var started = false
    var stopped = false
    private var context: EditorModuleContext?

    func start(context: EditorModuleContext) async throws {
        self.context = context
        started = true
    }

    func stop() async {
        stopped = true
        context = nil
    }

    func emitUndo() async {
        await context?.commandBus.send(.undo)
    }
}
