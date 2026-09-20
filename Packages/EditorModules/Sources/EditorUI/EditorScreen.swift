import SwiftUI
import AppKit
import EditorCore
import EditorEngine
import DesignSystem
import ExportFeature

public struct EditorScreen: View {
    @Binding private var text: String
    private let title: String
    private let recentURLs: [URL]
    private let openFile: (URL) -> Void
    @State private var session = EditorSession()
    @State private var showSidebar = true
    @State private var showLibrary = false
    @State private var search = ""
    @State private var showReadingControls = false
    @State private var showStatistics = false
    @AppStorage("editor.fontSize") private var fontSize = 18.0
    @AppStorage("editor.fontFamily") private var family = "system"
    @AppStorage("editor.lineSpacing") private var spacing = 6.0
    @AppStorage("editor.readingWidth") private var width = 760.0
    @AppStorage("editor.syntax") private var syntax = true
    @AppStorage("editor.statistics") private var statistics = true
    @AppStorage("editor.appearance") private var appearance = "system"

    public init(text: Binding<String>, title: String, recentURLs: [URL], openFile: @escaping (URL) -> Void) {
        _text = text
        self.title = title
        self.recentURLs = recentURLs
        self.openFile = openFile
    }

    private var style: WritingStyle { WritingStyle(size: fontSize, family: family, spacing: spacing, syntax: syntax) }
    private var activeHeading: Int? { session.headings.last(where: { $0.offset <= session.cursorOffset })?.id }
    private var filteredHeadings: [DocumentHeading] { session.headings.filter { search.isEmpty || $0.title.localizedStandardContains(search) } }
    private var filteredURLs: [URL] { recentURLs.filter { search.isEmpty || $0.lastPathComponent.localizedStandardContains(search) } }

    public var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if showSidebar && !session.focusMode {
                    sidebar
                        .frame(width: EditorMetrics.sidebarWidth)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                        .padding(10)
                    if !showLibrary && geometry.size.width >= 1000 {
                        outline.frame(width: EditorMetrics.outlineWidth)
                        Divider()
                    }
                }
                ZStack {
                    writingCanvas
                        .opacity(showLibrary ? 0 : 1)
                        .accessibilityHidden(showLibrary)
                        .allowsHitTesting(!showLibrary)
                    if showLibrary { library }
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(minWidth: 720, minHeight: 480)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .focusedSceneValue(\.writingSession, session)
        .focusedSceneValue(\.writingTitle, title)
        .onChange(of: showLibrary) { _, showing in
            if showing { session.textView?.window?.makeFirstResponder(nil) }
            else { focusEditor() }
        }
        .onChange(of: session.readingMode) { _, reading in
            showLibrary = false
            if reading { session.textView?.window?.makeFirstResponder(nil) }
            else { focusEditor() }
        }
        .onChange(of: session.focusMode) { _, _ in showLibrary = false }
        .toolbar { toolbar }
    }

    private var writingCanvas: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 32, weight: .semibold)).lineLimit(2).textSelection(.enabled)
                    Spacer(minLength: 12)
                    if session.readingMode {
                        Button("Editar") { session.readingMode = false }.buttonStyle(.glass)
                    }
                }
                .padding(.horizontal, 32).padding(.top, session.focusMode ? 20 : 28).padding(.bottom, 8)
                ZStack(alignment: .topLeading) {
                    NativeTextEditor(text: $text, session: session, style: style)
                        .opacity(session.readingMode ? 0 : 1)
                        .allowsHitTesting(!session.readingMode)
                        .accessibilityHidden(session.readingMode)
                    if text.isEmpty && !session.readingMode {
                        Text("Escribe aquí…")
                            .font(.system(size: fontSize)).foregroundStyle(.tertiary)
                            .padding(.leading, 33).padding(.top, 25).allowsHitTesting(false)
                    }
                    if session.readingMode {
                        MarkdownReader(text: text, style: style)
                    }
                }
            }
            .frame(maxWidth: max(480, width))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if statistics && !session.focusMode { statusBar }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { showSidebar.toggle() } label: { Image(systemName: "sidebar.left") }
                .help("Mostrar u ocultar navegación").accessibilityLabel("Mostrar u ocultar navegación")
                .disabled(session.focusMode)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { NSDocumentController.shared.newDocument(nil) } label: { Image(systemName: "plus") }
                .help("Nuevo documento · ⌘N").accessibilityLabel("Nuevo documento")
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItemGroup(placement: .primaryAction) {
            Button { session.readingMode.toggle() } label: { Image(systemName: session.readingMode ? "square.and.pencil" : "book") }
                .help(session.readingMode ? "Volver a escribir · ⇧⌘R" : "Vista de lectura · ⇧⌘R")
                .accessibilityLabel(session.readingMode ? "Volver a escribir" : "Vista de lectura")
            Button { session.focusMode.toggle() } label: { Image(systemName: session.focusMode ? "eye.slash" : "eye") }
                .help(session.focusMode ? "Salir de concentración · ⇧⌘F" : "Concentración · ⇧⌘F")
                .accessibilityLabel(session.focusMode ? "Salir de concentración" : "Concentración")
            Button { showReadingControls.toggle() } label: { Image(systemName: "textformat.size") }
                .help("Lectura y concentración").accessibilityLabel("Lectura y concentración")
                .popover(isPresented: $showReadingControls, arrowEdge: .bottom) { readingControls }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(showLibrary ? "Buscar documento" : "Buscar sección", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Borrar búsqueda")
                }
            }.padding(10).background(.primary.opacity(0.04), in: Capsule())
            VStack(alignment: .leading, spacing: 5) {
                Text("General").font(.caption).foregroundStyle(.secondary).padding(.leading, 8).padding(.bottom, 4)
                navigationButton("Documento", symbol: "doc.text", selected: !showLibrary) { showLibrary = false }
                navigationButton("Recientes", symbol: "clock", selected: showLibrary) { showLibrary = true }
                navigationButton("Abrir archivo…", symbol: "folder", selected: false) { NSDocumentController.shared.openDocument(nil) }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("En este documento").font(.caption).foregroundStyle(.secondary)
                Label(title, systemImage: "doc.text").lineLimit(2).font(.callout)
                if !session.headings.isEmpty {
                    Menu("Ir a una sección") {
                        ForEach(session.headings) { heading in
                            Button(heading.title) { navigate(to: heading) }
                        }
                    }.menuStyle(.borderlessButton).font(.callout)
                }
            }.padding(.horizontal, 8)
            Spacer()
            SettingsLink { Label("Configuración", systemImage: "gearshape") }
                .buttonStyle(.plain).font(.callout).padding(.horizontal, 8)
        }
        .padding(12).padding(.top, 6).padding(.bottom, 8)

    }

    private func navigationButton(_ name: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(name)
            } icon: {
                Image(systemName: symbol).foregroundStyle(Color.accentColor)
            }
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).padding(.horizontal, 8)
                .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var outline: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Secciones")
                    Spacer()
                    Text("\(session.headings.count)").monospacedDigit()
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 14)
                if session.headings.isEmpty {
                    Text("Escribe # antes de un título para organizar el documento.")
                        .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 10)
                } else if filteredHeadings.isEmpty {
                    Text("No hay secciones con ese nombre.").font(.callout).foregroundStyle(.secondary).padding(.horizontal, 10)
                }
                ForEach(filteredHeadings) { heading in
                    Button { navigate(to: heading) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            RoundedRectangle(cornerRadius: 1).fill(activeHeading == heading.id ? Color.accentColor : .clear).frame(width: 2)
                            Text(heading.title.isEmpty ? "Sin título" : heading.title)
                                .font(.system(size: 14, weight: activeHeading == heading.id ? .semibold : .regular))
                                .foregroundStyle(activeHeading == heading.id ? .primary : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 10).padding(.trailing, 8).padding(.leading, CGFloat(max(0, heading.level - 1)) * 6)
                        .background(activeHeading == heading.id ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(activeHeading == heading.id ? [.isSelected] : [])
                }
            }.padding(.horizontal, 12).padding(.top, 22)
        }.background(Color(nsColor: .textBackgroundColor))
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Button { showStatistics.toggle() } label: {
                Text("\(session.statistics.words.formatted()) palabras").monospacedDigit()
            }.buttonStyle(.plain).popover(isPresented: $showStatistics) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Este documento").font(.headline)
                    LabeledContent("Palabras", value: session.statistics.words.formatted())
                    LabeledContent("Caracteres", value: session.statistics.characters.formatted())
                    LabeledContent("Párrafos", value: session.statistics.paragraphs.formatted())
                    LabeledContent("Lectura estimada", value: "\(session.statistics.readingMinutes) min")
                }.padding(20).frame(width: 260)
            }
            if session.selectedCharacters > 0 && !session.readingMode {
                Text("\(session.selectedCharacters) caracteres seleccionados")
            }
            Spacer()
            if session.paragraphFocus { Image(systemName: "paragraphsign").help("Foco de párrafo activo") }
            if session.typewriterMode { Image(systemName: "text.line.first.and.arrowtriangle.forward").help("Máquina de escribir activa") }
            Text(session.readingMode ? "Lectura" : "Markdown")
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 18).padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 24).padding(.bottom, 12)
    }

    private var readingControls: some View {
        @Bindable var settings = session
        return VStack(alignment: .leading, spacing: 18) {
            Text("Lectura y concentración").font(.headline)
            Picker("Tipografía", selection: $family) {
                Text("Sistema").tag("system")
                Text("Georgia").tag("serif")
                Text("Mono").tag("mono")
            }.pickerStyle(.segmented)
            HStack {
                Text("Tamaño del texto")
                Spacer()
                Button { fontSize = max(12, fontSize - 1) } label: { Image(systemName: "minus") }.accessibilityLabel("Reducir texto")
                Text("\(Int(fontSize))").monospacedDigit().frame(width: 26)
                Button { fontSize = min(32, fontSize + 1) } label: { Image(systemName: "plus") }.accessibilityLabel("Aumentar texto")
            }
            Picker("Ancho", selection: $width) {
                Text("Estrecho").tag(600.0)
                Text("Medio").tag(760.0)
                Text("Amplio").tag(920.0)
            }
            Divider()
            Toggle("Resaltar el párrafo actual", isOn: $settings.paragraphFocus)
            Toggle("Modo máquina de escribir", isOn: $settings.typewriterMode)
            Text("Mantiene el cursor a una altura estable mientras escribes.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Button("Imprimir o guardar PDF…") {
                showReadingControls = false
                PrintDocument.run(text: text, title: title, window: session.textView?.window)
            }
        }.padding(22).frame(width: 320)
    }

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Button { showLibrary = false } label: { Label("Volver al documento", systemImage: "chevron.left") }.buttonStyle(.glass)
                Text("Recientes").font(.largeTitle.weight(.semibold))
                if filteredURLs.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "Todavía no hay archivos recientes" : "Sin coincidencias", systemImage: search.isEmpty ? "doc" : "magnifyingglass", description: Text(search.isEmpty ? "Abre o guarda un documento para encontrarlo aquí." : "Prueba con otro nombre."))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240))], alignment: .leading, spacing: 20) {
                    ForEach(filteredURLs, id: \.self) { url in
                        Button { openFile(url) } label: {
                            VStack(alignment: .leading, spacing: 16) {
                                Image(systemName: "doc.text").font(.system(size: 28, weight: .light)).foregroundStyle(Color.accentColor)
                                Text(url.deletingPathExtension().lastPathComponent).font(.headline).lineLimit(3)
                                Spacer(minLength: 0)
                                Text(url.deletingLastPathComponent().lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .padding(20).frame(maxWidth: .infinity, alignment: .leading).frame(height: 145)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 22))
                            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.quaternary, lineWidth: 1))

                        }.buttonStyle(.plain).help(url.path)
                        .accessibilityLabel("Abrir \(url.deletingPathExtension().lastPathComponent)")
                    }
                }
            }.padding(32)
        }.background(Color(nsColor: .textBackgroundColor))
    }

    private func focusEditor() {
        guard !session.readingMode, let view = session.textView else { return }
        view.window?.makeFirstResponder(view)
    }

    private func navigate(to heading: DocumentHeading) {
        showLibrary = false
        session.readingMode = false
        session.send(.selectRange(TextRange(location: heading.offset, length: 0)))
    }
}
