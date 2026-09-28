import Foundation
import EditorCore

/// Imágenes de un documento que aún no se ha guardado. Se copian a una carpeta temporal con la misma
/// estructura (`images/…`) que tendrán junto al archivo, así el Markdown no cambia al guardar.
public enum DraftImages {
    /// URL ficticia del documento dentro de una carpeta temporal nueva; la carpeta se crea al insertar.
    public static func makeDocumentURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorFinal-borradores", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Sin título.md")
    }

    /// Mueve junto a `documentURL` las imágenes del texto que siguen en la carpeta temporal.
    /// Devuelve cuántas movió. No sobrescribe archivos existentes con el mismo nombre.
    @discardableResult
    public static func move(text: String, from draftURL: URL, to documentURL: URL) throws -> Int {
        let manager = FileManager.default
        var moved = 0
        for line in MarkdownDocument(text).lines {
            guard let image = MarkdownImage(line: line.content),
                  let source = image.fileURL(relativeTo: draftURL), manager.fileExists(atPath: source.path),
                  let destination = image.fileURL(relativeTo: documentURL),
                  !manager.fileExists(atPath: destination.path) else { continue }
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: source, to: destination)
            try? manager.removeItem(at: source)
            moved += 1
        }
        return moved
    }
}
