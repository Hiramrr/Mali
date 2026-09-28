# Integración voz Fase 11 ↔ rama full (action-classifier)

## Qué se integró

Rama `prueba/action-classifier-voice-integration` = `prueba/action-classifier`
(menús nuevos, `VoiceModule` dictado, `GestureModule`, `ModuleKit`, bus de
comandos) + cambios de voz probados en `prueba/real-editor-command-integration`
(commit `3bc7e37`):

- `EditorEngine/VoiceCommandIntegration.swift` — `EditorCommandTarget`,
  `EditorCommandExecutor`, `EditorCommandResult`, `RealEditorTarget`,
  snapshot/stale, previews C20, fixtures, store temporal, harness.
- `EditorEngine/EditorSession+Voice.swift` — `session.makeVoiceExecutor(...)`.
- `VoiceRealEditorTests.swift` — 109 tests (verdes aquí: 178/178 total).
- `command-grammar/` completo — parser/gramática/STT/policy + 447/352/406/
  29/44/96 suites verdes + live 36/36.
- `Docs/Fase11-RealEditor.md` — entrega y métricas.

## Costura entre los dos sistemas de voz (intencionalmente sin auto-cablear)

- `VoiceModule` (dictado) → `EditorCommandBus` → `session.send(...)`:
  flujo existente, intacto, sigue funcionando.
- Fase 11 (`VoiceCommand` + `EditorCommandExecutor`): taxonomía de comandos
  validada con confirmación obligatoria. Expuesto vía
  `session.makeVoiceExecutor(title:titleWriter:store:)`.
- NO se conectó el transcript del dictado al executor porque eso exigiría:
  1. importar la gramática probada (vive en `command-grammar`, paquete
     ejecutable no importable; duplicarla violaría el congelamiento), y
  2. UI de confirmación (proposal/Enter/Esc), explícitamente fuera del
     alcance de Fase 11 ("No UI final").
- Cablear sin confirmación violaría el invariante `wrongAuto = 0`.
  El siguiente paso es una UI de modo-comando que use `makeVoiceExecutor`
  (proposal → Enter/Esc/R), no un atajo automático.

## Actualización: comandos completos por voz (2026-09-23)

Los 12 comandos probadas ahora funcionan en la app, SIN duplicar la
gramática: `command-grammar` expone la librería `CommandGrammar`
(`Types`+`Grammar`, solo cambio de acceso a `public` + `Sendable`; cero
funcional) y `VoiceModule` depende de ella (fuente única).

Ruta: transcript → legacy (frases exactas) → `parseCommand` real (+reintento
"cambia el título de X"→"a X", adaptación en app, `Grammar.swift` intacta)
→ `[EditorCommand]` → bus → sesión/pantalla.

Cobertura: find/select inmediatos (solo selección), delete/replace/format/
undo/redo/rename/save/open/export ejecutados, rewrite con propuesta local
y confirmación, unsupported/unknown/múltiple → dictado o aviso, 0 comandos.

El panel de voz muestra la transcripción y la propuesta. Dictado y comandos
comparten el mismo micrófono. En el modo por turnos, Enter confirma, Esc
descarta y R vuelve a grabar. Buscar y seleccionar se ejecutan al momento;
las acciones que cambian estado esperan confirmación. Si una frase como
«Titula bien tus ideas» se reconoce como comando, «Usar como texto» cambia
la propuesta a dictado sin volver a hablar.
Tras confirmar, el panel conserva la transcripción junto al resultado.
«Corrige eso» propone deshacer el último cambio.

Abrir por nombre consulta los documentos conocidos de la biblioteca. Solo
abre directamente cuando el nombre identifica un archivo único. Si no hay
coincidencia única, muestra el panel de apertura del sistema.

Manos libres: `continuousListening` (defecto sí) cierra cada frase tras 1.6 s
sin cambios en el parcial. El dictado parcial aparece en el documento sin
guardarse y se inserta al cerrar la pausa. El micrófono se rearma. Para un
cambio pendiente, sigue escuchando «confirmar», «descartar», «repetir» o
«usar como texto». «Detener voz» termina la escucha. El silencio total nunca
cierra solo. El umbral aún requiere medición con micrófono real.

## Actualización: reescritura real y Word (2026-09-23)

- «Hazlo más breve» y otras instrucciones de reescritura generan una
  propuesta con Foundation Models en este Mac. El panel muestra el texto
  generado antes de confirmar. Aceptar reemplaza la selección en un único
  undo; descartar conserva el documento y el historial. Si no hay selección,
  el modelo falla o cambia el documento o la selección, no aplica nada.
- «Exporta en Word» es real: `EditorScreen` guarda .docx (Office Open XML
  desde la lectura renderizada) vía panel del sistema. «Exporta a pdf»
  sigue yendo al diálogo de impresión.
- Harness (`VoiceCommandIntegration`, doble de pruebas): export pdf (PDF
  headless al store temporal) y word (.docx al store) reales. Rewrite sigue
  simulado a propósito (doble determinista para la política de
  confirmación; el path real de producción es `EditorSession`).

## Fase 12: verificación de reescritura local (2026-09-23)

- `EditorSession` envía solo la selección y la instrucción a Foundation Models
  en este Mac. El texto original y el historial de deshacer no cambian hasta
  que la persona confirma la propuesta visible.
- Cambiar el documento, la selección o el archivo antes de confirmar invalida
  la propuesta. Detener voz también la descarta e ignora respuestas tardías.
  Los espacios y saltos de línea al borde de la selección se conservan.
- `swift test --package-path Packages/EditorModules` pasó con 227 pruebas.
  Una prueba de consola con Foundation Models disponible devolvió una
  reescritura breve. Falta comprobar el flujo completo con micrófono y la
  interfaz en ejecución.
