# Referencias e integración pendiente

## Gestos

Implementado como pieza extraíble (21-sep-2026). Fuente: `/Users/hiram/Proyectos/EditorTDAH/Enfoque/Gestures` (más `LocalFallback` de `Intelligence/WritingAssistant.swift` para sinónimos locales).

- `GestureModule` (target en `Packages/EditorModules`, sin dependencias externas): `GestureTuning` + `GestureThresholds` (clave propia `editor.pinchActivation`, no se comparte con Enfoque), `HandLandmarks`/`GestureState`/`GestureRecognizer` (histéresis), `GestureCalibrationMath`, `WordNavigator`/`PinchStep`/`LengthLevel`/`LengthSpanStep`, `GestureSynonyms` (listas locales inmediatas), `SynonymProvider` (protocolo) + `FoundationModelsSynonymProvider` (mejora con Apple Intelligence on-device si hay modelo; si no, vacío y la tarjeta conserva locales) + `LocalSynonymProvider`, `CameraManager` (permiso solo al activar), `HandPoseDetector` (Vision on-device), `GestureModule` (máquina de estados), `GestureControl` (botón y panel: preview espejado, diagnóstico, umbral, calibración, estado de IA, pruebas sin cámara) y `GestureCards` (tarjetas de sinónimos, longitud y aviso con Deshacer).
- Frontera: el módulo nunca toca `NSTextView`. Navegación (`selectRange`) y barrido (`.undo`/`.redo`) viajan como `EditorCommand` por el bus en orden FIFO. Las sesiones usan comandos atómicos nuevos (`beginPreview`/`showPreview`/`commitPreview`/`cancelPreview`) que `EditorSession` aplica sin ensuciar undo ni guardado: el binding, el autosave y el índice ignoran la preview (`NativeTextEditor` la respeta) y al terminar se sincroniza vía `onPreviewCommitted`. Confirmar registra un único undo (o ninguno si no hubo cambio). El documento llega al módulo como instantánea (`updateDocument(text:selection:)` desde `onGestureDocument`); si el texto cambia por fuera, la sesión se cancela, nunca se confirma a ciegas. La pérdida de seguimiento (0.3 s de gracia) cancela y restaura; retirar UNA mano confirma la longitud, perder AMBAS la restaura.
- La longitud usa Foundation Models en este Mac para generar una versión corta completa y otra más extensa. Mientras se generan, la tarjeta no permite confirmarlas. Si el modelo no está disponible o las versiones no cumplen los mínimos de longitud, conserva el párrafo y explica el motivo. Los sinónimos conservan su lista local.
- Diferencias con Enfoque: sin anclaje de tarjeta sobre la palabra (overlay inferior), sin "el ratón manda" (el módulo no ve el ratón; los rangos obsoletos se rechazan al validar).
- Permisos: la cámara se pide solo al pulsar "Activar cámara" (`NSCameraUsageDescription`, entitlement `device.camera`). Sin la pieza, la app no la pide. Todo on-device, sin guardar vídeo.
- Quitar: borrar el bloque "Pieza Lego: Gestos" de `App/EditorApp.swift`, el target `GestureModule` de `Package.swift` y su producto del `.xcodeproj`. `EditorScreen` compila con `gesturePanel == nil` y Ajustes > Voz muestra "Módulo no disponible" en Gestos.
- Pruebas en `GestureLogicTests.swift` (histéresis, tracking, dos manos, calibración, navegadores, sinónimos) y `PreviewTests.swift` (commit con un solo undo, sin cambios sin undo, cancelación, edición externa, bloqueo en lectura).

## Voz

No apareció una carpeta llamada MiyuFlow en Proyectos. El proyecto de voz encontrado es `/Users/hiram/Proyectos/MiyuWisp/LocalFlow`.

Se revisaron su README, `SpeechRecognitionService.swift`, `VoiceResult.swift` y `RuleBasedIntentParser.swift`. La ruta Apple usa SpeechAnalyzer y DictationTranscriber de macOS 26. Existe también una variante WhisperKit, que no se añadió a EditorFinal.

Implementado como pieza Lego extraíble (21-sep-2026):

- `ModuleKit`: `EditorCommandBus` (actor con difusión), `EditorModuleContext`, `EditorInputModule`, `ModuleDescriptor`, `ModuleRegistry` (registro para Ajustes).
- `VoiceModule`: `VoiceModule` + `VoiceControl` (botón y HUD, ⌃⌘V), `AppleSpeechRecognizer` (micrófono local, parciales y nivel), `VoiceCommandParser` (comandos: nueva línea, nuevo párrafo, deshacer, borra eso, cancelar), `DictationCleaner` (muletillas, puntuación dictada, estilo formal).
- Frontera: la voz produce `EditorCommand` vía bus; nunca toca `NSTextView`. Sin inserción por Accesibilidad, atajos globales ni control de otras apps. "Borra eso" equivale a undo del editor. En lectura los comandos se ignoran solos.
- Permisos: micrófono y voz se piden solo al dictar (`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, entitlement `audio-input`). Sin la pieza, la app no los pide.
- Quitar: borrar el bloque "Pieza Lego: Voz" de `App/EditorApp.swift`, los productos `VoiceModule`/`ModuleKit` de `Package.swift` y del `.xcodeproj`. `EditorScreen` compila con `voicePanel == nil` y Ajustes > Voz muestra "Módulo no disponible".
- Pruebas sin micrófono en `VoiceModuleTests.swift` (parser, limpieza, bus, registro, inserción y undo por bus, silencio).

## Frontera futura

`EditorCore.EditorCommand` no importa AppKit ni SwiftUI. `EditorSession.send` recibe intenciones y aplica las operaciones al NSTextView. El bus (`EditorCommandBus`) y `ModuleKit` ya existen con el primer módulo (voz), con pruebas de cancelación, cierre y silencio. Falta probar destino por documento si alguna vez hay más de una ventana.

## Referencia de persistencia

La primera entrega usa DocumentGroup y FileDocument para conservar el ciclo nativo de documentos. Referencia de Apple: https://developer.apple.com/documentation/swiftui/documentgroup
