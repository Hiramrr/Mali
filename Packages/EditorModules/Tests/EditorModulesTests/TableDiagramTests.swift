import XCTest
import AppKit
import SwiftUI
import PDFKit
@testable import EditorCore
@testable import DocumentKit
@testable import EditorEngine
@testable import DiagramModule
import DesignSystem
@testable import ExportFeature

final class MarkdownTableTests: XCTestCase {
    func testTableLinesAreRecognized() {
        let source = "Antes\n\n| Nombre | Precio |\n| :--- | ---: |\n| Café | 2 € |\nTé | 1\n\nDespués\n"
        let kinds = MarkdownDocument(source).lines.map(\.kind)
        XCTAssertEqual(kinds, [.text, .text, .tableRow(header: true), .tableDelimiter, .tableRow(header: false), .tableRow(header: false), .text, .text])
    }

    func testRangesStayUTF16AndSetextStillWorks() {
        let source = "a 🐈 | b\n--|--\n\nTítulo\n---\n"
        let document = MarkdownDocument(source)
        XCTAssertEqual(document.lines[0].range, NSRange(location: 0, length: ("a 🐈 | b\n" as NSString).length))
        XCTAssertEqual(document.lines[1].kind, .tableDelimiter)
        XCTAssertEqual(document.headings.map(\.title), ["Título"])
        // Una sola columna en el separador no es tabla para una cabecera de dos.
        XCTAssertEqual(MarkdownDocument("a | b\n---\n").lines.first?.kind, .heading(2))
    }

    func testCellsAndAlignments() {
        XCTAssertEqual(MarkdownTable.cells(in: "| a | `b\\|c` |  |"), ["a", "`b|c`", ""])
        XCTAssertEqual(MarkdownTable.cells(in: "x|y"), ["x", "y"])
        XCTAssertEqual(MarkdownTable.alignments(delimiter: "| :-- | :-: | --: | --- |"), [.left, .center, .right, .natural])
        XCTAssertNil(MarkdownTable.alignments(delimiter: "| a | --- |"))
    }

    @MainActor func testReadingTableUsesTextTableAndHidesPipes() throws {
        let source = "| Nombre | Precio |\n| --- | ---: |\n| **Café** | 2 |\n| Té |\n"
        let rendered = MarkdownAppearance.readingText(source, document: MarkdownDocument(source), style: WritingStyle())
        XCTAssertFalse(rendered.string.contains("|"))
        XCTAssertFalse(rendered.string.contains("**"))
        var blocks: [NSTextTableBlock] = []
        rendered.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if let block = (value as? NSParagraphStyle)?.textBlocks.first as? NSTextTableBlock { blocks.append(block) }
        }
        // 3 filas × 2 columnas: la celda que falta se rellena vacía.
        XCTAssertEqual(blocks.count, 6)
        XCTAssertEqual(blocks.last?.startingRow, 2)
        XCTAssertEqual(blocks.last?.startingColumn, 1)
        let priceParagraph = try XCTUnwrap(rendered.attribute(.paragraphStyle, at: (rendered.string as NSString).range(of: "Precio").location, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(priceParagraph.alignment, .right)
    }

    @MainActor func testReaderFallsBackToTextKit1OnlyWithTables() throws {
        func readerView(_ text: String) throws -> NSTextView {
            let host = NSHostingView(rootView: MarkdownReader(text: text, style: WritingStyle()))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            func find(_ view: NSView) -> NSTextView? {
                (view as? NSScrollView)?.documentView as? NSTextView ?? view.subviews.lazy.compactMap(find).first
            }
            return try XCTUnwrap(find(host))
        }
        // TextKit 2 apila las celdas; TextKit 1 dibuja la tabla.
        XCTAssertNil(try readerView("| a | b |\n| - | - |\n| 1 | 2 |\n").textLayoutManager)
        XCTAssertNotNil(try readerView("Sin tablas").textLayoutManager)
    }

    @MainActor func testWordExportKeepsTableCells() throws {
        let text = "| Nombre | Precio |\n| --- | --- |\n| Café | 2 |\n"
        let word = try XCTUnwrap(DocumentExport.data(format: .word, text: text, title: "Tabla", richText: nil))
        let read = try NSAttributedString(data: word, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
        XCTAssertTrue(read.string.contains("Café"))
        XCTAssertFalse(read.string.contains("| Café"))
    }
}

final class DiagramParserTests: XCTestCase {
    func testParsesShapesChainsAndLabels() throws {
        let graph = try DiagramParser.parse("""
        direction LR
        # comentario
        request[Request] -> valid{Valid?}
        valid -- Yes --> process[Process request] -> ready((Ready))
        valid -->|No| repair[(Repair \\] input)] -> valid
        """)
        XCTAssertEqual(graph.direction, .leftRight)
        XCTAssertEqual(graph.nodes.map(\.id), ["request", "valid", "process", "ready", "repair"])
        XCTAssertEqual(graph.nodes.map(\.shape), [.rounded, .decision, .rounded, .terminal, .stadium])
        XCTAssertEqual(graph.nodes[4].text, "Repair ] input")
        XCTAssertEqual(graph.edges, [
            DiagramEdge(from: "request", to: "valid"),
            DiagramEdge(from: "valid", to: "process", label: "Yes"),
            DiagramEdge(from: "process", to: "ready"),
            DiagramEdge(from: "valid", to: "repair", label: "No"),
            DiagramEdge(from: "repair", to: "valid"),
        ])
    }

    func testImplicitNodesIdsWithDashesAndUnicode() throws {
        let graph = try DiagramParser.parse("paso-1 -> paso-2\npaso-2[Café ☕] --> fin")
        XCTAssertEqual(graph.nodes.map(\.text), ["paso-1", "Café ☕", "fin"])
        XCTAssertEqual(graph.edges.count, 2)
    }

    func testInvalidSyntaxThrowsTypedError() {
        for source in ["", "a -> ", "a[sin cerrar", "a => b", "direction XY", "-> b"] {
            XCTAssertThrowsError(try DiagramParser.parse(source), source) { error in
                XCTAssertTrue(error is DiagramParseError)
            }
        }
    }

    func testTooLargeGraphIsRejected() {
        let source = (0...DiagramParser.maxNodes).map { "n\($0)" }.joined(separator: "\n")
        XCTAssertThrowsError(try DiagramParser.parse(source))
    }
}

final class DiagramLayoutTests: XCTestCase {
    private func layout(_ source: String) throws -> (DiagramGraph, DiagramLayout) {
        let graph = try DiagramParser.parse(source)
        let sizes = graph.nodes.map { _ in CGSize(width: 100, height: 40) }
        return (graph, DiagramLayout(graph: graph, sizes: sizes))
    }

    private func assertNoOverlap(_ frames: [CGRect], file: StaticString = #filePath, line: UInt = #line) {
        for i in frames.indices {
            for j in frames.indices where j > i {
                XCTAssertFalse(frames[i].intersects(frames[j]), "\(i) y \(j) se solapan", file: file, line: line)
            }
        }
    }

    func testDeterministicAndWithoutOverlaps() throws {
        let source = "a -> b\na -> c\na -> d\nb -> e\nc -> e\nd -> e\na -> e\ne -> a"
        let (_, first) = try layout(source)
        let (_, second) = try layout(source)
        XCTAssertEqual(first, second)
        assertNoOverlap(first.frames)
        XCTAssertEqual(first.routes.count, 8)
        for frame in first.frames {
            XCTAssertTrue(CGRect(origin: .zero, size: first.size).contains(frame))
        }
    }

    func testTopBottomRanksGoDownAndCyclesResolve() throws {
        let (_, result) = try layout("a -> b -> c -> a")
        XCTAssertLessThan(result.frames[0].maxY, result.frames[1].minY)
        XCTAssertLessThan(result.frames[1].maxY, result.frames[2].minY)
        // La arista de retroceso termina en `a`, no en `c`.
        let back = try XCTUnwrap(result.routes.last?.points.last)
        XCTAssertEqual(back.y, result.frames[0].maxY, accuracy: 0.5)
    }

    func testLeftRightRanksGoRight() throws {
        let (_, result) = try layout("direction LR\na -> b")
        XCTAssertLessThan(result.frames[0].maxX, result.frames[1].minX)
        XCTAssertEqual(result.frames[0].midY, result.frames[1].midY, accuracy: 0.5)
    }

    func testLongEdgesDoNotCrossNodes() throws {
        let (_, result) = try layout("a -> b -> c -> d\na -> d\nb -> x\nx -> d")
        assertNoOverlap(result.frames)
        let long = result.routes[3]
        for (start, end) in zip(long.points, long.points.dropFirst()) {
            for (index, frame) in result.frames.enumerated() where index != 0 && index != 3 {
                let inner = frame.insetBy(dx: 1, dy: 1)
                for step in 0...20 {
                    let t = CGFloat(step) / 20
                    let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
                    XCTAssertFalse(inner.contains(point), "La arista larga atraviesa el nodo \(index)")
                }
            }
        }
    }

    func testSelfLoopAndLabels() throws {
        let (_, result) = try layout("a -- otra vez --> a\na -- sí --> b")
        XCTAssertEqual(result.routes.count, 2)
        XCTAssertNotNil(result.routes[0].labelCenter)
        XCTAssertNotNil(result.routes[1].labelCenter)
    }
}

final class DiagramRenderingTests: XCTestCase {
    private let diagram = "Antes\n\n```diagram\ninicio((Inicio)) -> paso[Paso] -> fin((Fin))\n```\n\nDespués\n"

    @MainActor func testReadingTextEmbedsDiagramAttachment() throws {
        let rendered = MarkdownAppearance.readingText(diagram, document: MarkdownDocument(diagram), style: WritingStyle())
        var attachments: [NSTextAttachment] = []
        rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment { attachments.append(attachment) }
        }
        let attachment = try XCTUnwrap(attachments.first)
        XCTAssertEqual(attachments.count, 1)
        XCTAssertGreaterThan(attachment.bounds.height, 0)
        XCTAssertTrue(attachment.image?.accessibilityDescription?.contains("Inicio flecha Paso") == true)
        XCTAssertFalse(rendered.string.contains("->"))
        XCTAssertTrue(rendered.string.contains("Antes"))
        XCTAssertTrue(rendered.string.contains("Después"))
    }

    @MainActor func testInvalidDiagramAndOtherFencesStayCode() {
        for source in ["```diagram\na => b\n```\n", "```swift\na -> b\n```\n"] {
            let rendered = MarkdownAppearance.readingText(source, document: MarkdownDocument(source), style: WritingStyle())
            XCTAssertEqual(rendered.string, "a \(source.contains("=>") ? "=>" : "->") b\n")
            XCTAssertNil(rendered.attribute(.attachment, at: 0, effectiveRange: nil))
        }
    }

    @MainActor func testPDFIncludesDiagramPage() throws {
        _ = NSApplication.shared
        let operation = PrintDocument.makeOperation(text: diagram, title: "Diagrama")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EditorFinal-diagram-test.pdf")
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.printInfo.jobDisposition = .save
        operation.printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        XCTAssertTrue(operation.run())
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertTrue(document.string?.contains("Después") == true)
        XCTAssertFalse(document.string?.contains("->") == true)
    }
}

final class DraftImagesTests: XCTestCase {
    func testMovesReferencedImagesNextToSavedDocument() throws {
        let draft = DraftImages.makeDocumentURL()
        let image = MarkdownImage(alt: "foto", path: "images/foto.png")
        let source = try XCTUnwrap(image.fileURL(relativeTo: draft))
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: source)
        let saved = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true).appendingPathComponent("Nota.md")
        defer { try? FileManager.default.removeItem(at: saved.deletingLastPathComponent()) }

        let moved = try DraftImages.move(text: "Texto\n" + image.markdown + "\n![otra](images/no-existe.png)\n", from: draft, to: saved)
        XCTAssertEqual(moved, 1)
        let destination = try XCTUnwrap(image.fileURL(relativeTo: saved))
        XCTAssertEqual(try Data(contentsOf: destination), Data([1, 2, 3]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertNotEqual(DraftImages.makeDocumentURL(), draft)
    }
}
