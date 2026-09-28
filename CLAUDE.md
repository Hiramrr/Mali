# Guía para continuar en EditorFinal

## Antes de cambiar código

- Lee `AGENTS.md` y comprueba `git status --short`. Puede haber trabajo sin confirmar; consérvalo y revisa el diff de los archivos que vayas a tocar.
- Usa `README.md` para el comportamiento actual y `Docs/Integracion.md`, `Docs/Integracion-Voz-Fase11.md` y `Docs/Verificacion.md` para detalles de módulos y pruebas. `Docs/Especificacion.md` es la propuesta original: algunas decisiones posteriores, como el mínimo macOS 26, la sustituyen.
- Mantén la app nativa, local y sin dependencias externas nuevas salvo necesidad concreta. Swift 6, SwiftUI, AppKit, NSTextView y TextKit 2; destino mínimo macOS 26. El entorno de desarrollo usa Xcode y SDK macOS 27.

## Mapa del proyecto

- `App/EditorApp.swift` es la entrada. Adapta `FileDocument`, crea el `DocumentGroup`, conecta voz y gestos y coordina la ventana única. `App/Resources/` contiene permisos, icono e Info.plist.
- `Packages/EditorModules/` es el paquete principal. `EditorCore` define texto, rangos UTF-16 y comandos; `EditorEngine` aplica los comandos sobre `NSTextView`, edita Markdown, lo decora y lo convierte a texto de lectura (`MarkdownAppearance`), y gestiona previews, undo y reescritura; `EditorUI` contiene pantalla, menús y ajustes. `DocumentKit` valida UTF-8 y la biblioteca; `DesignSystem` guarda estilos, tipografía y colores; `ExportFeature` prepara PDF (`PrintDocument`) y exporta a txt, rtf y Word (`DocumentExport`).
- `ModuleKit` contiene `EditorCommandBus`. `VoiceModule` y `GestureModule` envían comandos por ese bus sin acceder directamente al `NSTextView`. `EditorSession.send(_:)` ejecuta las operaciones de texto; `EditorScreen` atiende las que requieren documento o interfaz, como guardar, abrir, renombrar y exportar.
- `command-grammar/` es el paquete local que provee `CommandGrammar` a voz. No dupliques su gramática en la app. `action-classifier/` y las carpetas de experimentos de la raíz no son el paquete principal de la app.
- Las pruebas del paquete están en `Packages/EditorModules/Tests/EditorModulesTests/`. `Samples/` contiene documentos de ejemplo.

## Reglas que evitan regresiones

- Conserva el ciclo de documentos de SwiftUI y la coordinación de ventana única. No reemplaces `NSDocumentController` con una subclase: `App/EditorApp.swift` documenta un fallo de arranque que causó ese intento.
- Los rangos de edición usan UTF-16 por `NSTextView`. Valídalos contra el texto vigente antes de seleccionar o reemplazar, en especial después de cambios de selección o documento.
- Una preview de voz o gestos no debe guardarse ni crear undo hasta confirmarse. Cancelar restaura el texto; confirmar registra un solo undo. Las acciones de voz que cambian contenido requieren propuesta y confirmación. Conserva estas reglas al modificar el flujo.
- Micrófono, reconocimiento de voz y cámara se solicitan al activar sus funciones. El procesamiento de voz, gestos y reescritura ocurre en el Mac. Las pruebas automatizadas no requieren esos dispositivos.

## Comprobación

Desde la raíz:

```sh
swift build --package-path Packages/EditorModules
swift test --package-path Packages/EditorModules
xcodebuild -project EditorFinal.xcodeproj -scheme EditorFinal -configuration Debug -derivedDataPath build build
```

No abras ni ejecutes `EditorFinal.app` para compilar, probar o revisar cambios. Crea una ventana real y el binario local puede estar desactualizado. Abre la app solo si el usuario pide explícitamente revisar la interfaz en ejecución.

Siguen pendientes las comprobaciones manuales con micrófono y cámara reales, VoiceOver, recuperación tras una interrupción y rendimiento con documentos grandes. Consulta `Docs/PruebaVozEnVivo.md` y `Docs/Verificacion.md` antes de esas sesiones.
