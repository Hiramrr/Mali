# Intent Gate V3 (DICTATION / EDITOR_CONTROL / NO_ACTION)

Sin Foundation Models. Taxonomía de 3 clases + salida operacional
(AUTO_DICTATION / AUTO_CONTROL / NO_ACTION / UNCERTAIN) con dos thresholds
de CALIBRATION.

```text
FINAL_TEST_V3_SHA256=4eebb1feaa450f47d4f473ffd6c6e41b109a9c2b5e282f2549288ca270a48eb7
```

NOTA: el hash cambió una vez tras el hash inicial porque 130 filas E/I/J
pasaron de `expected_raw` vacío a `NO_ACTION` explícito (corrección de
etiquetado según la taxonomía; predicciones y thresholds idénticos).

## Estructura

```text
intent-gate-v3/
├── Package.swift, Sources/{TrainGate,EvalGate}
├── data/gen_pool.py        # pool 1986 (C871/D685/N430, 395 fams)
├── data/final_new.csv      # autoría manual FINAL (554)
├── data/make_splits.py     # checks + split por familias + hash
├── data/train.csv/.json    # 1559 | data/calibration.* # 397
├── data/final_test_v3.csv  # 554 (D237/C187/N130)
└── models/IntentGateV3.mlmodel (1.3 MB)
```

## Reproducir

```bash
cd intent-gate-v3
python3 data/gen_pool.py && python3 data/make_splits.py
swift run TrainGate   # transferLearning BERT rev1, español (~72 s)
swift run EvalGate    # T_CONTROL + T_DICTATION -> FREEZE -> FINAL
```

## Política

- T_CONTROL: recall>=95%, mín FCR, empate->max. T_DICTATION: dict-recall>=95%,
  mín Control-as-Dictation, empate->max. Candidatos: scores observados.
- `CONTROL+thr->AUTO_CONTROL; DICTATION+thr->AUTO_DICTATION;
  NO_ACTION->NO_ACTION; resto->UNCERTAIN`.

## Resultado (2026-09-23, macOS 27, Xcode 27)

- T_CONTROL 0.165, T_DICTATION 1.000 (CAL: FCR 3.52%, C-as-D 0%).
- Raw 89.0% (D P96.5/R94.1, C P96.1/R79.7, N P72.0/R93.1).
- FCR 1.63% (6/367, Wilson [0.75, 3.52]). Recall AUTO_CONTROL 79.7% [73.3, 84.8].
- Dangerous insertions 2 (F61, M17) [0.29, 3.82]. False Dictation 0.95%.
- NO_ACTION recall 93.1%. UNCERTAIN 8.5%. Cobertura 61.2%.
- Critical 0/125. Coverage 99/123 (80.5%). Ambigüedad 125/130.
- 32/32 pares H correctos. Legacy diag: 25/25 CONTROL->AUTO.
- Latencia: load 11 ms, media 7.0, mediana 7.0, p95 7.1 ms. RSS pico 302 MB.
- Criterio (FCR<=1% ✗ 1.63, CG=0 ✓, recall>=95% ✗ 79.7, dangerous=0 ✗ 2,
  NO_ACTION>=95% ✗ 93.1, cobertura>=85% ✗ 61.2): no alcanzado.
