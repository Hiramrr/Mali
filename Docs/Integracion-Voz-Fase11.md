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
