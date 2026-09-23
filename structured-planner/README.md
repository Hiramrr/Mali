# Structured Command Planner (FM como parser, sin tools)

COMMAND MODE explícito → Foundation Models con guided generation
(`CommandPlan`: actions/unsupported/noAction) → validador determinista.
Cero tools registradas, `toolCallingMode: .disallowed`, greedy.

## Ejecutar

```bash
cd structured-planner
swift run PlannerTest
```

FINAL_COMMAND_PLANNER_V1 (650, SHA en `data/FINAL_SHA256.txt`) +
PHASE5_REGRESSION (255, diagnóstico).

## Prompt exacto

```text
You parse spoken commands for a text editor. Return the requested editor actions in the same order they were requested. Preserve explicit user-provided text verbatim.
If the request is not an editor operation, return noAction. If it requests an operation not represented by the supported action schema, return unsupported. Never replace an unsupported request with a similar supported action.
```

Prompt por caso: `HAS SELECTION / CAN UNDO / CAN REDO / DOCUMENT OPEN /
USER SAID` (sin contenido seleccionado: evita el guardrail por TDAH).

## GenerationOptions

```swift
if #available(macOS 27, *) {
    GenerationOptions(samplingMode: .greedy, toolCallingMode: .disallowed)
}
```

Sesión nueva por test, sin `tools:` (el init por defecto no registra ninguna).

## Validadores

- Contexto: delete/replace/rewrite/format requieren hasSelection;
  undo→canUndo; redo→canRedo; save/export→documentIsOpen.
- Literal: renameTitle.newTitle, replaceSelection.newText, findText.query,
  selectText.target, openDocument.reference deben aparecer verbatim en la
  emisión (NFC, trim, espacios, comillas externas, puntuación final).
  `rewriteSelection.instruction` exenta (evaluación manual).

## Resultado FINAL (2026-09-23, macOS 27, Xcode 27, 650 tests, 1 config)

- Disposition: 31.8% (207/650). Single: 28.0%. Unsupported: 6.2% (5/80).
- Sustituciones unsupported: 13. NoAction: 75.0%. False Action Rate: 25.0%.
- Args raw: 73.7% (84/114). Rechazos literales: 22.
- redo/undo (H): 10.0% (3/30). find/select/format (I): 17.5% (7/40).
- Multi (F, n=60): exact=14, wrongOrder=0, missing=13, extra=1, wrong=32.
- Validator: VALID 246, NEEDS_CONTEXT 97, UNSUPPORTED 6, NO_ACTION 276,
  REJECTED_ARG 22. Errores generación: 3 (guardrail 3).
- Latencia med 1110 ms (vs 1349 tool-calling). G (sin contenido): 0 guardrail.
- Estructural: 0 tools registradas, 0 tool calls, 0 efectos.
- Criterios: todos incumplidos por amplio margen. Sin tuning posterior.

## PHASE5_REGRESSION (255, diagnóstico)

single 84/140 (60.0%), uns 0/15, subs 10, na 58/100, naFalse 42,
args 18/18, errs 0, guardrail 0.
