# EditorFinal

Editor nativo con edición Markdown, lectura y herramientas de concentración. Desarrollo y validación en macOS 27, destino mínimo macOS 26. Swift 6, SwiftUI, NSTextView y TextKit 2. Sin dependencias externas.

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
- Navegación por Inicio, Recientes, Favoritos, Archivado, Borradores y Basura. Las carpetas se obtienen de las ubicaciones reales de los documentos recientes; las notas aparecen en la columna central, no en el sidebar. El botón Volver de la barra superior, ⌘[, regresa a la última pantalla vista (la lista de notas anterior o la nota abierta).
- Concentración con ⇧⌘F, foco del párrafo con ⌥⌘F y máquina de escribir con ⌥⌘T.
- Títulos, negrita, cursiva y código con formato durante la edición. La vista de lectura, ⇧⌘R, oculta los marcadores sin cambiar el archivo. Al volver a editar se conserva la selección.
- Preferencias persistentes de fuente, tamaño, interlineado, ancho, apariencia y estadísticas. El índice y el conteo se actualizan tras una pausa de escritura.
- Menú Formato con negrita, cursiva, código, títulos, lista, cita y enlace. Repetir negrita o cursiva retira los marcadores de la selección.
- Imprimir o guardar PDF con ⌘P mediante el diálogo de macOS. El PDF usa texto negro y conserva los títulos con el párrafo siguiente al paginar.
- Sandbox con acceso a archivos elegidos por el usuario e impresión. No solicita red. El micrófono y el reconocimiento de voz solo se piden al usar el dictado por voz (⌃⌘V), que es una pieza extraíble: sin ella no se piden esos permisos.
- Gestos con la cámara desde el botón de la mano en la barra: mano abierta para elegir palabra, pinza quieta para sinónimos locales (suelta para confirmar), pinza + barrido lateral para deshacer/rehacer, dos manos para la longitud del párrafo (retira una para confirmar). “Probar sin cámara” abre las mismas tarjetas sin pedir permiso. La cámara solo se pide al activarla y todo se procesa en el Mac. Ver `Docs/Integracion.md` para quitar la pieza.
- Dictado local con el micrófono de la barra (⌃⌘V): habla, pulsa Insertar y el texto entra al documento con limpieza local. Comandos: “nueva línea”, “nuevo párrafo”, “deshacer”, “borra eso”, “cancelar”. Ver `Docs/Integracion.md` para quitar la pieza.

El formato cubre títulos ATX (incluido cierre `##`) y setext, código con cercas o sangría, listas con viñetas, ordenadas y de tareas, citas (`>` con o sin espacio, anidadas), reglas y formato en línea (`**`/`__`, `*`/`_`, `***`, `~~`, código, enlaces, autolinks y escapes). No implementa tablas ni imágenes incrustadas. Los enlaces de lectura solo admiten http, https y mailto.

`EditorCore` contiene comandos, rangos UTF-16 e índice. `EditorEngine` encapsula TextKit. `EditorUI` compone las vistas. `DocumentKit` valida y codifica UTF-8. El adaptador `FileDocument` vive en App, para mantener SwiftUI fuera de DocumentKit. El sistema realiza el I/O de documentos. `ExportFeature` prepara la impresión y el PDF sin intervenir en el motor de edición.

## Verificación

```sh
swift test --package-path Packages/EditorModules
```

Las pruebas cubren Unicode, rangos inválidos, títulos, texto vacío y codificación de documentos de 100 000, 500 000 y 1 000 000 caracteres. También ejecutan inserción, selección, sustitución, formato, undo y redo sobre un NSTextView real. La exportación se verifica con un PDF de varias páginas, incluidos el primer y el último párrafo y los saltos de títulos. La voz se prueba sin micrófono (comandos, limpieza, bus, inserción y silencio). Los gestos se prueban sin cámara (histéresis, calibración, navegación, sinónimos locales) y la preview atómica sobre un NSTextView real (un solo undo al confirmar, restauración al cancelar, edición externa que cancela, bloqueo en lectura). La prueba de codificación de archivos grandes no equivale a una medición de fluidez con Instruments.

## Próximas entregas

1. Medir documentos grandes con Instruments y ampliar pruebas de recuperación, accesibilidad y métodos de entrada.
2. Sesión manual de gestos con cámara real, VoiceOver sobre tarjetas y panel, y contraste aumentado.

La especificación completa está en `Docs/Especificacion.md`. Se conserva como referencia original. La decisión posterior del usuario elimina la compatibilidad con macOS 15 y permite APIs exclusivas de macOS 27.

El mapa de reutilización está en `Docs/Integracion.md`.
