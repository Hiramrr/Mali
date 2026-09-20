import Foundation

/// Offsets use UTF-16, the same units as TextKit and NSString.
public struct TextRange: Equatable, Sendable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public func validated(in text: String) -> NSRange? {
        guard location >= 0, length >= 0, location <= text.utf16.count,
              length <= text.utf16.count - location else { return nil }
        let range = NSRange(location: location, length: length)
        guard let indices = Range(range, in: text),
              (indices.lowerBound == text.endIndex || text.indices.contains(indices.lowerBound)),
              (indices.upperBound == text.endIndex || text.indices.contains(indices.upperBound)) else { return nil }
        return range
    }
}

public enum EditorCommand: Equatable, Sendable {
    case insertText(String)
    case replaceSelection(String)
    case selectRange(TextRange)
    case selectAll
    case deleteBackward
    case deleteForward
    case undo
    case redo
    case toggleBold
    case toggleItalic
    case toggleCode
    case heading(Int)
    case bulletList
    case quote
    case insertLink
}

public struct DocumentHeading: Identifiable, Equatable, Sendable {
    public var id: Int { offset }
    public let title: String
    public let offset: Int
    public let level: Int
}

public enum DocumentOutline {
    public static func headings(in text: String) -> [DocumentHeading] {
        MarkdownDocument(text).headings
    }
}
