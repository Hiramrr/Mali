import Foundation

public struct MarkdownLine: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case text, heading(Int), quote, list, code, fence, rule
    }
    public let range: NSRange
    public let content: String
    public let prefixLength: Int
    public let kind: Kind
}

public struct DocumentStatistics: Sendable, Equatable {
    public var words = 0
    public var characters = 0
    public var paragraphs = 0
    public var readingMinutes: Int { max(1, Int(ceil(Double(words) / 220))) }
    public init() {}
}

public struct MarkdownDocument: Sendable {
    public let lines: [MarkdownLine]
    public let statistics: DocumentStatistics

    public var headings: [DocumentHeading] {
        lines.compactMap { line in
            guard case .heading(let level) = line.kind else { return nil }
            return DocumentHeading(title: line.content, offset: line.range.location, level: level)
        }
    }

    public init(_ text: String) {
        var lines: [MarkdownLine] = []
        var fence: (Character, Int)?
        var offset = 0
        var statistics = DocumentStatistics()
        var inParagraph = false
        // ponytail: ATX headings and fenced code only; add setext/table blocks with a full Markdown parser when needed.
        text.enumerateSubstrings(in: text.startIndex..., options: [.byLines, .substringNotRequired]) { _, range, enclosing, _ in
            let raw = String(text[range])
            let indent = raw.prefix(while: { $0 == " " }).count
            let line = indent <= 3 ? String(raw.dropFirst(indent)) : raw
            var kind: MarkdownLine.Kind = .text
            var content = raw
            var prefix = 0
            let marker = line.first
            let fenceCount = line.prefix(while: { $0 == marker }).count
            if let current = fence {
                if marker == current.0, fenceCount >= current.1,
                   line.dropFirst(fenceCount).trimmingCharacters(in: .whitespaces).isEmpty {
                    kind = .fence
                    fence = nil
                } else { kind = .code }
            } else if (marker == "`" || marker == "~"), fenceCount >= 3, let marker {
                kind = .fence
                fence = (marker, fenceCount)
            } else {
                let level = line.prefix(while: { $0 == "#" }).count
                if (1...6).contains(level), line.count == level || line.dropFirst(level).first?.isWhitespace == true {
                    kind = .heading(level)
                    prefix = indent + level + (line.count > level ? 1 : 0)
                    content = String(raw.dropFirst(prefix))
                } else if line.hasPrefix("> ") {
                    kind = .quote; prefix = indent + 2; content = String(raw.dropFirst(prefix))
                } else if ["- ", "* ", "+ "].contains(where: line.hasPrefix) {
                    kind = .list; prefix = indent + 2; content = String(raw.dropFirst(prefix))
                } else if line == "---" || line == "***" || line == "___" {
                    kind = .rule
                }
            }
            let blank = raw.trimmingCharacters(in: .whitespaces).isEmpty
            if !blank && !inParagraph { statistics.paragraphs += 1 }
            inParagraph = !blank
            lines.append(MarkdownLine(range: NSRange(location: offset, length: text[enclosing].utf16.count), content: content, prefixLength: prefix, kind: kind))
            offset += text[enclosing].utf16.count
        }
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            statistics.words += 1
        }
        statistics.characters = text.count
        self.lines = lines
        self.statistics = statistics
    }
}
