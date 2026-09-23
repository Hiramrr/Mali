# Robustness del Intent Gate (CreateML BERT-es, splits por familias)

Sin Foundation Models. Preguntas: ¿separa bien con familias disjuntas?,
¿threshold por política de seguridad generaliza a un FINAL nunca observado?

```text
FINAL_TEST_V2_SHA256=7983a64d5aa6ac6537241cdfd7d1aeef803d0fc7dcb527952ac711e5684ad6e5
```

## Estructura

```text
intent-gate-v2/
├── Package.swift                 # TrainGate, EvalGate
├── Sources/TrainGate/main.swift  # mismo algoritmo, TRAIN por familias
├── Sources/EvalGate/main.swift   # CAL->threshold->FREEZE->FINAL (+legacy diag.)
├── data/gen_pool.py              # pool con family_id (seed 42)
├── data/pool.csv                 # 1218 (tras excluir legacy)
├── data/final_new.csv            # autoría manual FINAL
├── data/make_splits.py           # checks + split por familias + hash
├── data/train.csv / .json        # 991 (537 C / 454 D, 185 fams)
├── data/calibration.csv / .json  # 227 (122 C / 105 D, 41 fams)
├── data/final_test_v2.csv        # 376 (236 NO / 140 CTL, 83 critical)
├── data/legacy_diagnostic_holdout.csv  # fase 4, SOLO diagnóstico
└── models/IntentGateV2.mlmodel   # 1.3 MB
```

## Reproducir (orden obligatorio)

```bash
cd intent-gate-v2
python3 data/gen_pool.py
python3 data/make_splits.py   # ERROR_DATA_LEAKAGE / ERROR_FAMILY_LEAKAGE si hay fuga
swift run TrainGate
swift run EvalGate
```

## Regla de threshold (congelada)

1. Recall(control) >= 0.95 en CALIBRATION.
2. Minimizar False Control Rate.
3. Empate -> threshold MÁS ALTO.
Candidatos: scores observados en CALIBRATION (+puntos medios).
Scores = scores de ranking, sin asumir calibración.

## Resultado (2026-09-23, macOS 27, Xcode 27)

- Threshold: 0.709 (CAL recall 95.1%, FCR 0.00%).
- FINAL: raw 97.1%, gate 96.0%, FCR 0.85% (2/236, Wilson [0.23, 3.04]),
  missed 13/140 (9.3%), recall gate 90.7% (Wilson [84.8, 94.5]).
- Critical Challenge: 0/83. Legacy diagnóstico: 0/37 passes, 1/25 missed.
- 26/26 pares H separados correctamente.
- Latencia: load 12 ms, media 7.1, mediana 7.0, p95 7.4 ms.
- Criterio (FCR<=2% ✓, CG=0 ✓, recall>=95% ✗ 90.7%): parcial.
