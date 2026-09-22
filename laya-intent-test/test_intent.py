"""Prueba aislada de laya-mlx como clasificador de intención.

Clasifica frases en DICTATION / COMMAND / AMBIGUOUS usando únicamente
la decisión tipada (`choice`) de Laya. No hay heurísticas de palabras
clave ni otro LLM: la decisión la toma realmente Laya.

Uso:
    python test_intent.py
"""

import os
import statistics
import sys
import time

MODEL_ID = os.environ.get("LAYA_MODEL", "aac6fef/laya-multilingual-mlx")

LABELS = ("DICTATION", "COMMAND", "AMBIGUOUS")

# Pregunta tipada que se envía a Laya. El diseño del prompt (instrucciones
# y descripciones de cada opción) es la única ingeniería permitida: la
# clasificación la calcula el encoder bidireccional de Laya, sin reglas
# `if "palabra" in texto` en este archivo.
INTENT_QUESTION = {
    "type": "choice",
    "instructions": (
        "Clasifica la intencion de la frase del usuario en un editor "
        "de texto controlado por voz. "
        "Responde DICTATION si la frase es contenido que el usuario quiere "
        "escribir o dictar en el documento (texto expositivo o declarativo, "
        "sin orden al editor). "
        "Responde COMMAND si la frase es una orden clara y ejecutable "
        "dirigida al editor o al documento (modificar, borrar, formatear, "
        "deshacer, seleccionar o poner titulo, con accion y objetivo "
        "identificables). "
        "Responde AMBIGUOUS si la frase es vaga, incompleta o sin referente "
        "claro y no se puede ejecutar ninguna modificacion con seguridad "
        "(por ejemplo pronombres sin antecedente como eso, lo o esa parte)."
    ),
    "criteria": {
        "DICTATION": (
            "contenido para escribir o dictar en el documento; "
            "texto expositivo o declarativo sin orden al editor"
        ),
        "COMMAND": (
            "orden clara y ejecutable al editor o al documento, "
            "con accion y objetivo identificables"
        ),
        "AMBIGUOUS": (
            "frase vaga o incompleta sin referente claro; "
            "no se puede ejecutar ninguna accion con seguridad"
        ),
    },
}

TESTS = [
    ("La interacción humano computadora permite estudiar la relación entre usuarios y sistemas.", "DICTATION"),
    ("Cambia el título a Metodología.", "COMMAND"),
    ("Borra esta oración.", "COMMAND"),
    ("Durante los últimos años se han desarrollado nuevos sistemas interactivos.", "DICTATION"),
    ("Pon esto en negritas.", "COMMAND"),
    ("Cámbialo.", "AMBIGUOUS"),
    ("Mi proyecto consiste en desarrollar un editor multimodal.", "DICTATION"),
    ("Haz este párrafo más corto.", "COMMAND"),
    ("Eso no.", "AMBIGUOUS"),
    ("Deshaz eso.", "COMMAND"),
    ("Las interfaces multimodales permiten combinar voz, teclado y gestos.", "DICTATION"),
    ("Cambia esta palabra por accesibilidad.", "COMMAND"),
    ("Mejor así.", "AMBIGUOUS"),
    ("Pon como título Arquitectura del sistema.", "COMMAND"),
]


def classify(agent, text):
    """Devuelve (etiqueta, probabilidades, latencia_ms) según Laya."""
    start = time.perf_counter()
    result = agent.predict(text, {"intent": INTENT_QUESTION})
    latency_ms = (time.perf_counter() - start) * 1000.0
    answer = result["answers"]["intent"]
    label = answer["choice"]
    probs = {k: float(answer["probabilities"].get(k, 0.0)) for k in LABELS}
    return label, probs, latency_ms


def run_automatic_tests(agent):
    latencies = []
    correct = 0
    per_class_ok = {label: 0 for label in LABELS}
    per_class_total = {label: 0 for label in LABELS}
    wrong_cases = []

    for text, expected in TESTS:
        per_class_total[expected] += 1
        predicted, probs, latency_ms = classify(agent, text)
        latencies.append(latency_ms)
        ok = predicted == expected
        if ok:
            correct += 1
            per_class_ok[expected] += 1
        else:
            wrong_cases.append((text, expected, predicted))

        print("INPUT:")
        print(text)
        print()
        print("EXPECTED:")
        print(expected)
        print()
        print("PREDICTED:")
        print(predicted)
        print()
        print("SCORES:")
        for label in LABELS:
            print(f"{label}: {probs[label]:.4f}")
        print()
        print(f"Latency: {latency_ms:.1f} ms")
        print()
        print("✓ CORRECT" if ok else "✗ WRONG")
        print("-" * 50)

    total = len(TESTS)
    accuracy = 100.0 * correct / total if total else 0.0

    print("=============================")
    print("RESULTADOS")
    print("=============================")
    print()
    print(f"Correctas: {correct}/{total}")
    print(f"Accuracy: {accuracy:.1f}%")
    print()
    for label in LABELS:
        print(f"{label}:")
        print(f"{per_class_ok[label]}/{per_class_total[label]}")
        print()
    if wrong_cases:
        print("Casos incorrectos:")
        for text, expected, predicted in wrong_cases:
            print(f"- {text!r} esperado={expected} predicho={predicted}")
        print()
    else:
        print("Casos incorrectos: ninguno")
        print()
    print(f"Average latency: {statistics.mean(latencies):.1f} ms")
    print(f"Median latency: {statistics.median(latencies):.1f} ms")

    return latencies


def run_interactive(agent):
    print()
    print("Prueba interactiva. Escribe 'exit' para salir.")
    print()
    latencies = []
    while True:
        print("Escribe una frase:")
        try:
            text = input("> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if text.lower() == "exit":
            break
        if not text:
            continue
        predicted, _, latency_ms = classify(agent, text)
        latencies.append(latency_ms)
        print()
        print(f"Intent: {predicted}")
        print(f"Latency: {latency_ms:.1f} ms")
        print()
    if latencies:
        print(f"Average latency: {statistics.mean(latencies):.1f} ms")
        print(f"Median latency: {statistics.median(latencies):.1f} ms")


def main():
    import laya_mlx as laya

    print(f"Cargando modelo: {MODEL_ID} ...")
    start = time.perf_counter()
    agent = laya.load(MODEL_ID)
    print(f"Modelo cargado en {(time.perf_counter() - start):.1f} s")
    print()

    run_automatic_tests(agent)
    run_interactive(agent)


if __name__ == "__main__":
    sys.exit(main())
