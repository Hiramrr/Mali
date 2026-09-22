# Prueba aislada de intención con `laya-mlx`

Prueba mínima en Python para comprobar si
[Laya](https://github.com/mizorewww/laya-mlx) puede servir como
clasificador de intención para un editor controlado por voz.

Clasifica cada frase en exactamente una de estas tres intenciones:

- `DICTATION`: contenido que el usuario quiere dictar/escribir en el documento.
- `COMMAND`: orden clara y ejecutable dirigida al editor o al documento.
- `AMBIGUOUS`: frase vaga o sin referente claro; no debe ejecutarse nada.

La decisión la toma realmente Laya mediante una pregunta tipada `choice`.
No hay heurísticas de palabras clave ni otro LLM.

## 1. Cómo instalar las dependencias

Requisitos: Mac con Apple Silicon, macOS 14+, Python 3.11+.

```bash
cd laya-intent-test
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

`requirements.txt` contiene `laya-mlx` (que a su vez instala `mlx` y
`huggingface-hub`). No se necesita PyTorch, Transformers en runtime ni
ninguna API en la nube.

## 2. Cómo descargar/cargar el modelo necesario

La primera ejecución descarga el checkpoint automáticamente desde
Hugging Face (caché local en `~/.cache/huggingface`). Para pre-descargarlo:

```bash
hf download aac6fef/laya-multilingual-mlx
```

El script carga el modelo con:

```python
import laya_mlx as laya
agent = laya.load("aac6fef/laya-multilingual-mlx")
```

Para usar otro checkpoint (por ejemplo el inglés `aac6fef/laya-mlx`):

```bash
LAYA_MODEL=aac6fef/laya-mlx python test_intent.py
```

## 3. Cómo ejecutar la prueba

```bash
python test_intent.py
```

El programa primero ejecuta 14 tests automáticos (con etiqueta esperada,
predicción de Laya, probabilidades y latencia por caso, más resumen final)
y después entra en modo interactivo:

```text
Escribe una frase:
> cambia el título a Introducción

Intent: COMMAND
Latency: 8.3 ms
```

Escribe `exit` (o Ctrl-D) para terminar.

## 4. Qué modelo de Laya se está utilizando

- Checkpoint: **`aac6fef/laya-multilingual-mlx`**
  (conversión MLX publicada del checkpoint `convaiinnovations/laya-multilingual`).
- Encoder: mmBERT-base, **322M parámetros**, límite de contexto 1024 tokens.
- Precisión: FP16 (valor por defecto de `laya.load`).
- Se usa el checkpoint multilingüe porque las frases de prueba están en
  español; el propio repositorio indica que los checkpoints ingleses no son
  sustitutos del multilingüe.

## 5. Cuánta memoria utiliza aproximadamente

- Referencia oficial (`BENCHMARKS.md` del repositorio, M3 Max):
  pico de asignación MLX de **687.6 MiB** para una pregunta corta con el
  checkpoint multilingüe (943.6 MiB con el inglés de 421M).
- Medido en esta máquina (`/usr/bin/time -l`, proceso Python completo):
  **~1.06 GiB** de maximum resident set size
  (~1.23 GiB de peak memory footprint según el contador de macOS).
- En disco, el checkpoint ocupa **659 MB** en `~/.cache/huggingface`.

## 6. Tiempo aproximado de cada clasificación

Cada decisión se mide con `time.perf_counter()` alrededor de
`agent.predict(...)` (se excluye la carga del modelo).

- Referencia oficial (M3 Max, pregunta corta en inglés): mediana **7.39 ms**
  end-to-end con el checkpoint multilingüe.
- Medido en esta máquina (14 tests, Mac Apple Silicon, modelo ya en caché):
  mediana **~23.6 ms**, media **~26.7 ms** por clasificación.
  La primera inferencia en frío es más lenta (~60–140 ms); la carga del
  modelo tarda ~0.6 s con caché caliente (la primera vez descarga 659 MB).

```text
Average latency: 26.7 ms
Median latency: 23.6 ms
```

## 7. Resultado de la prueba (2026-09-22)

Con el prompt en español: **4/14 (28.6%)**, con sesgo fuerte a `AMBIGUOUS`
(DICTATION 0/4, COMMAND 2/7, AMBIGUOUS 2/3). Variantes probadas fuera del
script (experimentos temporales, no incluidos en el repo):

- Instrucciones en inglés, frases en español: **5/14**.
- Pregunta mínima (solo etiquetas): **1/14**.
- Frases traducidas al inglés: **8/14** (los textos expositivos se siguen
  clasificando como `COMMAND` con confianza 0.7–0.8).

Conclusión: no es solo el idioma del prompt; Laya no separa bien
`DICTATION` de `COMMAND` en este dominio (el contenido meta sobre editores
lo confunde). No recomendable como clasificador de intención tal cual.
Detalle completo en el reporte de la sesión.
