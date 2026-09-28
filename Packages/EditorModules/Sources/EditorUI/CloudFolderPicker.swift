import AppKit
import DocumentKit

/// Panel para autorizar la carpeta de iCloud Drive donde se guardan los documentos.
@MainActor enum CloudFolderPicker {
    static func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = CloudDocuments.driveURL
        panel.prompt = "Usar esta carpeta"
        panel.message = "Elige iCloud Drive o una carpeta dentro de iCloud Drive (por ejemplo, crea «EditorFinal»). Los documentos nuevos se guardarán ahí y macOS los sincronizará."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            try CloudDocuments.remember(folder)
        } catch {
            NSApplication.shared.presentError(error)
        }
    }
}
