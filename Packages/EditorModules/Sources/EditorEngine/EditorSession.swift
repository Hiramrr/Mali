import AppKit
import Observation
import EditorCore
import DesignSystem

@MainActor @Observable
public final class EditorSession {
    public var focusMode = false
    public var paragraphFocus = false
    public var typewriterMode = false
    public var readingMode = false
    public private(set) var headings: [DocumentHeading] = []
    public private(set) var statistics = DocumentStatistics()
    public private(set) var selectedCharacters = 0
    public private(set) var cursorOffset = 0
    public private(set) var analysisRevision = 0
    @ObservationIgnored public weak var textView: NSTextView?
    @ObservationIgnored public private(set) var analysis = MarkdownDocument("")
    @ObservationIgnored private var outlineTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    public init() {}

    public func refreshOutline(_ text: String) {
        generation += 1
        let revision = generation
        outlineTask?.cancel()
        outlineTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            let analysis = await Self.analyze(text)
            guard !Task.isCancelled, let self, self.generation == revision else { return }
            self.analysis = analysis
            self.headings = analysis.headings
            self.statistics = analysis.statistics
            self.analysisRevision += 1
            (self.textView as? WritingTextView)?.applyAnalysis(analysis)
        }
    }

    private nonisolated static func analyze(_ text: String) async -> MarkdownDocument {
        MarkdownDocument(text)
    }

    public func selectionChanged() {
        guard let view = textView else { return }
        cursorOffset = view.selectedRange().location
        selectedCharacters = view.selectedRange().length == 0 ? 0 : (view.string as NSString).substring(with: view.selectedRange()).count
        (view as? WritingTextView)?.updateParagraphHighlight()
    }

    public func stop() {
        outlineTask?.cancel()
        outlineTask = nil
        textView = nil
    }

    public func send(_ command: EditorCommand) {
        guard !readingMode, let view = textView else { return }
        switch command {
        case .insertText(let text), .replaceSelection(let text):
            view.insertText(text, replacementRange: view.selectedRange())
        case .selectRange(let range):
            guard let valid = range.validated(in: view.string) else { return }
            view.setSelectedRange(valid)
            view.scrollRangeToVisible(valid)
        case .selectAll: view.selectAll(nil)
        case .deleteBackward: view.deleteBackward(nil)
        case .deleteForward: view.deleteForward(nil)
        case .undo: view.undoManager?.undo()
        case .redo: view.undoManager?.redo()
        case .toggleBold: wrapSelection(in: "**", view: view)
        case .toggleItalic: wrapSelection(in: "*", view: view)
        case .toggleCode: wrapSelection(in: "`", view: view)
        case .heading(let level):
            guard (1...6).contains(level) else { return }
            prefixParagraph(String(repeating: "#", count: level) + " ", view: view)
        case .bulletList: prefixParagraph("- ", view: view)
        case .quote: prefixParagraph("> ", view: view)
        case .insertLink:
            let range = view.selectedRange()
            let selected = (view.string as NSString).substring(with: range)
            let label = selected.isEmpty ? "texto" : selected
            view.insertText("[\(label)](https://)", replacementRange: range)
            view.setSelectedRange(NSRange(location: range.location + label.utf16.count + 3, length: 8))
        }
        view.window?.makeFirstResponder(view)
    }

    private func prefixParagraph(_ prefix: String, view: NSTextView) {
        let text = view.string as NSString
        let range = text.paragraphRange(for: view.selectedRange())
        let paragraph = text.substring(with: range)
        let replacement = paragraph.hasPrefix(prefix) ? String(paragraph.dropFirst(prefix.count)) : prefix + paragraph
        view.insertText(replacement, replacementRange: range)
    }

    private func wrapSelection(in marker: String, view: NSTextView) {
        let text = view.string as NSString
        let range = view.selectedRange()
        let selected = text.substring(with: range)
        let width = marker.utf16.count
        let hasOuterMarkers = range.location >= width && NSMaxRange(range) + width <= text.length
            && text.substring(with: NSRange(location: range.location - width, length: width)) == marker
            && text.substring(with: NSRange(location: NSMaxRange(range), length: width)) == marker
        // A second press removes the markers around the still-selected content.
        if hasOuterMarkers {
            view.insertText(selected, replacementRange: NSRange(location: range.location - width, length: range.length + width * 2))
            view.setSelectedRange(NSRange(location: range.location - width, length: range.length))
            return
        }
        let unwrap = selected.count >= marker.count * 2 && selected.hasPrefix(marker) && selected.hasSuffix(marker)
        let replacement = unwrap ? String(selected.dropFirst(marker.count).dropLast(marker.count)) : marker + selected + marker
        view.insertText(replacement, replacementRange: range)
        view.setSelectedRange(NSRange(location: range.location + (unwrap ? 0 : width), length: unwrap ? replacement.utf16.count : range.length))
    }
}
