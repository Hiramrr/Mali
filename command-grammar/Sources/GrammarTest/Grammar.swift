// Gramática determinista. Sin ML, sin regex probabilístico, sin fuzzy.
// Precedencia: multi > replace > rewrite > format > rename > delete >
// redo > undo > find > select > save > export(sic, ver nota) > open >
// unsupported > unknown.
//
// NOTA de orden: export va ANTES que save ("Guarda una copia como pdf"
// debe ser export, no save). Redo va ANTES que undo ("deshaz el deshacer"
// es redo). Format va ANTES que select ("marca X en negritas" es formato).
import Foundation

private let exteriorPunct = CharacterSet(charactersIn: ".,!?;:()\"'«»¿¡")

func normalizeToken(_ s: String) -> String {
    s.lowercased().folding(options: .diacriticInsensitive, locale: .current)
}

func normalizeUtterance(_ raw: String) -> String {
    raw.lowercased()
        .folding(options: .diacriticInsensitive, locale: .current)
        .precomposedStringWithCanonicalMapping
}

func tokenize(_ raw: String) -> [CommandToken] {
    var tokens: [CommandToken] = []
    var idx = raw.startIndex
    func isSpace(_ c: Character) -> Bool { c.isWhitespace }
    while idx < raw.endIndex {
        while idx < raw.endIndex && isSpace(raw[idx]) { idx = raw.index(after: idx) }
        if idx >= raw.endIndex { break }
        let start = idx
        while idx < raw.endIndex && !isSpace(raw[idx]) { idx = raw.index(after: idx) }
        // Rango = palabra completa (con puntuación); normalized se calcula sin ella.
        let full = String(raw[start..<idx])
        let trimmed = full.trimmingCharacters(in: exteriorPunct)
        if trimmed.isEmpty { continue }
        tokens.append(CommandToken(raw: full,
                                   normalized: normalizeToken(trimmed),
                                   range: start..<idx))
    }
    return tokens
}

/// Subcadena raw correspondiente al span de tokens [from, to).
/// Recorta espacios y [.,;:] exteriores; conserva ?!¿¡; quita un nivel de
/// comillas externas coincidentes.
func rawSpan(_ raw: String, _ tokens: [CommandToken], _ from: Int, _ to: Int) -> String {
    guard from < to, from >= 0, to <= tokens.count else { return "" }
    let lo = tokens[from].range.lowerBound
    let hi = tokens[to - 1].range.upperBound
    var s = String(raw[lo..<hi]).trimmingCharacters(in: .whitespacesAndNewlines)
    // Recorta [.,;:] finales, pero conserva el punto de iniciales ("V.", "S. A.").
    while s.hasSuffix(".") || s.hasSuffix(",") || s.hasSuffix(";") || s.hasSuffix(":") {
        if s.hasSuffix(".") {
            let t = String(s.dropLast())
            if let last = t.last, last.isUppercase {
                let prev = t.dropLast()
                if prev.isEmpty || prev.last == " " { break }
            }
        }
        s = String(s.dropLast())
    }
    s = s.trimmingCharacters(in: .whitespacesAndNewlines)
    let pairs: [(String, String)] = [("\"", "\""), ("'", "'"), ("«", "»")]
    for (a, b) in pairs {
        if s.hasPrefix(a) && s.hasSuffix(b) && s.count >= 2 {
            s = String(s.dropFirst().dropLast())
            break
        }
    }
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Quita enclíticos (lo/la/los/las/le/les/me/te/se/nos) para matching verbal.
func deenclitic(_ s: String) -> String {
    for e in ["los", "las", "les", "nos", "lo", "la", "le", "me", "te", "se"] {
        if s.hasSuffix(e) && s.count > e.count + 2 {
            return String(s.dropLast(e.count))
        }
    }
    return s
}

/// Intenta verbo exacto primero; si no, prueba quitando enclíticos.
/// Evita romper verbos que terminan en esas sílabas ("halla" ≠ "ha").
func verbMatch(_ raw: String, _ verbs: Set<String>) -> Bool {
    if verbs.contains(raw) { return true }
    return verbs.contains(deenclitic(raw))
}

private let politeness: Set<String> = ["por", "favor"]

private let titleWords: Set<String> = ["titulo", "rotulo", "membrete", "encabezado",
                                       "nombre", "portada", "caratula"]

/// Sustantivos de acción que convierten anula/cancela/revierte en UNDO.
/// "Anula este inciso" (demostrativo + cosa) sigue siendo DELETE.
/// Solo "ya" también vale ("Anula ya"). Otro objeto → no coincide.
private let undoNouns: Set<String> = ["ultimo", "ultima", "cambio", "edicion",
    "pegado", "borrado", "envio", "firma", "formato", "sustitucion", "reemplazo",
    "ya", "eso", "esto"]

/// true si el resto tras anula/cancela/revierte indica UNDO.
func isUndoObject(_ rest: [String]) -> Bool {
    guard let r0 = rest.first else { return false }
    if r0 == "lo" && rest.dropFirst().first == "que" { return true }
    if r0 == "el" || r0 == "la" {
        let after = Array(rest.dropFirst())
        if let a0 = after.first, undoNouns.contains(a0) { return true }
        return false
    }
    return undoNouns.contains(r0)
}
private let stripWords: Set<String> = ["esto", "esta", "este", "lo", "la", "el", "parte"]

/// Quita "por favor" en cualquier posición y "favor" suelto.
/// Devuelve tokens supervivientes + mapa a índices originales.
func stripPoliteness(_ t: [CommandToken]) -> (toks: [CommandToken], map: [Int]) {
    var toks: [CommandToken] = []
    var map: [Int] = []
    var i = 0
    while i < t.count {
        if t[i].normalized == "por" && i + 1 < t.count && t[i + 1].normalized == "favor" {
            i += 2
            continue
        }
        if t[i].normalized == "favor" {
            i += 1
            continue
        }
        toks.append(t[i])
        map.append(i)
        i += 1
    }
    return (toks, map)
}

func normTokens(_ raw: String) -> [String] {
    tokenize(raw).map(\.normalized)
}

// MARK: - Patrones por acción (devuelven nombre + span de argumento o nil)

/// Intenta clasificar SOLO el tipo de acción (para detección multi).
func actionType(of tokens: [CommandToken]) -> String? {
    let (t, _) = stripPoliteness(tokens)
    if matchReplace(t) != nil { return "replaceSelection" }
    if matchRewrite(t) != nil { return "rewriteSelection" }
    if matchFormat(t) != nil { return "formatSelection" }
    if matchRename(t) != nil { return "renameTitle" }
    if matchDelete(t) { return "deleteSelection" }
    if matchRedo(t) { return "redo" }
    if matchUndo(t) { return "undo" }
    if matchFind(t) != nil { return "findText" }
    if matchSelect(t) != nil { return "selectText" }
    if matchExport(t) != nil { return "exportDocument" }
    if matchSave(t) { return "saveDocument" }
    if matchOpen(t) != nil { return "openDocument" }
    return nil
}

func matchReplace(_ t: [CommandToken]) -> (Int, Int)? {
    guard let first = t.first else { return nil }
    if ["reemplaza", "reemplazalo", "sustituye", "sustituyelo", "cambia", "troca", "trocalo", "escribe"].contains(first.normalized) {
        // "cambia el <TITLEWORD> por X" es rename, no replace.
        if first.normalized == "cambia" {
            let n = t.map(\.normalized)
            if let por = n.firstIndex(of: "por"),
               n[..<por].contains(where: { titleWords.contains($0) }) {
                return nil
            }
        }
        if let por = t.firstIndex(where: { $0.normalized == "por" }), por + 1 < t.count {
            return (por + 1, t.count)
        }
        // "escribe X" = teclear X (reemplaza la selección en editores).
        if first.normalized == "escribe" && t.count > 1 {
            return (1, t.count)
        }
    }
    // pon X tras Y / pon X donde Y → arg = X (solo el texto nuevo)
    if first.normalized == "pon" {
        let n = t.map(\.normalized)
        if let k = n.firstIndex(where: { $0 == "tras" || $0 == "donde" }), k > 1 {
            return (1, k)
        }
        if let k = n.firstIndex(of: "lugar"), k > 2, n[k - 1] == "en" {
            return (1, k - 1)
        }
    }
    return nil
}

func matchRewrite(_ t: [CommandToken]) -> (Int, Int)? {
    guard let first = t.first else { return nil }
    // Si menciona un estilo explícito, es formato (precedencia de formato).
    if t.contains(where: { styleOf($0.normalized) != nil }) { return nil }
    if ["hazlo", "hazla", "haz"].contains(first.normalized) {
        var i = 1
        // Solo "esto/esta/este" (+ "esta parte"); los artículos se conservan.
        if i < t.count && ["esto", "esta", "este"].contains(t[i].normalized) {
            i += 1
            if i == 2 && t[1].normalized == "esta" && i < t.count && t[i].normalized == "parte" { i += 1 }
        }
        return i < t.count ? (i, t.count) : nil
    }
    if ["reescribe", "reformula"].contains(first.normalized) {
        var i = 1
        if i < t.count && ["esto", "esta", "este"].contains(t[i].normalized) {
            i += 1
            if i == 2 && t[1].normalized == "esta" && i < t.count && t[i].normalized == "parte" { i += 1 }
        }
        return i < t.count ? (i, t.count) : nil
    }
    return nil
}

func styleOf(_ tok: String) -> FormatStyle? {
    if tok.hasPrefix("negrit") { return .bold }
    if tok.hasPrefix("cursiv") { return .italic }
    if tok.hasPrefix("subray") { return .underline }
    return nil
}

func matchFormat(_ t: [CommandToken]) -> FormatStyle? {
    guard !t.isEmpty else { return nil }
    if t.count == 1, let s = styleOf(t[0].normalized) { return s }
    let verbs: Set<String> = ["pon", "ponlo", "ponle", "haz", "hazlo", "hazla",
                              "marca", "aplica", "remarca", "resalta", "deja"]
    guard verbs.contains(t[0].normalized) || styleOf(t[0].normalized) != nil else { return nil }
    for tok in t {
        if let s = styleOf(tok.normalized) { return s }
    }
    // "remarca/resalta X" sin estilo explícito = énfasis = bold.
    if t[0].normalized == "remarca" || t[0].normalized == "resalta" { return .bold }
    return nil
}

func matchRename(_ t: [CommandToken]) -> (Int, Int)? {
    let n = t.map(\.normalized)
    // R1: cambia el <TITLEWORD> {a|por} ARG
    if n.count >= 4 && n[0] == "cambia" && titleWords.contains(n[2]) && (n[3] == "a" || n[3] == "por") {
        return t.count > 4 ? (4, t.count) : nil
    }
    // R2: pon como titulo ARG
    if n.count >= 4 && n[0] == "pon" && n[1] == "como" && n[2] == "titulo" {
        return t.count > 3 ? (3, t.count) : nil
    }
    // R3: ponle de titulo ARG
    if n.count >= 4 && n[0] == "ponle" && n[1] == "de" && n[2] == "titulo" {
        return t.count > 3 ? (3, t.count) : nil
    }
    // R4: ponle ARG al ... / R4b: ponle ARG
    if n.count >= 3 && n[0] == "ponle" {
        if let al = n.firstIndex(of: "al"), al > 1 { return (1, al) }
        if let a = n.firstIndex(of: "a"), a > 1,
           a + 1 < n.count && (n[a + 1] == "el" || n[a + 1] == "la") { return (1, a) }
        return (1, t.count)
    }
    // R5: renombra|nombra|bautiza ... {a|como} ARG
    if n.count >= 2 && (n[0] == "renombra" || n[0] == "nombra" || n[0] == "bautiza") {
        if let sep = n.firstIndex(where: { $0 == "a" || $0 == "como" }), sep + 1 < n.count {
            return (sep + 1, t.count)
        }
        // R5b: nombra|bautiza|renombra + el|la + X + RESTO → ARG = RESTO
        if n.count >= 4 && (n[1] == "el" || n[1] == "la") {
            return (3, t.count)
        }
    }
    // R6: titula [esto|esta|este] [como] ARG ; si hay "como", ARG va después
    if n.count >= 2 && n[0] == "titula" {
        if let como = n.firstIndex(of: "como"), como + 1 < n.count {
            return (como + 1, t.count)
        }
        var i = 1
        if i < n.count && ["esto", "esta", "este"].contains(n[i]) { i += 1 }
        return i < n.count ? (i, t.count) : nil
    }
    // R10: "nombre" inicial → ARG = resto ("Nombre: X")
    if n.count >= 2 && n[0] == "nombre" {
        return (1, t.count)
    }
    // R7: actualiza|modifica + TITLEWORD ... {a|por} ARG
    if let ti = n.firstIndex(where: { titleWords.contains($0) }),
       (n[0] == "actualiza" || n[0] == "modifica" || n[0] == "corrige") {
        if let sep = n[(ti + 1)...].firstIndex(where: { $0 == "a" || $0 == "por" }),
           sep + 1 < n.count { return (sep + 1, t.count) }
    }
    // R8: TITLEWORD {sera|seran} ARG
    if let ti = n.firstIndex(where: { titleWords.contains($0) }), ti + 2 < n.count,
       (n[ti + 1] == "sera" || n[ti + 1] == "seran") {
        return (ti + 2, t.count)
    }
    // R13: cambia|pon + nombre + a → ARG ("Cambia el nombre a X")
    if n.count >= 2 && (n[0] == "cambia" || n[0] == "pon") && n.contains("nombre") {
        if let a = n.firstIndex(of: "a"), a + 1 < n.count { return (a + 1, t.count) }
    }
    // R14: [el|este] TITLEWORD + {dira|diran|dice|dicen|diga|sea|sean} ARG
    if n.count >= 3 && (n[0] == "el" || n[0] == "este"),
       titleWords.contains(n[1]),
       ["dira", "diran", "dice", "dicen", "diga", "sea", "sean"].contains(n[2]) {
        return (3, t.count)
    }
    // R15: que (el) titulo {cite|cita|diga|dice} ARG ; R15b: que diga|digan ARG
    if n.count >= 2 && n[0] == "que" {
        var i = 1
        if i < n.count && n[i] == "el" { i += 1 }
        if i < n.count && titleWords.contains(n[i]) { i += 1 }
        if i < n.count && ["cite", "cita", "diga", "digan", "dice", "dicen"].contains(n[i]),
           i + 1 < n.count { return (i + 1, t.count) }
    }
    return nil
}

func matchDelete(_ t: [CommandToken]) -> Bool {
    guard let first = t.first else { return false }
    let verbs: Set<String> = ["borra", "borralo", "elimina", "eliminalo", "quita",
                              "quitalo", "quitale", "suprime", "tacha", "tachalo",
                              "corta", "cortalo", "descarta", "anula", "cancela",
                              "revierte", "remueve", "retira",
                              "limpia", "vacia", "rae"]
    if verbs.contains(first.normalized) {
        // "anula/cancela/revierte" + demostrativo + cosa → DELETE.
        // Con objeto de UNDO → false (lo resuelve matchUndo).
        // Otro objeto → false (unsupported/unknown, sin adivinar).
        if ["anula", "cancela", "revierte"].contains(first.normalized) {
            let rest = t.dropFirst().map(\.normalized)
            // Solo demostrativo + cosa es DELETE; lo demás lo resuelve
            // matchUndo (objetos de UNDO) o cae a unsupported/unknown.
            if let r0 = rest.first, ["este", "esta", "estos", "estas"].contains(r0) {
                return true
            }
            return false
        }
        return true
    }
    return false
}

func matchRedo(_ t: [CommandToken]) -> Bool {
    guard let first = t.first else { return false }
    let n = t.map(\.normalized)
    if first.normalized.hasPrefix("rehaz") || first.normalized == "rehazlo" { return true }
    if first.normalized == "rehace" { return true }
    if first.normalized == "reaplica" { return true }
    if n.starts(with: ["vuelve", "a", "aplicar"]) { return true }
    if n.starts(with: ["restaura", "lo", "deshecho"]) { return true }
    if n.count >= 4 && n[0] == "restaura" && n[1] == "lo" && n[2] == "que"
        && n[3] == "deshice" { return true }
    if n.starts(with: ["vuelve", "a", "poner"]) { return true }
    if n.starts(with: ["deshaz", "el", "deshacer"]) { return true }
    if n.starts(with: ["repite", "el", "cambio", "deshecho"]) { return true }
    return false
}

func matchUndo(_ t: [CommandToken]) -> Bool {
    guard let first = t.first else { return false }
    let n = t.map(\.normalized)
    if first.normalized.hasPrefix("deshaz") || first.normalized == "deshacer" { return true }
    if n.starts(with: ["vuelve", "atras"]) || n.starts(with: ["vuelve", "a", "como", "estaba"]) { return true }
    if n.starts(with: ["vuelve", "al", "estado"]) || n.starts(with: ["vuelve", "al", "borrador"]) { return true }
    if n.starts(with: ["regresa"]) { return true }
    if n.starts(with: ["restaura"]) { return true } // "restaura X" solo; "restaura lo deshecho" ya fue redo
    if n.starts(with: ["echalo", "para", "atras"]) { return true }
    if n.starts(with: ["dejalo", "como", "estaba"]) { return true }
    if ["anula", "cancela", "revierte"].contains(first.normalized) {
        let rest = Array(n.dropFirst())
        if isUndoObject(rest) { return true }
    }
    return false
}

func matchFind(_ t: [CommandToken]) -> (Int, Int)? {
    guard let first = t.first else { return nil }
    guard verbMatch(first.normalized, ["busca", "encuentra", "localiza", "halla", "rastrea", "detecta", "caza", "ubica"]) else { return nil }
    var i = 1
    // Solo se descarta la secuencia exacta "la palabra"; "la" sola se conserva.
    if i + 1 < t.count && t[i].normalized == "la" && t[i + 1].normalized == "palabra" { i += 2 }
    return i < t.count ? (i, t.count) : nil
}

func matchSelect(_ t: [CommandToken]) -> (Int, Int)? {
    guard let first = t.first else { return nil }
    guard verbMatch(first.normalized, ["selecciona", "marca", "elige", "toma", "aparta", "senala",
           "delimita", "aisla", "enfoca", "apunta", "enmarca", "encierra"]) else { return nil }
    return t.count > 1 ? (1, t.count) : nil
}

func matchSave(_ t: [CommandToken]) -> Bool {
    guard let first = t.first else { return false }
    return ["guarda", "guardalo", "archiva", "consigna", "respalda", "fija",
            "asegura", "preserva", "congela", "salvaguarda", "registra",
            "deposita", "custodia"].contains(first.normalized)
}

func matchOpen(_ t: [CommandToken]) -> (Int, Int)? {
    guard let first = t.first else { return nil }
    guard verbMatch(first.normalized, ["abre", "abrelo", "recupera", "reabre", "carga", "muestra", "trae",
           "desarchiva", "jala", "retoma", "exhibe", "despliega", "proyecta"]) else { return nil }
    if first.normalized == "abrelo" || t.count == 1 { return nil } // nil-arg se resuelve fuera
    return (1, t.count)
}

func matchExport(_ t: [CommandToken]) -> ExportFormat? {
    guard let first = t.first else { return nil }
    guard ["exporta", "pasalo", "saca", "genera", "convierte", "rinde", "produce", "emite",
           "migra", "funde", "extrae", "publica", "entrega", "baja", "vierte",
           "guarda", "archiva"].contains(first.normalized) else { return nil }
    let joined = " " + t.map(\.normalized).joined(separator: " ") + " "
    if joined.contains(" pdf ") { return .pdf }
    if joined.contains(" word ") || joined.contains(" docx ") { return .word }
    if joined.contains(" texto plano ") || joined.contains(" texto ") || joined.contains(" txt ")
        || joined.contains(" plana ") || joined.contains(" plano ") { return .plainText }
    if joined.contains(" enriquecid") || joined.contains(" formato ") || joined.contains(" rtf ")
        || joined.contains(" rica ") || joined.contains(" rico ") { return .richText }
    return nil
}

/// ¿Pide exportar pero con formato desconocido? → unsupported (no adivinar).
func matchExportUnknownFormat(_ t: [CommandToken]) -> Bool {
    guard let first = t.first else { return false }
    guard ["exporta", "convierte", "guarda", "saca", "genera"].contains(first.normalized) else { return false }
    let n = t.map(\.normalized)
    guard n.contains("como") || n.contains("en") || n.contains("a") else { return false }
    return matchExport(t) == nil
}

private let unsupportedVerbs: Set<String> = [
    "firma", "firmar", "traduce", "traducir", "envia", "enviar", "manda",
    "comparte", "compartir", "sube", "subir", "agenda", "agendar", "programa",
    "cifra", "cifrar", "encripta", "comprime", "comprimir", "imprime", "imprimir",
    "dicta", "dictar", "lee", "leer", "llama", "cancela", "copia", "copiar",
    "pega", "pegar", "exporta", "exportar", "cierra", "cerrar", "numera",
    "numerar", "centra", "centrar", "escanea", "escanear", "recorta",
    "recortar", "titula", "titular", "resume", "resumir", "formatea",
    "formatear", "rubrica", "notaria", "memoriza", "memorizar", "ensaya",
    "ensayar", "clasifica", "clasificar", "etiqueta", "etiquetar",
    "devuelve", "devolver", "confirma", "confirmar", "revisa", "revisar",
    "pide", "pedir", "reserva", "reservar", "compra", "comprar", "renta", "rentar",
    "riega", "regar", "tiende", "tender", "barre", "barrer", "lava", "lavar",
    "poda", "podar", "pinta", "pintar", "arregla", "arreglar", "vacuna", "vacunar",
    "esteriliza", "esterilizar", "bana", "banar", "cambia", "pon", "marca",
    "da", "dar", "timbra", "paga", "pagar", "deposita", "depositar", "retira",
    "retirar", "transfiere", "transferir", "endosa", "endosar", "hipoteca",
    "hipotecar", "vende", "vender", "invierte", "invertir", "declara", "declarar",
    "factura", "facturar", "cotiza", "cotizar", "contrata", "contratar",
    "reporta", "reportar", "denuncia", "denunciar", "demanda", "demandar",
    "apela", "apelar", "testifica", "testificar", "soborna", "sobornar",
    "extorsiona", "extorsionar", "hackea", "hackear", "crackea", "crackear",
    "minea", "minear", "ejecuta", "ejecutar", "compila", "compilar",
    "despliega", "desplegar", "reinicia", "reiniciar", "formatea", "formatear",
    "particiona", "particionar", "instala", "instalar", "configura", "configurar",
    "cablea", "cablear", "suelda", "sueldar", "sella", "sellar", "taladra", "taladrar", "lija",
    "lijar", "barniza", "barnizar", "tapiza", "tapizar", "repara", "reparar",
    "destapa", "destapar", "impermeabiliza", "fumiga", "fumigar", "captura",
    "capturar", "adopta", "adoptar", "cuenta", "contar", "alimenta", "alimentar",
    "trasplanta", "trasplantar", "abona", "abonar", "cosecha", "cosechar",
    "ordena", "ordenar", "planta", "plantar", "califica", "calificar",
    "evalua", "evaluar", "aprueba", "aprobar", "reprueba", "reprobar",
    "hornea", "hornear", "bate", "batir", "decora", "decorar",
    "saca", "sacar",
]

/// "busca en internet|google|la web" → unsupported (no es find del documento).
func matchInternetSearch(_ t: [CommandToken]) -> Bool {
    let n = t.map(\.normalized)
    guard n.first == "busca" else { return false }
    let rest = n.dropFirst().joined(separator: " ")
    return rest.contains("internet") || rest.contains("google") || rest.contains("la web")
}

private let unsupportedPhrases: [[String]] = [
    ["busca", "en", "internet"], ["busca", "en", "google"], ["busca", "en", "la", "web"],
]

func matchUnsupported(_ t: [CommandToken]) -> Bool {
    guard let first = t.first else { return false }
    if verbMatch(first.normalized, unsupportedVerbs) { return true }
    let n = t.map(\.normalized)
    for p in unsupportedPhrases {
        if n.starts(with: p) { return true }
    }
    return false
}

/// ¿Parece una acción (para segmentación multi)? Versión permisiva:
/// tipo estricto, verbo de acción suelto, o verbo operational sin tool.
/// Los segmentos multi pueden combinar soportadas y no soportadas.
func isActionLike(_ tokens: [CommandToken]) -> Bool {
    if actionType(of: tokens) != nil { return true }
    if matchUnsupported(tokens) { return true }
    if matchUnsupported(tokens) { return true }
    guard let first = tokens.first else { return false }
    let v = first.normalized
    let stem = deenclitic(v)
    let verbs: Set<String> = [
        "reemplaza", "reemplazalo", "sustituye", "sustituyelo", "cambia", "troca",
        "trocalo", "escribe", "pon",
        "hazlo", "hazla", "haz", "reescribe", "reformula",
        "ponlo", "ponle", "marca", "aplica", "remarca", "resalta", "deja",
        "subraya", "titula", "titular", "renombra", "nombra", "bautiza", "actualiza",
        "modifica", "corrige", "resume", "resumir", "formatea", "formatear",
        "borra", "borralo", "elimina", "eliminalo", "quita", "quitalo",
        "quitale", "suprime", "tacha", "tachalo", "corta", "cortalo",
        "descarta", "anula", "cancela", "revierte", "remueve", "retira",
        "limpia", "vacia", "rae",
        "deshaz", "deshacer", "vuelve", "regresa", "restaura", "echalo",
        "dejalo", "repite",
        "rehaz", "rehazlo", "rehace", "reaplica",
        "busca", "encuentra", "localiza", "halla", "rastrea", "detecta",
        "caza", "ubica",
        "selecciona", "elige", "toma", "aparta", "senala", "delimita",
        "aisla", "enfoca", "apunta", "enmarca", "encierra",
        "guarda", "guardalo", "archiva", "consigna", "respalda", "fija",
        "asegura", "preserva", "congela", "salvaguarda", "registra",
        "deposita", "custodia",
        "abre", "abrelo", "recupera", "reabre", "carga", "muestra", "trae",
        "desarchiva", "jala", "retoma", "exhibe", "despliega", "proyecta",
        "exporta", "pasalo", "saca", "genera", "convierte", "rinde",
        "produce", "emite", "migra", "funde", "extrae", "publica",
        "entrega", "baja", "vierte", "escanea", "escanear", "recorta",
        "recortar", "numera", "numerar", "centra", "centrar", "revisa",
        "revisar",
    ]
    return verbs.contains(v) || verbs.contains(stem)
}

func splitSegments(_ t: [CommandToken]) -> [[CommandToken]]? {
    let seps: Set<String> = ["y", "e", ","]
    let discourse: Set<String> = ["luego", "despues", "entonces"]
    var idxs: [Int] = []
    for (i, tok) in t.enumerated() {
        if seps.contains(tok.normalized) || discourse.contains(tok.normalized) { idxs.append(i) }
    }
    if idxs.isEmpty { return nil }
    var segs: [[CommandToken]] = []
    var start = 0
    for i in idxs + [t.count] {
        let seg = Array(t[start..<i])
        if !seg.isEmpty { segs.append(seg) }
        start = i + 1
    }
    guard segs.count >= 2 else { return nil }
    // Si todos los segmentos son del MISMO tipo (repetición enfática:
    // "Tacha, tacha"), no es multi-acción.
    let types = segs.map { actionType(of: $0) }
    if types.allSatisfy({ $0 != nil }) && Set(types.compactMap({ $0 })).count == 1 {
        return nil
    }
    for s in segs {
        guard isActionLike(s) else { return nil }
    }
    return segs
}

// MARK: - Parse principal

func parseCommand(raw: String) -> ParsedCommand {
    var tokens = tokenize(raw)
    if tokens.isEmpty { return .unknown }
    // "No, ..." inicial (con coma) modifica la polaridad: se descarta el "no".
    if tokens[0].normalized == "no"
        && raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("no,") {
        tokens = Array(tokens.dropFirst())
    }
    if tokens.isEmpty { return .unknown }
    let (t, pmap) = stripPoliteness(tokens)
    if t.isEmpty { return .unknown }
    func span(_ a: Int, _ b: Int) -> String {
        guard a < b, b <= pmap.count else { return "" }
        return rawSpan(raw, tokens, pmap[a], pmap[b - 1] + 1)
    }

    if splitSegments(t) != nil { return .multipleActions }

    // Coma como separador multi-acción ("Subraya X, archiva Y").
    // El tokenizer descarta comas sueltas, así que se parte el raw antes.
    let commaParts = raw.split(separator: ",", omittingEmptySubsequences: true)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    if commaParts.count >= 2 {
        let types = commaParts.map { actionType(of: tokenize(String($0))) }
        // Mismo tipo en todos = repetición, no multi-acción.
        if !(types.allSatisfy({ $0 != nil }) && Set(types.compactMap({ $0 })).count == 1)
            && commaParts.allSatisfy({ isActionLike(tokenize(String($0))) }) {
            return .multipleActions
        }
    }

    if let (a, b) = matchReplace(t) { return .replaceSelection(span(a, b)) }
    if let (a, b) = matchRewrite(t) { return .rewriteSelection(span(a, b)) }
    if let s = matchFormat(t) { return .formatSelection(s) }
    if let (a, b) = matchRename(t) { return .renameTitle(span(a, b)) }
    if matchDelete(t) { return .deleteSelection }
    if matchRedo(t) { return .redo }
    if matchUndo(t) { return .undo }
    if matchInternetSearch(t) { return .unsupported(raw) }
    if let (a, b) = matchFind(t) { return .findText(span(a, b)) }
    if let (a, b) = matchSelect(t) { return .selectText(span(a, b)) }
    if let f = matchExport(t) { return .exportDocument(f) }
    if matchSave(t) { return .saveDocument }
    if t.count == 1 && t[0].normalized == "abrelo" { return .openDocument(nil) }
    if let (a, b) = matchOpen(t) { return .openDocument(span(a, b)) }
    if t.count == 1 && t[0].normalized == "abre" { return .openDocument(nil) }
    if matchExportUnknownFormat(t) { return .unsupported(raw) }
    if matchUnsupported(t) { return .unsupported(raw) }
    return .unknown
}
