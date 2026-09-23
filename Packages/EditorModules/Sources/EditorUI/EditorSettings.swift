import SwiftUI
import DesignSystem
import ModuleKit

public struct EditorSettings: View {
    private var modules: ModuleRegistry
    @AppStorage("editor.fontSize") private var fontSize = 18.0
    @AppStorage("editor.fontFamily") private var family = "system"
    @AppStorage("editor.fontWeight") private var fontWeight = "regular"
    @AppStorage("editor.lineSpacing") private var spacing = 6.0
    @AppStorage("editor.paragraphSpacing") private var paragraph = 0.0
    @AppStorage("editor.tracking") private var tracking = 0.0
    @AppStorage("editor.alignment") private var alignment = "natural"
    @AppStorage("editor.textColor") private var lightTextHex = "auto"
    @AppStorage("editor.backgroundColor") private var lightBackgroundHex = "auto"
    @AppStorage("editor.accentColor") private var lightAccentHex = "auto"
    @AppStorage("editor.textColorDark") private var darkTextHex = "auto"
    @AppStorage("editor.backgroundColorDark") private var darkBackgroundHex = "auto"
    @AppStorage("editor.accentColorDark") private var darkAccentHex = "auto"
    @AppStorage("editor.readingWidth") private var width = 760.0
    @AppStorage("editor.syntax") private var syntax = true
    @AppStorage("editor.statistics") private var statistics = true
    @AppStorage("editor.appearance") private var appearance = "system"
    @State private var fontSearch = ""
    @State private var editingScheme: ColorScheme = .light
    public init(modules: ModuleRegistry = ModuleRegistry()) {
        self.modules = modules
    }

    private var filteredSystemFonts: [String] {
        let all = WritingStyle.systemFontFamilies
        guard !fontSearch.trimmingCharacters(in: .whitespaces).isEmpty else { return all }
        return all.filter { $0.localizedStandardContains(fontSearch) }
    }

    private var editingText: Binding<String> {
        Binding(
            get: { editingScheme == .dark ? darkTextHex : lightTextHex },
            set: { if editingScheme == .dark { darkTextHex = $0 } else { lightTextHex = $0 } }
        )
    }

    private var editingBackground: Binding<String> {
        Binding(
            get: { editingScheme == .dark ? darkBackgroundHex : lightBackgroundHex },
            set: { if editingScheme == .dark { darkBackgroundHex = $0 } else { lightBackgroundHex = $0 } }
        )
    }

    private var editingAccent: Binding<String> {
        Binding(
            get: { editingScheme == .dark ? darkAccentHex : lightAccentHex },
            set: { if editingScheme == .dark { darkAccentHex = $0 } else { lightAccentHex = $0 } }
        )
    }

    private var activePresetID: String? {
        let current = editingScheme == .dark
            ? (darkTextHex, darkBackgroundHex, darkAccentHex)
            : (lightTextHex, lightBackgroundHex, lightAccentHex)
        return WritingStyle.themePresets.first {
            let preset = $0.hexes(for: editingScheme)
            return preset.text.caseInsensitiveCompare(current.0) == .orderedSame
            && preset.background.caseInsensitiveCompare(current.1) == .orderedSame
            && preset.accent.caseInsensitiveCompare(current.2) == .orderedSame
        }?.id
    }

    private var effectiveScheme: ColorScheme {
        if appearance == "dark" { return .dark }
        if appearance == "light" { return .light }
        return systemScheme
    }

    public var body: some View {
        TabView {
            Form {
                Section("Tema") {
                    HStack(spacing: 16) {
                        themeOption("Sistema", value: "system", scheme: nil)
                        themeOption("Claro", value: "light", scheme: .light)
                        themeOption("Oscuro", value: "dark", scheme: .dark)
                    }
                    .padding(.vertical, 12)
                }
                Section("Combinación de colores") {
                    Picker("Colores para", selection: $editingScheme) {
                        Text("Claro").tag(ColorScheme.light)
                        Text("Oscuro").tag(ColorScheme.dark)
                    }
                    .pickerStyle(.segmented)
                    Text(effectiveScheme == editingScheme
                         ? "Estás editando los colores que se ven ahora."
                         : "Estás editando los colores del otro modo. Cambia el Tema o el modo del Mac para verlos.")
                        .font(.caption).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                        ForEach(WritingStyle.themePresets) { preset in
                            themePresetButton(preset)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("Colores personalizados (\(editingScheme == .dark ? "modo oscuro" : "modo claro"))") {
                    ThemeColorRow(
                        title: "Texto",
                        subtitle: "Color de la letra en escritura y lectura",
                        hex: editingText,
                        defaultHex: editingScheme == .dark ? "#E6E6E6" : "#24211C"
                    )
                    ThemeColorRow(
                        title: "Fondo",
                        subtitle: "Fondo del lienzo de escritura",
                        hex: editingBackground,
                        defaultHex: editingScheme == .dark ? "#1E1E1E" : "#FAF7F0"
                    )
                    ThemeColorRow(
                        title: "Acento",
                        subtitle: "Cursor, enlaces y resaltado de párrafo",
                        hex: editingAccent,
                        defaultHex: editingScheme == .dark ? "#0A84FF" : "#8A6D3B"
                    )
                    Text("En «Automático» se usan los colores del sistema. Con Tema en Sistema, la app cambia entre tus colores claros y oscuros según el Mac.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Apariencia", systemImage: "circle.lefthalf.filled") }

            Form {
                Section("Fuente") {
                    Picker("Estilo rápido", selection: $family) {
                        Section("Estilos rápidos") {
                            ForEach(WritingStyle.availableFamilies, id: \.id) { option in
                                Text(option.name).tag(option.id)
                            }
                        }
                        Section("Fuentes del sistema") {
                            ForEach(WritingStyle.systemFontFamilies, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                    Picker("Grosor", selection: $fontWeight) {
                        ForEach(WritingStyle.availableWeights, id: \.id) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    HStack {
                        TextField("Buscar fuente del sistema…", text: $fontSearch)
                            .textFieldStyle(.roundedBorder)
                        if !fontSearch.isEmpty {
                            Button { fontSearch = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).accessibilityLabel("Borrar búsqueda de fuente")
                        }
                    }
                    Text("\(WritingStyle.systemFontFamilies.count) fuentes del sistema disponibles. Actual: \(WritingStyle.displayName(for: family))")
                        .font(.caption).foregroundStyle(.secondary)
                    // Vista previa con la fuente elegida.
                    Text("Agil zorro marrón 123 — AaBbCc")
                        .font(Font.custom(familyPreviewName, size: 15))
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    List(filteredSystemFonts.prefix(60), id: \.self) { name in
                        Button {
                            family = name
                        } label: {
                            HStack {
                                Text(name)
                                    .font(Font.custom(name, size: 14))
                                    .lineLimit(1)
                                Spacer()
                                if family == name {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(minHeight: 140, maxHeight: 180)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
                    if filteredSystemFonts.count > 60 {
                        Text("Mostrando 60 de \(filteredSystemFonts.count). Afina la búsqueda para ver más.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Tamaño y espaciado") {
                    Slider(value: $fontSize, in: 12...32, step: 1) { Text("Tamaño: \(Int(fontSize)) pt") }
                    Slider(value: $spacing, in: 0...14, step: 1) { Text("Interlineado adicional: \(Int(spacing)) pt") }
                    Slider(value: $paragraph, in: 0...16, step: 1) { Text("Espaciado entre párrafos: \(Int(paragraph)) pt") }
                    Slider(value: $tracking, in: -0.5...3, step: 0.1) { Text(String(format: "Espaciado entre letras: %.1f pt", tracking)) }
                    Picker("Alineación", selection: $alignment) {
                        ForEach(WritingStyle.availableAlignments, id: \.id) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    Picker("Ancho de lectura", selection: $width) {
                        Text("Estrecho").tag(600.0)
                        Text("Medio").tag(760.0)
                        Text("Amplio").tag(920.0)
                    }
                }
                Section("Presentación") {
                    Toggle("Dar formato a los títulos Markdown al escribir", isOn: $syntax)
                    Toggle("Mostrar estadísticas al pie", isOn: $statistics)
                }
                Button("Restablecer lectura") {
                    resetReading()
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Lectura", systemImage: "textformat") }
            Form {
                LabeledContent("Buscar", value: "⌘F")
                LabeledContent("Concentración", value: "⇧⌘F")
                LabeledContent("Vista de lectura", value: "⇧⌘R")
                LabeledContent("Foco de párrafo", value: "⌥⌘F")
                LabeledContent("Máquina de escribir", value: "⌥⌘T")
                LabeledContent("Negrita · Cursiva", value: "⌘B · ⌘I")
                LabeledContent("Imprimir o guardar PDF", value: "⌘P")
                Text("Tus documentos siguen siendo archivos Markdown o texto UTF-8. La vista de lectura y las preferencias no modifican el archivo.")
                    .font(.callout).foregroundStyle(.secondary).padding(.top, 12)
            }.formStyle(.grouped)
            .tabItem { Label("Atajos", systemImage: "keyboard") }
            Form {
                Section("Voz") {
                    if modules.isRegistered(identifier: "voice.dictation") {
                        LabeledContent("Estado", value: "Activado")
                        LabeledContent("Dictar", value: "⌃⌘V")
                        Text("Pulsa el micrófono de la barra, habla y vuelve a pulsar para insertar. Comandos: “nueva línea”, “nuevo párrafo”, “deshacer”, “borra eso”, “cancelar”. El micrófono solo se pide al dictar y todo se procesa en este Mac.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text("Módulo no disponible")
                            .font(.headline)
                        Text("El editor funciona completo sin voz. Para activarla, añade la pieza VoiceModule (ver comentario “Pieza Lego: Voz” en VoiceModule.swift).")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Section("Gestos") {
                    if modules.isRegistered(identifier: "gestures.hand") {
                        LabeledContent("Estado", value: "Activado")
                        Text("Pulsa la mano de la barra para activar la cámara: mano abierta para elegir palabra, pinza quieta para sinónimos (suelta para confirmar), pinza + barrido lateral para deshacer/rehacer, dos manos para la longitud del párrafo (retira una para confirmar, perder ambas cancela). “Probar sin cámara” abre las mismas tarjetas. La cámara solo se pide al activarla y todo se procesa en este Mac. Los sinónimos mejoran con Apple Intelligence cuando está disponible; si no, listas locales.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text("Módulo no disponible")
                            .font(.headline)
                        Text("El editor funciona completo sin gestos y no pide cámara. Para activarlos, añade la pieza GestureModule (ver comentario “Pieza Lego: Gestos” en GestureTuning.swift).")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Text("Los módulos producen comandos (insertar, formato, deshacer); nunca tocan el texto directamente. Quitarlos no rompe el editor.")
                    .font(.callout).foregroundStyle(.secondary).padding(.top, 12)
            }.formStyle(.grouped)
            .tabItem { Label("Voz", systemImage: "mic") }
        }
        .padding(12).frame(width: 640, height: 640)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .onAppear { editingScheme = effectiveScheme }
    }

    private var familyPreviewName: String {
        switch family {
        case "system", "mono": return "Helvetica Neue"
        case "serif": return "Georgia"
        case "palatino": return "Palatino"
        case "helvetica": return "Helvetica Neue"
        case "verdana": return "Verdana"
        default: return family
        }
    }

    private func resetReading() {
        fontSize = 18; family = "system"; fontWeight = "regular"
        spacing = 6; paragraph = 0; tracking = 0; alignment = "natural"; width = 760
        lightTextHex = "auto"; lightBackgroundHex = "auto"; lightAccentHex = "auto"
        darkTextHex = "auto"; darkBackgroundHex = "auto"; darkAccentHex = "auto"
        syntax = true; statistics = true; appearance = "system"
    }

    private func themePresetButton(_ preset: WritingThemePreset) -> some View {
        let selected = activePresetID == preset.id
        let hexes = preset.hexes(for: editingScheme)
        return Button {
            if editingScheme == .dark {
                darkTextHex = hexes.text
                darkBackgroundHex = hexes.background
                darkAccentHex = hexes.accent
            } else {
                lightTextHex = hexes.text
                lightBackgroundHex = hexes.background
                lightAccentHex = hexes.accent
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(hexes.background == "auto" ? Color(nsColor: .textBackgroundColor) : (WritingStyle.swiftUIColor(fromHex: hexes.background) ?? .gray.opacity(0.2)))
                        .frame(height: 44)
                    Text("Aa")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(hexes.text == "auto" ? Color.primary : (WritingStyle.swiftUIColor(fromHex: hexes.text) ?? .primary))
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: selected ? 2 : 1))
                .environment(\.colorScheme, editingScheme)
                HStack(spacing: 4) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Color.accentColor)
                    }
                    Text(preset.name).font(.caption).lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Combinación \(preset.name) para modo \(editingScheme == .dark ? "oscuro" : "claro")")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func themeOption(_ label: String, value: String, scheme: ColorScheme?) -> some View {
        Button { appearance = value } label: {
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "sidebar.left")
                        RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.25)).frame(height: 10)
                        RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(height: 6)
                        Spacer()
                    }
                    .padding(10).frame(width: 48)
                    .background(.regularMaterial)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Aa").font(.system(size: 24, weight: .semibold))
                        RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.5)).frame(height: 3)
                        RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.3)).frame(height: 3)
                        RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.3)).frame(width: 30, height: 3)
                        Spacer()
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 110)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .environment(\.colorScheme, scheme ?? systemScheme)
                HStack(spacing: 5) {
                    Image(systemName: appearance == value ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(appearance == value ? Color.accentColor : .secondary)
                    Text(label)
                }.font(.callout)
            }
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tema \(label)")
        .accessibilityAddTraits(appearance == value ? [.isSelected] : [])
    }

    @Environment(\.colorScheme) private var systemScheme
}

struct ThemeColorRow: View {
    let title: String
    let subtitle: String
    @Binding var hex: String
    var defaultHex: String = "#000000"

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                if hex != "auto" {
                    Text(hex).font(.caption).monospaced().foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker("", selection: Binding(
                get: { hex == "auto" ? "auto" : "custom" },
                set: { hex = ($0 == "auto") ? "auto" : defaultHex }
            )) {
                Text("Automático").tag("auto")
                Text("Personalizado").tag("custom")
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            if hex != "auto" {
                ColorPicker("", selection: Binding(
                    get: { WritingStyle.swiftUIColor(fromHex: hex) ?? WritingStyle.swiftUIColor(fromHex: defaultHex) ?? .black },
                    set: { hex = WritingStyle.hex(from: $0) }
                ))
                .labelsHidden()
            }
        }
        .padding(.vertical, 4)
    }
}
