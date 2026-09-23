import CommandGrammar
// Fase Custom LM v1 — datos y configuración. NO toca CommandGrammar.
// Locale: es_MX (guion bajo, verificado en DictationTranscriber.supportedLocales).
// Weight único elegido a priori: 0.6 (moderado, sin tuning post-FINAL).
import Foundation
import Speech

let customLMLocale = Locale(identifier: "es_MX")
let customLMIdentifier = "com.editor.commands.v1"
let customLMVersion = "1.0"
let customLMWeightValue: Double = 0.6

func customLMWeight() -> NSNumber { NSNumber(value: customLMWeightValue) }

// MARK: - PhraseCounts (frase, count)
// Diseñadas desde gramática/aliases/vocabulario, SIN copiar literalmente
// ninguna frase de data/speech_protocol_v2.csv (ver leakage check).
// Incluyen variantes con/sin tilde relevantes a STT y formas cortas con
// modificadores ("ya", determinantes distintos) para no colisionar.
let customLMPhraseCounts: [(phrase: String, count: Int)] = [
    // Undo (15)
    ("deshaz el cambio ya", 15),
    ("deshaz ese cambio", 12),
    ("deshaz esta edicion", 10),
    ("deshaz aquello ya", 8),
    ("vuelve atras ya", 12),
    ("vuelve a como estaba ya", 10),
    ("anula ese cambio", 10),
    ("cancela esa edicion", 10),
    ("revierte ese cambio", 10),
    ("restaura ese borrador", 8),
    ("echalo para atras ya", 8),
    ("dejalo como estaba ya", 8),
    ("anula aquello ya", 8),
    ("vuelve al estado previo", 8),
    ("regresa a la version previa", 8),
    // Redo (12)
    ("rehaz el cambio ya", 15),
    ("rehaz ese cambio", 12),
    ("rehazlo de nuevo", 10),
    ("rehaz la edicion ya", 10),
    ("vuelve a aplicar ese cambio", 12),
    ("reaplica ese formato", 10),
    ("restaura aquello deshecho", 10),
    ("vuelve a poner ese texto", 10),
    ("deshaz aquello deshecho", 8),
    ("repite ese cambio deshecho", 10),
    ("rehace ese cambio", 10),
    ("restaura aquello que deshice", 8),
    // Format (15)
    ("ponlo con negritas ya", 12),
    ("dejalo en negrita ya", 10),
    ("aplica negritas al texto", 10),
    ("marca con negrita ya", 8),
    ("usa cursivas aqui", 10),
    ("ponlo con cursiva ya", 10),
    ("deja el texto en cursivas ya", 8),
    ("subraya esa cita", 10),
    ("aplica subrayado al texto", 10),
    ("resalta ese resultado", 10),
    ("remarca esa conclusion", 10),
    ("hazlo con negritas", 10),
    ("pon esa cita en cursivas", 8),
    ("marca ese texto en negrita", 8),
    ("deja esa frase en cursiva", 8),
    // Rename / delete / replace / rewrite / find / select / save / open / export
    ("cambia el encabezado a borrador", 8),
    ("pon como titulo borrador", 8),
    ("ponle ese nombre al acta", 8),
    ("titula ese informe como resumen", 8),
    ("renombra el acta a version previa", 8),
    ("actualiza el nombre a borrador final", 8),
    ("el titulo dira borrador previo", 8),
    ("nombra el anexo como apendice", 8),
    ("borra esa seleccion", 10),
    ("elimina aquello", 8),
    ("quita esa parte", 8),
    ("suprime ese parrafo", 8),
    ("tacha ese renglon", 8),
    ("corta ese fragmento", 8),
    ("descarta ese anexo", 8),
    ("reemplaza esa frase por borrador", 10),
    ("sustituye esa palabra por resumen", 10),
    ("cambia esa cita por borrador", 8),
    ("troca aquello por resumen", 8),
    ("escribe borrador previo", 8),
    ("pon resumen donde dice previo", 8),
    ("hazlo mas breve ya", 10),
    ("haz esa parte mas clara ya", 8),
    ("reescribe ese parrafo completo", 8),
    ("reformula aquello mas formal ya", 8),
    ("busca ese folio", 10),
    ("encuentra ese informe", 8),
    ("localiza ese resumen", 8),
    ("halla ese dato", 8),
    ("rastrea ese nombre", 8),
    ("selecciona ese parrafo", 10),
    ("marca esa frase ya", 8),
    ("elige ese apartado", 8),
    ("toma ese anexo", 8),
    ("guarda ese documento", 10),
    ("archiva ese informe", 8),
    ("respalda ese avance", 8),
    ("abre ese archivo previo", 10),
    ("recupera esa acta previa", 8),
    ("carga ese informe previo", 8),
    ("exporta a pdf ya", 10),
    ("guarda copia como pdf ya", 8),
    ("genera esa acta en word", 8),
    ("convierte ese texto a plano", 8),
    ("produce version en formato simple", 8),
    ("saca esa acta en pdf ya", 8),
    ("pon ese titulo en negritas", 8),
    ("cambia ese titulo a borrador", 8),
    ("busca la palabra resumen", 8),
    ("selecciona la palabra resumen", 8),
    ("vuelve atras sin guardar", 8),
    ("deshaz ultimo cambio ya", 8),
    ("rehaz ultimo cambio ya", 8),
]

// MARK: - Templates (body con <clase>, count) + clases
// Cuerpos diseñados para NO generar literalmente ninguna frase FINAL
// (usan vocabulario representativo distinto: borrador/resumen/folio/anexo,
// determinantes distintos, modificadores extra).
struct CustomLMTemplateDef {
    let body: String
    let count: Int
}

let customLMTemplates: [CustomLMTemplateDef] = [
    CustomLMTemplateDef(body: "cambia el encabezado a <titulo>", count: 8),
    CustomLMTemplateDef(body: "titula ese informe como <titulo>", count: 8),
    CustomLMTemplateDef(body: "busca ese <termino> previo", count: 10),
    CustomLMTemplateDef(body: "selecciona ese <objetivo> previo", count: 10),
    CustomLMTemplateDef(body: "exporta esa acta a <formato>", count: 8),
    CustomLMTemplateDef(body: "reemplaza aquello por <nuevoTexto>", count: 8),
    CustomLMTemplateDef(body: "pon <nuevoTexto> tras ese parrafo", count: 6),
    CustomLMTemplateDef(body: "deshaz <objetoUndo> ya", count: 12),
    CustomLMTemplateDef(body: "rehaz <objetoRedo> ya", count: 12),
    CustomLMTemplateDef(body: "ponlo con <estilo> ya", count: 10),
    CustomLMTemplateDef(body: "<verboGuardar> ese documento previo", count: 8),
    CustomLMTemplateDef(body: "abre ese <documento> previo", count: 8),
]

let customLMClasses: [String: [String]] = [
    "titulo": ["borrador", "resumen", "anexo", "acta previa", "version final"],
    "termino": ["folio", "resumen", "anexo", "dato", "acta"],
    "objetivo": ["apartado", "anexo", "resumen", "folio", "parrafo previo"],
    "formato": ["pdf", "word", "texto simple", "formato simple"],
    "nuevoTexto": ["borrador", "resumen", "anexo", "texto previo"],
    "objetoUndo": ["ese cambio", "esta edicion", "aquello", "ese formato"],
    "objetoRedo": ["ese cambio", "esta edicion", "ese formato", "aquello"],
    "estilo": ["negrita", "cursiva", "subrayado"],
    "verboGuardar": ["guarda", "archiva", "respalda"],
    "documento": ["acta previa", "informe previo", "anexo", "borrador"],
]

// MARK: - Construcción

func buildCustomLMData() -> SFCustomLanguageModelData {
    let data = SFCustomLanguageModelData(
        locale: customLMLocale,
        identifier: customLMIdentifier,
        version: customLMVersion
    )
    for pc in customLMPhraseCounts {
        data.insert(phraseCount: SFCustomLanguageModelData.PhraseCount(phrase: pc.phrase, count: pc.count))
    }
    let gen = SFCustomLanguageModelData.TemplatePhraseCountGenerator()
    for (k, v) in customLMClasses {
        gen.define(className: k, values: v)
    }
    for t in customLMTemplates {
        gen.insert(template: t.body, count: t.count)
    }
    data.insert(phraseCountGenerator: gen)
    return data
}

/// Expansión aproximada de templates para auditoría/leakage (producto cartesiano
/// de UNA clase por template; templates con 2+ clases se expanden por la primera
/// encontrada + conteo combinatorio estimado).
func expandCustomLMTemplates() -> [String] {
    var out: [String] = []
    for t in customLMTemplates {
        // Extrae <clase>
        var cls: String? = nil
        var cur = ""
        var inB = false
        for c in t.body {
            if c == "<" { inB = true; cur = "" }
            else if c == ">" { inB = false; cls = cur; break }
            else if inB { cur.append(c) }
        }
        if let c = cls, let vals = customLMClasses[c] {
            for v in vals {
                out.append(t.body.replacingOccurrences(of: "<\(c)>", with: v))
            }
        } else {
            out.append(t.body)
        }
    }
    return out
}

func allCustomLMPhrases() -> [String] {
    customLMPhraseCounts.map(\.phrase) + expandCustomLMTemplates()
}

// MARK: - Rutas

func customLMPaths() -> (asset: URL, lm: URL, vocab: URL) {
    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let dir = base.appendingPathComponent("data/custom_lm", isDirectory: true)
    let outDir = base.appendingPathComponent("data/custom_lm_compiled", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    return (
        asset: dir.appendingPathComponent("asset.bin"),
        lm: outDir.appendingPathComponent("lm.bin"),
        vocab: outDir.appendingPathComponent("vocab.bin")
    )
}

func loadCustomLMConfiguration() throws -> SFSpeechLanguageModel.Configuration {
    let p = customLMPaths()
    guard FileManager.default.fileExists(atPath: p.lm.path) else {
        throw NSError(domain: "CustomLM", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "falta modelo compilado en \(p.lm.path). Ejecuta `swift run GrammarTest prepare-lm` primero."])
    }
    let vocabExists = FileManager.default.fileExists(atPath: p.vocab.path)
    if vocabExists {
        return SFSpeechLanguageModel.Configuration(languageModel: p.lm, vocabulary: p.vocab, weight: customLMWeight())
    } else {
        return SFSpeechLanguageModel.Configuration(languageModel: p.lm, vocabulary: nil, weight: customLMWeight())
    }
}

// MARK: - Normalización para leakage (misma que gramática: lower + folding)

func normalizedForLeakage(_ s: String) -> String {
    s.lowercased()
        .folding(options: .diacriticInsensitive, locale: .current)
        .components(separatedBy: CharacterSet(charactersIn: ".,!?;:()\"'«»¿¡")).joined(separator: " ")
        .split(separator: " ").map(String.init).joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
