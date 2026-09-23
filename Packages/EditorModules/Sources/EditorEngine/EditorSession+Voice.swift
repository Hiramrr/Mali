// Fase 11 — Puente entre la sesión real de la app y los comandos de voz.
//
//  EditorSession (Dueño del NSTextView vía NativeTextEditor) expone un
//  RealEditorTarget + EditorCommandExecutor sobre su vista activa, con el
//  título del documento y un almacén temporal para save/open/export.
//  Sin cambios a la UI ni al ciclo de documentos de SwiftUI.
import AppKit
import Foundation

@MainActor extension EditorSession {
    /// Target de voz sobre el NSTextView real de esta sesión.
    /// - Parameters:
    ///   - title: título actual del documento (DocumentGroup).
    ///   - titleWriter: escritura diferida del título (solo tras confirm).
    ///   - store: almacén temporal para save/open/export.
    public func makeVoiceTarget(title: String,
                                titleWriter: @escaping (String) -> Void,
                                store: VoiceDocumentStore) -> RealEditorTarget? {
        guard let view = textView else { return nil }
        let target = RealEditorTarget(view: view, title: title, store: store)
        target.onTitleChange = { titleWriter($0) }
        return target
    }

    /// Executor listo para el modo `real-editor-command-test`:
    /// abrir fixture → Command Mode → proposal → Enter/Esc/R.
    public func makeVoiceExecutor(title: String,
                                  titleWriter: @escaping (String) -> Void,
                                  store: VoiceDocumentStore) -> EditorCommandExecutor? {
        guard let target = makeVoiceTarget(title: title, titleWriter: titleWriter, store: store) else {
            return nil
        }
        return EditorCommandExecutor(target: target)
    }
}
