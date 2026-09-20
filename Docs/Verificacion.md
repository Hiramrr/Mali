# Verificación de la primera entrega

20 de septiembre de 2026. Xcode 27 y SDK macOS 27. Destino mínimo macOS 26.

## Automatizada

`swift test --package-path Packages/EditorModules` ejecuta tres pruebas XCTest de codificación, Unicode, índice, rangos y comandos sobre NSTextView. Las tres pasan.

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

## Pendiente

Prueba prolongada de autosave y recuperación tras interrupción, Instruments, VoiceOver con lector activo, contraste aumentado, rendimiento de escritura con un millón de caracteres y ejecución en un Mac con macOS 26. La cobertura Unicode automatizada no sustituye una sesión manual con un método de entrada japonés.
