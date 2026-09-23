// Grupos F (15 no soportados) y G (8 multi-acción).
import Foundation

// F: COMMAND MODE con órdenes sin herramienta. Ideal: NO TOOL (sin sustituciones).
let groupF: [PipelineTest] = [
    T("F01", "F", .command, cx(), "Comparte esto por correo.", [], [:], false, "unsupported"),
    T("F02", "F", .command, cx(), "Agéndame una revisión mañana.", [], [:], false, "unsupported"),
    T("F03", "F", .command, cx(), "Sube el documento a Drive.", [], [:], false, "unsupported"),
    T("F04", "F", .command, cx(), "Firma este archivo.", [], [:], false, "unsupported"),
    T("F05", "F", .command, cx(), "Comprime el documento.", [], [:], false, "unsupported"),
    T("F06", "F", .command, cx(), "Envía esto por mensaje.", [], [:], false, "unsupported"),
    T("F07", "F", .command, cx(), "Programa un recordatorio.", [], [:], false, "unsupported"),
    T("F08", "F", .command, cx(), "Traduce esto al inglés.", [], [:], false, "unsupported"),
    T("F09", "F", .command, cx(), "Cifra el documento.", [], [:], false, "unsupported"),
    T("F10", "F", .command, cx(), "Imprime en color.", [], [:], false, "unsupported"),
    T("F11", "F", .command, cx(), "Publica en el blog.", [], [:], false, "unsupported"),
    T("F12", "F", .command, cx(), "Respalda en disco externo.", [], [:], false, "unsupported"),
    T("F13", "F", .command, cx(), "Convierte a mayúsculas todo.", [], [:], false, "unsupported"),
    T("F14", "F", .command, cx(), "Cuenta las palabras.", [], [:], false, "unsupported"),
    T("F15", "F", .command, cx(), "Dicta el siguiente párrafo.", [], [:], false, "unsupported"),
]

// G: COMMAND MODE multi-acción. Secuencias exactas esperadas.
let groupG: [PipelineTest] = [
    T("G01", "G", .command, cx(sel: selTDHA), "Cambia el título a Resultados y pon el texto seleccionado en negritas.",
      ["renameTitle", "formatSelection"], ["newTitle": "Resultados", "style": "bold"], true, "multi"),
    T("G02", "G", .command, cx(sel: "problemas"), "Reemplaza esta palabra por accesibilidad y guarda el documento.",
      ["replaceSelection", "saveDocument"], ["newText": "accesibilidad"], true, "multi"),
    T("G03", "G", .command, cx(sel: selTDHA), "Borra esto y deshaz el cambio anterior.",
      ["deleteSelection", "undo"], [:], false, "multi"),
    T("G04", "G", .command, cx(sel: selTDHA), "Ponlo en cursivas y guarda el documento.",
      ["formatSelection", "saveDocument"], ["style": "italic"], false, "multi"),
    T("G05", "G", .command, cx(sel: selTDHA), "Hazlo más corto y exporta el informe.",
      ["rewriteSelection", "exportDocument"], [:], false, "multi"),
    T("G06", "G", .command, cx(), "Busca la palabra resumen y selecciona el primer resultado.",
      ["findText", "selectText"], ["query": "resumen"], true, "multi"),
    T("G07", "G", .command, cx(sel: selTDHA), "Subraya esto y pon el título a Metodología.",
      ["formatSelection", "renameTitle"], ["style": "underline", "newTitle": "Metodología"], true, "multi"),
    T("G08", "G", .command, cx(undo: true), "Deshaz el último cambio y guarda el documento.",
      ["undo", "saveDocument"], [:], false, "multi"),
]

let allTests: [PipelineTest] = groupA + groupB + groupC + groupD + groupE + groupF + groupG
