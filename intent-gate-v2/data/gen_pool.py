#!/usr/bin/env python3
"""Pool TRAIN/CALIBRATION con family_id. Determinista (seed 42).

NO escribe splits ni toca FINAL_TEST_V2. Cada bloque de textos se trocea
en familias de ~6 para permitir split por familias.
"""
import csv
import random
import sys
from pathlib import Path

SEED = 42
rng = random.Random(SEED)
HERE = Path(__file__).resolve().parent

C, D = "EDITOR_CONTROL", "DICTATION"
rows: list[tuple[str, str, str, str]] = []

def fam_block(prefix, label, cat, texts, size=6):
    clean = []
    for t in texts:
        t = t.strip()
        if t and t not in clean:
            clean.append(t)
    for i in range(0, len(clean), size):
        fid = f"{prefix}_{i//size:02d}"
        for t in clean[i:i+size]:
            rows.append((t, label, cat, fid))

TITLES = ["Metodología", "Resultados", "Introducción", "Conclusiones", "Marco teórico",
          "Diseño del sistema", "Trabajo futuro", "Evaluación", "Antecedentes",
          "Discusión", "Resumen", "Bibliografía", "Anexos", "Claridad", "Hallazgos",
          "Limitaciones", "Propuesta", "Referencias", "Apéndice", "Síntesis"]
WORDS = ["dificultades", "interfaz", "accesibilidad", "sistema", "diseño",
         "término", "expresión", "palabra", "concepto", "párrafo", "encabezado",
         "sección", "figura", "tabla", "resumen"]

# ---------- CONTROL: título ----------
tt = []
for t in TITLES:
    tt.append(f"Cambia el título a {t}.")
fam_block("c_titulo_a", C, "titulo", tt)
tt = []
for t in TITLES[:14]:
    tt.append(f"Pon como título {t}.")
    tt.append(f"Quiero que cambies el título a {t}.")
fam_block("c_titulo_b", C, "titulo", tt)
tt = []
for t in TITLES:
    tt.append(f"Cámbiale el título a {t}.")
    tt.append(f"Actualiza el título a {t}.")
fam_block("c_titulo_c", C, "titulo", tt)
tt = []
for t in TITLES[:12]:
    tt.append(f"El título cámbialo a {t}.")
    tt.append(f"Ponle de título {t}.")
    tt.append(f"Titula esto como {t}.")
fam_block("c_titulo_d", C, "titulo", tt)
fam_block("c_titulo_e", C, "titulo", [
    "¿Puedes ponerle título a este documento?",
    "Actualiza el encabezado con el nombre del proyecto.",
    "Cambia el encabezado a Introducción.",
    "Reescribe el título para que sea más descriptivo.",
    "Corrige el título, tiene una errata.",
    "Haz el título más corto.",
    "Modifica el título a Conclusiones.",
    "Renombra el documento como Borrador final.",
    "El nuevo título será Versión revisada.",
    "Cambia el título a Claridad, por favor.",
    "Por favor pon como título Resumen.",
    "Necesito que el título sea Evaluación.",
    "Haz que el título diga Discusión.",
    "Mayusculiza cada palabra del título.",
    "Minusculiza esta oración.",
])

# ---------- CONTROL: borrar ----------
OBJ = ["esto", "eso", "esta parte", "esta oración", "este párrafo", "este texto",
       "la última frase", "esta palabra", "lo seleccionado", "esa sección",
       "el borrador", "la transcripción", "el duplicado", "la versión vieja",
       "el comentario resuelto", "este párrafo", "esta sección", "la cita",
       "el ejemplo", "la nota al pie", "el encabezado", "la lista",
       "el último bloque", "esta tabla", "el apéndice", "la firma"]
bb = []
for o in OBJ:
    bb.append(f"Borra {o}.")
fam_block("c_borrar_a", C, "borrar", bb)
bb = []
for o in OBJ:
    bb.append(f"Elimina {o}.")
    bb.append(f"Quita {o}.")
fam_block("c_borrar_b", C, "borrar", bb)
bb = []
for o in OBJ[:16]:
    bb.append(f"Suprime {o}.")
    bb.append(f"Descarta {o}.")
fam_block("c_borrar_c", C, "borrar", bb)
fam_block("c_borrar_d", C, "borrar", [
    "¿Puedes quitar esta parte?", "¿Puedes quitar este fragmento?",
    "Esto mejor elimínalo, sobra.", "Quita esta oración.",
    "Elimina el último párrafo.", "Suprime la sección repetida.",
    "Esto no va, bórralo.", "Corta esta parte y pégala al final.",
    "Limpia este párrafo.", "Vacía esta sección.",
    "Descarta el último cambio de redacción.", "Quita la palabra repetida.",
    "Borra desde aquí hasta el final.", "Elimina todo lo que está entre paréntesis.",
    "Quita los espacios duplicados.", "Quita eso de aquí.",
    "Elimina eso por favor.", "Borra eso ya.",
    "Corta el borrador.", "Limpia la transcripción.",
])

# ---------- CONTROL: reemplazar ----------
PAIRS = [("error", "errata"), ("problema", "dificultad"), ("uso", "utilización"),
         ("cosa", "elemento"), ("parte", "sección"), ("título", "encabezado"),
         ("inicio", "comienzo"), ("fin", "cierre"), ("imagen", "figura"),
         ("cuadro", "tabla"), ("autor", "autora"), ("capítulo", "sección"),
         ("nota", "aclaración"), ("resumen", "síntesis"), ("objetivo", "propósito"),
         ("método", "procedimiento"), ("dato", "cifra"), ("gráfico", "figura")]
rr = []
for a, b in PAIRS:
    rr.append(f"Sustituye {a} por {b}.")
    rr.append(f"Reemplaza {a} por {b}.")
fam_block("c_reemplazar_a", C, "reemplazar", rr)
rr = []
for a, b in PAIRS:
    rr.append(f"Cambia {a} por {b} en este párrafo.")
    rr.append(f"Donde dice {a} pon {b}.")
fam_block("c_reemplazar_b", C, "reemplazar", rr)
rr = []
for w in WORDS:
    rr.append(f"Cambia esta palabra por {w}.")
    rr.append(f"Reemplaza esta palabra por {w}.")
fam_block("c_reemplazar_c", C, "reemplazar", rr)
fam_block("c_reemplazar_d", C, "reemplazar", [
    "Sustituye esa expresión por algo más claro.",
    "Cambia todas las menciones al autor anterior.",
    "Reemplaza este término en todo el documento.",
    "Corrige el nombre del modelo en este párrafo.",
    "Pon dificultades donde dice problemas.",
    "Intercambia el orden de estos dos párrafos.",
    "Cambia las comillas inglesas por latinas.",
    "Sustituye los números por letras.",
    "Cambia cada mención al capítulo dos.",
    "Sustituye los ejemplos desactualizados.",
])

# ---------- CONTROL: reformular / resumir / expandir ----------
INST = ["más corto", "más formal", "más claro", "menos absoluto", "más breve",
        "más directo", "más sencillo", "más académico", "menos redundante",
        "más persuasivo", "más neutral", "más conciso", "más extenso",
        "más crítico", "más descriptivo", "menos técnico", "más urgente",
        "más amable", "más enérgico", "más sobrio", "más llano"]
rf = []
for inst in INST:
    rf.append(f"Hazlo {inst}.")
fam_block("c_reformular_a", C, "reformular", rf)
rf = []
for inst in INST[:12]:
    rf.append(f"Haz este párrafo {inst}.")
    rf.append(f"Reescribe lo seleccionado {inst}.")
fam_block("c_reformular_b", C, "reformular", rf)
fam_block("c_reformular_c", C, "reformular", [
    "Reescribe esto con un tono más formal.",
    "Reescribe esta oración sin cambiar su significado.",
    "Reformula el último párrafo.", "Dale otra redacción a esta parte.",
    "Mejora la redacción de lo seleccionado.", "Haz esta frase más elegante.",
    "Suaviza el tono de este párrafo.", "Endurece la conclusión.",
    "Haz esto más persuasivo.", "Simplifica la explicación.",
    "Acorta este párrafo.", "Extiende un poco esta idea.",
    "Desarrolla más este argumento.", "Condensa estas tres frases en una.",
    "Vuelve a redactar esto más conciso.", "Dale un giro sobrio a este texto.",
    "Reformula esto más amable.", "Hazle lo mismo a este párrafo.",
])
fam_block("c_resumir", C, "resumir", [
    "Resume este documento en un párrafo.", "Haz un resumen de lo seleccionado.",
    "Sintetiza las ideas principales.", "Extrae los puntos clave de esta sección.",
    "Resume lo anterior en dos frases.", "Dame un resumen ejecutivo.",
    "Resume el capítulo en una lista.", "Condensa la introducción.",
])
fam_block("c_expandir", C, "expandir", [
    "Expande esta sección con más detalles.", "Alarga la introducción.",
    "Añade un ejemplo a este párrafo.", "Completa esta idea.",
    "Agrega una frase de transición aquí.", "Desarrolla este punto.",
    "Añade contexto a la conclusión.", "Extiende el resumen.",
])

# ---------- CONTROL: formato ----------
ff = []
for fmt in ["negritas", "cursivas"]:
    for det in ["esto", "este texto", "lo seleccionado", "esta frase",
                "el título", "esta frase clave", "el ejemplo", "la conclusión"]:
        ff.append(f"Pon {det} en {fmt}.")
fam_block("c_formato_a", C, "formato", ff)
fam_block("c_formato_b", C, "formato", [
    "Subraya esto.", "Subraya esta parte.", "Pon este fragmento en cursivas.",
    "Quita las negritas de aquí.", "Aumenta el tamaño de letra del título.",
    "Pon el título en mayúsculas.", "Convierte esto en una lista.",
    "Aplica el estilo de cita a este párrafo.", "Centra este encabezado.",
    "Justifica el texto seleccionado.", "Ponlo en negritas.",
    "Marca esto como importante.", "Aplica subrayado a lo seleccionado.",
    "Pon en negrita el primer párrafo.", "Convierte la cita en cursivas.",
    "Agranda la letra de esta parte.", "Reduce el interlineado.",
    "Aplica viñetas a esta lista.", "Sangra este párrafo.",
    "Cambia la fuente del título.", "Resalta el título en negritas.",
])

# ---------- CONTROL: undo / redo ----------
fam_block("c_undo", C, "undo", [
    "Deshaz el último cambio.", "Deshaz el cambio.", "Deshaz eso.",
    "Vuelve a como estaba.", "No, déjalo como estaba.",
    "Revierte lo último que hiciste.", "Cancela la última edición.",
    "Deshaz la última acción.", "Regresa al estado anterior.",
    "Anula lo que acabas de hacer.", "Quiero deshacer lo anterior.",
    "Échalo para atrás.", "Deshaz lo último.", "Deshaz la edición anterior.",
    "Echa para atrás el cambio.", "Anula la última modificación.",
    "Vuelve atrás.", "Deshaz lo que hiciste.", "Retrocede un paso.",
    "Cancela lo anterior.", "Deshaz la última edición.",
    "Da un paso atrás.", "Anula la modificación.",
    "Vuelve al borrador anterior.", "Recupera la versión previa.",
])
fam_block("c_redo", C, "redo", [
    "Rehaz el cambio anterior.", "Rehaz lo anterior.", "Rehaz el cambio.",
    "Vuelve a aplicar lo que deshiciste.", "Repite la última acción.",
    "Rehaz eso.", "Adelante con el cambio otra vez.",
    "Recupera lo que deshiciste.", "Deshaz el deshacer.", "Rehaz la edición.",
    "Rehaz la última acción.", "Reaplica el cambio.",
    "Vuelve a hacer lo anterior.", "Adelante con lo deshecho.",
    "Restaura la edición.", "Repite lo que quitaste.",
    "Rehaz la acción.", "Vuelve a aplicar el cambio.", "Recupera lo deshecho.",
])

# ---------- CONTROL: selección / navegación / corrección / tono / transformar ----------
SEL = ["el segundo párrafo", "la última sección", "el primer capítulo",
       "la introducción", "el resumen", "esta página", "la cita", "el ejemplo",
       "el título", "toda la página", "este bloque", "el subtítulo"]
ss = []
for s in SEL:
    ss.append(f"Selecciona {s}.")
    ss.append(f"Marca {s}.")
fam_block("c_seleccion", C, "seleccion", ss + [
    "Selecciona todo el documento.", "Elige el tercer párrafo.",
    "Selecciona desde aquí hasta el final.", "Amplía la selección una palabra.",
    "Reduce la selección.", "Selecciona la palabra anterior.",
    "Marca todo lo que sigue.", "Resalta el subtítulo con el cursor.",
])
fam_block("c_navegacion", C, "navegacion", [
    "Ve al final del documento.", "Sube al principio.",
    "Muévete a la siguiente sección.", "Baja dos párrafos.",
    "Coloca el cursor al inicio.", "Salta al título.",
    "Ve a la página anterior.", "Desplázate hasta el resumen.",
    "Pon el cursor después de esta frase.", "Lléame a las conclusiones.",
    "Baja hasta las conclusiones.", "Sube a la introducción.",
    "Salta a la siguiente página.", "Ve al principio del párrafo.",
    "Coloca el cursor al final.", "Retrocede una sección.",
    "Avanza a la conclusión.", "Retrocede al resumen.", "Salta dos secciones.",
])
fam_block("c_correccion", C, "correccion", [
    "Corrige esta palabra.", "Corrige la ortografía de lo seleccionado.",
    "Revisa las tildes de este párrafo.", "Arregla la puntuación.",
    "Hay una errata, corrígela.", "Verifica la gramática de esta frase.",
    "Normaliza las comillas.", "Corrige los espacios dobles.",
    "Corrige las mayúsculas.", "Revisa la concordancia de este texto.",
    "Arregla los guiones largos.", "Unifica el formato de fechas.",
    "Corrige el estilo de las citas.", "Pule la puntuación final.",
    "Corrige la redacción.", "Pule este texto.", "Ajusta la puntuación.",
])
fam_block("c_tono", C, "tono", [
    "Haz esto más formal.", "Dale un tono más cercano.", "Hazlo más técnico.",
    "Hazlo más divulgativo.", "Cambia el tono a neutro.", "Hazlo sonar más seguro.",
    "Hazlo más solemne.", "Hazlo más coloquial.", "Dale un aire profesional.",
    "Hazlo más optimista.", "Vuelve el tono más serio.",
    "Vuelve esto más claro.", "Hazlo menos ambiguo.",
])
fam_block("c_transformar", C, "transformar", [
    "Convierte esto a mayúsculas.", "Pasa este texto a minúsculas.",
    "Convierte la lista en párrafo.", "Divide este párrafo en dos.",
    "Une estas dos frases.", "Ordena alfabéticamente esta lista.",
    "Numera estos puntos.", "Convierte esto en tabla.",
    "Pasa todo a mayúsculas.", "Pon en minúsculas el título.",
    "Divide la lista en dos columnas.", "Fusiona estos párrafos.",
    "Convierte los puntos en lista numerada.", "Parte esta oración larga.",
])

# ---------- CONTROL: deícticos ----------
fam_block("c_deictico", C, "deictico", [
    "Cámbialo.", "Pon eso.", "Borra eso.", "Quita esto.", "Hazlo.",
    "Cambia esa parte.", "Ponlo diferente.", "Hazlo diferente.",
    "Esto quítalo.", "Eso cámbialo.", "Déjalo como antes.",
    "Ponlo como estaba.", "Esto déjalo igual.", "Ese no, el otro.",
    "Arregla eso.", "Mejora esto.", "Cambia esto.", "Mueve eso aquí.",
    "Copia esto abajo.", "Pega lo que copiaste.", "Guarda el documento.",
    "Deshaz eso.", "Haz eso.", "Cambia aquello.", "Quita aquello.",
    "Ponlo ahí.", "Mueve esto allá.", "Arregla aquello.", "Copia eso.",
    "Borra aquello.", "Esto mismo, cámbialo.", "Lo mismo pero más corto.",
    "Igual pero en formal.", "Repite eso.", "Otra vez.",
    "Así no, de la otra forma.", "Como estaba antes.",
    "Hazle lo mismo a este.", "Igual que el anterior.", "Aplica lo mismo aquí.",
    "Cambia eso ya.", "Borra ya esto.", "Hazlo ahora.", "Ponlo ya.",
    "Quita eso de una vez.", "Arréglalo.", "Modifica esto.", "Edita esa parte.",
    "Trabaja este párrafo.", "Ocúpate de esta sección.", "Encárgate de esto.",
    "Esto quítalo ya.", "Ponlo ya en forma.",
])

# ---------- DICTATION: académico ----------
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
]
fam_block("d_academico_base", D, "academico", ACA)
SUJ = ["El estudio", "La investigación", "El análisis", "El experimento", "La evaluación",
       "El prototipo", "El sistema propuesto", "La herramienta", "El modelo", "La encuesta",
       "La tesis", "El informe", "La prueba piloto", "El grupo focal", "El cuestionario"]
PRED = ["muestra mejoras claras en velocidad de escritura.",
        "confirma la importancia del contexto durante el dictado.",
        "revela patrones interesantes de uso de la voz.",
        "sugiere nuevas líneas de trabajo futuro.",
        "destaca la relevancia de la accesibilidad cognitiva.",
        "aporta evidencia sobre fatiga en tareas prolongadas.",
        "propone un marco para evaluar editores multimodales.",
        "describe limitaciones del reconocimiento automático.",
        "aborda la ambigüedad de las órdenes habladas.",
        "cuantifica interrupciones durante la redacción.",
        "compara tres estrategias de confirmación.",
        "documenta errores típicos del dictado automático."]
xx = []
for s in SUJ:
    for p in PRED[:4]:
        xx.append(f"{s} {p}")
fam_block("d_academico_suj_a", D, "academico", xx)
xx = []
for s in SUJ:
    for p in PRED[4:8]:
        xx.append(f"{s} {p}")
fam_block("d_academico_suj_b", D, "academico", xx)
xx = []
for s in SUJ[5:]:
    for p in PRED[8:]:
        xx.append(f"{s} {p}")
fam_block("d_academico_suj_c", D, "academico", xx)

# ---------- DICTATION: general ----------
GS = ["El informe", "La presentación", "El documento", "La propuesta", "El artículo",
      "La carta", "El ensayo", "La memoria", "El resumen", "La crónica",
      "El acta", "La minuta", "El boletín", "La reseña", "El manifiesto"]
GP = ["quedó listo ayer por la tarde.", "incluye tres secciones principales.",
      "será revisado por el equipo editorial.", "circula ya entre los asistentes.",
      "necesita una última lectura atenta.", "describe el proceso con detalle.",
      "recoge opiniones de varios expertos.", "cierra con una reflexión abierta.",
      "apareció publicada esta mañana.", "pasó por tres rondas de corrección."]
gg = []
for s in GS:
    for p in GP[:4]:
        gg.append(f"{s} {p}")
fam_block("d_general_a", D, "general", gg)
gg = []
for s in GS:
    for p in GP[4:8]:
        gg.append(f"{s} {p}")
fam_block("d_general_b", D, "general", gg)
gg = []
for s in GS[5:]:
    for p in GP[8:]:
        gg.append(f"{s} {p}")
fam_block("d_general_c", D, "general", gg)

# ---------- DICTATION hard: infinitivos ----------
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
    "Borrar mensajes antiguos libera espacio en el teléfono.",
    "Cambiar contraseñas con frecuencia refuerza la seguridad.",
    "Seleccionar un buen asiento mejora la experiencia del vuelo.",
    "Reemplazar la batería extendió la vida del portátil.",
    "Deshacer la maleta lleva menos tiempo del esperado.",
    "Poner límites claros evita malentendidos en el equipo.",
    "Eliminar duplicados ordenó por fin la biblioteca.",
    "Rehacer el presupuesto trimestral tomó toda la tarde.",
    "Borrar historiales antiguos es una práctica recomendada.",
    "Cambiar tipografías altera la personalidad del documento.",
    "Seleccionar fondos claros favorece la lectura prolongada.",
    "Reemplazar conectores repetidos mejora la fluidez.",
    "Deshacer particiones del disco requiere herramientas especiales.",
    "Poner subtítulos descriptivos orienta al espectador.",
    "Eliminar anuncios emergentes agiliza la navegación.",
    "Rehacer maquetas del proyecto consumió el fin de semana.",
    "Modificar registros antiguos exige permisos especiales.",
    "Subrayar ideas clave facilita el repaso posterior.",
    "Rehacer cálculos extensos introduce errores de arrastre.",
    "Seleccionar el menú degustación fue un acierto.",
]
fam_block("d_hard_inf", D, "hard-infinitivo", INF)

# ---------- DICTATION hard: citas ----------
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
    'El profesor dictó la consigna "lean el capítulo tres".',
    'El cartel advierte "no borrar este aviso".',
    'La guía recomienda decir "siguiente" para avanzar.',
    'La nota al pie aclara "título provisional sujeto a cambios".',
    'El examen pide "describa el procedimiento" en pasado.',
    'La rúbrica exige "cambios justificados" en cada entrega.',
    'El aviso dice "no cambiar la configuración".',
    'La etiqueta indica "reemplazar cada seis meses".',
    'El letrero pide "seleccionar una opción".',
    'La receta ordena "poner a fuego lento".',
    'El formulario solicita "borrar lo que no aplique".',
    'La instrucción "borra esto" aparece en el ejemplo.',
    'Una persona puede decir "cambia el título a Resultados".',
    'La frase "hazlo más corto" necesita contexto.',
]
fam_block("d_hard_cita", D, "hard-cita", CIT)

# ---------- DICTATION hard: metalenguaje ----------
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
    "El modo dictado desactiva temporalmente los atajos de formato.",
    "La papelera conserva archivos eliminados durante treinta días.",
    "El atajo de deshacer funciona en casi todas las aplicaciones.",
    "El selector de idioma aparece en la barra de estado.",
    "El reemplazo de texto expande abreviaturas frecuentes.",
    "El panel de estilos centraliza títulos y citas.",
    "El comando borrar elimina la selección.",
    "La opción deshacer restaura el cambio anterior.",
    "Cambiar un título puede modificar la interpretación.",
    "El corrector de estilo sugiere dividir oraciones largas.",
    "El modo control por voz enumera sus comandos disponibles.",
    "El asistente de escritura propone reformulaciones opcionales.",
]
fam_block("d_hard_meta", D, "hard-metalenguaje", MET)

# ---------- DICTATION hard: primera persona / mixto ----------
fam_block("d_hard_1p", D, "hard-primera-persona", [
    "Quiero escribir que el editor puede cambiar el título automáticamente.",
    "Voy a contar que borrar párrafos me cuesta mucho trabajo.",
    "Pienso explicar que deshacer cambios tranquiliza a quien escribe.",
    "Quiero decir que seleccionar bien las ideas ordena el texto.",
    "Voy a escribir que poner ejemplos mejora cualquier explicación.",
    "Me gustaría contar que reemplazar términos aclara el mensaje.",
    "Quiero mencionar que cambiar de enfoque renovó mi proyecto.",
    "Pienso escribir que el comando deshacer salvó mi documento ayer.",
    "Voy a narrar que cambiar de ciudad me enseñó a adaptarme.",
    "Quiero relatar que borrar aquel mensaje fue un alivio.",
    "Pienso contar que seleccionar el tema llevó semanas.",
    "Me propongo escribir que poner límites me ayudó a avanzar.",
    "Voy a explicar que reemplazar hábitos cuesta varios intentos.",
    "Voy a describir que poner orden alivió el caos inicial.",
    "Pienso relatar que deshacer acuerdos cuesta más que firmarlos.",
    "Voy a anotar que reemplazar quejas por propuestas unió al grupo.",
])
fam_block("d_hard_mixto", D, "hard-mixto", [
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
    "Deshizo el nudo con paciencia antes de continuar.",
    "Cambiaron la cerradura después del incidente.",
    "El jurado cambió el veredicto tras la apelación.",
    "Reemplazó la bombilla antes de que anocheciera.",
    "Deshicieron las maletas nada más llegar.",
    "El título nobiliario recayó en la hija mayor.",
    "Poner fin a la reunión llevó otra hora de debate.",
    "Seleccionar al azar garantiza imparcialidad estadística.",
    "Borrar es la acción más temida por los novatos.",
])

# ---------- DICTATION: fragmentos ----------
fam_block("d_frag_a", D, "fragmento", [
    "Eso no.", "Mejor.", "No me gusta.", "Ese.", "Así está bien.",
    "Hmm, no.", "Bueno.", "Tal vez.", "Ya veo.", "Claro.", "Entiendo.",
    "De acuerdo.", "Perfecto.", "Interesante.", "Vaya.", "Ah, sí.",
    "Mmm.", "Vale.", "Exacto.", "Correcto.", "Ajá.", "Oh.", "Bien.",
])
fam_block("d_frag_b", D, "fragmento", [
    "Ni idea.", "Quién sabe.", "Puede ser.", "Ya.", "Listo.", "Hecho.",
    "Siguiente.", "Continúa.", "Prosigue.", "Te escucho.", "Dime.",
    "A ver.", "Espera.", "Un momento.", "Pausa.", "Sigo.", "Adelante.",
    "Ya casi.", "Falta poco.", "Sigo pensando.", "Déjame ver.",
    "A ver si entiendo.", "Claro que sí.", "Por supuesto.", "Desde luego.",
])
fam_block("d_frag_c", D, "fragmento", [
    "Qué bien.", "Qué raro.", "No sé.", "No estoy seguro.", "Depende.",
    "Más o menos.", "Eso creo.", "Supongo.", "Imagino.", "Ojalá.",
    "Oye.", "Mira.", "Fíjate.", "Anda.", "Venga.", "Hala.", "Uf.",
    "Ay.", "Eh.", "Pues.", "Bueno, sigo.", "Nada más.", "Eso es todo.",
    "Fin del párrafo.", "Punto final.", "No sé todavía.", "Tal vez sí.",
    "Eso no está bien.", "Me parece mejor así.", "Eso podría funcionar.",
    "Me gusta más de esta manera.", "Bueno, tal vez.", "No estoy seguro aún.",
    "Así no.", "Creo que está correcto.", "Mejor déjalo así.",
])

with open(HERE / "pool.csv", "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f)
    w.writerow(["text", "label", "category", "family_id"])
    for t, l, c, fid in rows:
        w.writerow([t, l, c, fid])

n_c = sum(1 for r in rows if r[1] == C)
n_d = len(rows) - n_c
fams = len({r[3] for r in rows})
print(f"pool: {len(rows)} filas C={n_c} D={n_d} familias={fams}", file=sys.stderr)
hard = sum(1 for r in rows if r[1] == D and r[2].startswith("hard"))
print(f"hard: {hard} ({100.0*hard/max(n_d,1):.1f}% de D)", file=sys.stderr)
