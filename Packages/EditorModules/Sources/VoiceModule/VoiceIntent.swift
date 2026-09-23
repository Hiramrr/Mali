import Foundation

/// Intención detectada en un dictado. El editor la convierte en `EditorCommand`;
/// este tipo no sabe nada de `NSTextView` ni de SwiftUI.
public enum VoiceIntent: Sendable, Equatable {
    case dictation(String)
    case deleteLastInsertion
    case undo
    case newline
    case paragraph
    case renameTitle(String)
    case cancel
}
