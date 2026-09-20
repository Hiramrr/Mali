import AppKit
import EditorCore

public struct WritingStyle: Equatable, Sendable {
    public var size: Double
    public var family: String
    public var spacing: Double
    public var syntax: Bool
    public init(size: Double = 18, family: String = "system", spacing: Double = 6, syntax: Bool = true) {
        self.size = min(36, max(12, size))
        self.family = family
        self.spacing = min(16, max(0, spacing))
        self.syntax = syntax
    }

    @MainActor public var font: NSFont {
        switch family {
        case "serif": NSFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
        case "mono": .monospacedSystemFont(ofSize: size, weight: .regular)
        default: .systemFont(ofSize: size)
        }
    }

    @MainActor public var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = spacing
        return [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
    }
}

@MainActor public enum MarkdownAppearance {
    private static let inlinePatterns: [(NSRegularExpression, NSFontTraitMask)] = [
        (#"(?<![\\*])\*\*[^*\n]+\*\*"#, NSFontTraitMask.boldFontMask),
        (#"(?<![\\*])\*[^*\n]+\*(?!\*)"#, NSFontTraitMask.italicFontMask),
        (#"`[^`\n]+`"#, NSFontTraitMask.fixedPitchFontMask)
    ].compactMap { pattern, trait in
        (try? NSRegularExpression(pattern: pattern)).map { ($0, trait) }
    }

    public static func decorate(_ storage: NSMutableAttributedString, document: MarkdownDocument, style: WritingStyle) {
        let full = NSRange(location: 0, length: storage.length)
        storage.setAttributes(style.attributes, range: full)
        guard style.syntax else { return }
        for line in document.lines {
            guard NSMaxRange(line.range) <= storage.length else { continue }
            switch line.kind {
            case .heading(let level):
                let size = style.size + Double(max(2, 16 - level * 3))
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .semibold), range: line.range)
            case .code, .fence:
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: style.size - 1, weight: .regular), range: line.range)
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: line.range)
            case .quote:
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: line.range)
            default: break
            }
            if line.kind != .code && line.kind != .fence {
                for (pattern, trait) in inlinePatterns {
                    pattern.enumerateMatches(in: storage.string, range: line.range) { match, _, _ in
                        guard let match else { return }
                        let font = storage.attribute(.font, at: match.range.location, effectiveRange: nil) as? NSFont ?? style.font
                        let styled = trait == .fixedPitchFontMask ? NSFont.monospacedSystemFont(ofSize: style.size - 1, weight: .regular) : NSFontManager.shared.convert(font, toHaveTrait: trait)
                        storage.addAttribute(.font, value: styled, range: match.range)
                    }
                }
            }
            if line.prefixLength > 0 {
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: NSRange(location: line.range.location, length: line.prefixLength))
            }
        }
    }

    public static func readingText(_ source: String, document: MarkdownDocument, style: WritingStyle, forPrint: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let color = forPrint ? NSColor.black : NSColor.textColor
        for line in document.lines {
            if line.kind == .fence { continue }
            var content = line.content
            if line.kind == .list { content = "• " + content }
            if line.kind == .rule { content = "────────────" }
            let output: NSMutableAttributedString
            if line.kind == .code {
                output = NSMutableAttributedString(string: content)
            } else if let parsed = try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                output = NSMutableAttributedString(attributedString: NSAttributedString(parsed))
            } else { output = NSMutableAttributedString(string: content) }
            output.append(NSAttributedString(string: "\n"))
            let range = NSRange(location: 0, length: output.length)
            output.addAttributes(style.attributes, range: range)
            output.addAttribute(.foregroundColor, value: color, range: range)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = style.spacing
            if case .heading(let level) = line.kind {
                output.addAttribute(.font, value: NSFont.systemFont(ofSize: style.size + Double(max(2, 16 - level * 3)), weight: .semibold), range: range)
                paragraph.paragraphSpacingBefore = 12
                paragraph.paragraphSpacing = 6
            } else if line.kind == .code {
                output.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: style.size - 1, weight: .regular), range: range)
                output.addAttribute(.backgroundColor, value: forPrint ? NSColor(white: 0.95, alpha: 1) : NSColor.quaternaryLabelColor, range: range)
            } else if line.kind == .quote {
                paragraph.headIndent = 18
                paragraph.firstLineHeadIndent = 18
                output.addAttribute(.foregroundColor, value: forPrint ? NSColor.darkGray : NSColor.secondaryLabelColor, range: range)
            }
            output.addAttribute(.paragraphStyle, value: paragraph, range: range)
            output.enumerateAttribute(.inlinePresentationIntent, in: range) { value, run, _ in
                guard let raw = value as? NSNumber else { return }
                let intent = InlinePresentationIntent(rawValue: raw.uintValue)
                var font = output.attribute(.font, at: run.location, effectiveRange: nil) as? NSFont ?? style.font
                if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                if intent.contains(.code) { font = .monospacedSystemFont(ofSize: style.size - 1, weight: .regular) }
                output.addAttribute(.font, value: font, range: run)
                if intent.contains(.strikethrough) { output.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: run) }
            }
            // Only explicit web/email links can be opened from a document.
            output.enumerateAttribute(.link, in: range) { value, run, _ in
                guard let url = value as? URL else { return }
                if !["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                    output.removeAttribute(.link, range: run)
                }
            }
            result.append(output)
        }
        return result
    }
}
