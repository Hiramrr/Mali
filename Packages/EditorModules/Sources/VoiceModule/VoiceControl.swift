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
            if module.isListening || module.pendingAction == nil { Task { await module.toggle() } }
            showHUD = true
        } label: {
            Image(systemName: module.isListening ? symbol : module.pendingAction == nil ? symbol : "exclamationmark.bubble")
                .foregroundStyle(showHUD || module.isListening || module.pendingAction != nil ? .white : .primary)
                .frame(minWidth: 28, minHeight: 28)
                .background(showHUD || module.isListening || module.pendingAction != nil ? Color.accentColor : Color.clear, in: Circle())
        }
        .help(module.isListening ? "Detener escucha" : module.pendingAction != nil ? "Revisar propuesta de voz" : "Dictar con la voz · mantén ⌥Espacio o pulsa ⌃⌘V")
        .accessibilityLabel(module.isListening ? "Detener escucha" : module.pendingAction != nil ? "Revisar propuesta de voz" : "Iniciar dictado")
        .accessibilityHint("Mantén Opción Espacio para hablar y suelta para revisar, o pulsa para empezar y de nuevo para terminar.")
        .keyboardShortcut("v", modifiers: [.control, .command])
        .popover(isPresented: $showHUD, arrowEdge: .bottom) {
            hud
        }
        .onChange(of: isActive) { _, active in
            if active { showHUD = true }
        }
        .onChange(of: module.pendingAction) { previous, action in
            if action != nil { showHUD = true }
            else if previous != nil { showHUD = false }
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
            if !module.microphoneReady {
                "Preparando micrófono…"
            } else if module.partialTranscript.isEmpty {
                module.pushToTalkHeld ? "Hablando… suelta ⌥Espacio para terminar" : "Escuchando… habla ahora"
            } else {
                module.partialTranscript
            }
        case .processing:
            "Procesando…"
        case .failed(let message):
            message
        }
    }

    private var hud: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(module.pendingAction == nil ? "Dictado por voz" : "Confirmar acción").font(.headline)
            if let action = module.pendingAction {
                Text("Escuché: \(action.transcript)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let text = module.pendingDictationText {
                    TextField("Texto a insertar", text: Binding(
                        get: { module.pendingDictationText ?? text },
                        set: { module.updatePendingDictation($0) }
                    ), axis: .vertical)
                    .lineLimit(2...5)
                    .onKeyPress(keys: [.return]) { press in
                        if press.modifiers.contains(.shift) { return .ignored }
                        Task { await module.confirmPending() }
                        return .handled
                    }
                } else {
                    ScrollView {
                        Text(action.preview)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                }
                HStack {
                    Button("Confirmar (Enter)") { Task { await module.confirmPending() } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .help("Confirmar con Enter")
                        .disabled(module.pendingDictationText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true)
                    Button("Descartar", role: .cancel) {
                        module.cancelPending()
                        if module.isListening && !module.continuousListening {
                            Task { await module.cancelDictation() }
                        }
                    }
                        .keyboardShortcut(.cancelAction)
                    Button("Repetir") {
                        Task {
                            await module.repeatPending()
                            showHUD = true
                        }
                    }
                }
                if !action.isDictation {
                    Button("Usar como texto") { module.usePendingAsDictation() }
                }
                if module.isListening {
                    Text(module.microphoneReady ? "Escuchando. Di «confirmar», «descartar» o «repetir»." : "Preparando micrófono…")
                        .font(.callout)
                    if module.lastCommandFeedback == "Di confirmar, descartar o repetir" {
                        Text(module.lastCommandFeedback).font(.caption).foregroundStyle(.secondary)
                    }
                    if !module.partialTranscript.isEmpty {
                        Text("Escuchando: \(module.partialTranscript)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Responder por voz") { Task { await module.listenForPendingDecision() } }
                        .disabled(module.state == .processing)
                }
            } else {
                if !module.lastTranscript.isEmpty && module.state == .idle {
                    Text("Escuché: \(module.lastTranscript)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if module.handsFreeActive && !module.lastCommandFeedback.isEmpty {
                    Text(module.lastCommandFeedback)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if module.state == .listening {
                ProgressView(value: Double(module.inputLevel))
                    .accessibilityLabel("Nivel del micrófono")
                if module.pushToTalkHeld {
                    Text("Suelta ⌥Espacio para terminar y revisar la propuesta.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if module.pendingAction == nil {
                HStack {
                    if module.isListening {
                        Button("Terminar") { Task { await module.finish() } }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .help("Cierra el enunciado y prepara la propuesta")
                        Button("Descartar", role: .cancel) { Task { await module.cancelDictation() } }
                    } else {
                        Button(module.lastInsertedText.isEmpty && module.lastCommandFeedback.isEmpty ? "Dictar" : "Dictar de nuevo") {
                            Task { await module.toggle() }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        if case .failed = module.state {
                            Button("Cerrar") { showHUD = false }
                        }
                    }
                }
            }
            if module.pendingAction == nil {
                Toggle("Manos libres", isOn: $module.continuousListening)
                    .font(.callout)
                    .help("Un toque inicia. Cada pausa inserta el dictado; los cambios esperan confirmación por voz. Di «detener voz» para salir.")
                Toggle("Estilo formal (mayúscula y punto final)", isOn: $module.formalStyle)
                    .font(.callout)
                Picker("Idioma", selection: $module.localeIdentifier) {
                    Text("Español (México)").tag("es-MX")
                    Text("Español (España)").tag("es-ES")
                    Text("English (US)").tag("en-US")
                }
                .pickerStyle(.menu)
                .font(.callout)
                Text("Con Manos libres, pulsa una vez y dicta. El texto aparece en el documento y se inserta tras una pausa. Para cambios, di el comando y luego «confirmar», «descartar» o «repetir». Di «detener voz» para salir. También puedes mantener ⌥Espacio para hablar por turnos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: module.pendingAction == nil ? 300 : 340)
    }
}
