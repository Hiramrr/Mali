// Fase 11 — Integración de comandos de voz con el editor Swift real.
//
//  Pipeline: VoiceCommand (espejo 1:1 de ParsedCommand) → validación de
//  contexto → política de confirmación → EditorCommandExecutor → editor real.
//
//  CONGELADO (no duplicar lógica funcional, solo espejar lectura):
//  Grammar.swift, Types.swift, CommandGrammar, ParsedCommand, Validator,
//  CommandRisk, ConfirmationPolicy, Speech/DictationTranscriber. Esos viven en
//  command-grammar y NO se tocan aquí. Este archivo espeja su política:
//
//      NAVIGATION (find/select) → IMMEDIATE
//      TODO LO QUE MUTA ESTADO → CONFIRM
//
//  Tecnología real: NSTextView (TextKit 2) vía EditorSession/NativeTextEditor.
//  Toda mutación ocurre en @MainActor. Sin Foundation Models, sin gestos.
//
//  Decisiones documentadas:
//  - Búsqueda: coincidencia literal exacta primero; si no hay, reintento
//    normalizado (caseInsensitive + diacriticInsensitive). Sin fuzzy, sin
//    corrección automática del query.
//  - Duplicados: primera coincidencia en o después del cursor; si no hay
//    ninguna después, se envuelve a la primera del documento (wrap).
//  - Formato: el editor persiste Markdown visible (**bold**, *italic*).
//    Grammar soporta underline pero el motor no tiene toggleUnderline, así
//    que underline se persiste como <u>…</u> (HTML inline válido en Markdown).
//    Una sola llamada insertText por formato = una sola operación de Undo.
//    Segunda aplicación sobre el mismo rango conmuta (unwrap), igual que
//    EditorSession.wrapSelection.
//  - Título: no forma parte del UndoManager del NSTextView; se registra en el
//    MISMO UndoManager vía registerUndo (deshacer/restaurar incluidos).
//  - rewriteSelection: NO llama Foundation Models. Registra
//    SIMULATED_REWRITE_REQUEST con texto, instrucción y rango. 0 mutación.
//    (Doble determinista para la política de confirmación; la reescritura
//    real de producción vive en EditorSession con RewriteProvider.)
//  - Export: texto plano (.txt), enriquecido (.rtf), PDF headless (.pdf) y
//    Word (.docx vía Office Open XML), todos al almacén temporal.
//  - Guardar/abrir: solo archivos dentro del directorio temporal (fixtures).
import AppKit
import Foundation
import DesignSystem
import EditorCore

// MARK: - Comando (espejo de ParsedCommand; la gramática sigue congelada)

/// Estilos soportados por Grammar (FormatStyle). Espejo local para no
/// depender del paquete command-grammar (target ejecutable, no importable).
public enum TextFormatStyle: String, Equatable, Sendable {
    case bold
    case italic
    case underline
}

/// Formatos de exportación. Todos implementados contra el almacén temporal.
public enum VoiceExportFormat: String, Equatable, Sendable {
    case pdf
    case word
    case plainText
    case richText
}

/// Espejo 1:1 de ParsedCommand para el flujo del editor real.
public enum VoiceCommand: Equatable, Sendable {
    case renameTitle(String)
    case deleteSelection
    case replaceSelection(String)
    case rewriteSelection(String)
    case formatSelection(TextFormatStyle)
    case undo
    case redo
    case selectText(String)
    case findText(String)
    case saveDocument
    case openDocument(String?)
    case exportDocument(VoiceExportFormat)
    case unsupported(String)
    case multipleActions
    case unknown
}

// MARK: - Riesgo y política (espejo congelado de RiskPolicy Fase 10C)

public enum VoiceCommandRisk: String, Equatable, Sendable {
    case navigation
    case reversible
    case contentChanging
    case externalSideEffect
}

/// Espejo de riskOf(_:). NO modificar sin cambiar también command-grammar.
public func voiceRiskOf(_ cmd: VoiceCommand) -> VoiceCommandRisk {
    switch cmd {
    case .selectText, .findText: return .navigation
    case .undo, .redo, .formatSelection: return .reversible
    case .renameTitle, .deleteSelection, .replaceSelection, .rewriteSelection: return .contentChanging
    case .saveDocument, .openDocument, .exportDocument: return .externalSideEffect
    case .unsupported, .unknown, .multipleActions: return .navigation
    }
}

public enum VoiceConfirmationPolicy: String, Equatable, Sendable {
    case immediate
    case confirm
}

/// Espejo de policyFor(risk:). Fase 10C: solo NAVIGATION es inmediata.
public func voicePolicyFor(risk: VoiceCommandRisk) -> VoiceConfirmationPolicy {
    switch risk {
    case .navigation: return .immediate
    case .reversible, .contentChanging, .externalSideEffect: return .confirm
    }
}

public func voicePolicyForCommand(_ cmd: VoiceCommand) -> VoiceConfirmationPolicy {
    voicePolicyFor(risk: voiceRiskOf(cmd))
}

// MARK: - Resultado y error explícitos (nunca Bool)

public enum EditorCommandError: Equatable, Sendable {
    case noSelection
    case cannotUndo
    case cannotRedo
    case noMatch(String)
    case staleProposal
    case invalidRange
    case unsupportedCommand(String)
    case notImplementedInEditor(String)
    case ioError(String)

    public var message: String {
        switch self {
        case .noSelection: return "No hay texto seleccionado."
        case .cannotUndo: return "Nada que deshacer."
        case .cannotRedo: return "Nada que rehacer."
        case .noMatch(let q): return "Sin coincidencia: \"\(q)\"."
        case .staleProposal: return "El contenido cambió. Repite el comando."
        case .invalidRange: return "Rango inválido."
        case .unsupportedCommand(let s): return "Comando no disponible: \(s)."
        case .notImplementedInEditor(let s): return "NOT_IMPLEMENTED_IN_EDITOR: \(s)."
        case .ioError(let s): return "Error de documento: \(s)."
        }
    }
}

public enum EditorEffect: Equatable, Sendable {
    case found(NSRange)
    case selected(NSRange)
    case deleted(range: NSRange, text: String)
    case replaced(range: NSRange, old: String, new: String)
    case formatted(style: TextFormatStyle, range: NSRange)
    case undone(label: String)
    case redone(label: String)
    case titleChanged(old: String, new: String)
    case saved(URL)
    case opened(name: String, url: URL?)
    case exported(VoiceExportFormat, URL)
}

public enum EditorCommandResult: Equatable, Sendable {
    case success(EditorEffect)
    case noMatch(String)
    case invalidContext(EditorCommandError)
    case cancelled
    case simulated(SimulatedRewriteRequest)
    case failure(EditorCommandError)
}

public struct SimulatedRewriteRequest: Equatable, Sendable {
    public let selectedText: String
    public let instruction: String
    public let range: NSRange
    public let documentRevision: Int
}

// MARK: - Rangos Unicode (nunca 1 Character == 1 UTF-16 unit)

public enum UnicodeRanges {
    /// Valida un NSRange (unidades UTF-16) contra el texto. Rechaza rangos
    /// fuera de límites y rangos que partirían un grafema compuesto
    /// (acentos, emoji ZWJ, ñ, japonés). Devuelve nil si es inválido.
    public static func validated(_ range: NSRange, in text: String) -> Range<String.Index>? {
        guard range.location >= 0, range.length >= 0,
              range.location <= text.utf16.count,
              range.length <= text.utf16.count - range.location else { return nil }
        guard let swiftRange = Range(range, in: text) else { return nil }
        // Range(NSRange,in:) ya devuelve nil si parte un Character, pero se
        // verifica explícitamente por seguridad (doble barrera).
        let lowerOK = swiftRange.lowerBound == text.endIndex || text.indices.contains(swiftRange.lowerBound)
        let upperOK = swiftRange.upperBound == text.endIndex || text.indices.contains(swiftRange.upperBound)
        guard lowerOK && upperOK else { return nil }
        return swiftRange
    }

    public static func clampCursor(_ range: NSRange, in text: String) -> NSRange {
        let loc = max(0, min(range.location, text.utf16.count))
        return NSRange(location: loc, length: 0)
    }
}

// MARK: - Snapshot / versioning de proposal

/// Captura mínima para detectar cambios entre proposal y confirmación.
public struct EditorProposalSnapshot: Equatable, Sendable {
    public let selectedRange: NSRange?
    public let selectedText: String?
    public let textFingerprint: Int
    public let title: String
    public let documentRevision: Int

    public init(selectedRange: NSRange?, selectedText: String?, text: String, title: String, documentRevision: Int) {
        self.selectedRange = selectedRange
        self.selectedText = selectedText
        var hasher = Hasher()
        hasher.combine(text)
        self.textFingerprint = hasher.finalize()
        self.title = title
        self.documentRevision = documentRevision
    }
}

// MARK: - Abstracción del editor (el sistema no depende de la UI)

/// Destino de comandos sobre el editor real. Todo @MainActor.
@MainActor public protocol EditorCommandTarget: AnyObject {
    var currentText: String { get }
    var selectedNSRange: NSRange { get }
    var selectedText: String? { get }
    var hasSelection: Bool { get }
    var canUndo: Bool { get }
    var canRedo: Bool { get }
    var undoActionLabel: String? { get }
    var redoActionLabel: String? { get }
    var documentTitle: String { get }
    var documentRevision: Int { get }
    var simulatedRewrites: [SimulatedRewriteRequest] { get }

    func snapshot() -> EditorProposalSnapshot
    func findText(_ query: String) -> EditorCommandResult
    func selectText(_ query: String) -> EditorCommandResult
    func deleteSelection() -> EditorCommandResult
    func replaceSelection(with text: String) -> EditorCommandResult
    func formatSelection(_ style: TextFormatStyle) -> EditorCommandResult
    func renameTitle(to newTitle: String) -> EditorCommandResult
    func rewriteSelection(instruction: String) -> EditorCommandResult
    func undo() -> EditorCommandResult
    func redo() -> EditorCommandResult
    func save() -> EditorCommandResult
    func open(name: String?) -> EditorCommandResult
    func export(as format: VoiceExportFormat) -> EditorCommandResult
}

// MARK: - Almacén de documentos (solo temporales; nunca personales)

/// Guarda/abre/exporta únicamente dentro de un directorio base (tests usan
/// FileManager.temporaryDirectory). Fixtures, jamás archivos personales.
/// Todo el acceso ocurre en @MainActor (las vistas AppKit lo exigen).
@MainActor public final class VoiceDocumentStore {
    public let baseDirectory: URL
    public var lastOpenedName: String?

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    private func isAllowed(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(baseDirectory.standardizedFileURL.path)
    }

    public func url(for name: String, extension ext: String) -> URL? {
        let safe = name.replacingOccurrences(of: "/", with: "_")
        let url = baseDirectory.appendingPathComponent(safe).appendingPathExtension(ext)
        return isAllowed(url) ? url : nil
    }

    public func write(text: String, name: String, extension ext: String) throws -> URL {
        guard let url = url(for: name, extension: ext) else { throw StoreError.outsideBase }
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }

    public func read(name: String, extension ext: String) throws -> (String, URL) {
        guard let url = url(for: name, extension: ext) else { throw StoreError.outsideBase }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw StoreError.invalidEncoding }
        return (text, url)
    }

    public enum StoreError: Error {
        case outsideBase
        case invalidEncoding
    }
}

// MARK: - Fixtures reales de texto

public enum VoiceFixtureText {
    /// Documento de prueba con acentos, ñ, emoji, japonés, cifras y TDAH.
    public static var real: String {
        """
        Texto normal en español.

        TDAH y accesibilidad cognitiva.

        Metodología de evaluación.

        María-José Pérez.

        IHC 2026.

        7.5%.

        Emoji: 🧠

        Texto con acentos:
        interacción, evaluación, metodología.

        Texto japonés:
        ユーザーインターフェース
        """
    }

    /// Variante con duplicados para probar la regla determinista de selección.
    public static var withDuplicates: String {
        real + "\n\nMetodología repetida para TDAH y TDAH otra vez.\n"
    }
}

// MARK: - Adaptador real sobre NSTextView

/// Implementación de EditorCommandTarget sobre el NSTextView real del editor
/// (TextKit 2). Usa rangos NSRange nativos, UndoManager real y selección real.
/// NO reconstruye selección a partir de Strings.
@MainActor public final class RealEditorTarget: EditorCommandTarget {
    private weak var view: NSTextView?
    public var documentTitle: String
    public var onTitleChange: ((String) -> Void)?
    public private(set) var documentRevision: Int = 0
    public private(set) var simulatedRewrites: [SimulatedRewriteRequest] = []
    public private(set) var lastFindQuery: String?
    private let store: VoiceDocumentStore
    private var documentName: String

    public init(view: NSTextView, title: String = "Proyecto",
                store: VoiceDocumentStore, documentName: String = "fixture") {
        self.view = view
        self.documentTitle = title
        self.store = store
        self.documentName = documentName
    }

    private var textView: NSTextView? { view }

    public var currentText: String { textView?.string ?? "" }

    public var selectedNSRange: NSRange { textView?.selectedRange() ?? NSRange(location: 0, length: 0) }

    public var selectedText: String? {
        let r = selectedNSRange
        guard r.length > 0 else { return nil }
        let text = currentText
        guard let swiftRange = UnicodeRanges.validated(r, in: text) else { return nil }
        return String(text[swiftRange])
    }

    public var hasSelection: Bool { selectedNSRange.length > 0 && selectedText != nil }

    public var canUndo: Bool { textView?.undoManager?.canUndo ?? false }
    public var canRedo: Bool { textView?.undoManager?.canRedo ?? false }

    public var undoActionLabel: String? {
        guard canUndo else { return nil }
        let name = textView?.undoManager?.undoActionName ?? ""
        return name.isEmpty ? nil : name
    }

    public var redoActionLabel: String? {
        guard canRedo else { return nil }
        let name = textView?.undoManager?.redoActionName ?? ""
        return name.isEmpty ? nil : name
    }

    public func snapshot() -> EditorProposalSnapshot {
        let r = selectedNSRange
        let text = currentText
        let valid: NSRange? = (r.length > 0 && UnicodeRanges.validated(r, in: text) != nil) ? r : (r.length == 0 ? r : nil)
        return EditorProposalSnapshot(
            selectedRange: valid,
            selectedText: selectedText,
            text: text,
            title: documentTitle,
            documentRevision: documentRevision
        )
    }

    // MARK: Búsqueda (navegación; no muta contenido)

    private func searchRange(for query: String) -> NSRange? {
        guard !query.isEmpty else { return nil }
        let text = currentText
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        // 1. Literal exacto.
        if let r = firstValidMatch(of: query, in: text, options: [], afterCursor: true) { return r }
        // 2. Normalizado (insensible a mayúsculas y acentos). Sin fuzzy.
        if let r = firstValidMatch(of: query, in: text,
                                   options: [.caseInsensitive, .diacriticInsensitive],
                                   afterCursor: true) { return r }
        _ = full
        return nil
    }

    /// Primera coincidencia válida en o después del cursor; si no hay,
    /// envuelve a la primera del documento. Solo devuelve rangos que no
    /// parten grafemas.
    private func firstValidMatch(of query: String, in text: String,
                                 options: NSString.CompareOptions, afterCursor: Bool) -> NSRange? {
        let ns = text as NSString
        let cursor = UnicodeRanges.clampCursor(selectedNSRange, in: text).location
        var candidates: [NSRange] = []
        var search = NSRange(location: 0, length: ns.length)
        while search.location < ns.length {
            let found = ns.range(of: query, options: options, range: search)
            guard found.location != NSNotFound else { break }
            if UnicodeRanges.validated(found, in: text) != nil { candidates.append(found) }
            let next = found.location + max(found.length, 1)
            if next >= ns.length { break }
            search = NSRange(location: next, length: ns.length - next)
        }
        guard !candidates.isEmpty else { return nil }
        if afterCursor, let after = candidates.first(where: { $0.location >= cursor }) { return after }
        return candidates.first
    }

    public func findText(_ query: String) -> EditorCommandResult {
        guard let match = searchRange(for: query) else { return .noMatch(query) }
        textView?.setSelectedRange(match)
        textView?.scrollRangeToVisible(match)
        lastFindQuery = query
        return .success(.found(match))
    }

    public func selectText(_ query: String) -> EditorCommandResult {
        guard let match = searchRange(for: query) else { return .noMatch(query) }
        textView?.setSelectedRange(match)
        textView?.scrollRangeToVisible(match)
        return .success(.selected(match))
    }

    // MARK: Mutaciones (una sola operación de Undo cada una)

    private func groupedMutation(_ body: () -> Void) {
        guard let view = textView else { return }
        view.breakUndoCoalescing()
        view.undoManager?.beginUndoGrouping()
        body()
        view.undoManager?.endUndoGrouping()
        view.breakUndoCoalescing()
        documentRevision += 1
    }

    public func deleteSelection() -> EditorCommandResult {
        let sel = selectedNSRange
        guard hasSelection, let swiftRange = UnicodeRanges.validated(sel, in: currentText) else {
            return .invalidContext(.noSelection)
        }
        let removed = String(currentText[swiftRange])
        groupedMutation { [weak self] in
            self?.textView?.insertText("", replacementRange: sel)
        }
        textView?.window?.makeFirstResponder(textView)
        return .success(.deleted(range: NSRange(location: sel.location, length: 0), text: removed))
    }

    public func replaceSelection(with text: String) -> EditorCommandResult {
        let sel = selectedNSRange
        guard hasSelection, let swiftRange = UnicodeRanges.validated(sel, in: currentText) else {
            return .invalidContext(.noSelection)
        }
        let old = String(currentText[swiftRange])
        groupedMutation { [weak self] in
            self?.textView?.insertText(text, replacementRange: sel)
        }
        textView?.window?.makeFirstResponder(textView)
        return .success(.replaced(range: NSRange(location: sel.location, length: (text as NSString).length), old: old, new: text))
    }

    public func formatSelection(_ style: TextFormatStyle) -> EditorCommandResult {
        let sel = selectedNSRange
        guard hasSelection, let swiftRange = UnicodeRanges.validated(sel, in: currentText) else {
            return .invalidContext(.noSelection)
        }
        let selected = String(currentText[swiftRange])
        let (replacement, target, fullRange): (String, NSRange, NSRange) = formatReplacement(
            selected: selected, range: sel, fullText: currentText as NSString, style: style)
        groupedMutation { [weak self] in
            self?.textView?.insertText(replacement, replacementRange: fullRange)
            self?.textView?.setSelectedRange(target)
        }
        textView?.window?.makeFirstResponder(textView)
        return .success(.formatted(style: style, range: target))
    }

    private func formatReplacement(selected: String, range: NSRange, fullText: NSString,
                                   style: TextFormatStyle) -> (String, NSRange, NSRange) {
        let marker: String
        switch style {
        case .bold: marker = "**"
        case .italic: marker = "*"
        case .underline: marker = "<u>"
        }
        let closer: String = (style == .underline) ? "</u>" : marker
        let width = (marker as NSString).length
        let closeWidth = (closer as NSString).length
        // Si ya está envuelto por fuera (toggle como EditorSession), desenvolver.
        if range.location >= width && NSMaxRange(range) + closeWidth <= fullText.length,
           fullText.substring(with: NSRange(location: range.location - width, length: width)) == marker,
           fullText.substring(with: NSRange(location: NSMaxRange(range), length: closeWidth)) == closer {
            let outer = NSRange(location: range.location - width, length: range.length + width + closeWidth)
            let target = NSRange(location: range.location - width, length: range.length)
            return (selected, target, outer)
        }
        if selected.hasPrefix(marker) && selected.hasSuffix(closer) && selected.count >= marker.count + closer.count {
            let inner = String(selected.dropFirst(marker.count).dropLast(closer.count))
            return (inner, NSRange(location: range.location, length: (inner as NSString).length), range)
        }
        let replacement = marker + selected + closer
        let target = NSRange(location: range.location + width, length: range.length)
        return (replacement, target, range)
    }

    public func renameTitle(to newTitle: String) -> EditorCommandResult {
        let old = documentTitle
        let undo = textView?.undoManager
        undo?.beginUndoGrouping()
        documentTitle = newTitle
        onTitleChange?(newTitle)
        undo?.registerUndo(withTarget: self, handler: { target in
            target.applyTitleUndo(newTitle, old: old)
        })
        undo?.setActionName("Renombrar título")
        undo?.endUndoGrouping()
        documentRevision += 1
        return .success(.titleChanged(old: old, new: newTitle))
    }

    private func applyTitleUndo(_ current: String, old: String) {
        documentTitle = old
        onTitleChange?(old)
        textView?.undoManager?.registerUndo(withTarget: self, handler: { target in
            target.applyTitleUndo(old, old: current)
        })
        textView?.undoManager?.setActionName("Renombrar título")
        documentRevision += 1
    }

    public func rewriteSelection(instruction: String) -> EditorCommandResult {
        guard hasSelection else { return .invalidContext(.noSelection) }
        let req = SimulatedRewriteRequest(
            selectedText: selectedText ?? "",
            instruction: instruction,
            range: selectedNSRange,
            documentRevision: documentRevision
        )
        // SIMULATED_REWRITE_REQUEST: se registra, el documento NO cambia y el
        // UndoManager NO se toca (Fase 12 hará la transformación real).
        simulatedRewrites.append(req)
        return .simulated(req)
    }

    public func undo() -> EditorCommandResult {
        guard canUndo else { return .invalidContext(.cannotUndo) }
        let label = undoActionLabel ?? "último cambio"
        textView?.undoManager?.undo()
        documentRevision += 1
        return .success(.undone(label: label))
    }

    public func redo() -> EditorCommandResult {
        guard canRedo else { return .invalidContext(.cannotRedo) }
        let label = redoActionLabel ?? "último cambio"
        textView?.undoManager?.redo()
        documentRevision += 1
        return .success(.redone(label: label))
    }

    public func save() -> EditorCommandResult {
        guard let view = textView else { return .failure(.ioError("sin vista")) }
        do {
            let url = try store.write(text: view.string, name: documentName, extension: "md")
            store.lastOpenedName = documentName
            return .success(.saved(url))
        } catch {
            return .failure(.ioError("guardado: \(error)"))
        }
    }

    public func open(name: String?) -> EditorCommandResult {
        let key = (name?.isEmpty == false ? name! : nil) ?? store.lastOpenedName ?? documentName
        do {
            let (loaded, url) = try store.read(name: key, extension: "md")
            groupedMutation { [weak self] in
                self?.textView?.selectAll(nil)
                if let sel = self?.textView?.selectedRange() {
                    self?.textView?.insertText(loaded, replacementRange: sel)
                }
            }
            documentName = key
            store.lastOpenedName = key
            textView?.window?.makeFirstResponder(textView)
            return .success(.opened(name: key, url: url))
        } catch {
            return .failure(.ioError("apertura: \(error)"))
        }
    }

    public func export(as format: VoiceExportFormat) -> EditorCommandResult {
        guard let view = textView else { return .failure(.ioError("sin vista")) }
        switch format {
        case .plainText:
            do {
                let url = try store.write(text: view.string, name: documentName, extension: "txt")
                return .success(.exported(format, url))
            } catch {
                return .failure(.ioError("exportación txt: \(error)"))
            }
        case .richText:
            do {
                let storage = view.textStorage ?? NSTextStorage(string: view.string)
                let full = NSRange(location: 0, length: storage.length)
                guard let data = storage.rtf(from: full, documentAttributes: [:]) else {
                    return .failure(.ioError("exportación rtf: sin datos"))
                }
                let url = store.url(for: documentName, extension: "rtf")!
                try data.write(to: url, options: .atomic)
                return .success(.exported(format, url))
            } catch {
                return .failure(.ioError("exportación rtf: \(error)"))
            }
        case .pdf:
            guard let url = store.url(for: documentName, extension: "pdf") else {
                return .failure(.ioError("exportación pdf: ruta"))
            }
            // PDF sin modal: misma renderización que PrintDocument, guardada
            // directo al almacén temporal (jobSavingURL).
            let source = "# \(documentTitle)\n\n" + view.string
            let rendered = MarkdownAppearance.readingText(
                source, document: MarkdownDocument(source),
                style: WritingStyle(size: 12, family: "serif", spacing: 4),
                forPrint: true, documentURL: nil)
            let info = NSPrintInfo()
            info.topMargin = 48
            info.bottomMargin = 48
            info.leftMargin = 54
            info.rightMargin = 54
            info.horizontalPagination = .fit
            info.verticalPagination = .automatic
            let width = info.paperSize.width - info.leftMargin - info.rightMargin
            let printView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
            printView.textStorage?.setAttributedString(rendered)
            printView.sizeToFit()
            let operation = NSPrintOperation(view: printView, printInfo: info)
            operation.jobTitle = documentTitle
            operation.showsPrintPanel = false
            operation.showsProgressPanel = false
            operation.printInfo.jobDisposition = .save
            operation.printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
            return operation.run()
                ? .success(.exported(format, url))
                : .failure(.ioError("exportación pdf: cancelada"))
        case .word:
            do {
                let attr = NSAttributedString(string: view.string)
                let data = try attr.data(
                    from: NSRange(location: 0, length: attr.length),
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
                guard let url = store.url(for: documentName, extension: "docx") else {
                    return .failure(.ioError("exportación word: ruta"))
                }
                try data.write(to: url, options: .atomic)
                return .success(.exported(format, url))
            } catch {
                return .failure(.ioError("exportación word: \(error)"))
            }
        }
    }
}

// MARK: - Preview real (desde el estado actual del editor, no del transcript)

public enum VoicePreview {
    public static func styleName(_ s: TextFormatStyle) -> String {
        switch s { case .bold: return "negritas"; case .italic: return "cursiva"; case .underline: return "subrayado" }
    }

    public static func exportName(_ f: VoiceExportFormat) -> String {
        switch f {
        case .pdf: return "PDF"; case .word: return "Word"
        case .plainText: return "texto plano"; case .richText: return "texto enriquecido"
        }
    }

    /// C20: undo/redo inequívocos (↶ vs ↷ + etiqueta de UndoManager si existe).
    public static func undoPreview(label: String?) -> String {
        if let label, !label.isEmpty { return "↶ Deshacer: \(label)" }
        return "↶ Deshacer último cambio"
    }

    public static func redoPreview(label: String?) -> String {
        if let label, !label.isEmpty { return "↷ Rehacer: \(label)" }
        return "↷ Rehacer último cambio"
    }

    @MainActor public static func description(for cmd: VoiceCommand, in target: any EditorCommandTarget) -> String {
        switch cmd {
        case .renameTitle(let a): return "Cambiar título:\n\"\(target.documentTitle)\"\n→\n\"\(a)\""
        case .deleteSelection: return "Eliminar:\n\"\(target.selectedText ?? "")\""
        case .replaceSelection(let a): return "Reemplazar:\n\"\(target.selectedText ?? "")\"\n→\n\"\(a)\""
        case .rewriteSelection(let a):
            return "Reescribir selección\nInstrucción:\n\"\(a)\"\nTexto:\n\"\(target.selectedText ?? "")\""
        case .formatSelection(let s): return "Aplicar \(styleName(s)) a:\n\"\(target.selectedText ?? "")\""
        case .undo: return undoPreview(label: target.undoActionLabel)
        case .redo: return redoPreview(label: target.redoActionLabel)
        case .selectText(let a): return "Seleccionar:\n\"\(a)\""
        case .findText(let a): return "Buscar:\n\"\(a)\""
        case .saveDocument: return "Guardar documento \"\(target.documentTitle)\""
        case .openDocument(let a): return "Abrir:\n\"\(a ?? "Último documento")\""
        case .exportDocument(let f): return "Exportar como \(exportName(f))"
        case .unsupported: return "Ese comando no está disponible."
        case .unknown: return "No entendí el comando."
        case .multipleActions: return "Prueba una acción a la vez."
        }
    }
}

// MARK: - Executor (solo ejecuta acciones ya validadas; no reconoce ni parsea)

public struct VoiceProposal: Equatable, Sendable {
    public let id: Int
    public let command: VoiceCommand
    public let preview: String
    public let snapshot: EditorProposalSnapshot
}

public enum ProposalOutcome: Equatable, Sendable {
    case executed(EditorCommandResult)
    case needsConfirm(VoiceProposal)
    case invalid(EditorCommandError)
    case rejected(EditorCommandError)
}

/// Parse → validate → preview → (Enter) → REVALIDATE → execute.
/// Executor + sesión de confirmación sobre el editor real.
@MainActor public final class EditorCommandExecutor {
    private let target: any EditorCommandTarget
    private var nextID = 0
    public private(set) var pending: VoiceProposal?
    public private(set) var attempts = 0
    public private(set) var autoLog: [EditorEffect] = []

    public init(target: any EditorCommandTarget) {
        self.target = target
    }

    // MARK: Validación de contexto (antes de cualquier proposal ejecutable)

    private func contextError(for cmd: VoiceCommand) -> EditorCommandError? {
        switch cmd {
        case .deleteSelection, .replaceSelection, .rewriteSelection, .formatSelection:
            return target.hasSelection ? nil : .noSelection
        case .undo: return target.canUndo ? nil : .cannotUndo
        case .redo: return target.canRedo ? nil : .cannotRedo
        default: return nil
        }
    }

    /// Recibe un comando ya parseado. Navegación → inmediata (vía Validator +
    /// editor real). Mutación → proposal con preview + snapshot (0 mutación).
    @discardableResult
    public func receive(_ cmd: VoiceCommand) -> ProposalOutcome {
        attempts += 1
        switch cmd {
        case .unsupported(let s): return .rejected(.unsupportedCommand(s))
        case .unknown: return .rejected(.unsupportedCommand("unknown"))
        case .multipleActions: return .rejected(.unsupportedCommand("multipleActions"))
        default: break
        }
        if let err = contextError(for: cmd) { return .invalid(err) }
        if voicePolicyForCommand(cmd) == .immediate {
            let result = execute(cmd)
            if case .success(let effect) = result { autoLog.append(effect) }
            return .executed(result)
        }
        nextID += 1
        let proposal = VoiceProposal(
            id: nextID,
            command: cmd,
            preview: VoicePreview.description(for: cmd, in: target),
            snapshot: target.snapshot()
        )
        pending = proposal
        return .needsConfirm(proposal)
    }

    /// Enter: único camino con efecto para mutaciones. Revalida contexto y
    /// snapshot; si el estado cambió → STALE_PROPOSAL, 0 mutación.
    public func confirm(_ proposal: VoiceProposal) -> EditorCommandResult {
        guard pending == proposal else { return .failure(.staleProposal) }
        if let err = contextError(for: proposal.command) {
            pending = nil
            return .invalidContext(err)
        }
        if target.snapshot() != proposal.snapshot {
            pending = nil
            return .failure(.staleProposal)
        }
        pending = nil
        return execute(proposal.command)
    }

    /// Enter sobre el pending actual (atajo de UI).
    public func confirmPending() -> EditorCommandResult {
        guard let proposal = pending else { return .failure(.staleProposal) }
        return confirm(proposal)
    }

    /// Esc: sin cambios.
    public func cancel() {
        pending = nil
    }

    /// R: descarta proposal, nueva captura. Sin combinar.
    public func requestRepeat() {
        pending = nil
        attempts += 1
    }

    // Ejecución directa (asume validación + snapshot vigentes).
    private func execute(_ cmd: VoiceCommand) -> EditorCommandResult {
        switch cmd {
        case .findText(let q): return target.findText(q)
        case .selectText(let q): return target.selectText(q)
        case .deleteSelection: return target.deleteSelection()
        case .replaceSelection(let t): return target.replaceSelection(with: t)
        case .formatSelection(let s): return target.formatSelection(s)
        case .renameTitle(let t): return target.renameTitle(to: t)
        case .rewriteSelection(let i): return target.rewriteSelection(instruction: i)
        case .undo: return target.undo()
        case .redo: return target.redo()
        case .saveDocument: return target.save()
        case .openDocument(let n): return target.open(name: n)
        case .exportDocument(let f): return target.export(as: f)
        case .unsupported(let s): return .failure(.unsupportedCommand(s))
        case .unknown: return .failure(.unsupportedCommand("unknown"))
        case .multipleActions: return .failure(.unsupportedCommand("multipleActions"))
        }
    }
}

// MARK: - Modo de prueba real-editor-command-test (harness, sin UI final)

/// Runner de integración para operar el editor real por voz simulada:
/// abrir fixture → modo comando → proposal → Enter/Esc/R → observar efecto.
/// Sin UI final; suficiente para proposal/confirm/cancel/repeat/feedback.
@MainActor public final class RealEditorCommandTestHarness {
    public struct Step: Sendable {
        public let transcript: String
        public let command: VoiceCommand
        public let outcome: String
        public let stateAfter: String
    }

    public let target: RealEditorTarget
    public let executor: EditorCommandExecutor
    public private(set) var steps: [Step] = []

    public init(fixtureText: String = VoiceFixtureText.real, title: String = "Proyecto",
                store: VoiceDocumentStore, view: NSTextView) {
        view.string = fixtureText
        self.target = RealEditorTarget(view: view, title: title, store: store)
        self.executor = EditorCommandExecutor(target: target)
    }

    public func transcriptState() -> String {
        "title=\(target.documentTitle) text=\(target.currentText.count)ch sel=\(target.selectedNSRange) rev=\(target.documentRevision)"
    }

    @discardableResult
    public func run(_ transcript: String, _ cmd: VoiceCommand, decision: String = "enter") -> Step {
        let outcome = executor.receive(cmd)
        let desc: String
        switch outcome {
        case .executed(let r): desc = "immediate:\(r)"
        case .needsConfirm(let p):
            if decision == "enter" { desc = "confirm:\(executor.confirm(p))" }
            else if decision == "esc" { executor.cancel(); desc = "cancelled" }
            else { executor.requestRepeat(); desc = "repeat" }
        case .invalid(let e): desc = "invalid:\(e.message)"
        case .rejected(let e): desc = "rejected:\(e.message)"
        }
        let step = Step(transcript: transcript, command: cmd, outcome: desc, stateAfter: transcriptState())
        steps.append(step)
        return step
    }
}
