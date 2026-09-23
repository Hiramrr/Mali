# Prueba de intención con Foundation Models (fase 2)

Clasifica frases en `DICTATION` / `COMMAND` / `AMBIGUOUS` usando
exclusivamente `SystemLanguageModel.default` con guided generation
(`@Generable`). Sin heurísticas, sin tool calling, sin modificar documentos.

## Requisitos

- Mac Apple Silicon, macOS 26+, Xcode con SDK macOS 26+.
- Apple Intelligence activado y modelo local descargado
  (Ajustes → Apple Intelligence). Sin esto la prueba se detiene.

## Ejecutar

```bash
cd fm-intent-test
swift run
```

43 tests automáticos + modo interactivo (`exit` para salir).

## Estrategia anti-contaminación

Una `LanguageModelSession` nueva por caso, con las mismas instrucciones.
Ninguna prueba ve el historial de otra.

## Instrucciones exactas (una sola vez, sin respuestas de tests)

```text
Clasifica lo que dice el usuario en un editor de texto. Responde con una de estas tres intenciones.
DICTATION: el usuario está dictando contenido para escribirlo en el documento, no pide ninguna acción.
COMMAND: el usuario pide una acción explícita y ejecutable con el contexto disponible del editor, sin necesidad de adivinar nada.
AMBIGUOUS: hay una posible intención de editar, pero falta información esencial para ejecutar una acción con seguridad.
```

Prompt por caso:

```text
CURRENT TITLE:
<introducción>

SELECTED TEXT:
<texto o "none">

USER SAID:
<frase>
```

## Resultado (2026-09-23, macOS 27.0, Xcode 27.0)

- Total: 30/43 (69.8%). DICTATION 14/18, COMMAND 12/14, AMBIGUOUS 4/11.
- False commands: 7 → FCR 24.1%. Missed commands: 2 → MCR 14.3%.
- Latencia: cold start 2430 ms; media 361, mediana 351, p95 398, min 339, max 420 ms.
- Criterio (>=90% y FCR <=5%): **no alcanzado**. Sin prompt engineering posterior.
