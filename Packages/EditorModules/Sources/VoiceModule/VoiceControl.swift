import SwiftUI

/// Botón + HUD del dictado. Vive dentro de `VoiceModule` para que `EditorUI`
/// nunca importe voz: la app lo envuelve en `AnyView` y lo pasa a
/// `EditorScreen(voicePanel:)`. Si la pieza se quita, ese parámetro es `nil`.
public struct VoiceControl: View {
    @Bindable private var module: VoiceModule
    @State private var showHUD = false

    public init(module: VoiceModule) {
        self.module = module
    }

    public var body: some View {
        Button {
            Task { await module.toggle() }
            showHUD = true
        } label: {
            Image(systemName: symbol)
                .foregroundStyle(showHUD ? .white : .primary)
                .frame(minWidth: 28, minHeight: 28)
                .background(showHUD ? Color.accentColor : Color.clear, in: Circle())
        }
        .help("Dictar con la voz · ⌃⌘V")
        .accessibilityLabel("Dictar con la voz")
        .accessibilityHint("Pulsa para empezar a dictar y de nuevo para insertar el texto.")
        .keyboardShortcut("v", modifiers: [.control, .command])
        .popover(isPresented: $showHUD, arrowEdge: .bottom) {
            hud
        }
        .onChange(of: isActive) { _, active in
            if active { showHUD = true }
        }
    }

    private var isActive: Bool {
        switch module.state {
        case .idle: false
        case .listening, .processing, .failed: true
        }
    }

    private var symbol: String {
        switch module.state {
        case .listening: "mic.fill"
        case .processing: "ellipsis"
        case .failed: "mic.slash"
        case .idle: "mic"
        }
    }

    private var statusText: String {
        switch module.state {
        case .idle:
            if !module.lastCommandFeedback.isEmpty {
                module.lastCommandFeedback
            } else if module.lastInsertedText.isEmpty {
                "Pulsa para dictar"
            } else {
                "Insertado: \(module.lastInsertedText.prefix(80))"
            }
        case .listening:
            module.partialTranscript.isEmpty ? "Escuchando… habla ahora" : module.partialTranscript
        case .processing:
            "Procesando…"
        case .failed(let message):
            message
        }
    }

    private var hud: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dictado por voz").font(.headline)
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            if module.state == .listening {
                ProgressView(value: Double(module.inputLevel))
                    .accessibilityLabel("Nivel del micrófono")
            }
            HStack {
                if module.isListening {
                    Button("Terminar") { Task { await module.finish() } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .help("Cierra el enunciado y lo ejecuta sin esperar la pausa")
                    Button("Descartar", role: .cancel) { Task { await module.cancelDictation() } }
                } else {
                    Button(module.lastInsertedText.isEmpty && module.lastCommandFeedback.isEmpty ? "Dictar" : "Dictar de nuevo") {
                        Task { await module.begin() }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    if case .failed = module.state {
                        Button("Cerrar") { showHUD = false }
                    }
                }
            }
            Toggle("Escucha continua (cierra solo con pausas)", isOn: $module.continuousListening)
                .font(.callout)
                .help("Un toque inicia; cada pausa ejecuta y sigue escuchando; otro toque detiene.")
            Toggle("Estilo formal (mayúscula y punto final)", isOn: $module.formalStyle)
                .font(.callout)
            Picker("Idioma", selection: $module.localeIdentifier) {
                Text("Español (México)").tag("es-MX")
                Text("Español (España)").tag("es-ES")
                Text("English (US)").tag("en-US")
            }
            .pickerStyle(.menu)
            .font(.callout)
            Text("Comandos: “busca…”, “selecciona…”, “pon en negritas”, “borra la selección”, “guarda”, “abre”, “exporta…”, “cambia el título a…”, “deshacer”, “cancelar”.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300)
    }
}
