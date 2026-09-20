# EditorFinal

Primera entrega del editor nativo. Desarrollo y validación en macOS 27, destino mínimo macOS 26. Swift 6, SwiftUI, NSTextView y TextKit 2. Sin dependencias externas.

## Ejecutar

Abre `EditorFinal.xcodeproj` y ejecuta el esquema EditorFinal. También puedes compilar desde esta carpeta:

```sh
xcodebuild -project EditorFinal.xcodeproj -scheme EditorFinal -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/EditorFinal.app
```

Para ver un documento de ejemplo:

```sh
open -a "$PWD/build/Build/Products/Debug/EditorFinal.app" "$PWD/Samples/Felis catus.md"
```

## Alcance de esta entrega

- Crear, abrir y guardar `.md` y `.txt` UTF-8 con el ciclo de documentos de SwiftUI. DocumentGroup gestiona autosave, cierre y recuperación mediante el sistema de macOS.
- Edición nativa con selección, copiar, pegar, deshacer, rehacer y búsqueda del sistema.
- Navegación lateral, índice de títulos Markdown y vista de archivos recientes inspirados en la captura. No hay carpetas, favoritos o papelera ficticios.
- Concentración con ⇧⌘F, tamaño de texto persistente y colores del sistema para claro y oscuro.
- Formato Markdown con ⌘B y ⌘I. Por ahora los marcadores son visibles. No es todavía un editor visual de Markdown ni muestra imágenes incrustadas.
- Sandbox con acceso de lectura y escritura a archivos elegidos por el usuario. No solicita cámara, micrófono ni red.

`EditorCore` contiene comandos, rangos UTF-16 e índice. `EditorEngine` encapsula TextKit. `EditorUI` compone las vistas. `DocumentKit` valida y codifica UTF-8. El adaptador `FileDocument` vive en App, para mantener SwiftUI fuera de DocumentKit. El sistema realiza el I/O de documentos.

## Verificación

```sh
swift test --package-path Packages/EditorModules
```

Las pruebas cubren Unicode, rangos inválidos, títulos, texto vacío y codificación de documentos de 100 000, 500 000 y 1 000 000 caracteres. También ejecutan inserción, selección, sustitución, formato, undo y redo sobre un NSTextView real. La prueba de codificación de archivos grandes no equivale a una medición de fluidez con Instruments.

## Próximas entregas

1. Afinar edición y presentación Markdown, probar recuperación y rendimiento con Instruments, ampliar pruebas de accesibilidad y UI.
2. Foco de línea, modo máquina de escribir y preferencias de lectura.
3. Integrar voz de LocalFlow mediante comandos. Después, gestos de EditorTDAH con calibración.

La especificación completa está en `Docs/Especificacion.md`. Se conserva como referencia original. La decisión posterior del usuario elimina la compatibilidad con macOS 15 y permite APIs exclusivas de macOS 27.

El mapa de reutilización está en `Docs/Integracion.md`.
