# Diagramas en la vista de lectura

Especificación de la pieza futura que renderiza diagramas de flujo dentro de la vista de lectura, en lugar de mostrar el bloque de código crudo. Referencia: demo de Amelia Wattenberger (22-sep-2026, x.com/Wattenberger/status/2102425299237720493), donde un agente publica notas con diagramas nativos (nodos, rombos de decisión, aristas con etiquetas) y recorre la ruta paso a paso.

Estado: especificación. Sin código en esta entrega. Todo el diseño cumple el marco actual: Swift 6, macOS 26 de mínimo, SwiftUI + AppKit, sin dependencias externas, sin red, sandbox.

## 1. Alcance

- Bloque cercado ` ```diagram ` con un DSL propio chico, interpretado solo en la vista de lectura (⇧⌘R) y al imprimir (⌘P).
- En edición se conserva el texto crudo, como todo el formato actual. El diagrama nunca modifica el archivo.
- Layout de grafos propio (por capas), determinista y testeable, sin binarios externos ni Graphviz.
- Render vectorial con SwiftUI `Canvas` dentro del `NSTextView` de lectura.

Fuera de alcance de esta pieza: tablas e imágenes incrustadas (hoy tampoco existen), Mermaid completo, cualquier red, edición visual del diagrama con ratón.

## 2. Sintaxis

### 2.1 Bloque

````
```diagram
direction LR
request[Request] -> valid{Valid?}
valid -- Yes --> process[Process request] -> ready((Ready))
valid -- No --> repair[Repair input] -> valid
```
````

- La info string de la apertura es `diagram` (case-insensitive). Cualquier otra info string sigue siendo código normal con su resaltado de siempre.
- Cada línea es una declaración: nodo suelto, arista o directiva. Líneas en blanco y `#` inicial se ignoran.
- Un bloque sin info string o con sintaxis inválida se muestra como código (degradación silenciosa, nunca un bloque vacío).

### 2.2 Gramática (EBNF)

```
block     = { statement } ;
statement = direction | nodeDecl | edgeDecl ;
direction = "direction", ("TB" | "LR") ;          // por defecto TB
nodeDecl  = id, shape ;
edgeDecl  = endpoint, [ label ], "->", [ label ], endpoint ;
endpoint  = id | id, shape ;
label     = "--", texto, "--" ;                   // etiqueta de arista
shape     = "[" , texto , "]"                     // rectángulo redondeado (proceso)
          | "{" , texto , "}"                     // rombo (decisión)
          | "(" , "(" , texto , ")" , ")"         // círculo (inicio/fin)
          | "[" , "(" , texto , ")" , "]"         // stadium
          ;
id        = identificador ASCII sin espacios, [A-Za-z0-9_.-]+ ;
texto     = cualquier Unicode sin los delimitadores de la forma, con escapes \[ \] \{ \} \( \) ;
```

- Un `id` repetido reutiliza el nodo (permite `a -> b` y luego `b -> c` sin declarar dos veces).
- Referenciar un `id` nunca declarado crea implícitamente un rectángulo con el id como texto.
- Las aristas hacia atrás crean ciclo; se permiten (el layout los resuelve, ver §4).
- Las formas usan texto con formato en línea mínimo: nada de anidamiento recursivo.

### 2.3 Modelo de datos

```swift
struct DiagramGraph: Equatable {
    var direction: Direction            // .topBottom | .leftRight
    var nodes: [DiagramNode]
    var edges: [DiagramEdge]
}
struct DiagramNode: Equatable {
    var id: String
    var text: String
    var shape: Shape                    // .rounded | .decision | .terminal | .stadium
}
struct DiagramEdge: Equatable {
    var from: String
    var to: String
    var label: String?                  // símbolo →
}
```

Puro Foundation, sin AppKit/SwiftUI: vive en `EditorCore` o en el módulo nuevo, testeable igual que `MarkdownDocument`.

## 3. Parseo

- `MarkdownLine.Kind.fence` hoy descarta la info string de las cercas (`EditorCore/MarkdownDocument.swift`). Cambio mínimo: pasar a `case fence(info: String)` y conservar el texto de la apertura, sin alterar el resto de líneas ni los rangos UTF-16.
- El lector de lectura (`MarkdownAppearance.readingText`) detecta `info == "diagram"`, acumula el contenido del bloque (hoy ya se acumula en `codeBuffer`) y lo pasa al parser. Si falla, llama a `renderCodeBlock` como hasta ahora.
- El parseo es síncrono y lineal sobre el contenido del bloque: un bloque de diagrama es corto por definición. Tope práctico de 200 líneas; por encima, degradar a código.
- El parser no ve el documento completo ni el rango del cursor: solo el texto entre cercas. Eso lo mantiene aislado del motor de edición.

## 4. Layout

Fases, todas puras sobre `DiagramGraph → [Position]`:

1. **Normalización**: ids a índices, aristas duplicadas colapsadas (misma dupla y etiqueta).
2. **Ciclos**: detectar con DFS; las aristas que cierran un ciclo se marcan "back" y se invierten solo para el ordenamiento, nunca para el enrutamiento. Con ciclos marcados, el grafo dirigido resultante es un DAG.
3. **Ranking por capas**: orden topológico con cola de prioridad (empate por id, para que sea determinista) + paso de refinamiento empujando nodos hacia abajo. En `TB` la capa es Y; en `LR` es X.
4. **Orden dentro de la capa**: dos pasadas de barycenter (descendente y ascendente) para minimizar cruces. Empate por id otra vez.
5. **Coordenadas**: cada nodo a la media del espacio disponible en su rango; separación mínima de 40 pt entre nodos y 96 pt entre capas; el grafo se centra en su caja.
6. **Enrutamiento de aristas**:
   - arista entre capas contiguas: línea recta del centro al borde con punto de salida/entrada según la dirección;
   - arista que salta capas o es "back": polilínea ortogonal por el canal lateral libre de la capa, con esquinas redondeadas de 8 pt (evita los "quiebros innecesarios" del reporte del video);
   - puntas de flecha de 7 pt en el borde del nodo destino, nunca dentro.
7. **Medición de texto**: `NSAttributedString.size()` con la tipografía del DesignSystem antes de posicionar; el ancho del nodo = ancho de texto + 24 pt (mín. 96, máx. 320; más largo se trunca con `…`).

Propiedades a garantizar (y a probar): mismo grafo → mismo layout en cualquier corrida; ningún nodo solapado; ninguna arista atravesando un nodo (si el canal lateral queda ocupado, se desplaza el canal, no el nodo); aristas cruzadas de idénticos extremos y etiquetas se separan 6 pt para que no se superpongan.

Límites honestos: no es un Sugiyama completo. Sin optimización de forma de onda ni minimización global de longitud de aristas; con grafos densos (>60 nodos o >120 aristas) el resultado es correcto pero no óptimo. Por encima de esos topes, degradar a código en lugar de prometer calidad.

## 5. Render

- SwiftUI `Canvas` dibujando `Path` (nodos, aristas) + `Text`/`AttributedString` (etiquetas y texto de nodo). Un solo paso de dibujo, sin vistas por nodo.
- Tokens del DesignSystem: color de texto (`effectiveTextColor`), secundario para etiquetas, `faintFillColor` para el relleno de nodos, radios y grosor derivados de `EditorMetrics`. Modo claro/oscuro y apariencia siguen funcionando porque salen de los mismos tokens.
- Ancho: 100% del ancho de lectura (`EditorMetrics.readingWidth`, 760 pt menos márgenes). Altura natural del layout, con tope de 3× el ancho; si el grafo es más alto, se escala para caber manteniendo proporción y se ofrece ampliar con un clic.
- `forPrint: true`: mismo dibujo en negro sobre blanco, sin relleno tenue, escala 2× para que el PDF no salga borroso.

## 6. Integración

### 6.1 Vista de lectura

`MarkdownReader` ya hace `textStorage?.setAttributedString(readingText(...))`. El diagrama entra como un `NSTextAttachment` con `NSTextAttachmentViewProvider` (disponible desde macOS 13; el mínimo es macOS 26), que aloja un `NSHostingView` con el `Canvas`. Detalles:

- El provider reutiliza un `NSHostingController` por bloque, destruido al recalcular la lectura (no acumular hosting views en documentos largos).
- El alto del attachment se fija tras medir el layout; si el ancho de la ventana cambia, se relanza el layout al nuevo ancho (el lector ya recalcula al cambiar `readingWidth`).
- El cursor y la selección no atraviesan el attachment: se comporta como una unidad, igual que una imagen.
- Zona interactiva mínima: clic para ampliar/restaurar. El texto crudo sigue siendo lo que se copia al portapapeles desde el modo edición.

### 6.2 Edición

Sin cambios. El modo edición (`NativeTextEditor`) sigue mostrando el bloque entre cercas con el formato de código actual. El diagrama no participa en undo, ni en el binding, ni en el índice: `readingText` es una proyección y el adjunto vive solo en su `textStorage` efímero.

### 6.3 Imprimir / PDF

`PrintDocument` llama a `readingText(..., forPrint: true)`. Un `NSTextAttachment` con imagen rasterizada imprime directo; para que salga nítido, el provider genera el `NSImage` a 2× antes de adjuntarla. Prueba existente de PDF multipágina debe seguir pasando, ahora con un caso que incluya un diagrama.

### 6.4 Accesibilidad

- VoiceOver lee el diagrama como un grupo con descripción textual generada desde el grafo (lista de conexiones: "Request flecha Valid? flecha Sí flecha Process request"), no como una imagen muda.
- Si `reduceMotion` está activo, el paso animado (§7) se sustituye por resaltado instantáneo.
- El adjunto expone `NSAccessibility.Image` con esa descripción; sin descripción generada, `aria-label` = primera línea del bloque.

## 7. Paso animado (fase posterior)

Recorrer la ruta como en el video: un índice de paso sobre `edges` (orden topológico, o DFS desde el nodo inicial si hay ciclos) que va pintando la arista activa con color de acento y atenuando las pasadas. `TimelineView(.animation)` dentro del mismo `Canvas`, o un `Canvas` con `context.addFilter(.shadow...)` liviano. Se activa con un botón dentro del diagrama (▶ / ‖), respeta `reduceMotion` y no bloquea el scroll de lectura. No hay estado persistente: al salir de la vista de lectura se resetea.

## 8. Pieza extraíble

Como las de voz y gestos, se quita sin romper nada:

1. Borrar `DiagramModule` de `Package.swift` y del `.xcodeproj`.
2. `readingText` deja de detectar `info == "diagram"` y todo bloque vuelve a `renderCodeBlock` (comportamiento actual exacto).
3. El cambio de `MarkdownLine.Kind.fence(info:)` se conserva (es un dato, no una dependencia) o se revierte junto con el lector.
4. Ajustes no muestra nada nuevo (no hay preferencias propias: se hereda la apariencia general).

## 9. Pruebas

- **Parser**: formas, escapes, ids repetidos e implícitos, etiquetas, directiva `direction`, unicode y anchos de grafo, bloque vacío, sintaxis inválida → error tipado (no crash).
- **Layout**: determinismo (mismo input, dos corridas, resultado idéntico), sin solapamientos en grafos de prueba, ciclos resueltos, saltos de capa con canal libre, `TB` y `LR`, empates por id.
- **Integración**: `readingText` con un ` ```diagram ` produce un adjunto con alto > 0; con bloque inválido produce el mismo string que hoy; el resto del documento no cambia.
- **Impresión**: PDF con diagrama incluye la página y el diagrama no queda cortado (extiende la prueba multipágina existente).
- **Voz**: sin cambios (el módulo no ve la vista de lectura; sus comandos ya se ignoran ahí).

Las pruebas de layout viven en `EditorModulesTests` con fixtures pequeños, igual que las de voz y gestos: sin capturas de pantalla, con coordenadas numéricas.

## 10. Fases

1. **MVP**: fence con info string, parser, layout por capas con rectángulo/rombo/círculo, render en lectura y PDF, pruebas de parser y layout.
2. **Pulido de enrutamiento**: canales laterales para saltos de capa y ciclos, separación de aristas duplicadas, texto truncado con `…`.
3. **Paso animado** (§7) y ampliación con clic.
4. **Opcional**: subconjunto Mermaid (`flowchart TD/LR`) traducido a `DiagramGraph` en el parser, para poder pegar lo que generan otros agentes. Solo si el DSL propio se queda corto; no antes.
