# Fase 4: intent gate con CreateML (`MLTextClassifier` + BERT, español)

Compuerta DICTATION / EDITOR_CONTROL. Sin Foundation Models, sin LLM,
sin keywords. Solo `USER UTTERANCE` como feature.

## Estructura

```text
intent-gate/
├── Package.swift                 # targets TrainGate, EvalGate
├── Sources/TrainGate/main.swift  # split + entrenamiento
├── Sources/EvalGate/main.swift   # threshold (validation) -> freeze -> holdout
├── data/gen_dataset.py           # generador determinista (seed 42)
├── data/dataset.csv / .json      # 1181 ejemplos
├── data/holdout.csv              # 62 casos (única fuente para check y eval)
└── models/IntentGate.mlmodel     # modelo entrenado (1.4 MB)
```

## Reproducir

```bash
cd intent-gate
python3 data/gen_dataset.py   # genera + leakage check (falla si hay dups)
swift run TrainGate           # entrena (~45 s), guarda modelo + validation.csv
swift run EvalGate            # threshold en validation, freeze, holdout
```

## Algoritmo exacto

- `MLTextClassifier.ModelParameters(validation: .table(...), algorithm: .transferLearning(.bertEmbedding, revision: 1), language: .spanish)`
- Resto de parámetros: valores por defecto del framework.
- Split: estratificado 80/20, RNG propio con seed 42 (train 944: 443 control + 501 dict; validation 237: 111 + 126).

## Dataset

1181 ejemplos (554 CONTROL / 627 DICTATION; hard negatives 25.2% del dictado).
43 frases excluidas en generación por coincidir con holdout; check final 0 dups.
Fragmentos conversacionales etiquetados DICTATION (decisión documentada: el
binario obliga a elegir y lo seguro es alejarlos del control).

## Threshold (solo validation, congelado)

`Selected threshold: 0.11` — Validation FPR 1.59%, recall 100%.
Regla: entre thresholds con FPR<=2%, el de mayor recall (empate -> menor
threshold). Estrategia de zona: single-threshold; bajo el umbral todo es
`NO_CONTROL_GATE` (UNCERTAIN plegado ahí; el label raw se imprime siempre).

## Resultado holdout (2026-09-23, macOS 27, Xcode 27)

- Raw accuracy 100% (54/54). Control P/R 100/100. Dictation P/R 100/100.
- False passes 2/37 = 5.41%. Missed 0/25. Critical group 0/6.
- F1 `Cambiar el título mejora la claridad.` (c=0.115), H5 `Así está bien.` (c=0.370).
- Criterio (FPR<=2%, CG=0, recall>=90%): FPR **no alcanzado** (5.41%), resto sí.
- Análisis (solo informativo): thr 0.50/0.70 -> FPR 0% + recall 100% en holdout.
- Latencia inferencia: media 7.0, mediana 7.0, p95 7.1 ms. Carga ~instantánea.
- .mlmodel 1.4 MB, compilado 1.4 MB, RSS ~161 MB.
- Diagnóstico: en validation el control mínimo puntuó 0.614 y el dictado
  máximo 0.432 (`Más o menos`); el empate de recall al 100% resolvió al
  threshold factible más bajo (0.11), que el holdout reveló demasiado permisivo.
