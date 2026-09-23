# Instrucciones para agentes

- No abras ni ejecutes `EditorFinal.app` para compilar, probar o revisar cambios. La app crea una ventana real al iniciar y el binario local puede estar desactualizado.
- Usa `swift build --package-path Packages/EditorModules` para comprobar los módulos y `xcodebuild -project EditorFinal.xcodeproj -scheme EditorFinal -configuration Debug -derivedDataPath build build` para compilar la app. No añadas `open` al final.
- Abre la app solo si el usuario pide explícitamente revisar la interfaz en ejecución.
