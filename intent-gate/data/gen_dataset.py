#!/usr/bin/env python3
"""Genera dataset.csv (entrenamiento) y verifica leakage contra holdout.csv.

Determinista: seed fija. NO incluye frases del holdout.
"""
import csv
import random
import re
import sys
from pathlib import Path

SEED = 42
rng = random.Random(SEED)
HERE = Path(__file__).resolve().parent

TITLES = ["Metodología", "Resultados", "Introducción", "Conclusiones", "Marco teórico",
          "Diseño del sistema", "Trabajo futuro", "Evaluación", "Antecedentes",
          "Discusión", "Resumen", "Bibliografía", "Anexos", "Claridad"]
WORDS = ["dificultades", "interfaz", "accesibilidad", "sistema", "diseño",
         "término", "expresión", "palabra", "concepto", "párrafo"]
SECTIONS = ["el segundo párrafo", "la última sección", "el primer capítulo",
            "la introducción", "el resumen", "esta página"]

C, D = "EDITOR_CONTROL", "DICTATION"
rows: list[tuple[str, str, str]] = []

# Holdout: exclusión antes de generar (además del check posterior).
def norm(s: str) -> str:
    s = s.strip().lower()
    s = re.sub(r"^[\s\"'“”‘’«»¿?¡!.,;:()\[\]-]+|[\s\"'“”‘’«»¿?¡!.,;:()\[\]-]+$", "", s)
    s = re.sub(r"\s+", " ", s)
    return s

with open(HERE / "holdout.csv", encoding="utf-8") as f:
    HOLDOUT_NORMS = {norm(r["text"]) for r in csv.DictReader(f)}

skipped_holdout = 0

def add(text, label, cat):
    global skipped_holdout
    text = text.strip()
    if not text:
        return
    if norm(text) in HOLDOUT_NORMS:
        skipped_holdout += 1
        return
    rows.append((text, label, cat))

# ---------------- EDITOR_CONTROL ----------------
# título
for t in TITLES[:12]:
    add(f"Cambia el título a {t}.", C, "control/titulo")
for t in ["Arquitectura del sistema", "Resultados finales", "Versión revisada"]:
    add(f"Pon como título {t}.", C, "control/titulo")
for t in TITLES[2:10]:
    add(f"Quiero que cambies el título a {t}.", C, "control/titulo")
for t in TITLES[4:12]:
    add(f"El título cámbialo a {t}.", C, "control/titulo")
add("¿Puedes ponerle título a este documento?", C, "control/titulo")
add("Actualiza el encabezado con el nombre del proyecto.", C, "control/titulo")
add("Cambia el encabezado a Introducción.", C, "control/titulo")
add("Reescribe el título para que sea más descriptivo.", C, "control/titulo")
add("Corrige el título, tiene una errata.", C, "control/titulo")
add("Haz el título más corto.", C, "control/titulo")

# borrar / eliminar
for obj in ["esto", "eso", "esta parte", "esta oración", "este párrafo", "este texto",
            "la última frase", "esta palabra", "lo seleccionado", "esa sección"]:
    add(f"Borra {obj}.", C, "control/borrar")
for obj in ["esta parte", "este fragmento", "esta oración", "este párrafo"]:
    add(f"¿Puedes quitar {obj}?", C, "control/borrar")
for obj in ["esto", "esa parte", "este párrafo"]:
    add(f"Esto mejor elimínalo: {obj} sobra.", C, "control/borrar")
add("Quita esta oración.", C, "control/borrar")
add("Elimina el último párrafo.", C, "control/borrar")
add("Suprime la sección repetida.", C, "control/borrar")
add("Quita esto.", C, "control/borrar")
add("Borra este texto.", C, "control/borrar")
add("Esto no va, bórralo.", C, "control/borrar")
add("Corta esta parte y pégala al final.", C, "control/borrar")
add("Limpia este párrafo.", C, "control/borrar")
add("Vacía esta sección.", C, "control/borrar")
add("Descarta el último cambio de redacción.", C, "control/borrar")
add("Quita la palabra repetida.", C, "control/borrar")
add("Borra desde aquí hasta el final.", C, "control/borrar")
add("Elimina todo lo que está entre paréntesis.", C, "control/borrar")
add("Quita los espacios duplicados.", C, "control/borrar")

# reemplazar / sustituir
for w in WORDS[:8]:
    add(f"Cambia esta palabra por {w}.", C, "control/reemplazar")
for pair in [("error", "errata"), ("problema", "dificultad"), ("uso", "utilización"),
             ("cosa", "elemento"), ("parte", "sección")]:
    add(f"Sustituye {pair[0]} por {pair[1]}.", C, "control/reemplazar")
for w in WORDS[2:9]:
    add(f"Reemplaza la última palabra por {w}.", C, "control/reemplazar")
add("Sustituye esa expresión por algo más claro.", C, "control/reemplazar")
add("Cambia todas las menciones al autor anterior.", C, "control/reemplazar")
add("Reemplaza este término en todo el documento.", C, "control/reemplazar")
add("Corrige el nombre del modelo en este párrafo.", C, "control/reemplazar")
add("Pon dificultades donde dice problemas.", C, "control/reemplazar")
add("Intercambia el orden de estos dos párrafos.", C, "control/reemplazar")
add("Cambia las comillas inglesas por latinas.", C, "control/reemplazar")
add("Sustituye los números por letras.", C, "control/reemplazar")
for w in ["accesibilidad", "interfaz", "sistema"]:
    add(f"Reemplaza esta palabra por {w}.", C, "control/reemplazar")

# reformular / reescribir
for inst in ["más corto", "más formal", "más claro", "menos absoluto", "más breve",
             "más directo", "más sencillo", "más académico", "menos redundante"]:
    add(f"Hazlo {inst}.", C, "control/reformular")
for inst in ["más corto", "más formal", "más claro", "más breve"]:
    add(f"Haz este párrafo {inst}.", C, "control/reformular")
add("Reescribe esto con un tono más formal.", C, "control/reformular")
add("Reescribe esta oración sin cambiar su significado.", C, "control/reformular")
add("Reformula el último párrafo.", C, "control/reformular")
add("Dale otra redacción a esta parte.", C, "control/reformular")
add("Mejora la redacción de lo seleccionado.", C, "control/reformular")
add("Haz esta frase más elegante.", C, "control/reformular")
add("Suaviza el tono de este párrafo.", C, "control/reformular")
add("Endurece la conclusión.", C, "control/reformular")
add("Haz esto más persuasivo.", C, "control/reformular")
add("Simplifica la explicación.", C, "control/reformular")
add("Acorta este párrafo.", C, "control/reformular")
add("Extiende un poco esta idea.", C, "control/reformular")
add("Desarrolla más este argumento.", C, "control/reformular")
add("Condensa estas tres frases en una.", C, "control/reformular")

# resumir / expandir
add("Resume este documento en un párrafo.", C, "control/resumir")
add("Haz un resumen de lo seleccionado.", C, "control/resumir")
add("Sintetiza las ideas principales.", C, "control/resumir")
add("Extrae los puntos clave de esta sección.", C, "control/resumir")
add("Resume lo anterior en dos frases.", C, "control/resumir")
add("Dame un resumen ejecutivo.", C, "control/resumir")
add("Expande esta sección con más detalles.", C, "control/expandir")
add("Alarga la introducción.", C, "control/expandir")
add("Añade un ejemplo a este párrafo.", C, "control/expandir")
add("Completa esta idea.", C, "control/expandir")
add("Agrega una frase de transición aquí.", C, "control/expandir")

# formato
for fmt in ["negritas", "cursivas"]:
    for det in ["esto", "este texto", "lo seleccionado", "esta frase"]:
        add(f"Pon {det} en {fmt}.", C, "control/formato")
add("Subraya esto.", C, "control/formato")
add("Subraya esta parte.", C, "control/formato")
add("Pon este fragmento en cursivas.", C, "control/formato")
add("Quita las negritas de aquí.", C, "control/formato")
add("Aumenta el tamaño de letra del título.", C, "control/formato")
add("Pon el título en mayúsculas.", C, "control/formato")
add("Convierte esto en una lista.", C, "control/formato")
add("Aplica el estilo de cita a este párrafo.", C, "control/formato")
add("Centra este encabezado.", C, "control/formato")
add("Justifica el texto seleccionado.", C, "control/formato")
add("Ponlo en negritas.", C, "control/formato")
add("Marca esto como importante.", C, "control/formato")

# undo
for u in ["Deshaz el último cambio.", "Deshaz el cambio.", "Deshaz eso.",
          "Vuelve a como estaba.", "No, déjalo como estaba.", "Revierte lo último que hiciste.",
          "Cancela la última edición.", "Deshaz la última acción.", "Regresa al estado anterior.",
          "Anula lo que acabas de hacer."]:
    add(u, C, "control/undo")
add("Quiero deshacer lo anterior.", C, "control/undo")
add("Échalo para atrás.", C, "control/undo")

# redo
for r in ["Rehaz el cambio anterior.", "Rehaz lo anterior.", "Rehaz el cambio.",
          "Vuelve a aplicar lo que deshiciste.", "Repite la última acción.",
          "Rehaz eso.", "Adelante con el cambio otra vez.", "Recupera lo que deshiciste."]:
    add(r, C, "control/redo")
add("Deshaz el deshacer.", C, "control/redo")
add("Rehaz la edición.", C, "control/redo")

# selección
for s in SECTIONS:
    add(f"Selecciona {s}.", C, "control/seleccion")
add("Selecciona todo el documento.", C, "control/seleccion")
add("Marca esta oración.", C, "control/seleccion")
add("Elige el tercer párrafo.", C, "control/seleccion")
add("Selecciona desde aquí hasta el final.", C, "control/seleccion")
add("Amplía la selección una palabra.", C, "control/seleccion")
add("Reduce la selección.", C, "control/seleccion")
add("Selecciona la palabra anterior.", C, "control/seleccion")
add("Marca todo lo que sigue.", C, "control/seleccion")

# navegación
for n in ["Ve al final del documento.", "Sube al principio.", "Muévete a la siguiente sección.",
          "Baja dos párrafos.", "Coloca el cursor al inicio.", "Salta al título.",
          "Ve a la página anterior.", "Desplázate hasta el resumen.",
          "Pon el cursor después de esta frase.", "Lléame a las conclusiones."]:
    add(n, C, "control/navegacion")

# corrección
for c in ["Corrige esta palabra.", "Corrige la ortografía de lo seleccionado.",
          "Revisa las tildes de este párrafo.", "Arregla la puntuación.",
          "Hay una errata, corrígela.", "Verifica la gramática de esta frase.",
          "Normaliza las comillas.", "Corrige los espacios dobles."]:
    add(c, C, "control/correccion")

# tono
for t in ["Haz esto más formal.", "Dale un tono más cercano.", "Hazlo más técnico.",
          "Hazlo más divulgativo.", "Cambia el tono a neutro.", "Hazlo sonar más seguro."]:
    add(t, C, "control/tono")

# transformar
for t in ["Convierte esto a mayúsculas.", "Pasa este texto a minúsculas.",
          "Convierte la lista en párrafo.", "Divide este párrafo en dos.",
          "Une estas dos frases.", "Ordena alfabéticamente esta lista.",
          "Numera estos puntos.", "Convierte esto en tabla."]:
    add(t, C, "control/transformar")

# deícticas / incompletas (son control aunque no ejecutables)
for d in ["Cámbialo.", "Pon eso.", "Borra eso.", "Quita esto.", "Hazlo.", "Cambia esa parte.",
          "Ponlo diferente.", "Hazlo más corto.", "Hazlo diferente.", "Esto quítalo.",
          "Eso cámbialo.", "Déjalo como antes.", "Ponlo como estaba.", "Esto déjalo igual.",
          "Ese no, el otro.", "Arregla eso.", "Mejora esto.", "Cambia esto.", "Mueve eso aquí.",
          "Copia esto abajo.", "Pega lo que copiaste.", "Guarda el documento.", "Deshaz eso."]:
    add(d, C, "control/deictico")

# ---------------- DICTATION ----------------
# académico dominio real
ACA = [
    "La interacción humano computadora estudia la relación entre las personas y los sistemas interactivos.",
    "Durante los últimos años se han desarrollado nuevas interfaces multimodales.",
    "Mi proyecto busca diseñar un editor de texto para personas con TDAH.",
    "Las personas pueden experimentar dificultades durante tareas prolongadas de escritura.",
    "Las interfaces multimodales combinan voz, teclado y gestos en un mismo sistema.",
    "La accesibilidad cognitiva reduce la carga mental durante la escritura.",
    "Los usuarios con TDAH se benefician de sesiones cortas y retroalimentación inmediata.",
    "La usabilidad de un editor depende de la claridad de sus mecanismos de control.",
    "El reconocimiento de voz permite dictar documentos completos sin utilizar el teclado.",
    "Los gestos táctiles complementan la entrada tradicional en tabletas modernas.",
    "Un estudio reciente evaluó la fatiga durante tareas de escritura prolongada.",
    "Los participantes prefirieron interfaces con menos interrupciones visuales.",
    "La multimodalidad distribuye la atención entre varios canales sensoriales.",
    "El diseño centrado en el usuario requiere pruebas con personas reales.",
    "La carga cognitiva aumenta cuando el sistema exige demasiadas decisiones.",
    "Los editores modernos incorporan correctores automáticos cada vez más precisos.",
    "La escritura asistida plantea preguntas interesantes sobre autoría y control.",
    "Un experimento comparó dictado por voz frente a escritura manual.",
    "Los resultados sugieren menor esfuerzo percibido con entrada multimodal.",
    "La tesis analiza barreras de acceso en herramientas de productividad.",
    "El capítulo siguiente describe el protocolo de evaluación con usuarios.",
    "La muestra incluyó estudiantes universitarios con diagnóstico de TDAH.",
    "Cada sesión duró aproximadamente cuarenta y cinco minutos.",
    "Las métricas incluyeron tiempo de tarea y errores cometidos.",
    "El análisis cualitativo reveló tres temas principales.",
    "La discusión relaciona los hallazgos con literatura previa sobre accesibilidad.",
    "El trabajo futuro explorará adaptaciones personalizadas del editor.",
    "La voz como modalidad principal reduce la dependencia del teclado físico.",
    "Los sistemas interactivos deben tolerar expresiones incompletas del hablante.",
    "Una interfaz bien diseñada anticipa las necesidades de quien escribe.",
]
for a in ACA:
    add(a, D, "dict/academico")
# paráfrasis académicas generadas por combinación (diversidad sintáctica)
SUJ = ["El estudio", "La investigación", "El análisis", "El experimento", "La evaluación",
       "El prototipo", "El sistema propuesto", "La herramienta", "El modelo", "La encuesta"]
PRED = ["muestra mejoras claras en velocidad de escritura.",
        "confirma la importancia del contexto durante el dictado.",
        "revela patrones interesantes de uso de la voz.",
        "sugiere nuevas líneas de trabajo futuro.",
        "destaca la relevancia de la accesibilidad cognitiva.",
        "aporta evidencia sobre fatiga en tareas prolongadas.",
        "propone un marco para evaluar editores multimodales.",
        "describe limitaciones del reconocimiento automático.",
        "incluye recomendaciones prácticas de diseño.",
        "permitió observar estrategias espontáneas de los participantes."]
for s in SUJ:
    for p in PRED[:4]:
        add(f"{s} {p}", D, "dict/academico")
for s in SUJ[3:8]:
    for p in PRED[4:8]:
        add(f"{s} {p}", D, "dict/academico")
for s in SUJ[5:]:
    for p in PRED[6:]:
        add(f"{s} {p}", D, "dict/academico")

# expositivo general
GEN_SUBJ = ["El informe", "La presentación", "El documento", "La propuesta", "El artículo",
            "La carta", "El ensayo", "La memoria", "El resumen", "La crónica"]
GEN_PRED = ["quedó listo ayer por la tarde.", "incluye tres secciones principales.",
            "será revisado por el equipo editorial.", "circula ya entre los asistentes.",
            "necesita una última lectura atenta.", "describe el proceso con detalle.",
            "recoge opiniones de varios expertos.", "cierra con una reflexión abierta."]
for s in GEN_SUBJ:
    for p in GEN_PRED[:4]:
        add(f"{s} {p}", D, "dict/general")
for s in GEN_SUBJ[4:]:
    for p in GEN_PRED[4:]:
        add(f"{s} {p}", D, "dict/general")
for s in GEN_SUBJ[:4]:
    for p in GEN_PRED[6:]:
        add(f"{s} {p}", D, "dict/general")

# hard negatives: infinitivos con vocabulario de comando
INF = [
    "Borrar archivos accidentalmente puede generar problemas graves.",
    "Cambiar el formato sin avisar confunde a quien lee.",
    "Seleccionar adecuadamente la muestra determina la validez del estudio.",
    "Reemplazar palabras sin criterio empobrece el texto.",
    "Deshacer acciones forma parte del aprendizaje con herramientas nuevas.",
    "Poner títulos descriptivos facilita la navegación del documento.",
    "Eliminar párrafos enteros debería requerir confirmación previa.",
    "Rehacer un trabajo desde cero consume demasiado tiempo.",
    "Borrar información accidentalmente puede afectar la experiencia.",
    "Cambiar el título puede ayudar a comunicar mejor el objetivo.",
    "Deshacer una acción debería resultar sencillo para cualquier persona.",
    "Seleccionar participantes correctamente exige criterios explícitos.",
    "Poner texto en negritas permite destacar información importante.",
    "Reemplazar palabras automáticamente puede introducir errores inesperados.",
    "Borrar datos por accidente provoca pérdida de información valiosa.",
    "Cambiar un encabezado modifica la interpretación de una sección.",
    "Deshacer una modificación debería ser una operación sencilla.",
    "Seleccionar correctamente una muestra es fundamental para el estudio.",
    "Reemplazar términos automáticamente puede introducir errores sutiles.",
    "Poner demasiado texto en negritas reduce su utilidad visual.",
    "Eliminar contenido sin confirmación resulta frustrante.",
    "Rehacer una acción permite recuperar un cambio revertido.",
    "Borrar texto accidentalmente es frustrante para cualquiera.",
    "Cambiar el título mejora la claridad del documento.",
    "Deshacer modificaciones es una función importante del editor.",
    "Seleccionar bien las palabras define el tono del mensaje.",
    "Reemplazar expresiones coloquiales eleva el registro del texto.",
    "Poner ejemplos concretos ayuda a entender ideas abstractas.",
    "Cambiar de tema bruscamente desorienta al lector.",
    "Borrar el pizarrón al final de la clase es costumbre aquí.",
]
for t in INF:
    add(t, D, "dict/hard-infinitivo")

# hard negatives: citas
CIT = [
    'La frase "borra esto" puede resultar ambigua sin contexto.',
    'Un ejemplo de comando sería "pon esto en negritas".',
    'La documentación utiliza la instrucción "deshaz el cambio".',
    'El manual incluye el ejemplo "cambia el título a Resultados".',
    'En clase analizamos la orden "selecciona el segundo párrafo".',
    'El tutorial muestra cómo decir "hazlo más corto".',
    'La expresión "cambia esa parte" aparece en las instrucciones.',
    'Voy a escribir la frase: reemplaza esta palabra por accesibilidad.',
    'Quiero escribir que el usuario puede pedir "hazlo más corto".',
    'El comando "borra esto" necesita un referente claro.',
    'Una persona podría decir "pon esto en negritas" para dar formato.',
    'En el ejemplo anterior el usuario dijo "deshaz el cambio".',
    'La consigna "reescribe este párrafo" confunde a algunos estudiantes.',
    'Escuché a alguien decir "quita esta oración" durante la prueba.',
    'El artículo cita la instrucción "subraya esta parte".',
]
for t in CIT:
    add(t, D, "dict/hard-cita")

# hard negatives: metalenguaje
MET = [
    "El comando borrar elimina el contenido seleccionado.",
    "La función deshacer restaura el estado anterior del documento.",
    "La opción reemplazar busca coincidencias en todo el texto.",
    "El botón guardar conserva una copia automáticamente.",
    "El menú formato agrupa las opciones de estilo disponibles.",
    "La herramienta de selección permite marcar varios fragmentos.",
    "El historial de cambios registra cada edición realizada.",
    "El corrector sugiere alternativas mientras se escribe.",
    "El dictado por voz interpreta pausas como signos de puntuación.",
    "El editor permite cambiar el título desde la barra superior.",
    "La función deshacer recupera el contenido anterior sin esfuerzo.",
    "El corrector automático puede reemplazar palabras mientras escribes.",
    "Seleccionar texto con el teclado requiere práctica inicial.",
    "El título del documento aparece en la ventana principal.",
]
for t in MET:
    add(t, D, "dict/hard-metalenguaje")

# hard negatives: primera persona como contenido
PRI = [
    "Quiero escribir que el editor puede cambiar el título automáticamente.",
    "Voy a contar que borrar párrafos me cuesta mucho trabajo.",
    "Pienso explicar que deshacer cambios tranquiliza a quien escribe.",
    "Quiero decir que seleccionar bien las ideas ordena el texto.",
    "Voy a escribir que poner ejemplos mejora cualquier explicación.",
    "Me gustaría contar que reemplazar términos aclara el mensaje.",
    "Quiero mencionar que cambiar de enfoque renovó mi proyecto.",
    "Pienso escribir que el comando deshacer salvó mi documento ayer.",
]
for t in PRI:
    add(t, D, "dict/hard-primera-persona")

# expositivo con vocabulario de comando (no infinitivo)
MIX = [
    "Es importante cambiar la manera en que diseñamos interfaces.",
    "Borrar información sin respaldo es una mala práctica profesional.",
    "El título debe comunicar claramente el objetivo del proyecto.",
    "Seleccionar correctamente los participantes es importante para el estudio.",
    "Deshacer una acción debería ser sencillo para el usuario.",
    "Reemplazar el cable dañado resolvió el problema del laboratorio.",
    "Poner la mesa antes de cenar es tradición en mi casa.",
    "Cambiar de opinión con nuevos datos es señal de criterio.",
    "El editor de la revista pidió cambios antes del viernes.",
    "Borró su presentación anterior y empezó de nuevo.",
    "La ponente cambió el título a última hora.",
    "Seleccionaron tres casos para el análisis detallado.",
    "El taller enseña a reemplazar piezas defectuosas.",
    "Pusieron subtítulos en negritas para cada sección.",
    "Deshizo el nudo con paciencia antes de continuar.",
]
for t in MIX:
    add(t, D, "dict/hard-mixto")

# fragmentos conversacionales (decisión documentada: van a DICTATION porque
# el binario obliga a elegir y lo seguro es alejarlos del control)
FRAG = ["Eso no.", "Mejor.", "No me gusta.", "Ese.", "Así está bien.",
        "Hmm, no.", "Bueno.", "Tal vez.", "Ya veo.", "Claro.", "Entiendo.",
        "De acuerdo.", "Perfecto.", "Interesante.", "Vaya.", "Ah, sí.",
        "Mmm.", "Vale.", "Exacto.", "Correcto.", "Ajá.", "Oh.", "Bien.",
        "Ni idea.", "Quién sabe.", "Puede ser.", "Ya.", "Listo.", "Hecho.",
        "Siguiente.", "Continúa.", "Prosigue.", "Te escucho.", "Dime.",
        "A ver.", "Espera.", "Un momento.", "Pausa.", "Sigo.", "Adelante."]
for t in FRAG:
    add(t, D, "dict/fragmento")

# ---------------- EXPANSIÓN (volumen + diversidad) ----------------
T2 = ["Metodología", "Resultados", "Conclusiones", "Evaluación", "Discusión",
      "Resumen", "Anexos", "Propuesta", "Hallazgos", "Limitaciones"]
for t in T2:
    add(f"Cámbiale el título a {t}.", C, "control/titulo")
    add(f"Ponle de título {t}.", C, "control/titulo")
    add(f"Titula esto como {t}.", C, "control/titulo")
    add(f"Actualiza el título a {t}.", C, "control/titulo")
for t in T2[:6]:
    add(f"Modifica el título a {t}.", C, "control/titulo")
    add(f"Renombra el documento como {t}.", C, "control/titulo")
    add(f"El nuevo título será {t}.", C, "control/titulo")

OBJ = ["este párrafo", "esta sección", "la cita", "el ejemplo", "la nota al pie",
       "el encabezado", "la lista", "el último bloque", "esta tabla", "el apéndice"]
for o in OBJ:
    add(f"Elimina {o}.", C, "control/borrar")
    add(f"Suprime {o}.", C, "control/borrar")
    add(f"Descarta {o}.", C, "control/borrar")
for o in OBJ[:6]:
    add(f"Corta {o}.", C, "control/borrar")
    add(f"Limpia {o}.", C, "control/borrar")

PAIRS = [("título", "encabezado"), ("inicio", "comienzo"), ("fin", "cierre"),
         ("imagen", "figura"), ("cuadro", "tabla"), ("autor", "autora"),
         ("capítulo", "sección"), ("nota", "aclaración")]
for a, b in PAIRS:
    add(f"Cambia {a} por {b} en este párrafo.", C, "control/reemplazar")
    add(f"Sustituye cada {a} por {b}.", C, "control/reemplazar")

for inst in ["más persuasivo", "más neutral", "más conciso", "más extenso",
             "más crítico", "más descriptivo", "menos técnico", "más urgente"]:
    add(f"Reescribe lo seleccionado {inst}.", C, "control/reformular")
    add(f"Vuelve a redactar esto {inst}.", C, "control/reformular")

for fmt in ["negritas", "cursiva"]:
    for o in ["el título", "esta frase", "el ejemplo", "la conclusión"]:
        add(f"Aplica {fmt} a {o}.", C, "control/formato")
        add(f"Resalta {o} en {fmt}.", C, "control/formato")
add("Pon en cursiva la cita.", C, "control/formato")
add("Marca la conclusión en negritas.", C, "control/formato")

for u in ["Deshaz lo último.", "Deshaz la edición anterior.", "Echa para atrás el cambio.",
          "Anula la última modificación.", "Vuelve atrás.", "Deshaz lo que hiciste.",
          "Retrocede un paso.", "Cancela lo anterior."]:
    add(u, C, "control/undo")
for r in ["Rehaz la última acción.", "Reaplica el cambio.", "Vuelve a hacer lo anterior.",
          "Adelante con lo deshecho.", "Restaura la edición.", "Repite lo que quitaste."]:
    add(r, C, "control/redo")
for s in ["la cita", "el ejemplo", "el título", "toda la página", "este bloque"]:
    add(f"Selecciona {s}.", C, "control/seleccion")
    add(f"Marca {s}.", C, "control/seleccion")
for n in ["Baja hasta las conclusiones.", "Sube a la introducción.",
          "Salta a la siguiente página.", "Ve al principio del párrafo.",
          "Coloca el cursor al final.", "Retrocede una sección."]:
    add(n, C, "control/navegacion")
for c in ["Corrige las mayúsculas.", "Revisa la concordancia de este texto.",
          "Arregla los guiones largos.", "Unifica el formato de fechas.",
          "Corrige el estilo de las citas.", "Pule la puntuación final."]:
    add(c, C, "control/correccion")
for t in ["Hazlo más solemne.", "Hazlo más coloquial.", "Dale un aire profesional.",
          "Hazlo más optimista.", "Vuelve el tono más serio."]:
    add(t, C, "control/tono")
for t in ["Pasa todo a mayúsculas.", "Pon en minúsculas el título.",
          "Divide la lista en dos columnas.", "Fusiona estos párrafos.",
          "Convierte los puntos en lista numerada.", "Parte esta oración larga."]:
    add(t, C, "control/transformar")
for d in ["Haz eso.", "Cambia aquello.", "Quita aquello.", "Ponlo ahí.",
          "Mueve esto allá.", "Arregla aquello.", "Copia eso.", "Borra aquello.",
          "Esto mismo, cámbialo.", "Lo mismo pero más corto.", "Igual pero en formal.",
          "Repite eso.", "Otra vez.", "Así no, de la otra forma.", "Como estaba antes.",
          "Hazle lo mismo a este.", "Igual que el anterior.", "Aplica lo mismo aquí."]:
    add(d, C, "control/deictico")

ACA2 = [
    "El dictado continuo exige modelos tolerantes a pausas y titubeos.",
    "La mirada puede complementar la voz como señal deíctica.",
    "Los comandos hablados reducen el uso del menú en usuarios expertos.",
    "La confirmación explícita evita modificaciones accidentales del texto.",
    "El historial de revisiones facilita el trabajo colaborativo asíncrono.",
    "Las personas mayores prefieren instrucciones paso a paso muy explícitas.",
    "El contraste alto mejora la legibilidad en pantallas pequeñas.",
    "La latencia percibida afecta la confianza en el asistente de escritura.",
    "Un buen editor distingue dictado de órdenes sin pedir aclaraciones.",
    "La personalización del vocabulario mejora el reconocimiento de nombres propios.",
    "Los atajos de teclado conviven con la entrada por voz sin conflicto.",
    "El subrayado automático de errores guía la revisión posterior.",
    "La lectura en voz alta ayuda a detectar frases demasiado largas.",
    "El modo sin distracciones oculta barras y menús secundarios.",
    "Guardar versiones intermedias protege contra pérdidas inesperadas.",
    "La sincronización en la nube plantea dilemas de privacidad evidentes.",
    "El tamaño de fuente ajustable beneficia a personas con baja visión.",
    "Los temas oscuros reducen la fatiga visual en sesiones nocturnas.",
    "La autocorrección agresiva puede cambiar palabras correctamente escritas.",
    "El portapapeles múltiple acelera la reorganización de fragmentos.",
    "Arrastrar y soltar sigue siendo útil junto al control por voz.",
    "Las plantillas estructuran documentos repetitivos con eficacia.",
    "El conteo de palabras orienta el cumplimiento de límites editoriales.",
    "Exportar a varios formatos evita fricciones con coautores.",
    "La escritura colaborativa necesita indicar quién cambió cada parte.",
    "El control de cambios colorea inserciones y eliminaciones recientes.",
    "Aceptar todas las revisiones cierra el ciclo de edición colectiva.",
    "El bloqueo de secciones evita ediciones simultáneas conflictivas.",
    "Los comentarios al margen enriquecen la discusión sobre el borrador.",
    "Resolver comentarios uno por uno ordena la revisión final.",
]
for a in ACA2:
    add(a, D, "dict/academico")
SUJ2 = ["La tesis", "El informe", "La prueba piloto", "El grupo focal", "El cuestionario",
        "La entrevista", "El registro de uso", "La sesión observada", "El corpus", "El taller"]
PRED2 = ["aborda la ambigüedad de las órdenes habladas.",
         "cuantifica interrupciones durante la redacción.",
         "compara tres estrategias de confirmación.",
         "documenta errores típicos del dictado automático.",
         "propone umbrales conservadores para acciones automáticas.",
         "evalúa satisfacción con escalas validadas.",
         "registra el número de correcciones por minuto.",
         "concluye con pautas para diseñadores de editores.",
         "será publicado como capítulo de libro.",
         "quedó archivado junto al material suplementario."]
for s in SUJ2:
    for p in PRED2[:5]:
        add(f"{s} {p}", D, "dict/academico")
for s in SUJ2[4:]:
    for p in PRED2[5:]:
        add(f"{s} {p}", D, "dict/academico")

GEN2S = ["El acta", "La minuta", "El boletín", "La reseña", "El manifiesto",
         "La semblanza", "El parte", "La fe de erratas", "El compendio", "La antología"]
GEN2P = ["apareció publicada esta mañana.", "recibió comentarios favorables.",
         "será traducida a dos idiomas.", "pasó por tres rondas de corrección.",
         "incluye fotografías de archivo.", "llegó con retraso a la redacción.",
         "menciona a varios colaboradores.", "cierra con agradecimientos."]
for s in GEN2S:
    for p in GEN2P[:4]:
        add(f"{s} {p}", D, "dict/general")
for s in GEN2S[5:]:
    for p in GEN2P[4:]:
        add(f"{s} {p}", D, "dict/general")

INF2 = [
    "Borrar mensajes antiguos libera espacio en el teléfono.",
    "Cambiar contraseñas con frecuencia refuerza la seguridad.",
    "Seleccionar un buen asiento mejora la experiencia del vuelo.",
    "Reemplazar la batería extendió la vida del portátil.",
    "Deshacer la maleta lleva menos tiempo del esperado.",
    "Poner límites claros evita malentendidos en el equipo.",
    "Eliminar duplicados ordenó por fin la biblioteca.",
    "Rehacer el presupuesto trimestral tomó toda la tarde.",
    "Borrar pizarras digitales requiere un gesto específico.",
    "Cambiar de carril sin señalizar es peligroso.",
    "Deshacer nudos marineros exige paciencia y práctica.",
    "Seleccionar frutas maduras se aprende con la experiencia.",
    "Poner atención plena transforma cualquier conversación.",
    "Reemplazar focos fundidos iluminó toda la sala.",
    "Eliminar barreras arquitectónicas beneficia a toda la comunidad.",
    "Borrar huellas del navegador protege la privacidad básica.",
    "Cambiar la ruta habitual descubrió un parque nuevo.",
]
for t in INF2:
    add(t, D, "dict/hard-infinitivo")
CIT2 = [
    'El profesor dictó la consigna "lean el capítulo tres".',
    'El cartel advierte "no borrar este aviso".',
    'La guía recomienda decir "siguiente" para avanzar.',
    'El ejemplo del libro usa "seleccionar todo" sin comillas simples.',
    'La nota al pie aclara "título provisional sujeto a cambios".',
    'El examen pide "describa el procedimiento" en pasado.',
    'La rúbrica exige "cambios justificados" en cada entrega.',
    'El foro discute si "hacerlo más corto" pierde matices.',
]
for t in CIT2:
    add(t, D, "dict/hard-cita")
MET2 = [
    "El modo dictado desactiva temporalmente los atajos de formato.",
    "La papelera conserva archivos eliminados durante treinta días.",
    "El atajo de deshacer funciona en casi todas las aplicaciones.",
    "El selector de idioma aparece en la barra de estado.",
    "El reemplazo de texto expande abreviaturas frecuentes.",
    "El panel de estilos centraliza títulos y citas.",
    "El título de la ventana refleja el archivo abierto.",
    "La vista de esquema colapsa secciones completas.",
]
for t in MET2:
    add(t, D, "dict/hard-metalenguaje")
PRI2 = [
    "Voy a narrar que cambiar de ciudad me enseñó a adaptarme.",
    "Quiero relatar que borrar aquel mensaje fue un alivio.",
    "Pienso contar que seleccionar el tema llevó semanas.",
    "Me propongo escribir que poner límites me ayudó a avanzar.",
    "Voy a explicar que reemplazar hábitos cuesta varios intentos.",
]
for t in PRI2:
    add(t, D, "dict/hard-primera-persona")
MIX2 = [
    "Cambiaron la cerradura después del incidente.",
    "Borraban la pizarra entre clase y clase.",
    "Eligieron seleccionar muestras al azar.",
    "Reemplazaron al ponente por motivos de agenda.",
    "Puso énfasis en Negritas el diseñador del cartel.",
    "Deshicieron el trato antes de firmarlo.",
    "El título del partido se decidió en penales.",
    "Seleccionar es un verbo que describe muy bien el estudio.",
    "Borrar es la acción más temida por los novatos.",
    "Cambiaron el formato del festival este año.",
]
for t in MIX2:
    add(t, D, "dict/hard-mixto")
FRAG2 = ["Ya casi.", "Falta poco.", "Sigo pensando.", "Déjame ver.", "A ver si entiendo.",
         "Claro que sí.", "Por supuesto.", "Desde luego.", "Qué bien.", "Qué raro.",
         "No sé.", "No estoy seguro.", "Depende.", "Más o menos.", "Eso creo.",
         "Supongo.", "Imagino.", "Ojalá.", "Oye.", "Mira.", "Fíjate.", "Anda.",
         "Venga.", "Hala.", "Uf.", "Ay.", "Eh.", "Pues.", "Bueno, sigo.",
         "Nada más.", "Eso es todo.", "Fin del párrafo.", "Punto final."]
for t in FRAG2:
    add(t, D, "dict/fragmento")

# ---------------- EXPANSIÓN 2 (cierre a ~600/600 y hard>=25%) ----------------
T3 = ["Introducción", "Antecedentes", "Metodología", "Resultados",
      "Discusión", "Conclusiones", "Referencias", "Apéndice"]
for t in T3:
    add(f"Cambia el título a {t}, por favor.", C, "control/titulo")
    add(f"Por favor pon como título {t}.", C, "control/titulo")
    add(f"Necesito que el título sea {t}.", C, "control/titulo")
    add(f"Haz que el título diga {t}.", C, "control/titulo")
OBJ2 = ["el borrador", "la transcripción", "el duplicado", "la versión vieja",
        "el comentario resuelto", "la firma", "el sello", "la marca de agua"]
for o in OBJ2:
    add(f"Borra {o}.", C, "control/borrar")
    add(f"Quita {o} de aquí.", C, "control/borrar")
    add(f"Elimina {o} por favor.", C, "control/borrar")
PAIRS2 = [("resumen", "síntesis"), ("objetivo", "propósito"), ("método", "procedimiento"),
          ("dato", "cifra"), ("gráfico", "figura"), ("anexo", "apéndice")]
for a, b in PAIRS2:
    add(f"Cambia el {a} por {b}.", C, "control/reemplazar")
    add(f"Donde dice {a} pon {b}.", C, "control/reemplazar")
for inst in ["más amable", "más enérgico", "más poético", "más sobrio"]:
    add(f"Reformula esto {inst}.", C, "control/reformular")
    add(f"Dale un giro {inst} a este texto.", C, "control/reformular")
for f in ["Aplica subrayado a lo seleccionado.", "Pon en negrita el primer párrafo.",
          "Convierte la cita en cursivas.", "Agranda la letra de esta parte.",
          "Reduce el interlineado.", "Aplica viñetas a esta lista.",
          "Sangra este párrafo.", "Cambia la fuente del título."]:
    add(f, C, "control/formato")
for u in ["Deshaz la última edición.", "Da un paso atrás.", "Anula la modificación.",
          "Vuelve al borrador anterior.", "Recupera la versión previa."]:
    add(u, C, "control/undo")
for r in ["Rehaz la acción.", "Vuelve a aplicar el cambio.", "Recupera lo deshecho."]:
    add(r, C, "control/redo")
for s in ["el subtítulo", "la primera línea", "el último renglón"]:
    add(f"Selecciona {s}.", C, "control/seleccion")
    add(f"Resalta {s} con el cursor.", C, "control/seleccion")
for n in ["Avanza a la conclusión.", "Retrocede al resumen.", "Salta dos secciones."]:
    add(n, C, "control/navegacion")
for c in ["Corrige la redacción.", "Pule este texto.", "Ajusta la puntuación."]:
    add(c, C, "control/correccion")
for t in ["Vuelve esto más claro.", "Hazlo menos ambiguo."]:
    add(t, C, "control/tono")
for t in ["Mayusculiza cada palabra del título.", "Minusculiza esta oración."]:
    add(t, C, "control/transformar")
for d in ["Cambia eso ya.", "Borra ya esto.", "Hazlo ahora.", "Ponlo ya.",
          "Quita eso de una vez.", "Arréglalo.", "Modifica esto.", "Edita esa parte.",
          "Trabaja este párrafo.", "Ocúpate de esta sección.", "Encárgate de esto."]:
    add(d, C, "control/deictico")

INF3 = [
    "Borrar historiales antiguos es una práctica recomendada.",
    "Cambiar tipografías altera la personalidad del documento.",
    "Seleccionar fondos claros favorece la lectura prolongada.",
    "Reemplazar conectores repetidos mejora la fluidez.",
    "Deshacer particiones del disco requiere herramientas especiales.",
    "Poner subtítulos descriptivos orienta al espectador.",
    "Eliminar anuncios emergentes agiliza la navegación.",
    "Rehacer maquetas del proyecto consumió el fin de semana.",
    "Borrar caché de la aplicación liberó dos gigabytes.",
    "Cambiar pañales es rutina en la guardería.",
    "Deshacer costuras permite ajustar el vestido.",
    "Seleccionar el menú degustación fue un acierto.",
]
for t in INF3:
    add(t, D, "dict/hard-infinitivo")
CIT3 = [
    'El aviso dice "no cambiar la configuración".',
    'La etiqueta indica "reemplazar cada seis meses".',
    'El letrero pide "seleccionar una opción".',
    'La receta ordena "poner a fuego lento".',
    'El formulario solicita "borrar lo que no aplique".',
    'El guion marca "pausa y continúa".',
]
for t in CIT3:
    add(t, D, "dict/hard-cita")
MET3 = [
    "El corrector de estilo sugiere dividir oraciones largas.",
    "El inspector de documento resume estadísticas básicas.",
    "El modo control por voz enumera sus comandos disponibles.",
    "El asistente de escritura propone reformulaciones opcionales.",
    "El panel de navegación lista todos los encabezados.",
    "El registro de actividad muestra quién editó cada línea.",
]
for t in MET3:
    add(t, D, "dict/hard-metalenguaje")
PRI3 = [
    "Voy a describir que poner orden alivió el caos inicial.",
    "Quiero plasmar que borrar borradores libera espacio mental.",
    "Pienso relatar que deshacer acuerdos cuesta más que firmarlos.",
    "Me dispongo a escribir que seleccionar despacio rinde mejor.",
    "Voy a anotar que reemplazar quejas por propuestas unió al grupo.",
]
for t in PRI3:
    add(t, D, "dict/hard-primera-persona")
MIX3 = [
    "El jurado cambió el veredicto tras la apelación.",
    "Borraron grafitis del centro durante la madrugada.",
    "Seleccionar al azar garantiza imparcialidad estadística.",
    "Reemplazó la bombilla antes de que anocheciera.",
    "Ponen música suave en negritas no, en la sala de espera.",
    "Deshicieron las maletas nada más llegar.",
    "El título nobiliario recayó en la hija mayor.",
    "Poner fin a la reunión llevó otra hora de debate.",
]
for t in MIX3:
    add(t, D, "dict/hard-mixto")
ACA3S = ["El taller", "El seminario", "La mesa redonda", "El póster", "La demo",
         "El video", "El podcast", "El blog", "La wiki", "El manual"]
ACA3P = ["explica cómo dictar sin mirar la pantalla.",
         "resume hallazgos sobre control por voz.",
         "incluye transcripciones anonimizadas.",
         "muestra capturas del prototipo evaluado.",
         "cierra con preguntas abiertas al público."]
for s in ACA3S:
    for p in ACA3P[:3]:
        add(f"{s} {p}", D, "dict/academico")
for s in ACA3S[5:]:
    for p in ACA3P[3:]:
        add(f"{s} {p}", D, "dict/academico")
GEN3S = ["La gaceta", "El folleto", "El tríptico", "La separata", "El anuario"]
GEN3P = ["saldrá el próximo mes.", "agotó su primera edición.",
         "llegó ayer a los suscriptores.", "incluye un índice detallado."]
for s in GEN3S:
    for p in GEN3P[:3]:
        add(f"{s} {p}", D, "dict/general")
for s in GEN3S[2:]:
    for p in GEN3P[2:]:
        add(f"{s} {p}", D, "dict/general")

# ---------------- dedupe + balance ----------------
print(f"excluidas por holdout durante generación: {skipped_holdout}", file=sys.stderr)
seen = set()
uniq: list[tuple[str, str, str]] = []
for text, label, cat in rows:
    if text not in seen:
        seen.add(text)
        uniq.append((text, label, cat))

n_control = sum(1 for _, l, _ in uniq if l == C)
n_dict = sum(1 for _, l, _ in uniq if l == D)
print(f"CONTROL={n_control} DICTATION={n_dict} TOTAL={len(uniq)}", file=sys.stderr)
hard = sum(1 for _, l, c in uniq if l == D and c.startswith("dict/hard"))
print(f"hard negatives dictation: {hard} ({100.0*hard/max(n_dict,1):.1f}%)", file=sys.stderr)

# ---------------- leakage check ----------------
def norm(s: str) -> str:
    s = s.strip().lower()
    s = re.sub(r"^[\s\"'“”‘’«»¿?¡!.,;:()\[\]-]+|[\s\"'“”‘’«»¿?¡!.,;:()\[\]-]+$", "", s)
    s = re.sub(r"\s+", " ", s)
    return s

train_norms = {norm(t) for t, _, _ in uniq}
leaks = []
with open(HERE / "holdout.csv", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        if norm(row["text"]) in train_norms:
            leaks.append(row["text"])
if leaks:
    print("ERROR_DATA_LEAKAGE:", file=sys.stderr)
    for t in leaks:
        print(f"  DUP: {t}", file=sys.stderr)
    sys.exit(1)
print("leakage check: OK (0 duplicados exactos normalizados)", file=sys.stderr)

with open(HERE / "dataset.csv", "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f)
    w.writerow(["text", "label", "category"])
    w.writerows(uniq)
print(f"dataset.csv escrito: {len(uniq)} filas", file=sys.stderr)
