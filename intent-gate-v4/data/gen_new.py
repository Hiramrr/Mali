#!/usr/bin/env python3
"""Bloques nuevos V4: cobertura archivo/app, deícticos/enclíticos,
hard espejo, utterances cortas, fragmentos dictados."""
import csv
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
C, N = "EDITOR_CONTROL", "NON_CONTROL"
rows: list[tuple[str, str, str, str]] = []

def fam(prefix, label, cat, texts, size=6):
    clean = []
    for t in texts:
        t = t.strip()
        if t and t not in clean:
            clean.append(t)
    for i in range(0, len(clean), size):
        fid = f"{prefix}_{i//size:02d}"
        for t in clean[i:i+size]:
            rows.append((t, label, cat, fid))

# ---- archivo/app nuevos ----
CLOSE = ["este documento", "la ventana", "todas las pestañas", "el archivo",
         "el panel lateral", "la vista previa", "este borrador", "la sesión"]
for o in CLOSE:
    fam(f"n4_close_{o.split()[-1]}", C, "close",
        [f"Cierra {o}.", f"Cierra {o} por favor.", f"Ya puedes cerrar {o}.",
         f"Necesito que cierres {o}."])
SAVEAS = ["en el escritorio", "como borrador", "con fecha de hoy", "en la carpeta",
          "como plantilla", "en pdf", "con otro nombre", "en la nube"]
for o in SAVEAS:
    fam(f"n4_saveas_{o.split()[-1]}", C, "save-as",
        [f"Guarda {o}.", f"Guarda el archivo {o}.", f"Guarda una copia {o}."])
FR = ["los espacios dobles", "el nombre antiguo", "las comillas simples", "los guiones",
      "los acentos faltantes", "las mayúsculas", "los ceros de más", "la palabra repetida"]
for o in FR:
    fam(f"n4_findrep_{o.split()[1]}", C, "find-replace",
        [f"Busca {o} y corrígelos.", f"Encuentra {o} y arréglalos.",
         f"Localiza {o} en el texto."])
DUP = ["esta sección", "este bloque", "el formato", "la tabla", "el encabezado"]
for o in DUP:
    fam(f"n4_dup_{o.split()[-1]}", C, "duplicate",
        [f"Duplica {o}.", f"Duplica {o} abajo.", f"Haz un duplicado de {o}."])
SPELL = ["este capítulo", "lo seleccionado", "el documento", "esta página"]
for o in SPELL:
    fam(f"n4_spell_{o.split()[-1]}", C, "spellcheck",
        [f"Revisa la ortografía de {o}.", f"Pasa el corrector en {o}.",
         f"Verifica la ortografía de {o}."])
SUMM = ["este informe", "la minuta", "el capítulo", "lo anterior", "esta sección"]
for o in SUMM:
    fam(f"n4_sum_{o.split()[-1]}", C, "summarize",
        [f"Resume {o}.", f"Resume {o} en dos frases.", f"Haz un resumen de {o}."])
EXP = ["esta idea", "la introducción", "el ejemplo", "este argumento", "la conclusión"]
for o in EXP:
    fam(f"n4_exp_{o.split()[-1]}", C, "expand",
        [f"Expande {o}.", f"Desarrolla {o} con detalle.", f"Alarga {o} un poco."])
COMM = ["este párrafo", "la conclusión", "esta cifra", "el último cambio"]
for o in COMM:
    fam(f"n4_comm_{o.split()[-1]}", C, "comment",
        [f"Comenta {o}.", f"Agrega un comentario a {o}.", f"Deja una nota en {o}."])
AR = ["los cambios", "la sugerencia", "la corrección", "el formato nuevo"]
for o in AR:
    fam(f"n4_acrej_{o.split()[1]}", C, "accept-reject",
        [f"Acepta {o}.", f"Rechaza {o}.", f"Confirma {o}."])
REN = ["este archivo", "la carpeta", "el documento", "la versión"]
for o in REN:
    fam(f"n4_ren_{o.split()[-1]}", C, "rename",
        [f"Renombra {o}.", f"Cámbiale el nombre a {o}.", f"Ponle otro nombre a {o}."])
SYNC = ["la carpeta", "el proyecto", "los cambios", "tu copia"]
for o in SYNC:
    fam(f"n4_sync_{o.split()[1]}", C, "sync-share",
        [f"Sincroniza {o}.", f"Comparte {o} con el equipo.", f"Sube {o} a la nube."])
VIEW = ["la página", "el zoom", "hacia arriba", "hasta el final", "a la cita"]
for o in VIEW:
    fam(f"n4_view_{o.split()[-1]}", C, "view",
        [f"Ajusta {o}.", f"Ve {o}.", f"Desplázate {o}."])
GOTO = ["al índice", "a la firma", "al anexo", "al principio", "a la tabla"]
for o in GOTO:
    fam(f"n4_goto_{o.split()[-1]}", C, "go-to",
        [f"Ve {o}.", f"Salta {o}.", f"Llévame {o}."])
DOCP = ["el autor", "la fecha", "las palabras clave", "el idioma", "la versión"]
for o in DOCP:
    fam(f"n4_docp_{o.split()[1]}", C, "document-properties",
        [f"Actualiza {o} del documento.", f"Cambia {o} en propiedades.",
         f"Revisa {o} del archivo."])

# ---- deícticos/enclíticos ----
ENCL = ["Ábrelo", "Guárdalo", "Bórralo", "Márcalo", "Súbelo", "Muévelo",
        "Cópialo", "Pégalo", "Respáldalo", "Léelo", "Revísalo", "Acéptalo",
        "Recházalo", "Ciérralo", "Imprímelo", "Compártelo", "Renómbralo",
        "Bájalo", "Envíalo", "Fírmalo", "Archívalo", "Sincronízalo"]
for v in ENCL:
    fam(f"n4_encl_{v[:5]}", C, "deictico",
        [f"{v}.", f"{v} ya.", f"{v} por favor.", f"Por favor, {v[0].lower() + v[1:]}."])
DEIC = ["Hazlo más corto", "Ponlo aquí", "Déjalo igual", "Vuelve a ponerlo",
        "Cambia esa parte", "Quita eso", "Ponlo allá", "Déjalo así",
        "Muévelo acá", "Cámbialo de lugar", "Ponlo bonito", "Déjalo claro"]
for d in DEIC:
    fam(f"n4_deic_{d.split()[0]}", C, "deictico",
        [f"{d}.", f"{d}, por favor.", f"¿Puedes {d[0].lower() + d[1:]}?"])

# ---- hard espejo ----
MIRROR = [
    "Abrir documentos grandes puede ser lento.",
    "Guarda es una forma verbal del verbo guardar.",
    "Imprimir documentos utiliza papel.",
    "Buscar información puede tomar tiempo.",
    "Copiar texto puede introducir duplicados.",
    "Firmar documentos digitalmente requiere autenticación.",
    "Sincronizar información entre dispositivos puede generar conflictos.",
    "Renombrar archivos facilita su organización.",
    "Leer en voz alta puede apoyar la revisión.",
    "Cerrar sesiones viejas libera memoria.",
    "Guardar copias impresas ocupa archiveros.",
    "Abrir debates largos cansa al público.",
    "Imprimir actas oficiales exige sello.",
    "Buscar culpables rara vez ayuda.",
    "Copiar diseños registrados infringe derechos.",
    "Pegar afiches viejos decora cuartos.",
    "Leer contratos ajenos indispone.",
    "Exportar datos personales vulnera privacidad.",
    "Compartir contraseñas es temerario.",
    "Sincronizar relojes antiguos es ritual.",
    "Renombrar mascotas confunde veterinarios.",
    "Borrar historiales clínicos es delito.",
    "Cambiar pañales fríos despierta bebés.",
    "Mover rocas gigantes exige grúa.",
    "Cortar listones inaugura obras.",
    "Firmar autógrafos cansa muñecas.",
    "Revisar mochilas ajenas ofende.",
    "Aceptar sobornos destruye carreras.",
    "Separar gemelos idénticos confunde.",
    "Navegar ríos bravos emociona.",
    "Duplicar recetas caseras une familias.",
    "Traducir refranes pierde gracia.",
    "Contar chistes malos aburre.",
    "Ordenar discos viejos entretiene.",
    "Insertar comerciales interrumpe películas.",
    "Combinar estampados arriesga el look.",
    "Archivar cartas viejas conmueve.",
    "Reenviar memes satura grupos.",
    "Comprimir equipaje ahorra tarifas.",
]
fam("n4_mirror", N, "hard-espejo", MIRROR, size=6)

# ---- cortas control ----
SHORT_C = ["Bórralo.", "Guárdalo.", "Deshaz eso.", "Ponlo aquí.", "Ábrelo.",
           "Busca esto.", "Léelo.", "Fírmalo.", "Cierra eso.", "Abre esto.",
           "Imprime ya.", "Guarda ya.", "Copia eso.", "Pega aquí.", "Mueve eso.",
           "Cambia eso.", "Quita eso.", "Pon eso.", "Haz eso.", "Mira esto.",
           "Escucha esto.", "Repite eso.", "Anula eso.", "Confirma eso.",
           "Rechaza eso.", "Acepta eso.", "Envía eso.", "Sube eso.", "Baja eso."]
fam("n4_shortc", C, "corto", SHORT_C, size=6)

# ---- cortas non-control ----
SHORT_N = ["No sé.", "Tal vez.", "Bueno.", "Un momento.", "Estoy pensando.",
           "Así parece.", "Quién sabe.", "Ya veremos.", "A ver pues.",
           "Hmm.", "Eh.", "Ay.", "Uf.", "Oh.", "Ah.", "Mmm, no.",
           "Pues sí.", "Pues no.", "Claro.", "Obvio.", "Nel pastel.",
           "Simón que sí.", "Arre pues.", "Sale.", "Va.", "Dale.",
           "Listo pues.", "Ahorita.", "Al ratito.", "Luego vemos."]
fam("n4_shortn", N, "corto", SHORT_N, size=6)

# ---- fragmentos dictados (sustantivos) ----
FRAGD = ["Accesibilidad cognitiva.", "Interacción multimodal.", "Resultados preliminares.",
         "Metodología propuesta.", "Diseño centrado en el usuario.", "Carga mental reducida.",
         "Entrada por voz.", "Reconocimiento automático.", "Fatiga visual.",
         "Sesiones cortas.", "Retroalimentación inmediata.", "Barreras de acceso.",
         "Pruebas con usuarios.", "Análisis cualitativo.", "Trabajo futuro.",
         "Marco teórico.", "Estado del arte.", "Preguntas abiertas.",
         "Hallazgos principales.", "Limitaciones del estudio."]
fam("n4_fragd", N, "fragmento-dictado", FRAGD, size=6)

with open(HERE / "pool_new.csv", "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f)
    w.writerow(["text", "label", "category", "family_id"])
    for t, l, c, fid in rows:
        w.writerow([t, l, c, fid])
print(f"new: {len(rows)} fams={len({r[3] for r in rows})}", file=sys.stderr)
