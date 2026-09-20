import Foundation
import EditorCore

public enum DocumentError: LocalizedError {
    case invalidEncoding

    public var errorDescription: String? {
        "No se pudo abrir el archivo como texto UTF-8. El archivo original no se ha modificado."
    }
}

public enum UTF8Document {
    public static func decode(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw DocumentError.invalidEncoding
        }
        return text
    }

    public static func encode(_ text: String) -> Data { Data(text.utf8) }
}
