# Command Grammar + Speech (sin ML para decidir acciones)

Parser determinista (`CommandGrammar`) + STT local (`DictationTranscriber`
es_MX, preset phrase, `contextualStrings` ≤100). Cero Foundation Models.

## Ejecutar

```bash
cd command-grammar
swift run GrammarTest                  # 447 unit tests del parser
swift run GrammarTest transcribe f.wav # transcribe + parsea un archivo
swift run GrammarTest live             # sesión guiada con micrófono
```

El micrófono requiere permiso (Ajustes > Privacidad y seguridad > Micrófono).

## API real usada (macOS 27 / Xcode 27)

- `DictationTranscriber(locale: Locale(identifier: "es_MX"), preset: .phrase)`
- `AnalysisContext()` + `contextualStrings = [.general: [...]]` (69 entradas)
- `SpeechAnalyzer(inputAudioFile: AVAudioFile, modules: [...], analysisContext:)`
  (init de actor → `try await`; no existe `init(modules:)` solo en este SDK)
- `transcriber.results` (propiedad AsyncSequence; `r.text: AttributedString`,
  `r.isFinal`); cierre con `finalizeAndFinishThroughEndOfInput()`
- `AssetInventory.assetInstallationRequest(supporting:)` → nil (assets ya instalados)
- `DictationTranscriber.supportedLocales` incluye `es_MX` (ojo: con guion bajo)

## Gramática

Precedencia: multi > replace > rewrite > format > rename > delete >
redo > undo > find > select > export > save > open > export-desconocido >
unsupported > unknown. Desviaciones documentadas en código:
export antes que save ("Guarda copia como pdf"), redo antes que undo
("deshaz el deshacer"), format antes que select ("marca X en negritas").
Sin fuzzy: lo no reconocido es unknown (o unsupported con verbos explícitos).

## Fase A: 447/447 ✓

Patrones soportados, tildes, mayúsculas, 100+ args literales, unsupported,
unknown, multi-action, colisiones. Sin `insertText` deliberado.

## Humo TTS (NO oficial, solo verifica la cadena)

Paulina es_MX → wav → STT → parse: 6/7.
STT produce minúsculas ("claridad") y errores reales ("Deshaz eso"→"Les hace eso").

## Fase B: protocolo en vivo (PENDIENTE de voz humana)

`data/live_protocol.csv`: 48 órdenes ×2 + 15 unsupported + 15 unknown = 126.
`swift run GrammarTest live` guía y registra en `live_results.csv`.

## Fase B en vivo (2026-09-23, voz humana, 126 utterances)

- WER: 13.5% (51/377 palabras).
- End-to-end órdenes: 80/96 = 83.3%.
- Unsupported hablado: 15/15 (0 sustituciones).
- Unknown hablado: 15/15 (0 acciones).
- Args literales verbatim del raw: 60/60 = 100%.
- Parser con transcript limpio: ~94/96 = 97.9%.
- STT: media 227, mediana 221, p95 259 ms. Parser ~0 ms.
- Undo/redo: correctos con transcript limpio; fallos solo por STT
  ("Re hazlo", "Deshace", "Se hace el cambio", "Fe haz eso", truncados).
- Hallazgos STT: minúsculas ("claridad"), splits ("Pon lo", "Re hazlo"),
  confusiones ("negritas"->"Netflix", "Rehaz"->"Se hace"),
  prefijos del hablante ("Hola", "Sí" -> unknown), "Ponle X" de 2 tokens.
- Criterios voz (>=95% end-to-end, args >=95%): end-to-end NO (83.3%),
  args SÍ (100%), unsupported SÍ (0), undo/redo parcial por STT.
  El parser no se modifica tras el protocolo (congelado).

## Fase Custom LM v1 (rama pruning/command-speech-custom-lm) — SIN modificar gramática

Objetivo exclusivo: mejorar transcripción del canal COMMAND con
`SFSpeechLanguageModel`, sin LLMs ni clasificadores, misma gramática congelada.

Orden obligatorio:
1. `data/speech_protocol_v2.csv` creado y congelado (SHA abajo).
2. Datos Custom LM SIN frases exactas de FINAL + leakage 0.
3. `prepare-lm` (una vez; latencia NO cuenta por comando).
4. Grabar cada utterance UNA SOLA VEZ a `data/audio_v2/<id>.wav`.
5. Mismos WAV con BASELINE y CUSTOM → gramática congelada → comparar.

```bash
cd command-grammar
swift run GrammarTest validate-v2  # parse limpio vs esperado (debe ser 100%)
swift run GrammarTest leakage      # 0 coincidencias normalizadas LM vs FINAL
swift run GrammarTest prepare-lm   # export + prepareCustomLanguageModel
swift run GrammarTest dump-lm      # auditoría phrases/templates/config
swift run GrammarTest record-v2    # guía mic, guarda WAVs (no regrabar)
swift run GrammarTest eval-v2      # A/B sobre mismos WAVs + métricas
swift run GrammarTest smoke-ab f.wav  # humo TTS (NO oficial)
```

### Protocolo v2 (congelado)

- `data/speech_protocol_v2.csv`: 180 utterances (V001–V180).
- SHA-256: `6330bb08681a9f967556e78fbbf027cce6bf51ee43b700d69031380ba8583e2a`
- Soportadas 136 (rename 14, delete 10, replace 10, rewrite 8, format 22,
  undo 16, redo 16, find 12, select 10, save 6, open 6, export 6).
- Undo/redo 32, format 22, argumentos 59, unsupported 22, unknown 22.
- `validate-v2` limpio: 180/180 = 100% (aisla errores a STT).
- Columnas: id,category,expected_spoken,expected,argument_expected,challenge.

### Configuración A — BASELINE (idéntica Fase 7B)

- `DictationTranscriber(locale: es_MX, preset: .phrase)`
- `AnalysisContext.contextualStrings` idénticas (commandContext(), sin cambios)
- Sin custom LM.

### Configuración B — CUSTOM LM (idéntica excepto hint)

- Mismo locale `es_MX` (guion bajo), mismo preset `.phrase`,
  mismos `contextualStrings`.
- Único cambio: `var p = Preset.phrase; p.contentHints.insert(.customizedLanguage(modelConfiguration: cfg))`
  + `DictationTranscriber(locale:contentHints:transcriptionOptions:reportingOptions:attributeOptions:)`
  con los mismos options del preset.
- Conexión documentada en `TranscribeAB.swift`.

### Custom LM v1 (una sola configuración, sin tuning post-FINAL)

- Locale: `es_MX` (igual que transcriber).
- `SFCustomLanguageModelData(locale: es_MX, identifier: com.editor.commands.v1, version: 1.0)`
- `PhraseCount`: 95 entradas (conteos 6–15; alto para deshaz/rehaz/format).
- Templates: 12 (`TemplatePhraseCountGenerator` + `define(class:values:)`),
  1 clase por template, 3–5 valores cada una → 50 expandidas.
- Total aprox: 145 frases, vocab unigramas aprox 143.
- Weight: `0.6` (moderado a priori; evita sesgar unsupported/unknown).
- Training: `export(to:)` → asset 4858 bytes (2.3 ms), generación 0.3 ms.
- `SFSpeechLanguageModel.prepareCustomLanguageModel(for:configuration:ignoresCache:true)`:
  744.7 ms, LM 8870069 bytes, vocab 3860 bytes (NO cuenta por comando).
- Auditoría: `data/custom_lm/phrases.txt`, `templates.txt`, `config.json`, `asset.bin`.
- Compilado en `data/custom_lm_compiled/` (regenerable; no se versiona por tamaño).
- Leakage: `LEAKAGE_OK 0` (normalizado lower+folding+sin puntuación).

### Gramática congelada

- `Grammar.swift` SHA-256: `ab31d616398d436ad4f6c4e126d97a0e48d2a43f151ef1333bf7df5b943530e2`
  (base commit `1e8b943`).
- `Types.swift` SHA-256: `df57355...` (sin cambios funcionales).
- Si cambia funcionalmente: `EXPERIMENT_INVALID_GRAMMAR_CHANGED`.

### Evaluación (voz humana 180/180, mismos WAVs A/B — FINAL)

- `data/audio_v2/`: 180 WAVs (V001–V180, 81 MB, mismos archivos para A y B).
- `data/eval_v2_results.csv`: 180 filas + `data/eval_v2_console.log`.
- Métrica primaria E2E: baseline 161/180=89.4%, custom 162/180=90.0% (+0.6 pp, reducción error 5.3%).
- WER mismos audios: baseline 14.4% (94/655), custom 14.2% (93/655) (+0.2 pp, relativa 1.1%).
- Pareada: B✓C✓ 161, B✗C✓ 1 (V082 `Rehaz eso`: `Reto`→`Rehaz esto`), B✓C✗ 0, B✗C✗ 18.
- `CUSTOM_LM_REGRESSIONS`: 0 = 0.0% (≤2% ✓).
- Challenges: UNDO/REDO 75.0%→78.1%, FORMAT 90.9%→90.9%, FIND/SELECT 90.9%→90.9%, SAVE/EXPORT 100%→100%, SHORT 88.5%→92.3%, ARGUMENTS 88.1%→88.1%.
- Argumentos: EXACT 149/149, CASE 8/8, MINOR 6/6, WRONG 17/17; aceptable 163/180=90.6% ambos (<95% ✗).
- Safety: unsupported→supported 0/0 ✓; unknown→supported 1/1 ✗ (V173 `Borrar...`→`Borra...`→delete, idéntico en A y B, inducido por STT, no por LM).
- Latencias: STT baseline mean 198 med 193 p95 223; custom mean 195 med 192 p95 218. Parser ~0.06 ms. Sin overhead significativo.
- Criterios valor real: E2E ≥95% NO (90.0%), safety 0/1 NO, args ≥95% NO (90.6%), regresiones SÍ (0%). Preferido WER<8% NO, undo/redo ≥95% NO (78.1%).
- Veredicto: el Custom LM v1 NO aporta valor real. Una sola corrección (V082), cero regresiones, pero mejora marginal. NO modificar gramática/weight/frases ni regrabar (reportar y detener).
- Fallos persistentes: `deshace` por `deshaz` (V066/V068), `Fea hazlo` (V083), `Aplicar el formato` sin `re-` (V086), `Les haz el deshacer` (V089), `desecho` por `deshecho` (V090), `Haya` por `Halla` (V103), `Te limita` por `Delimita` (V118), `Central` por `Centra` (V154), rename con `a` elidida (V005/V006) y `cite`→`si te` (V012).

### Estado actual (FINAL completo)

- [x] Rama, protocolo 180 + SHA, validación 100%, leakage 0, LM preparado.
- [x] Humo TTS (NO oficial).
- [x] `record-v2` voz humana (180/180 WAVs).
- [x] `eval-v2` + entrega 32 puntos. DETENIDO (no conectar editor real).

## Fase Alternatives+Confidence (rama prueba/speech-alternatives-confidence)

Pregunta: ¿la interpretación correcta aparece entre las alternativas de
`DictationTranscriber` cuando el Top-1 falla? ¿confidence separa correctos?

Base congelada: commit `1e8b943`, `Grammar.swift` `ab31d6…530e2`,
`Types.swift` `df5735…` (verificado al inicio; sin cambios).
Mismos 180 WAVs Fase 8, sin regrabar. Sin baseline como experimento principal.

```bash
cd command-grammar
swift run GrammarTest eval-alts  # CUSTOM LM + alternatives + confidence, 180 WAVs
```

Config (`Alternatives.swift`): `Locale es_MX`, `Preset.phrase` + hint
custom LM (weight 0.6) + `reportingOptions [.alternativeTranscriptions]` +
`attributeOptions [.transcriptionConfidence]` (resto del preset intacto),
mismo `commandContext()`. Confidence = media de runs con atributo
`transcriptionConfidence` (nil si ausente; nil = reject en thresholds).

Hallazgos SDK (macOS 27): los flags segmentan más fino (Fase 8: 1 segmento;
ahora hasta 4; 47/180 multi-segmento, 2 con 0 segmentos). Top-1 utterance =
concatenación en orden de rango. N-best utterance solo si 1 segmento
(alt_1..alt_5 en orden, sin reordenar/dedup/combinar). Multi-segmento se
registra por segmento (`segment_alternatives.csv`). Top-2={top1,alt1},
Top-3={top1,alt1,alt2}, Top-5=todo lo registrado. STRONG: expected ≥2 y ningún
otro soportado ≥2; MIXED: expected ≥1 sin ser STRONG; NONE: ausente.

Resultados (`alternatives_results.csv`, `confidence_analysis.csv`,
`error_recovery.csv`):
- Top-1 161/180=89.4% (Fase 8 custom dio 162; V082 cambió entre corridas:
  no-determinismo documentado, sin re-correr para elegir).
- Top-2 161, Top-3 162/180=90.0%, Top-5 162. Transcript oracle 121 en K=2/3/5.
- Failures 19 (los 18 de Fase 8 + V082). Recovery Top-2 0, Top-3 1, Top-5 1
  (V082 `Reto`→alt2 `Rehaz esto`), never 18. STRONG 0, MIXED 1, NONE 18.
- Alts utterance: mean 0.77, min 0, max 4 (mayoría duplican top1 o vacías).
- Confidence: correct median 0.953 (n=159), incorrect 0.703 (n=19, 2 nil).
  Thresholds: ningún t da accepted ≥98% con coverage ≥50% (t=0.95: 97.6% @46.1%;
  t=0.90: 95.6% @63.3%).
- Safety: unsupported→supported 0/0/0; unknown 1/1/1 (V173, desde el propio
  top1, igual que Fase 8; ninguna alternativa inferior introduce soportadas).
- Challenges (Top1→Top5): UNDO/REDO 24→25, SHORT 23→24, resto plano.
- Argumentos (59 con arg): 0 mejoradas por alternativas (EXACT 28, CASE 8,
  MINOR 6, WRONG 17 idénticos).
- Criterios: Top-3 ≥95% NO (90.0%); ≥50% failures STRONG NO (0%);
  confidence útil NO. Escenario C: Top-5 casi no mejora → dejar de optimizar
  recognizer + UX de repeat/confirmation. Sin auto-resolve ni gates.

## Fase Confirmation UX (rama prueba/command-confirmation-ux)

Capa DESPUÉS de Speech→Grammar→ParsedCommand. Sin mejorar reconocimiento,
sin tocar Speech ni Grammar (base `1e8b943`, SHA verificados). Sin
alternatives/confidence para decidir (solo diagnóstico). Sin Foundation
Models (rewrite simulado), sin editor real (FakeEditorState + historial
undo/redo). Política: ALL SUPPORTED REQUIRE CONFIRMATION.

```bash
cd command-grammar
swift run GrammarTest confirm-tests  # 352 tests + invariante seguridad
swift run GrammarTest sim-19         # 19 fallos reales, sin retranscribir
swift run GrammarTest confirm-live   # protocolo manual 30 (requiere humano+mic)
```

Componentes (`ConfirmationUX.swift`): `FakeEditorState` (title/text/selección/
doc + undo/redo stacks + rewrite log + find/save/export), `CommandProposal`
(transcript+command+preview+riesgo), `CommandInteractionState`
(idle/listening/recognized/unsupported/notUnderstood/invalidContext/executed/
cancelled), validador (`No hay texto seleccionado.` / `Nada que deshacer.` /
`Nada que rehacer.`), `CommandRisk` (metadato NO operativo). Solo Enter
confirma (`NO CONFIRMATION = NO STATE CHANGE`); Esc cancela; R repite sin
combinar (attempts, descarta transcript). Mensajes: unsupported
"Ese comando no está disponible.", unknown "No entendí el comando.", multi
"Prueba una acción a la vez.". UI mínima: overlay de terminal en
`confirm-live` (Listening…/Reconocido/Enter/Esc/R; sin SwiftUI: paquete CLI
sin host de app).

Tests 352/352 (`ConfirmationTests.swift`): confirm 60, cancel 36, repeat 20,
invalid-context 40, unknown/unsupported/multi 50, undo/redo 40, argumentos 30,
riesgo-política 24, rewrite-simulado 12, barrido-cancel 40. Invariante
verificado por test (`SAFETY-INVARIANTS-OK`): unconfirmed/cancelled/
unsupported/unknown/invalid-context changes = 0.

sim-19 (`data/ux_sim19.csv`, editor generoso peor caso): A→unknown 18
(repeat), B→unsupported 0, C→SUPPORTED ERRÓNEO 1 (V173 `Borra…`→deleteSelection).
Sin confirmación: 1 efecto incorrecto. Con confirmación ideal: 0.
Supported confirmed success: 352-tests confirman efectos + previews (≥98% ✓
estructural sobre FakeEditorState).

Live (`data/confirmation_live_protocol.csv`: 20 normal + 5 repeat + 5 cancel;
runner con timings speech-end→proposal/proposal→decisión/total;
`confirmation_live_results.csv`): EJECUTADO 2026-09-23, 30/30 voz humana.
Decisiones: 24 confirm, 6 repeat, 0 cancel (desvíos de modo: L26/L28
modo=cancel pero confirmados; L03–L05 modo=normal pero repetidos). Efectos
ejecutados 17, todos correctos o inocuos (L08 arg truncado en texto vacío);
0 incorrectos. No-op absorbidos 7 (L07/L10/L12 invalid-context por estado
persistente tras el borrado de L02; L18/L22 unknown; L29 unsupported; L30
unknown). Repeats: STT real (Deshace, TTAH, Pone, Crea haz hazlo) + L03/L21
exploratorios. Tiempos ms: STT med 228 (L01 506 warmup); proposal≈STT
(artefacto); decisión med 2197 p95 7739; total med 2422. Confirms/efecto
24/17=1.41; repeat 20%, cancel 0%. Friction baseline ≈2.4 s/comando.
Recomendación: Fase 10 risk-based (navigation→inmediato,
reversible→inmediato+Undo, content/external→confirm). DETENIDO.

## Fase Risk-Based (rama prueba/risk-based-confirmation)

Política post-ParsedCommand: navigation (find/select) + reversible con
contexto válido (undo/redo/format) → inmediato con feedback; content
(rename/delete/replace/rewrite) + external (save/open/export) → confirm;
unknown/unsupported/multi/invalid → sin confirmación ni ejecución.
Speech/Grammar/LM/parsing/FM intactos (SHA verificados).

```bash
cd command-grammar
swift run GrammarTest risk-tests    # 406 tests + invariantes
swift run GrammarTest sim-19-risk   # 19 fallos bajo risk-based, sin retranscribir
swift run GrammarTest risk-live     # protocolo 40 (requiere humano+mic)
```

Cambios: `RiskPolicy.swift` (policy, feedback ✓, AUTO_EXECUTED log,
`RiskBasedSession`: ParsedCommand→Validator→Policy; inválidos jamás llegan
a confirm). Logger Fase 9 corregido (proposal pre-decisión; speech_start/end,
stt/proposal_generation/decision/execution/total independientes; sin cambio
de comportamiento). Estados existentes reutilizados (`.executed` + log
`auto_executed` vs `executed`).

Tests 406/406 (`RiskTests.swift`): mapping 30 (UNMAPPED… si falta), nav 120,
reversible+format 64, content/external 70, no-ops 60, rollback 50
(format→undo 100%), guardas 12. Invariantes: inmediato solo si
supported+válido+immediate; 0 efectos en resto.

sim-19-risk (`data/ux_risk_sim19.csv`): NO EFFECT 18, SAFE IMMEDIATE 0,
WRONG IMMEDIATE 0, CONFIRMABLE WRONG 1. V173 delete=contentChanging→confirm,
auto=false ✓. Objetivo `wrong content modifications = 0` ✓.

Live (`data/risk_live_protocol.csv`: 10 nav + 10 rev + 10 content + 5 ext +
5 error; `risk_live_results.csv` con command/risk/policy y 5 tiempos):
PENDIENTE humano. Criterios: wrong-auto 0, inválidos 0, éxito ≥98%,
fricción < 2422 ms med / 1.41 conf/efecto. DETENIDO sin editor real.
