import AppKit
import UniformTypeIdentifiers
import EditorCore
import DesignSystem
import EditorEngine

/// Exportación a archivo (txt, rtf y Word). PDF sigue en `PrintDocument`,
/// porque el diálogo de impresión ya gestiona destino y sobrescritura.
@MainActor public enum DocumentExport {
    public enum Format: String, Sendable {
        case plainText = "txt"
        case richText = "rtf"
        case word = "docx"

        public var contentTypes: [UTType] {
            switch self {
            case .plainText: [.plainText]
            case .richText: [.rtf]
            case .word: [UTType(filenameExtension: "docx")].compactMap { $0 }
            }
        }
    }

    /// Pide destino con un panel de guardado y escribe el archivo.
    /// `richText` es el texto decorado del editor, usado para rtf.
    public static func run(format: Format, text: String, title: String, richText: NSAttributedString?, documentURL: URL? = nil) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = title
        panel.allowedContentTypes = format.contentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let data = try data(format: format, text: text, title: title, richText: richText, documentURL: documentURL) else { return }
            try data.write(to: url, options: .atomic)
        } catch {
            NSApplication.shared.presentError(error)
        }
    }

    /// Contenido del archivo exportado; `nil` si falta el texto enriquecido para rtf.
    public static func data(format: Format, text: String, title: String, richText: NSAttributedString?, documentURL: URL? = nil) throws -> Data? {
        switch format {
        case .plainText:
            return Data(text.utf8)
        case .richText:
            guard let richText else { return nil }
            return richText.rtf(from: NSRange(location: 0, length: richText.length), documentAttributes: [:])
        case .word:
            let source = "# \(title)\n\n" + text
            let rendered = MarkdownAppearance.readingText(
                source, document: MarkdownDocument(source),
                style: WritingStyle(size: 12, family: "serif", spacing: 4),
                forPrint: false, documentURL: documentURL)
            return try rendered.data(
                from: NSRange(location: 0, length: rendered.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
        }
    }
}
