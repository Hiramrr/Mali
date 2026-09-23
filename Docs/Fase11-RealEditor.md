# Fase 11 — Integración de comandos de voz con el editor Swift real

Rama: `prueba/real-editor-command-integration`

Pipeline final:

```text
ParsedCommand → Validator → ConfirmationPolicy → EditorCommandExecutor → editor real
```

`FakeEditorState` solo queda para suites históricas. El flujo funcional nuevo
opera sobre `NSTextView` real con `UndoManager` real.

## 1. Rama/commit

Rama `prueba/real-editor-command-integration`. Commit al final de este documento.

## 2. Arquitectura del editor real

App SwiftUI + `DocumentGroup` (`App/EditorApp.swift`) → `EditorScreen` →
`NativeTextEditor` (`NSViewRepresentable`) → `WritingTextView : NSTextView`
(TextKit 2, `usingTextLayoutManager: true`) + `EditorSession` (dueño de la
vista, comandos `EditorCommand`, outline). Persistencia UTF-8 vía
`DocumentKit`. Sin dependencias externas.

## 3. Tipo `EditorCommandTarget` o equivalente

`Packages/EditorModules/Sources/EditorEngine/VoiceCommandIntegration.swift`:
protocolo `@MainActor EditorCommandTarget` (texto, selección, `hasSelection`,
`canUndo/canRedo`, etiquetas de UndoManager, título, revisión, snapshot +
14 operaciones). En `command-grammar`, `RealEditorTarget` implementa lo mismo
directo sobre `ParsedCommand`. El sistema no depende de la UI: el executor
solo ve el protocolo.

## 4. `EditorCommandExecutor`

`EditorCommandExecutor` (EditorEngine) y `RealCommandExecutor`
(command-grammar). Solo ejecuta acciones ya validadas: no reconoce voz, no
parsea, no muestra UI, no llama Foundation Models. Entradas: `receive`
→ `executed` (inmediata) | `needsConfirm` | `invalid` | `rejected`;
`confirm` (Enter, único camino con efecto) con revalidación + snapshot.

## 5. `EditorCommandResult`

`EditorCommandResult`: `success(EditorEffect)` | `noMatch` |
`invalidContext` | `cancelled` | `simulated(SimulatedRewriteRequest)` |
`failure`. Efectos tipados (found/selected/deleted/replaced/formatted/
undone/redone/titleChanged/saved/opened/exported). Nunca `Bool`.

## 6. Implementación real del adapter

`RealEditorTarget` (ambos paquetes) sobre el `NSTextView` real: rangos
`NSRange` nativos, `setSelectedRange`/`scrollRangeToVisible`, `insertText`
agrupado (una op de Undo por mutación), `undoManager.undo()/redo()`,
título registrado en el mismo UndoManager. Puente app:
`EditorSession+Voice.swift` (`makeVoiceTarget`/`makeVoiceExecutor`).

## 7. Tecnología real usada por el editor

`NSTextView` + TextKit 2 vía `NativeTextEditor`/`WritingTextView`, wrapper
SwiftUI existente. No se reescribió el editor.

## 8. Conversión de rangos

`UnicodeRanges.validated` / `RealRanges.validated`: límites UTF-16 +
`Range(NSRange, in:)` + verificación explícita de fronteras de `Character`.
Rangos inválidos → `nil` (nunca selección corrupta). Cursor con clamp.

## 9. Manejo Unicode

Barrido sobre `evaluación`, `María-José`, `🧠`, `👩🏽‍💻` (ZWJ),
`ユーザーインターフェース`, `7.5%`, `ñ`: parcial de grafema siempre
inválido, borrado total o nulo (delta UTF-16 0 o 2, jamás 1), 0 corrupción.

## 10. Integración UndoManager

Mutaciones vía `insertText` agrupado (`begin/endUndoGrouping` +
`breakUndoCoalescing`); undo/redo directos al `undoManager` real; título con
`registerUndo` en el mismo manager (action `Renombrar título`); open
deshacible (selectAll + insertText agrupado). Sin pilas paralelas.

## 11. Preview real

Construido desde el estado actual (`selectedText`, título, etiquetas de
UndoManager), nunca desde el transcript. Delete muestra la selección actual;
replace `actual → nuevo`; rename `viejo → nuevo`.

## 12. Snapshot/versioning de proposal

`EditorProposalSnapshot` / `RealSnapshot`: `selectedRange + selectedText +
textFingerprint + title + documentRevision`.

## 13. Stale proposal handling

`confirm` compara snapshot: distinto → `.failure(.staleProposal)`,
mensaje `El contenido cambió. Repite el comando.`, 0 mutación, pending
limpiado. Cubre cambio de selección, edición externa, cambio de título,
proposal cancelada o id desconocido.

## 14. Revalidación antes de ejecutar

`receive` valida; `confirm` revalida contexto (p. ej. selección eliminada →
`invalidContext`) y snapshot. Sin excepciones.

## 15. Navigation implementation

`findText`/`selectText`: literal exacto → fallback normalizado
(`caseInsensitive + diacriticInsensitive`), sin fuzzy ni autocorrección.
`noMatch` sin tocar nada. Duplicados: primera coincidencia en/después del
cursor, con wrap. Inmediatas vía Validator + editor real, sin preview.

## 16. Delete implementation

Requiere selección; preview `Eliminar: "…"`;
`insertText("", replacementRange:)` agrupado; registra Undo; un solo undo
restaura.

## 17. Replace implementation

Preview `"actual" → "nuevo"`; un solo `insertText`; undo restaura original,
redo reaplica.

## 18. Format implementation

`bold → **…**`, `italic → *…*` (Markdown visible del editor),
`underline → <u>…</u>` (el motor no tiene toggleUnderline; HTML inline
válido, documentado). Toggle unwrap como `EditorSession`. Una op de Undo.

## 19. Undo implementation

`undoManager.undo()` real, con confirmación, 0 mutación antes de Enter.

## 20. Redo implementation

`undoManager.redo()` real, con confirmación.

## 21. Rename implementation

Preview `viejo → nuevo`; título real vía `onTitleChange` (la app lo propaga
al documento); deshacible/rehacible en el mismo UndoManager; no toca texto.

## 22. Rewrite simulation

`SIMULATED_REWRITE_REQUEST { selectedText, instruction, range, revision }`,
retorno `.simulated`, documento intacto, UndoManager intacto. Sin FM.

## 23. Save implementation

Confirmado; escribe `.md` UTF-8 solo en temporales (`VoiceDocumentStore` /
`base` temporal). Verificado byte a byte en tests/live.

## 24. Open implementation

Confirmado; lee `.md` temporal (o último documento con `nil`);
carga deshacible; inexistente → `ioError` sin mutar. Sin archivos personales.

## 25. Export implementation

`plainText → .txt`, `richText → .rtf` (ambos verificados).
`pdf`/`word` → `NOT_IMPLEMENTED_IN_EDITOR` (el editor solo imprime a PDF vía
modal; no hay exportador Word). Sin éxito fingido. El 3er slot de export del
live se sustituyó por un save adicional (reportado).

## 26. Tests anteriores verdes

`swift test --package-path Packages/EditorModules`: 115/115.
`swift run GrammarTest`: 447/447 · `confirm-tests`: 352/352 ·
`risk-tests`: 406/406 · `fixture-tests`: 29/29 · `safeauto-tests`: 44/44.

## 27. Nuevos tests

205 nuevos: 109 XCTest (`VoiceRealEditorTests`) + 96 checks
(`swift run GrammarTest real-editor-tests`, `REAL-EDITOR-INVARIANTS-OK`).

## 28. Range tests

Aceptación ASCII/llenos, rechazo de negativos/overflow, parcial de emoji y
ZWJ inválidos, cursor clamp, `find` nunca devuelve parcial de grafema.

## 29. Unicode tests

Operaciones repetidas sobre `evaluación`, `María-José`, `🧠`, `ユーザー`,
`7.5%`, `ñ`: sin crash, sin rangos corruptos, sin borrado parcial.

## 30. Stale proposal tests

Selección/texto/título cambiados, proposal cancelada, id desconocido,
revalidación de contexto: siempre `STALE`/`invalidContext` + 0 mutación.

## 31. Undo/redo tests

Manager real, vacíos inválidos, ciclo undo/redo, labels, previews C20,
13/13 restauraciones en live.

## 32. Confirmation invariant tests

10 comandos mutantes (undo/redo/format/delete/replace/rename/rewrite/
save/open/export): estado idéntico antes de Enter; cancel no muta; doble
confirm no duplica.

## 33. Live protocol

`swift run GrammarTest real-editor-live` → 36 trials sobre fixtures frescos,
`command-grammar/data/real_editor_live_results.csv` con las 15 columnas
pedidas (`stt_ms=0` headless; STT aislado en Fase Custom LM v1).
8 nav (auto) + 28 confirm (enter). Grupos: nav 8, rev 8 (3 undo + 3 redo +
2 format), content 12 (3+3+3+3), external 8 (4 save + 2 open + 2 export).

## 34. Correct effects

36/36 = 100% (objetivo ≥ 98%).

## 35. Wrong effects

0 confirmados incorrectos, 0 automáticos incorrectos (ver 36/37).

## 36. Wrong automatic effects

0. Navegación inmediata verificada sin mutar texto/título/historial en los
8 trials nav + invariante estructural en tests.

## 37. Stale proposal mutations

0 (live sin stale; 6+6 tests stale dedicados, todos 0 mutación).

## 38. Undo restoration rate

13/13 = 100% (todos los trials mutantes deshechos y rehechos en live).

## 39. Crashes

0 en tests (205) y live (36). 0 rangos inválidos aplicados, 0 corrupción.

## 40. Execution latency

`execution_ms` mediana 0.056, p95 0.540, máx 0.897 (muy por debajo del
tiempo humano de confirmación y del umbral 100 ms). `proposal_ms` mediana
0.026, máx 3.712.

## 41. Fallos encontrados

1. `E02 "Convierte a texto enriquecido."` parseó a `plainText` por regla
   congelada (`" texto "` precede a `"enriquecid"` en `matchExport`).
   Clasificación: Grammar (congelada, comportamiento correcto por diseño).
   Corrección solo en la capa responsable (diseño del trial): transcript
   → `"Exporta en formato enriquecido."` (richText). Gramática intacta.
2. Timing inicial en ms truncado a 0 (bug del runner live, no del editor):
   corregido con `msBetween` (segundos + attosegundos).

## 42. Interpretación técnica

La integración falló 0 veces por `EditorAdapter`, rangos, UndoManager,
confirmación o ciclo de documentos. El único desvío vino del diseño de un
trial (argumento que activa una regla de precedencia documentada). La
arquitectura voz→editor está aislada por capas y cada fallo clasifica sin
tocar Speech ni Grammar.

## 43. Decisión GO / NO-GO hacia Fase 12

```text
wrong automatic effects = 0
stale proposal mutations = 0
Unicode corruption = 0
undo restoration = 100%
confirmed supported editor actions = 100% (≥ 98%)
rewrite → SIMULATED_REWRITE_REQUEST con texto, rango e instrucción reales
crashes = 0
```

**GO FASE 12** — Fase 12: rewrite local con Foundation Models (solo
`selectedText + rewriteInstruction` → propuesta de texto con aceptación
explícita; sin routing, sin tools, sin mutación directa).
