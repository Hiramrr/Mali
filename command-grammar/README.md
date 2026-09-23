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

### Evaluación (pendiente voz humana)

- `data/audio_v2/`: WAV/PCM mono, un archivo por utterance, mismos archivos para A y B.
- `data/eval_v2_results.csv`: columnas id,expected_spoken_text,expected_command,
  audio_file,baseline_transcript,baseline_wer,baseline_parsed_command,baseline_correct,
  custom_transcript,custom_wer,custom_parsed_command,custom_correct,
  argument_expected,baseline_argument,custom_argument (+ stt/parse ms).
- Métrica primaria: END-TO-END COMMAND ACCURACY (audio→STT→gramática).
- Pareada: B✓C✓, B✗C✓, B✓C✗ (=CUSTOM_LM_REGRESSIONS), B✗C✗.
- Argumentos: EXACT / CASE_ONLY_DIFFERENCE / MINOR_STT_ERROR / WRONG (reglas, sin LLM).
- Safety: unsupported→supported = 0, unknown→supported = 0.
- Latencias: STT (end-of-audio→transcript), parser, E2E; mean/median/p95 por condición.
- Criterios valor real: E2E ≥95%, safety 0/0, args aceptable ≥95%,
  regresiones ≤2%, preferido WER <8%, undo/redo ≥95%.
- Si falla: NO cambiar gramática/weight/frases ni regrabar; reportar y detener.
- Si funciona: DETENERSE (siguiente experimento: Preview/Confirmation, no editor real).

### Estado actual (código listo, audio pendiente)

- [x] Rama, protocolo 180 + SHA, validación 100%, leakage 0, LM preparado.
- [x] Humo TTS (NO oficial): `Deshaz eso`→`Les hace eso` en A y B; `Ponlo en negritas` OK en ambos.
- [ ] `record-v2` voz humana (0/180 WAVs).
- [ ] `eval-v2` + entrega 32 puntos.
