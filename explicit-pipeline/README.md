# Pipeline explícito dictation/command (sin clasificador)

La señal de interacción (`VoiceInteractionMode`) decide el routing.
Ningún modelo infiere `command`. En DICTATION MODE, Foundation Models
no recibe la emisión (0 invocaciones por construcción).

## Ejecutar

```bash
cd explicit-pipeline
swift run PipelineTest
```

455 tests (A100 B100 | C120 D12 E100 F15 G8) + modo interactivo.

## Sesiones

Una `LanguageModelSession` nueva por test de COMMAND MODE.
Tool calling por defecto (`GenerationOptions()` sin `toolCallingMode`):
el modelo decide libremente llamar o no.

## Prompt exacto (instructions, solo COMMAND MODE)

```text
You interpret spoken input directed at a text editor.
Call an editor tool only when the user clearly requests an executable editor action.
The user may also be dictating ordinary document content. Text that talks about editing, titles, deleting, replacing, formatting, or editors is not necessarily an instruction.
Use the current editor state when determining whether an action is applicable.
If the user is dictating text, making an incomplete request, or the intended action is unclear, do not call a tool.
```

Prompt por caso: `CURRENT TITLE / SELECTED TEXT / CAN UNDO / CAN REDO /
DOCUMENT OPEN / USER SAID`.

## Tools (12 stubs, sin efectos)

renameTitle(newTitle), deleteSelection(), replaceSelection(newText),
rewriteSelection(instruction), formatSelection(style: bold|italic|underline),
undo(), redo(), selectText(target), findText(query), saveDocument(),
openDocument(), exportDocument(). Validador determinista por precondiciones.

## IntentGate V4

No cargado en esta prueba (la señal explícita ya garantiza el routing).

## Resultado (2026-09-23, macOS 27, Xcode 27, 455 tests)

- Routing Safety: 200/200 dictation sin FM ni tools. SAFE por construcción.
- Single-command accuracy: 75.0% (90/120; 10 wrong, 20 missed).
- Argument accuracy: 90.5% (19/21). Fallo de idioma: C003 Claridad->Clarabidad.
- Grupo D: semántica 8/12, bloqueos de validador 10/12.
- Grupo E False Tool Rate: 37% (37/100; domina findText como acción refugio).
- Grupo F: 10 no-tool, 5 sustituciones (Firma->save, Traduce/Programa/Convierte->rewrite, Cifra->format).
- Grupo G: 4/8 secuencias exactas; en las 4 restantes todas las acciones presentes pero en otro orden (saveDocument siempre primero).
- Validador: 182 propuestas, 145 válidas, 37 bloqueadas.
- Guardarraíl del framework: ~14 rechazos en C con selección que menciona TDAH (rewrite/format/replace), patrón ya visto en fase 3.
- redo->undo sistemático en 5/10 casos (Rehaz eso, Deshaz el deshacer...).
- Latencias: cold start 2907 ms; single med 1349; no-tool 1425 vs tool-call 1252; multi med 1641; routing dictation ~0.003 ms.
- Criterios (acc>=95% ✗, sustituciones=0 ✗ 5, args>=95% ✗ 90.5, E<=5% ✗ 37%): no alcanzados en el nivel 2. La seguridad primaria (routing) sí garantizada.
