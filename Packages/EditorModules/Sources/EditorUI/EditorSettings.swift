import SwiftUI

public struct EditorSettings: View {
    @AppStorage("editor.fontSize") private var fontSize = 18.0
    @AppStorage("editor.fontFamily") private var family = "system"
    @AppStorage("editor.lineSpacing") private var spacing = 6.0
    @AppStorage("editor.readingWidth") private var width = 760.0
    @AppStorage("editor.syntax") private var syntax = true
    @AppStorage("editor.statistics") private var statistics = true
    @AppStorage("editor.appearance") private var appearance = "system"
    public init() {}
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
            }
            .formStyle(.grouped)
            .tabItem { Label("Apariencia", systemImage: "circle.lefthalf.filled") }
            Form {
                Section("Texto") {
                    Picker("Tipografía", selection: $family) {
                        Text("Sistema").tag("system")
                        Text("Georgia").tag("serif")
                        Text("Monoespaciada").tag("mono")
                    }
                    Slider(value: $fontSize, in: 12...32, step: 1) { Text("Tamaño: \(Int(fontSize)) pt") }
                    Slider(value: $spacing, in: 0...14, step: 1) { Text("Interlineado adicional: \(Int(spacing)) pt") }
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
                    fontSize = 18; family = "system"; spacing = 6; width = 760
                    syntax = true; statistics = true; appearance = "system"
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
        }
        .padding(12).frame(width: 560, height: 510)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
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
