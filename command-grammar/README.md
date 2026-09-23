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
