# Verificación del editor

Actualizada el 21 de septiembre de 2026. Xcode 27 y SDK macOS 27. Destino mínimo macOS 26.

## Automatizada

`swift test --package-path Packages/EditorModules` ejecuta 69 pruebas XCTest. Cubren codificación, Unicode, índice, rangos, comandos sobre NSTextView, lectura y decoración Markdown (títulos ATX/setext con cierre, citas, listas ordenadas y de tareas, reglas, énfasis `**`/`__`/`*`/`_`/`***`/tachado, código, enlaces, autolinks y escapes, párrafos con saltos suaves), alternancia de formato con undo, exportación PDF multipágina, bus de comandos y registro de módulos, lógica de gestos sin cámara (histéresis, calibración, navegación, sinónimos locales) y preview atómica sobre NSTextView real.

`xcodebuild -project EditorFinal.xcodeproj -scheme EditorFinal -configuration Debug -derivedDataPath build build` compila y firma la app con sandbox. El compilador Swift no reporta advertencias. La herramienta de Xcode AppIntents emite su aviso de metadatos omitidos porque la app no usa AppIntents.

## En la aplicación

- Abrir el ejemplo Markdown y comprobar el índice y los controles con el árbol de accesibilidad.
- Verificar el diseño con una captura en modo oscuro.
- Buscar Cazador con ⌘F y obtener una coincidencia.
- Crear un documento con ⌘N y escribir.
- Guardar con ⌘S en `build/Prueba de guardado.md`.
- Copiar y pegar texto con ⌘C y ⌘V, deshacer con ⌘Z y rehacer con ⇧⌘Z.
- Activar concentración y comprobar que desaparecen ambas columnas laterales.
- Guardar, cerrar y volver a abrir. Comprobar en disco y en el editor que persisten ambas líneas de prueba.

## Lectura, concentración y PDF

- Vista de lectura comprobada visualmente con títulos, énfasis, listas y enlaces. El editor de origen queda oculto también para accesibilidad y el lector recibe el foco.
- Búsqueda nativa disponible en la vista de lectura.
- Concentración oculta navegación e inspector. Se comprobaron los atajos de foco de párrafo y máquina de escribir.
- El diálogo de impresión abre con sandbox y el permiso de impresión firmado. No requiere seleccionar una impresora para guardar PDF.
- Prueba de exportación con 50 secciones. PDF de nueve páginas renderizado con Poppler e inspeccionado visualmente. La prueba comprueba que no termina ninguna página con un título aislado y que las secciones 1 y 50 permanecen en el archivo.
- El renderizado no reemplaza el texto ni añade operaciones al historial de deshacer.
- Se conservaron los cambios recientes del usuario en la distribución de paneles y el tamaño de ventana.

## Gestos (pieza extraíble)

Automatizado sin cámara: `GestureLogicTests` (pinza con histéresis, pérdida de seguimiento, dos manos, mediana y umbral de calibración, anclaje y pasos de palabra, avance de opción y de nivel, sinónimos y longitudes locales) y `PreviewTests` (confirmar registra un único undo, sin cambios no registra nada, cancelar restaura, edición externa cancela en vez de aplicar a ciegas, lectura bloquea la preview).

Manual pendiente con cámara real:

- Sin activar la pieza no hay botón de mano en la barra y el sistema no pide cámara.
- Activar cámara pide permiso una sola vez; el panel muestra preview espejado, insignia en vivo y diagnóstico (mano, pinza, apertura + umbral).
- Mano abierta camina la selección palabra por palabra; pinza quieta abre sinónimos, mover cambia el preview, soltar confirma con un solo undo; abrir cancela y restaura.
- Pinza + barrido amplio ejecuta deshacer/rehacer una vez por pinza.
- Dos manos abren corto/medio/largo; retirar una confirma (con aviso y Deshacer), perder ambas restaura. Si no abre: el overlay debe etiquetar ambas manos (1 y 2) con la línea blanca entre ellas, la insignia debe decir "Dos manos" y la Separación del diagnóstico debe moverse; con las manos juntas Vision las fusiona en una.
- "Probar sin cámara" (Sinónimos/Longitud) abre las mismas tarjetas: clic confirma, ✕ cancela.
- Calibración en dos pasos de 3 s ajusta el umbral; muestras solapadas se rechazan con mensaje.

## Pendiente

Prueba prolongada de autosave y recuperación tras interrupción, Instruments, VoiceOver con lector activo, contraste aumentado, rendimiento de escritura con un millón de caracteres y ejecución en un Mac con macOS 26. La cobertura Unicode automatizada no sustituye una sesión manual con un método de entrada japonés.
