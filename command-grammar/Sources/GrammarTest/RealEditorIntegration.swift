import CommandGrammar

// Fase 11 — ParsedCommand → Validator → ConfirmationPolicy → EditorCommandExecutor → editor real.
//
//  Usa la gramática, tipos, riesgo y política CONGELADOS solo en lectura
//  (parseCommand, riskOf, policyForCommand). Nada de este archivo modifica
//  Speech, Grammar, Types, Validator ni Policy.
//
//  Pipeline obligatorio: parse → validate → preview → ENTER → REVALIDATE → execute.
//  Navegación (find/select) → inmediata vía Validator + editor real.
//  Todo lo que muta → CONFIRM + snapshot/stale (STALE_PROPOSAL, 0 mutación).
//  rewriteSelection → SIMULATED_REWRITE_REQUEST (Fase 12 hará lo generativo).
import Foundation
import AppKit

// MARK: - Resultado explícito (nunca Bool)

enum RealEditorError: Equatable {
    case noSelection
    case cannotUndo
    case cannotRedo
    case staleProposal
    case unsupportedCommand(String)
    case notImplementedInEditor(String)
    case ioError(String)
}

enum RealEditorEffect: Equatable {
    case found(NSRange)
    case selected(NSRange)
    case deleted(text: String)
    case replaced(old: String, new: String)
    case formatted(CommandGrammar.FormatStyle)
    case undone(label: String)
    case redone(label: String)
    case titleChanged(old: String, new: String)
    case saved(URL)
    case opened(name: String)
    case exported(ExportFormat, URL)
}

struct RealRewriteRequest: Equatable {
    let selectedText: String
    let instruction: String
    let range: NSRange
    let revision: Int
}

enum RealEditorResult: Equatable {
    case success(RealEditorEffect)
    case noMatch(String)
    case invalidContext(RealEditorError)
    case simulated(RealRewriteRequest)
    case failure(RealEditorError)
}

// MARK: - Rangos Unicode (1 Character != 1 UTF-16 unit)

enum RealRanges {
    static func validated(_ range: NSRange, in text: String) -> Range<String.Index>? {
        guard range.location >= 0, range.length >= 0,
              range.location <= text.utf16.count,
              range.length <= text.utf16.count - range.location else { return nil }
        guard let r = Range(range, in: text) else { return nil }
        let loOK = r.lowerBound == text.endIndex || text.indices.contains(r.lowerBound)
        let hiOK = r.upperBound == text.endIndex || text.indices.contains(r.upperBound)
        return (loOK && hiOK) ? r : nil
    }
}

// MARK: - Snapshot

struct RealSnapshot: Equatable {
    let selectedRange: NSRange?
    let selectedText: String?
    let fingerprint: Int
    let title: String
    let revision: Int
}

// MARK: - Fixture real

enum RealFixtureText {
    static var real: String {
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
    static var duplicates: String { real + "\n\nMetodología repetida para TDAH y TDAH otra vez.\n" }
}

// MARK: - Target real (NSTextView + UndoManager real + temporales)

@MainActor final class RealEditorTarget {
    private weak var view: NSTextView?
    var title: String
    var revision = 0
    var simulated: [RealRewriteRequest] = []
    var lastFind: String?
    let base: URL
    var docName: String
    var lastOpened: String?

    init(view: NSTextView, title: String = "Proyecto", base: URL, docName: String = "fixture") {
        self.view = view
        self.title = title
        self.base = base
        self.docName = docName
    }

    var text: String { view?.string ?? "" }
    var sel: NSRange { view?.selectedRange() ?? NSRange(location: 0, length: 0) }
    var selectedText: String? {
        let r = sel
        guard r.length > 0, let sr = RealRanges.validated(r, in: text) else { return nil }
        return String(text[sr])
    }
    var hasSelection: Bool { selectedText != nil }
    var canUndo: Bool { view?.undoManager?.canUndo ?? false }
    var canRedo: Bool { view?.undoManager?.canRedo ?? false }
    var undoLabel: String? {
        guard canUndo else { return nil }
        let n = view?.undoManager?.undoActionName ?? ""
        return n.isEmpty ? nil : n
    }
    var redoLabel: String? {
        guard canRedo else { return nil }
        let n = view?.undoManager?.redoActionName ?? ""
        return n.isEmpty ? nil : n
    }

    func snapshot() -> RealSnapshot {
        let r = sel
        let valid: NSRange? = r.length == 0 ? r : (RealRanges.validated(r, in: text) != nil ? r : nil)
        var h = Hasher(); h.combine(text)
        return RealSnapshot(selectedRange: valid, selectedText: selectedText,
                            fingerprint: h.finalize(), title: title, revision: revision)
    }

    // Búsqueda: literal exacto, luego normalizada. Sin fuzzy.
    // Duplicados: primera coincidencia en/después del cursor, con wrap.
    func search(_ query: String) -> NSRange? {
        guard !query.isEmpty else { return nil }
        if let r = allMatches(query, options: []) { return r }
        return allMatches(query, options: [.caseInsensitive, .diacriticInsensitive])
    }

    private func allMatches(_ query: String, options: NSString.CompareOptions) -> NSRange? {
        let t = text
        let ns = t as NSString
        var found: [NSRange] = []
        var at = NSRange(location: 0, length: ns.length)
        while at.location < ns.length {
            let r = ns.range(of: query, options: options, range: at)
            guard r.location != NSNotFound else { break }
            if RealRanges.validated(r, in: t) != nil { found.append(r) }
            let nx = r.location + max(r.length, 1)
            if nx >= ns.length { break }
            at = NSRange(location: nx, length: ns.length - nx)
        }
        guard !found.isEmpty else { return nil }
        let cursor = max(0, min(sel.location, (text as NSString).length))
        return found.first(where: { $0.location >= cursor }) ?? found.first
    }

    func findText(_ q: String) -> RealEditorResult {
        guard let m = search(q) else { return .noMatch(q) }
        view?.setSelectedRange(m)
        view?.scrollRangeToVisible(m)
        lastFind = q
        return .success(.found(m))
    }

    func selectText(_ q: String) -> RealEditorResult {
        guard let m = search(q) else { return .noMatch(q) }
        view?.setSelectedRange(m)
        view?.scrollRangeToVisible(m)
        return .success(.selected(m))
    }

    private func grouped(_ body: () -> Void) {
        guard let v = view else { return }
        v.breakUndoCoalescing()
        v.undoManager?.beginUndoGrouping()
        body()
        v.undoManager?.endUndoGrouping()
        v.breakUndoCoalescing()
        revision += 1
    }

    func deleteSelection() -> RealEditorResult {
        let s = sel
        guard hasSelection, let sr = RealRanges.validated(s, in: text) else {
            return .invalidContext(.noSelection)
        }
        let removed = String(text[sr])
        grouped { [weak self] in self?.view?.insertText("", replacementRange: s) }
        return .success(.deleted(text: removed))
    }

    func replaceSelection(with t: String) -> RealEditorResult {
        let s = sel
        guard hasSelection, let sr = RealRanges.validated(s, in: text) else {
            return .invalidContext(.noSelection)
        }
        let old = String(text[sr])
        grouped { [weak self] in self?.view?.insertText(t, replacementRange: s) }
        return .success(.replaced(old: old, new: t))
    }

    func formatSelection(_ style: CommandGrammar.FormatStyle) -> RealEditorResult {
        let s = sel
        guard hasSelection, let sr = RealRanges.validated(s, in: text) else {
            return .invalidContext(.noSelection)
        }
        let selected = String(text[sr])
        let ns = text as NSString
        let marker: String
        switch style {
        case .bold: marker = "**"
        case .italic: marker = "*"
        case .underline: marker = "<u>"
        }
        let closer: String = (style == .underline) ? "</u>" : marker
        let w = (marker as NSString).length
        let cw = (closer as NSString).length
        let replacement: String
        let full: NSRange
        var target: NSRange
        if s.location >= w && NSMaxRange(s) + cw <= ns.length,
           ns.substring(with: NSRange(location: s.location - w, length: w)) == marker,
           ns.substring(with: NSRange(location: NSMaxRange(s), length: cw)) == closer {
            full = NSRange(location: s.location - w, length: s.length + w + cw)
            target = NSRange(location: s.location - w, length: s.length)
            replacement = selected
        } else if selected.hasPrefix(marker) && selected.hasSuffix(closer)
                    && selected.count >= marker.count + closer.count {
            let inner = String(selected.dropFirst(marker.count).dropLast(closer.count))
            full = s
            target = NSRange(location: s.location, length: (inner as NSString).length)
            replacement = inner
        } else {
            full = s
            target = NSRange(location: s.location + w, length: s.length)
            replacement = marker + selected + closer
        }
        grouped { [weak self] in
            self?.view?.insertText(replacement, replacementRange: full)
            self?.view?.setSelectedRange(target)
        }
        return .success(.formatted(style))
    }

    func renameTitle(to nt: String) -> RealEditorResult {
        let old = title
        let um = view?.undoManager
        um?.beginUndoGrouping()
        title = nt
        um?.registerUndo(withTarget: self, handler: { $0.undoTitle(to: old, redo: nt) })
        um?.setActionName("Renombrar título")
        um?.endUndoGrouping()
        revision += 1
        return .success(.titleChanged(old: old, new: nt))
    }

    private func undoTitle(to t: String, redo: String) {
        title = t
        view?.undoManager?.registerUndo(withTarget: self, handler: { $0.undoTitle(to: redo, redo: t) })
        view?.undoManager?.setActionName("Renombrar título")
        revision += 1
    }

    func rewriteSelection(instruction: String) -> RealEditorResult {
        guard hasSelection else { return .invalidContext(.noSelection) }
        let req = RealRewriteRequest(selectedText: selectedText ?? "", instruction: instruction,
                                     range: sel, revision: revision)
        simulated.append(req) // SIMULATED_REWRITE_REQUEST; 0 mutación, 0 undo.
        return .simulated(req)
    }

    func undo() -> RealEditorResult {
        guard canUndo else { return .invalidContext(.cannotUndo) }
        let label = undoLabel ?? "último cambio"
        view?.undoManager?.undo()
        revision += 1
        return .success(.undone(label: label))
    }

    func redo() -> RealEditorResult {
        guard canRedo else { return .invalidContext(.cannotRedo) }
        let label = redoLabel ?? "último cambio"
        view?.undoManager?.redo()
        revision += 1
        return .success(.redone(label: label))
    }

    private func url(_ name: String, _ ext: String) -> URL? {
        let safe = name.replacingOccurrences(of: "/", with: "_")
        let u = base.appendingPathComponent(safe).appendingPathExtension(ext)
        return u.standardizedFileURL.path.hasPrefix(base.standardizedFileURL.path) ? u : nil
    }

    func save() -> RealEditorResult {
        guard let v = view, let u = url(docName, "md") else { return .failure(.ioError("save")) }
        do {
            try Data(v.string.utf8).write(to: u, options: .atomic)
            lastOpened = docName
            return .success(.saved(u))
        } catch { return .failure(.ioError("save: \(error)")) }
    }

    func open(name: String?) -> RealEditorResult {
        let key = (name?.isEmpty == false ? name! : nil) ?? lastOpened ?? docName
        guard let u = url(key, "md") else { return .failure(.ioError("open")) }
        do {
            let data = try Data(contentsOf: u)
            guard let loaded = String(data: data, encoding: .utf8) else {
                return .failure(.ioError("open encoding"))
            }
            grouped { [weak self] in
                self?.view?.selectAll(nil)
                if let s = self?.view?.selectedRange() {
                    self?.view?.insertText(loaded, replacementRange: s)
                }
            }
            docName = key
            lastOpened = key
            return .success(.opened(name: key))
        } catch { return .failure(.ioError("open: \(error)")) }
    }

    func export(as f: ExportFormat) -> RealEditorResult {
        guard let v = view else { return .failure(.ioError("sin vista")) }
        switch f {
        case .plainText:
            guard let u = url(docName, "txt") else { return .failure(.ioError("export")) }
            do {
                try Data(v.string.utf8).write(to: u, options: .atomic)
                return .success(.exported(f, u))
            } catch { return .failure(.ioError("export txt: \(error)")) }
        case .richText:
            let storage = v.textStorage ?? NSTextStorage(string: v.string)
            guard let data = storage.rtf(from: NSRange(location: 0, length: storage.length),
                                         documentAttributes: [:]),
                  let u = url(docName, "rtf") else {
                return .failure(.ioError("export rtf"))
            }
            do {
                try data.write(to: u, options: .atomic)
                return .success(.exported(f, u))
            } catch { return .failure(.ioError("export rtf: \(error)")) }
        case .pdf, .word:
            return .failure(.notImplementedInEditor("export \(f.rawValue)"))
        }
    }
}

// MARK: - Preview real + C20

enum RealPreview {
    static func undo(_ label: String?) -> String {
        if let l = label, !l.isEmpty { return "↶ Deshacer: \(l)" }
        return "↶ Deshacer último cambio"
    }
    static func redo(_ label: String?) -> String {
        if let l = label, !l.isEmpty { return "↷ Rehacer: \(l)" }
        return "↷ Rehacer último cambio"
    }

    @MainActor static func description(for cmd: ParsedCommand, in t: RealEditorTarget) -> String {
        switch cmd {
        case .renameTitle(let a): return "Cambiar título:\n\"\(t.title)\"\n→\n\"\(a)\""
        case .deleteSelection: return "Eliminar:\n\"\(t.selectedText ?? "")\""
        case .replaceSelection(let a): return "Reemplazar:\n\"\(t.selectedText ?? "")\"\n→\n\"\(a)\""
        case .rewriteSelection(let a):
            return "Reescribir selección\nInstrucción:\n\"\(a)\"\nTexto:\n\"\(t.selectedText ?? "")\""
        case .formatSelection(let s):
            let n: String
            switch s { case .bold: n = "negritas"; case .italic: n = "cursiva"; case .underline: n = "subrayado" }
            return "Aplicar \(n) a:\n\"\(t.selectedText ?? "")\""
        case .undo: return undo(t.undoLabel)
        case .redo: return redo(t.redoLabel)
        case .selectText(let a): return "Seleccionar:\n\"\(a)\""
        case .findText(let a): return "Buscar:\n\"\(a)\""
        case .saveDocument: return "Guardar documento \"\(t.title)\""
        case .openDocument(let a): return "Abrir:\n\"\(a ?? "Último documento")\""
        case .exportDocument(let f):
            let n: String
            switch f {
            case .pdf: n = "PDF"; case .word: n = "Word"
            case .plainText: n = "texto plano"; case .richText: n = "texto enriquecido"
            }
            return "Exportar como \(n)"
        case .unsupported: return "Ese comando no está disponible."
        case .unknown: return "No entendí el comando."
        case .multipleActions: return "Prueba una acción a la vez."
        }
    }
}

// MARK: - Executor: parse → validate → preview → ENTER → REVALIDATE → execute

struct RealProposal: Equatable {
    let id: Int
    let command: ParsedCommand
    let preview: String
    let snapshot: RealSnapshot
}

enum RealOutcome: Equatable {
    case autoExecuted(RealEditorResult)
    case needsConfirm(RealProposal)
    case invalid(String)
    case rejected(String)
}

@MainActor final class RealCommandExecutor {
    let target: RealEditorTarget
    private var nextID = 0
    var pending: RealProposal?
    var autoCount = 0

    init(target: RealEditorTarget) { self.target = target }

    private func contextError(for cmd: ParsedCommand) -> String? {
        switch cmd {
        case .deleteSelection, .replaceSelection, .rewriteSelection, .formatSelection:
            return target.hasSelection ? nil : "No hay texto seleccionado."
        case .undo: return target.canUndo ? nil : "Nada que deshacer."
        case .redo: return target.canRedo ? nil : "Nada que rehacer."
        default: return nil
        }
    }

    @discardableResult
    func receive(_ cmd: ParsedCommand) -> RealOutcome {
        switch cmd {
        case .unsupported(let s): return .rejected("unsupported: \(s)")
        case .unknown: return .rejected("unknown")
        case .multipleActions: return .rejected("multipleActions")
        default: break
        }
        if let reason = contextError(for: cmd) { return .invalid(reason) }
        if policyForCommand(cmd) == .immediate {
            let r = execute(cmd)
            autoCount += 1
            return .autoExecuted(r)
        }
        nextID += 1
        let p = RealProposal(id: nextID, command: cmd,
                             preview: RealPreview.description(for: cmd, in: target),
                             snapshot: target.snapshot())
        pending = p
        return .needsConfirm(p)
    }

    func confirm(_ p: RealProposal) -> RealEditorResult {
        guard pending == p else { return .failure(.staleProposal) }
        if contextError(for: p.command) != nil {
            pending = nil
            return .invalidContext(.noSelection)
        }
        if target.snapshot() != p.snapshot {
            pending = nil
            return .failure(.staleProposal)
        }
        pending = nil
        return execute(p.command)
    }

    func cancel() { pending = nil }

    private func execute(_ cmd: ParsedCommand) -> RealEditorResult {
        switch cmd {
        case .findText(let q): return target.findText(q)
        case .selectText(let q): return target.selectText(q)
        case .deleteSelection: return target.deleteSelection()
        case .replaceSelection(let t): return target.replaceSelection(with: t)
        case .rewriteSelection(let i): return target.rewriteSelection(instruction: i)
        case .formatSelection(let s): return target.formatSelection(s)
        case .renameTitle(let t): return target.renameTitle(to: t)
        case .undo: return target.undo()
        case .redo: return target.redo()
        case .saveDocument: return target.save()
        case .openDocument(let n): return target.open(name: n)
        case .exportDocument(let f): return target.export(as: f)
        case .unsupported(let s): return .failure(.unsupportedCommand(s))
        case .unknown: return .failure(.unsupportedCommand("unknown"))
        case .multipleActions: return .failure(.unsupportedCommand("multiple"))
        }
    }
}

// MARK: - Harness de prueba (real-editor-command-test)

@MainActor func makeRealProbe(text: String = RealFixtureText.real) -> (NSWindow, NSTextView, RealEditorTarget, RealCommandExecutor) {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let view = NSTextView(usingTextLayoutManager: true)
    view.isRichText = false
    view.allowsUndo = true
    window.contentView = view
    window.makeFirstResponder(view)
    view.undoManager?.groupsByEvent = false
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("real11-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    view.string = text
    view.breakUndoCoalescing()
    view.undoManager?.removeAllActions()
    let target = RealEditorTarget(view: view, base: dir)
    return (window, view, target, RealCommandExecutor(target: target))
}

@MainActor func probeSelect(_ view: NSTextView, _ q: String) {
    let ns = view.string as NSString
    let r = ns.range(of: q)
    if r.location != NSNotFound, RealRanges.validated(r, in: view.string) != nil {
        view.setSelectedRange(r)
    }
}
