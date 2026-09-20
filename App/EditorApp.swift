import SwiftUI
import UniformTypeIdentifiers
import DocumentKit
import EditorUI

extension UTType {
    static let editorMarkdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

struct TextDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.editorMarkdown, .plainText, .utf8PlainText]
    static let writableContentTypes: [UTType] = [.editorMarkdown, .plainText]
    var text = ""

    init() {}
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        text = try UTF8Document.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: UTF8Document.encode(text))
    }
}

@main
struct EditorApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: TextDocument()) { configuration in
            EditorScreen(
                text: configuration.$document.text,
                title: configuration.fileURL?.deletingPathExtension().lastPathComponent ?? "Sin título",
                recentURLs: NSDocumentController.shared.recentDocumentURLs,
                openFile: { url in
                    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                        if let error { NSApplication.shared.presentError(error) }
                    }
                }
            )
        }
        .defaultSize(width: 1120, height: 740)
        .commands {
            EditorMenus()
            CommandGroup(after: .textEditing) {
                Button("Buscar…") {
                    let item = NSMenuItem()
                    item.tag = NSTextFinder.Action.showFindInterface.rawValue
                    NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: item)
                }.keyboardShortcut("f")
            }
        }
        Settings { EditorSettings() }
    }
}
