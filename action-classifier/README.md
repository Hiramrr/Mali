# Action Classifier (15 clases, CreateML BERT-es, sin thresholds)

Solo clasifica la acción (top-1). Sin argumentos, sin FM, sin tools.

## Reproducir

```bash
cd action-classifier
python3 data/gen_pool.py && python3 data/make_splits.py
swift run TrainGate
swift run EvalGate
./.build/debug/Regression models/ActionClassifier.mlmodel regression_p5.csv regression_p6.csv
```

FINAL_ACTION_TEST_SHA256=[ver FINAL_SHA256.txt]

## Resultado (2026-09-23, macOS 27, Xcode 27)

- Top-1: 68.64% (858/1250). Macro F1: 0.6623.
- Supported: 60.38%. UnsSub: 11.43% [7.80, 16.44].
- NoAction false: 6.00%. Multi false-single: 0.91%.
- REDO->UNDO 9.2%. Confusable 66.7%. Paraphrase 55.0%. Short 36.4%.
- CAL 86.3%. P5 92.2%. P6 74.5%.
- Latencia med 6.9 ms. Modelo ~1.3 MB.
- Criterios: ninguno alcanzado. Sin Fase 4E: se reporta y detiene.
