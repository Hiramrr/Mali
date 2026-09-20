# Referencias e integración pendiente

## Gestos

Fuente revisada: `/Users/hiram/Proyectos/EditorTDAH/Enfoque`.

El reconocedor usa Vision, histéresis de pinza y un umbral ajustable. `GestureRecognizer.swift`, `Calibration.swift` y `HandPoseDetector.swift` son los candidatos a extraer. `HandInput.swift` coordina sesiones de previsualización, sinónimos y longitud del párrafo, y depende del estado de aquella app. No se debe copiar íntegro al motor del editor.

Se reutilizó el patrón de configuración de NSTextView con TextKit 2 de `TextEditorRepresentable.swift`. Esta versión conserva la búsqueda nativa y no incluye IA, cámara o dictado en el control de texto.

Antes de incorporar gestos, extraer las intenciones y enviar `EditorCommand` a la sesión activa. La calibración debe mantenerse. La pérdida de seguimiento cancela una previsualización, nunca confirma un cambio de texto por sí sola.

## Voz

No apareció una carpeta llamada MiyuFlow en Proyectos. El proyecto de voz encontrado es `/Users/hiram/Proyectos/MiyuWisp/LocalFlow`.

Se revisaron su README, `SpeechRecognitionService.swift`, `VoiceResult.swift` y `RuleBasedIntentParser.swift`. La ruta Apple usa SpeechAnalyzer y DictationTranscriber de macOS 26. Existe también una variante WhisperKit, que no se añadió a EditorFinal.

Reutilizar captura, cierre de sesión y análisis de intenciones. Dentro del editor no hace falta copiar la inserción por Accesibilidad, los atajos globales ni el control de otras aplicaciones. La transcripción debe terminar en `EditorCommand.insertText`; deshacer debe utilizar el UndoManager del editor.

## Frontera futura

`EditorCore.EditorCommand` no importa AppKit ni SwiftUI. `EditorSession.send` recibe intenciones y aplica las operaciones al NSTextView. Todavía no hay bus asíncrono ni ModuleKit, porque no hay productores multimodales activos. Incorporarlos junto con el primer módulo, con pruebas de cancelación, cierre y destino por documento.

## Referencia de persistencia

La primera entrega usa DocumentGroup y FileDocument para conservar el ciclo nativo de documentos. Referencia de Apple: https://developer.apple.com/documentation/swiftui/documentgroup
