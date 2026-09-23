# Intent Gate V4 (EDITOR_CONTROL / NON_CONTROL)

Última fase aislada del gate. Sin Foundation Models.

```text
FINAL_TEST_V4_SHA256=e52b908271debce4e82fc413062f08c2d999a72282b052633ff076bcf100337e
```

## Estructura

```text
intent-gate-v4/
├── Package.swift, Sources/{TrainGate,EvalGate}
├── data/pool_v2.csv, pool_v3.csv (reutilizados, misma family_id)
├── data/gen_new.py + pool_new.csv (472 nuevos)
├── data/assemble_pool.py  # binariza, dedupe, excluye observados
├── data/pool.csv          # 3227 (C1567/N1660, 693 fams)
├── data/final_new.csv     # autoría manual (810)
├── data/make_splits.py    # checks + split + hash
├── data/{train,calibration}.csv/.json  # 2657 / 570
├── data/final_test_v4.csv # 810 (NON410/CTL400)
├── data/obs_{legacy,v2final,v3final}.csv (regresión diagnóstica)
└── models/IntentGateV4.mlmodel (1.3 MB)
```

## Reproducir

```bash
cd intent-gate-v4
python3 data/gen_new.py && python3 data/assemble_pool.py && python3 data/make_splits.py
swift run TrainGate   # transferLearning BERT rev1, español
swift run EvalGate    # T_CONTROL -> FREEZE -> FINAL + regresión
```

## Regla

Candidatos con Control Recall >= 97% en CALIBRATION; mín FCR; empate->max.
Fallback documentado (no fue necesario). Salida: PASS_TO_COMMAND_INTERPRETER
(score >= T) o DO_NOT_PASS.

## Resultado (2026-09-23, macOS 27, Xcode 27)

- T_CONTROL 0.777 (CAL recall 97.1%, FCR 3.08%).
- Raw 93.33% (C P96.0/R90.2, N P91.0/R96.3).
- FCR 11/410 = 2.68% [1.50, 4.74]. Gate recall 324/400 = 81.0% [76.9, 84.5].
- Critical 7/220 [1.55, 6.42]. Coverage 147/175 = 84.0% [77.8, 88.7].
- Pares 34/40. Short: sin categoría corta en FINAL (gap); E conversacional 48/50.
- Regresión V2: 3/236 passes, 18/140 missed. V3: 14/367, 25/187.
- Latencia: load 16 ms, media 6.8, mediana 6.8, p95 6.9 ms. RSS pico 532 MB.
- Criterio (FCR<=1% ✗, recall>=95% ✗, CG=0 ✗ 7, cobertura>=95% ✗ 84%):
  NO alcanzado. Sin Fase 4E: se entrega y se detiene.
