import CommandGrammar
import Foundation

/// Intención detectada en un dictado. El editor la convierte en `EditorCommand`;
/// este tipo no sabe nada de `NSTextView` ni de SwiftUI.
public enum VoiceIntent: Sendable, Equatable {
    case dictation(String)
    case deleteLastInsertion
    case undo
    case newline
    case paragraph
    /// Comando de la gramática probada (find/select/save/open/export/format/
    /// delete/replace/undo/redo/rename/rewrite). Se traduce a `EditorCommand`.
    case command(ParsedCommand)
    case cancel
}
