#!/usr/bin/env python3
"""Pool V3 con family_id + scope. Determinista (seed 42)."""
import csv
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
C, D, N = "EDITOR_CONTROL", "DICTATION", "NO_ACTION"
SUP, UNS = "SUPPORTED", "UNSUPPORTED"
rows: list[tuple[str, str, str, str, str]] = []

def fam_block(prefix, label, cat, texts, scope="", size=6):
    clean = []
    for t in texts:
        t = t.strip()
        if t and t not in clean:
            clean.append(t)
    for i in range(0, len(clean), size):
        fid = f"{prefix}_{i//size:02d}"
        for t in clean[i:i+size]:
            rows.append((t, label, cat, fid, scope if label == C else ""))

# ================= CONTROL (existentes, resumido) =================
TITLES = ["Metodología", "Resultados", "Introducción", "Conclusiones", "Evaluación",
          "Discusión", "Resumen", "Hallazgos", "Propuesta", "Síntesis", "Antecedentes"]
tt = []
for t in TITLES:
    tt += [f"Cambia el título a {t}.", f"Pon como título {t}.", f"Cámbiale el título a {t}.",
           f"Actualiza el título a {t}.", f"Quiero que cambies el título a {t}."]
fam_block("c_titulo", C, "titulo", tt, SUP)
fam_block("c_titulo_b", C, "titulo", [
    "¿Puedes ponerle título a este documento?", "Reescribe el título para que sea más descriptivo.",
    "Corrige el título, tiene una errata.", "Haz el título más corto.",
    "Titula esto como Apéndice.", "Renombra el encabezado principal."], SUP)

OBJ = ["esto", "eso", "esta parte", "esta oración", "este párrafo", "este texto",
       "la última frase", "esta palabra", "lo seleccionado", "esa sección",
       "el borrador", "la cita", "el ejemplo", "la nota al pie", "el encabezado"]
bb = []
for o in OBJ:
    bb += [f"Borra {o}.", f"Elimina {o}.", f"Quita {o}."]
fam_block("c_borrar", C, "borrar", bb, SUP)
fam_block("c_borrar_b", C, "borrar", [
    "¿Puedes quitar esta parte?", "Esto mejor elimínalo, sobra.",
    "Suprime la sección repetida.", "Corta esta parte y pégala al final.",
    "Descarta el último cambio de redacción.", "Borra desde aquí hasta el final.",
    "Elimina todo lo que está entre paréntesis.", "Quita los espacios duplicados."], SUP)

WORDS = ["dificultades", "interfaz", "accesibilidad", "sistema", "diseño", "término"]
rr = []
for w in WORDS:
    rr += [f"Cambia esta palabra por {w}.", f"Reemplaza esta palabra por {w}.",
           f"Sustituye esta palabra por {w}."]
fam_block("c_reemplazar", C, "reemplazar", rr, SUP)
fam_block("c_reemplazar_b", C, "reemplazar", [
    "Sustituye esa expresión por algo más claro.", "Reemplaza este término en todo el documento.",
    "Pon dificultades donde dice problemas.", "Intercambia el orden de estos dos párrafos.",
    "Cambia las comillas inglesas por latinas.", "Donde dice error pon errata."], SUP)

INST = ["más corto", "más formal", "más claro", "menos absoluto", "más breve",
        "más directo", "más sencillo", "más académico", "más persuasivo", "más neutro"]
rf = []
for inst in INST:
    rf += [f"Hazlo {inst}.", f"Haz este párrafo {inst}.", f"Reescribe lo seleccionado {inst}."]
fam_block("c_reformular", C, "reformular", rf, SUP)
fam_block("c_reformular_b", C, "reformular", [
    "Reescribe esto con un tono más formal.", "Dale otra redacción a esta parte.",
    "Mejora la redacción de lo seleccionado.", "Suaviza el tono de este párrafo.",
    "Acorta este párrafo.", "Condensa estas tres frases en una.",
    "Resume este documento en un párrafo.", "Sintetiza las ideas principales.",
    "Expande esta sección con más detalles.", "Añade un ejemplo a este párrafo."], SUP)

ff = []
for fmt in ["negritas", "cursivas"]:
    for det in ["esto", "este texto", "lo seleccionado", "esta frase", "el título", "la conclusión"]:
        ff.append(f"Pon {det} en {fmt}.")
fam_block("c_formato", C, "formato", ff, SUP)
fam_block("c_formato_b", C, "formato", [
    "Subraya esto.", "Quita las negritas de aquí.", "Pon el título en mayúsculas.",
    "Convierte esto en una lista.", "Centra este encabezado.", "Ponlo en negritas.",
    "Aplica subrayado a lo seleccionado.", "Resalta el título en negritas."], SUP)

fam_block("c_undo", C, "undo", [
    "Deshaz el último cambio.", "Deshaz eso.", "Vuelve a como estaba.",
    "No, déjalo como estaba.", "Revierte lo último que hiciste.",
    "Cancela la última edición.", "Anula lo que acabas de hacer.",
    "Échalo para atrás.", "Vuelve atrás.", "Recupera la versión previa."], SUP)
fam_block("c_redo", C, "redo", [
    "Rehaz el cambio anterior.", "Rehaz lo anterior.", "Vuelve a aplicar lo que deshiciste.",
    "Rehaz eso.", "Recupera lo que deshiciste.", "Deshaz el deshacer.",
    "Rehaz la última acción.", "Repite lo que quitaste."], SUP)

SEL = ["el segundo párrafo", "la última sección", "el primer capítulo", "toda la página"]
ss = []
for s in SEL:
    ss += [f"Selecciona {s}.", f"Marca {s}."]
fam_block("c_seleccion", C, "seleccion", ss + [
    "Selecciona todo el documento.", "Elige el tercer párrafo.",
    "Amplía la selección una palabra.", "Marca todo lo que sigue."], SUP)

fam_block("c_deictico", C, "deictico", [
    "Cámbialo.", "Pon eso.", "Borra eso.", "Quita esto.", "Hazlo.",
    "Cambia esa parte.", "Ponlo diferente.", "Hazlo diferente.",
    "Esto quítalo.", "Eso cámbialo.", "Arregla eso.", "Mejora esto.",
    "Mueve eso aquí.", "Copia esto abajo.", "Guarda el documento.",
    "Haz eso.", "Cambia aquello.", "Ponlo ahí.", "Arréglalo.",
    "Modifica esto.", "Hazlo ahora.", "Ponlo ya.", "Encárgate de esto.",
    "Cámbialo todo.", "Bórralo completo.", "Hazlo de nuevo."], SUP)

# ================= CONTROL nuevo (mayoría UNSUPPORTED) =================
fam_block("c_open", C, "open", [
    "Abre el archivo anterior.", "Abre el documento adjunto de ayer.",
    "Abre la carpeta del proyecto.", "Abre el último borrador.",
    "Abre el pdf de referencia.", "Abre una ventana nueva."], UNS)
fam_block("c_save", C, "save", [
    "Guarda el documento.", "Guarda los cambios.", "Guarda una copia.",
    "Guarda antes de salir.", "Guarda el archivo con otro nombre.",
    "Guarda el progreso hasta aquí."], UNS)
fam_block("c_saveas", C, "save-as", [
    "Guarda como pdf.", "Guarda una copia en el escritorio.",
    "Exporta una copia de respaldo.", "Guarda con el nombre final.",
    "Duplica el archivo con fecha de hoy."], UNS)
fam_block("c_export", C, "export", [
    "Exporta esto como PDF.", "Exporta el documento como epub.",
    "Exporta a texto plano.", "Genera el pdf para enviar.",
    "Convierte el archivo a Word."], UNS)
fam_block("c_print", C, "print", [
    "Imprime esta página.", "Imprime solamente las páginas pares.",
    "Imprime el documento completo.", "Manda a imprimir dos copias.",
    "Previsualiza antes de imprimir."], UNS)
fam_block("c_find", C, "find", [
    "Busca la palabra accesibilidad.", "Busca todas las menciones al autor.",
    "Encuentra la sección de resultados.", "Localiza la cita que falta.",
    "Busca el párrafo duplicado.", "Encuentra dónde dice conclusiones."], UNS)
fam_block("c_findreplace", C, "find-replace", [
    "Busca comas y reemplázalas por punto y coma.",
    "Encuentra espacios dobles y elimínalos.",
    "Busca el nombre viejo y actualízalo en todo el texto."], UNS)
fam_block("c_navigate", C, "navigate", [
    "Ve al final del documento.", "Sube al principio.", "Muévete a la siguiente sección.",
    "Baja dos párrafos.", "Salta al título.", "Ve a la página anterior.",
    "Coloca el cursor al inicio.", "Lléame a las conclusiones."], UNS)
fam_block("c_readaloud", C, "read-aloud", [
    "Léeme este párrafo.", "Lee en voz alta lo seleccionado.",
    "Lee desde aquí hasta el final.", "Reproduce la lectura del capítulo.",
    "Léeme el resumen en voz alta."], UNS)
fam_block("c_doctitle", C, "document-title", [
    "Ponle nombre al documento.", "Cambia el nombre del archivo.",
    "Renombra el archivo como informe final.", "Actualiza las propiedades del documento.",
    "Agrega el autor a los metadatos."], UNS)
fam_block("c_select2", C, "select", [
    "Selecciona desde aquí hasta el final.", "Marca la oración completa.",
    "Elige todo el capítulo.", "Selecciona la tabla entera."], SUP)
fam_block("c_copy", C, "copy", [
    "Copia este párrafo.", "Copia la cita al portapapeles.",
    "Copia esto para pegarlo después.", "Duplica esta sección abajo."], UNS)
fam_block("c_cut", C, "cut", [
    "Corta este fragmento.", "Recorta la introducción.",
    "Corta y pega esto al final.", "Mueve este bloque más arriba."], UNS)
fam_block("c_paste", C, "paste", [
    "Pega lo que copiaste.", "Pega aquí el texto.",
    "Pega sin formato.", "Inserta lo del portapapeles."], UNS)
fam_block("c_insert", C, "insert", [
    "Inserta una imagen después del título.", "Agrega una nota al pie aquí.",
    "Crea una tabla de dos columnas.", "Inserta el número de página.",
    "Agrega el encabezado institucional.", "Inserta un salto de página."], UNS)
fam_block("c_move", C, "move", [
    "Mueve esta cita al epígrafe.", "Sube este párrafo dos lugares.",
    "Reordena estos apartados.", "Traslada la conclusión al inicio."], UNS)
fam_block("c_correct", C, "correct", [
    "Corrige esta palabra.", "Corrige la ortografía de lo seleccionado.",
    "Revisa las tildes de este párrafo.", "Hay una errata, corrígela.",
    "Verifica la gramática.", "Pule la puntuación final."], UNS)
fam_block("c_tone", C, "tone", [
    "Haz esto más formal.", "Dale un tono más cercano.", "Hazlo más técnico.",
    "Hazlo más divulgativo.", "Hazlo sonar más seguro.", "Hazlo menos ambiguo."], UNS)

# ================= DICTATION =================
ACA = [
    "La interacción humano computadora estudia los sistemas interactivos.",
    "Durante los últimos años surgieron interfaces multimodales.",
    "Mi proyecto propone un editor para personas con TDAH.",
    "Las sesiones prolongadas de escritura generan fatiga.",
    "La accesibilidad cognitiva reduce la carga mental.",
    "El reconocimiento de voz permite dictar sin teclado.",
    "Un estudio evaluó interrupciones durante la redacción.",
    "La multimodalidad distribuye la atención del usuario.",
    "El diseño centrado en el usuario exige pruebas reales.",
    "Los correctores automáticos mejoran cada año.",
    "La tesis analiza barreras en herramientas de productividad.",
    "La muestra incluyó estudiantes con diagnóstico de TDAH.",
    "Las métricas cubrieron tiempo y errores por tarea.",
    "El dictado continuo tolera pausas y titubeos.",
    "La confirmación explícita evita cambios accidentales.",
    "Guardar versiones intermedias protege el trabajo.",
    "La lectura en voz alta detecta frases largas.",
    "El portapapeles múltiple agiliza reorganizar texto.",
    "Exportar a varios formatos evita fricciones.",
    "El control de cambios colorea ediciones recientes.",
    "La sincronización en la nube plantea dilemas de privacidad.",
    "La autocorrección agresiva altera palabras correctas.",
    "Abrir archivos grandes puede requerir más memoria.",
    "Imprimir documentos sigue siendo necesario en algunos contextos.",
    "Buscar información es frecuente durante la escritura.",
    "Leer en voz alta ayuda durante la revisión.",
    "Copiar y pegar texto puede producir duplicados.",
]
fam_block("d_academico", D, "academico", ACA)
SUJ = ["El estudio", "La investigación", "El análisis", "El experimento",
       "La evaluación", "El prototipo", "La tesis", "El informe"]
PRED = ["muestra mejoras en velocidad de escritura.",
        "confirma el valor del contexto al dictar.",
        "revela patrones de uso de la voz.",
        "sugiere líneas de trabajo futuro.",
        "destaca la accesibilidad cognitiva.",
        "aporta evidencia sobre fatiga prolongada.",
        "propone evaluar editores multimodales.",
        "documenta errores del dictado automático."]
xx = []
for s in SUJ:
    for p in PRED[:4]:
        xx.append(f"{s} {p}")
fam_block("d_acad_suj_a", D, "academico", xx)
xx = []
for s in SUJ:
    for p in PRED[4:]:
        xx.append(f"{s} {p}")
fam_block("d_acad_suj_b", D, "academico", xx)

GEN = ["El informe quedó listo ayer.", "La propuesta incluye tres secciones.",
       "El artículo será revisado por pares.", "La carta circula entre asistentes.",
       "El ensayo necesita una última lectura.", "La memoria describe el proceso.",
       "El acta apareció publicada hoy.", "La reseña recibió buenos comentarios.",
       "El boletín saldrá el próximo mes.", "La gaceta agotó su edición.",
       "El museo inaugura una sala interactiva.", "La orquesta dará un concierto.",
       "El mercado abre solo los domingos.", "El tren amplió su recorrido.",
       "La feria reunió a decenas de editoriales.", "El hospital atiende urgencias.",
       "El puente quedó iluminado con led.", "El zoológico liberó tres cóndores."]
fam_block("d_general", D, "general", GEN)

# hard con vocabulario de archivo/edición
fam_block("d_hard_file", D, "hard-archivo", [
    "Guardar documentos automáticamente mejora la recuperación ante fallos.",
    "Abrir archivos grandes puede requerir más memoria.",
    "Imprimir demasiado contenido genera desperdicio.",
    "Buscar información es una tarea frecuente durante la escritura.",
    "Copiar y pegar texto puede producir duplicados.",
    "Exportar un documento permite utilizarlo en otros sistemas.",
    "Leer en voz alta puede ayudar durante la revisión.",
    "Seleccionar correctamente una muestra es fundamental para el estudio.",
    "Guardar información automáticamente reduce la pérdida de datos.",
    "Abrir varias ventanas facilita comparar versiones.",
    "Imprimir borradores ayuda a revisar con distancia.",
    "Buscar definiciones interrumpe menos que preguntar.",
    "Copiar citas textuales exige referenciar la fuente.",
    "Exportar en pdf congela el formato final.",
    "Leer poesía en voz alta mejora la dicción.",
    "Pegar capturas ilustra mejor el procedimiento.",
    "Guardar silencio también comunica en una reunión.",
    "Abrir debate sobre el tema enriqueció la clase.",
    "Imprimir carteles difundió el evento.",
    "Buscar consenso llevó toda la tarde.",
])
fam_block("d_hard_inf", D, "hard-infinitivo", [
    "Borrar archivos viejos libera espacio útil.",
    "Cambiar el formato sin avisar confunde.",
    "Seleccionar la muestra determina la validez.",
    "Reemplazar palabras sin criterio empobrece.",
    "Deshacer acciones forma parte del aprendizaje.",
    "Poner títulos descriptivos facilita navegar.",
    "Eliminar párrafos debería pedir confirmación.",
    "Rehacer trabajos consume demasiado tiempo.",
    "Guardar copias frecuentes evita desastres.",
    "Abrir enlaces desconocidos es arriesgado.",
    "Imprimir a doble cara ahorra papel.",
    "Buscar atajos mejora la productividad.",
    "Copiar a mano fija mejor los conceptos.",
    "Exportar datos crudos permite auditarlos.",
    "Leer contratos completos evita sorpresas.",
    "Pegar con formato arrastra estilos indeseados.",
    "Modificar horarios exige negociar antes.",
    "Subrayar ideas clave facilita repasar.",
])
fam_block("d_hard_cita", D, "hard-cita", [
    'La frase "borra esto" resulta ambigua sin contexto.',
    'Un ejemplo sería "pon esto en negritas".',
    'El manual muestra "cambia el título a Resultados".',
    'La consigna "reescribe este párrafo" confunde.',
    'El tutorial dice "hazlo más corto".',
    'La frase "guarda este documento" es una orden.',
    'El ejemplo "abre el archivo" ilustra el tema.',
    'La guía cita "imprime dos copias".',
    'El aviso reza "no borrar este mensaje".',
    'La etiqueta pide "seleccionar una opción".',
])
fam_block("d_hard_meta", D, "hard-metalenguaje", [
    "El comando borrar elimina la selección.",
    "La función deshacer restaura el cambio.",
    "La opción reemplazar busca coincidencias.",
    "El botón guardar conserva copias.",
    "El menú formato agrupa estilos.",
    "El historial registra cada edición.",
    "El corrector sugiere alternativas.",
    "El modo dictado desactiva atajos.",
    "La papelera conserva eliminados treinta días.",
    "El atajo de deshacer es casi universal.",
    "El reemplazo expande abreviaturas.",
    "El panel de estilos centraliza títulos.",
])
fam_block("d_hard_mix", D, "hard-mixto", [
    "Es importante cambiar cómo diseñamos interfaces.",
    "El título debe comunicar el objetivo.",
    "Deshacer tratos genera desconfianza.",
    "Reemplazó la bombilla antes del anochecer.",
    "Cambiaron la cerradura tras el incidente.",
    "El jurado cambió el veredicto.",
    "Seleccionar al azar garantiza imparcialidad.",
    "Guardaron silencio durante el homenaje.",
    "Abrieron debate tras la ponencia.",
    "Imprimieron carteles para el festival.",
    "Buscaron consenso hasta la madrugada.",
    "Copiaron el esquema en sus cuadernos.",
    "Pegaron los avisos en la entrada.",
    "Leyeron el manifiesto en voz alta.",
])

# ================= NO_ACTION =================
fam_block("n_conv_a", N, "conversacion", [
    "Hmm, no.", "No sé.", "Tal vez.", "Bueno.", "A ver.", "Espera un momento.",
    "Ya veo.", "Entiendo.", "De acuerdo.", "Interesante.", "Vaya.", "Mmm.",
    "Vale.", "Ni idea.", "Puede ser.", "Supongo.", "Oye.", "Mira.", "Eh.",
    "Pues.", "Ya casi.", "Falta poco.", "Sigo pensando.", "Déjame ver.",
    "Claro que sí.", "Desde luego.", "Qué bien.", "No estoy seguro.", "Depende.",
])
fam_block("n_conv_b", N, "conversacion", [
    "Eso no.", "Mejor.", "No me gusta.", "Ese.", "Así está bien por ahora.",
    "No importa.", "Olvídalo.", "Ya veremos.", "Está pasable.", "No me convence.",
    "Pues no sé.", "Ah, ya entiendo.", "Sí, eso mero.", "Ni modo.", "Pues bueno.",
    "Este...", "Nada más.", "Eso es todo.", "Fin del párrafo.", "Punto final.",
    "No sé todavía.", "Tal vez sí.", "Tal vez después.", "Creo que no.",
    "No estoy convencido.", "Podría ser.", "Quién sabe todavía.", "Suena razonable.",
    "Déjame pensarlo.", "Mejor lo pienso.", "Eso no me convence.",
    "Déjalo, todavía no estoy seguro.", "No importa, sigue.",
    "Olvídalo, no era nada.", "Déjame terminar.", "Espera, todavía estoy hablando.",
])
fam_block("n_imp_a", N, "imperative-like", [
    "Mira, no estoy seguro.", "Espera, todavía no termino.",
    "Pon atención a lo que voy a decir.", "Déjalo, luego vemos.",
    "Olvida eso, estoy pensando en otra cosa.", "Dame un segundo.",
    "Aguanta un momento.", "Escucha, todavía falta una parte.",
    "Fíjate que no me decido.", "Anda, déjame ordenar mis ideas.",
    "Venga, que ya casi lo tengo.", "Para, que me estoy liando.",
    "Calla un momento, que pienso.", "Suelta eso, que ya voy.",
    "Toma aire conmigo antes de seguir.", "Quédate ahí, que ya te digo.",
    "Párate un segundo a pensar.", "Siéntate, que esto va para largo.",
    "Acuérdate de respirar de vez en cuando.", "Imagínate que no funciona.",
    "Supón que tenemos que empezar de cero.", "Dime tú qué harías.",
    "Cuenta hasta diez antes de responder.", "Mira bien antes de opinar.",
])
fam_block("n_imp_b", N, "imperative-like", [
    "Perdona, estaba distraído.", "Disculpa, ¿decías algo?",
    "Repite eso último, por favor.", "Habla más despacio, por favor.",
    "Deja que lo anote primero.", "Permíteme dudar de ese dato.",
    "Ayúdame a pensar en voz alta.", "Acompáñame mientras lo reviso.",
    "Quédate callado un momento.", "No digas nada todavía.",
    "Borra eso de tu mente por ahora.", "Quita esa idea de tu cabeza.",
    "Cambia de tema un momento.", "Vuelve a eso más tarde.",
    "Guarda silencio mientras pienso.", "Abre tu mente a otra opción.",
    "Cierra los ojos e imagina el resultado.", "Haz como si no hubiera pasado.",
    "Ponle pausa a esta discusión.", "Dale vueltas esta noche.",
    "Échale un ojo cuando puedas.", "Tómate tu tiempo para decidir.",
    "Hazme caso por una vez.", "Créeme, lo tengo controlado.",
])

# ================= EXPANSIÓN MASIVA =================
T2 = ["Prólogo", "Epílogo", "Glosario", "Índice", "Prefacio", "Agradecimientos",
      "Cronología", "Genealogía", "Atlas", "Compendio", "Antología", "Memorias"]
for t in T2:
    fam_block(f"x_tit_{t[:4]}", C, "titulo", [
        f"Cambia el título a {t}.", f"Pon {t} como título.",
        f"El documento se titulará {t}.", f"Actualiza el encabezado a {t}."], SUP)
OBJ2 = ["el subtítulo", "la primera línea", "el último renglón", "el sumario",
        "el epígrafe", "la dedicatoria", "el colofón", "la fe de erratas"]
for o in OBJ2:
    fam_block(f"x_bor_{o.split()[-1]}", C, "borrar", [
        f"Borra {o}.", f"Elimina {o} por favor.", f"Quita {o} de aquí.",
        f"Suprime {o} sin falta."], SUP)
PAIRS2 = [("prólogo", "introducción"), ("epílogo", "cierre"), ("cita", "referencia"),
          ("gráfica", "ilustración"), ("esquema", "diagrama"), ("versículo", "párrafo")]
for a, b in PAIRS2:
    fam_block(f"x_re_{a[:4]}", C, "reemplazar", [
        f"Cambia {a} por {b}.", f"Sustituye {a} por {b}.",
        f"Donde ponga {a} escribe {b}.", f"Troca {a} por {b}."], SUP)
for inst in ["más ameno", "más riguroso", "más poético", "más sobrio", "más crítico"]:
    fam_block(f"x_rf_{inst.split()[-1]}", C, "reformular", [
        f"Hazlo {inst}.", f"Reformula esto {inst}.",
        f"Dale un aire {inst} al texto.", f"Vuelve el párrafo {inst}."], SUP)
for fmt, obj in [("negritas", "los subtítulos"), ("cursivas", "las citas"),
                 ("subrayado", "los enlaces"), ("versales", "el encabezado")]:
    fam_block(f"x_fm_{fmt[:4]}", C, "formato", [
        f"Pon {obj} en {fmt}.", f"Aplica {fmt} a {obj}.",
        f"Marca {obj} con {fmt}."], SUP)
for u in ["Da un paso atrás.", "Anula la modificación.", "Recupera la versión previa.",
          "Deshaz lo último.", "Cancela lo anterior.", "Retrocede un cambio."]:
    fam_block(f"x_un_{u.split()[0]}", C, "undo", [u, u.replace(".", ", por favor.")], SUP)
for r in ["Reaplica el cambio.", "Vuelve a hacer lo anterior.", "Restaura la edición.",
          "Adelante con lo deshecho.", "Repite la acción.", "Recupera lo deshecho."]:
    fam_block(f"x_re2_{r.split()[0]}", C, "redo", [r, "Por favor, " + r[0].lower() + r[1:]], SUP)
for v in ["guarda", "abre", "imprime", "busca", "exporta", " comparte".strip()]:
    fam_block(f"x_fv_{v}", C, "archivo", [
        f"Ahora {v} el documento.", f"Por favor {v} el archivo.",
        f"Necesito que {v} esto ya.", f"¿Puedes {v} el documento?"], UNS)
for v in ["selecciona", "copia", "corta", "pega", "mueve", "duplica"]:
    fam_block(f"x_ev_{v}", C, "edicion", [
        f"Ahora {v} este bloque.", f"Por favor {v} el fragmento.",
        f"Necesito que {v} eso.", f"¿Puedes {v} la selección?"], UNS)
for v in ["lee", "traduce", "resume", "expande", "corrige", "numerA".lower()]:
    fam_block(f"x_xv_{v}", C, "transformar", [
        f"Ahora {v} este texto.", f"Por favor {v} el párrafo.",
        f"Necesito que {v} la sección.", f"¿Puedes {v} esto?"], UNS)
for d in ["Haz eso ya.", "Cambia aquello.", "Ponlo ahí mismo.", "Mueve esto para allá.",
          "Arregla aquello otro.", "Copia eso también.", "Bórralo completo.",
          "Hazlo de nuevo.", "Quítalo ya.", "Tómalo y muévelo.", "Guárdalo.",
          "Imprímelo.", "Envíalo.", "Revísalo.", "Compártelo.", "Archívalo."]:
    fam_block(f"x_dx_{d.split()[0]}", C, "deictico", [d, "Por favor, " + d[0].lower() + d[1:]], SUP)

ACA2 = ["El teclado mecánico suena al escribir.", "La pantalla refleja luz por la tarde.",
        "El seminario reúne varias carreras.", "La biblioteca cierra en vacaciones.",
        "El laboratorio tiene equipos nuevos.", "El comedor ofrece menús vegetarianos.",
        "La tesis recibió mención honorífica.", "El museo inaugura sala interactiva.",
        "Los horarios se publican al inicio.", "El tren amplió su recorrido.",
        "La feria reunió editoriales.", "El hospital atiende urgencias.",
        "El puente quedó iluminado.", "El zoológico liberó cóndores.",
        "La pista recibe mantenimiento.", "El coro participará en primavera.",
        "El banco necesita donadores.", "El mercado abre los domingos.",
        "El parque protege especies.", "La red conecta cinco alcaldías.",
        "El acuario renovó el tanque.", "Los viernes hay cine al aire libre.",
        "El observatorio organiza visitas.", "Las clases terminan de noche.",
        "El gimnasio abre al amanecer.", "La cafetería amplió su horario.",
        "El club compite a nivel nacional.", "La librería guarda joyas.",
        "Los talleres fomentan lectura.", "Las noches permiten ver estrellas."]
fam_block("d_gen2", D, "general", ACA2)
SUJ2 = ["La tesis", "El informe", "La prueba piloto", "El grupo focal", "El taller",
        "El seminario", "La demo", "El manual", "La encuesta", "El registro"]
PRED2 = ["aborda órdenes habladas ambiguas.", "cuantifica interrupciones al redactar.",
         "compara estrategias de confirmación.", "documenta errores del dictado.",
         "propone umbrales conservadores.", "evalúa satisfacción con escalas.",
         "registra correcciones por minuto.", "cierra con pautas de diseño."]
xx2 = []
for s in SUJ2:
    for p in PRED2[:4]:
        xx2.append(f"{s} {p}")
fam_block("d_acad2_a", D, "academico", xx2)
xx2 = []
for s in SUJ2:
    for p in PRED2[4:]:
        xx2.append(f"{s} {p}")
fam_block("d_acad2_b", D, "academico", xx2)
for v in ["guardar", "abrir", "imprimir", "buscar", "copiar", "pegar", "leer", "exportar"]:
    fam_block(f"d_hf_{v}", D, "hard-archivo", [
        f"{v.capitalize()} a diario mantiene el orden del taller.",
        f"Saber {v} bien distingue a los profesionales.",
        f"Dicen que {v} con calma evita errores.",
        f"Aprender a {v} lleva unas semanas."], size=4)
for v in ["borrar", "cambiar", "modificar", "reemplazar", "seleccionar", "deshacer",
          "rehacer", "subrayar", "eliminar", "poner"]:
    fam_block(f"d_hi_{v}", D, "hard-infinitivo", [
        f"{v.capitalize()} sin pensar trae consecuencias.",
        f"Conviene {v} solo cuando hace falta.",
        f"Dicen que {v} de a poco funciona mejor.",
        f"Hay que {v} con cuidado siempre."], size=4)
CIT2 = ['La maestra escribió "abran el libro" en el pizarrón.',
        'El reglamento dice "guarden silencio".',
        'El anuncio pide "no pisar el césped".',
        'La carta termina con "atentamente".',
        'El examen indica "justifique su respuesta".',
        'El cartel reza "cerrado por inventario".',
        'El instructivo advierte "no agitar".',
        'La pantalla muestra "cargando".']
fam_block("d_cita2", D, "hard-cita", CIT2)
MET2 = ["El verbo guardar rige preposición en algunos usos.",
        "El sustantivo título lleva tilde por ser esdrújula.",
        "Borrar es un verbo regular de la primera conjugación.",
        "Seleccionar implica elegir entre opciones.",
        "El imperativo usa formas propias en cada persona.",
        "Imprimir viene del latín premere.",
        "Buscar y encontrar no son sinónimos exactos.",
        "Copiar en exámenes se sanciona con cero."]
fam_block("d_meta2", D, "hard-metalenguaje", MET2)
MIX2 = ["Guardaron las sobras para mañana.", "Abrieron la tienda muy temprano.",
        "Imprimieron volantes para la marcha.", "Buscaron al perro hasta tarde.",
        "Copiaron las llaves de emergencia.", "Pegaron estampas en el álbum.",
        "Leyeron cuentos antes de dormir.", "Exportaron café de altura.",
        "Seleccionaron a los finalistas ayer.", "Borraron las fotos movidas."]
fam_block("d_mix2", D, "hard-mixto", MIX2)

fam_block("n_conv_c", N, "conversacion", [
    "Está bien así.", "No, así no.", "Mejor déjalo.", "Creo que no.",
    "No estoy convencido.", "Podría ser.", "Quién sabe todavía.",
    "No sé aún.", "Tal vez después.", "Eso está mejor.", "No, mejor no.",
    "Me parece bien.", "Suena razonable.", "Ya veremos.", "Está pasable.",
    "Mmm, tal vez.", "Bueno, ya qué.", "Pues no sé.", "Ah, ya entiendo.",
    "Claro, claro.", "Sí, eso mero.", "Nel.", "Simón.", "Órale.", "Chido.",
    "Ni modo.", "Pues bueno.", "Este...", "Ajá, ajá.", "Ya ni modo.",
    "No, mejor déjalo.", "Está bien por ahora.", "Ya casi termino.",
])
fam_block("n_conv_d", N, "conversacion", [
    "Permíteme un segundo.", "Dame chance de revisar.",
    "Aguántame tantito.", "Espérame, ya voy.", "Ahorita lo veo.",
    "Al rato lo checamos.", "Luego lo platicamos.", "Mañana lo decidimos.",
    "En un momento te digo.", "Deja termino esto.", "Ya merito acabo.",
    "Casi, casi.", "Ahí va quedando.", "Va tomando forma.",
    "Ya se está armando.", "Esto promete.", "Pinta bien.",
    "Huele a éxito.", "Se ve prometedor.", "Tiene potencial.",
    "Hay que pulirlo.", "Le falta sazón.", "Está crudo todavía.",
    "Ya madurará.", "Dale tiempo.", "Sin prisa.", "Con calma.",
    "Paso a paso.", "Poco a poco.", "Día a día.", "Ahí la llevamos.",
])
fam_block("n_imp_c", N, "imperative-like", [
    "Piensa antes de hablar.", "Respira hondo primero.",
    "Calma, que hay tiempo.", "Tranquilo, todo saldrá bien.",
    "Frena un poco el ritmo.", "Baja la voz, por favor.",
    "Sube el ánimo, compañero.", "Abre bien los ojos.",
    "Cierra la puerta al salir.", "Apaga la luz si no estás.",
    "Tiende tu cama cada mañana.", "Lava los trastes después.",
    "Barre la entrada por favor.", "Riega las plantas del patio.",
    "Saca la basura esta noche.", "Tiende la ropa tendida.",
    "Haz la tarea temprano.", "Estudia para el examen.",
    "Practica piano media hora.", "Corre tres kilómetros.",
    "Camina hasta la esquina.", "Maneja con precaución.",
    "Cruza por el puente.", "Toma el camión de las siete.",
    "Baja en la siguiente parada.", "Sube las escaleras despacio.",
])
fam_block("n_imp_d", N, "imperative-like", [
    "No te preocupes por eso.", "No hagas caso de los rumores.",
    "No corras antes de caminar.", "No cantes victoria todavía.",
    "No vendas la piel del oso.", "No cuentes los pollos.",
    "No dejes para mañana.", "No tires la toalla.",
    "No pierdas la calma.", "No te rindas ahora.",
    "No olvides sonreír.", "No dejes de intentarlo.",
    "No temas preguntar.", "No dudes en llamar.",
    "No tardes mucho.", "No te entretengas.",
    "Perdona el desorden.", "Disculpa la tardanza.",
    "Con permiso, voy pasando.", "Salud, por los buenos tiempos.",
    "Felicidades por tu logro.", "Bienvenido a bordo.",
    "Hasta luego, nos vemos.", "Que descanses esta noche.",
    "Cuídate mucho.", "Pórtate bien.", "Éxito en todo.",
])

# ================= EXPANSIÓN 2 (volumen + cobertura archivo) =================
FILE_FRAMES = {
    "open": [("Abre {}", "."), ("Abre {} por favor.", ""), ("Necesito que abras {}.", ""),
             ("¿Puedes abrir {}?", "")],
    "save": [("Guarda {}", "."), ("Guarda {} por favor.", ""), ("Guarda {} antes de cerrar.", ""),
             ("No olvides guardar {}.", "")],
    "print": [("Imprime {}", "."), ("Imprime {} por favor.", ""), ("Manda a imprimir {}.", ""),
              ("Saca una copia impresa de {}.", "")],
    "find": [("Busca {} en el documento.", ""), ("Encuentra {} por favor.", ""),
             ("Localiza {} en el texto.", ""), ("¿Dónde dice {}?", "")],
    "export": [("Exporta {} como pdf.", ""), ("Exporta {} a texto plano.", ""),
               ("Genera el pdf de {}.", ""), ("Convierte {} a Word.", "")],
    "read": [("Léeme {}", "."), ("Lee {} en voz alta.", ""), ("Reproduce la lectura de {}.", "")],
}
FILE_FILL = {
    "open": ["el informe de ayer", "la hoja de cálculo", "el contrato final", "el borrador",
             "la presentación", "el archivo adjunto", "el manual", "la tesis"],
    "save": ["el documento", "los cambios", "el borrador", "el informe", "esta versión",
             "el archivo", "tu avance", "la carta"],
    "print": ["esta página", "el informe", "el contrato", "las primeras páginas",
              "el borrador", "la propuesta", "el anexo", "dos copias"],
    "find": ["la palabra resumen", "el nombre del autor", "la fecha de entrega",
             "el párrafo repetido", "la cita pendiente", "los errores de dedo"],
    "export": ["el informe", "la tesis", "el manual", "el folleto", "la propuesta"],
    "read": ["este párrafo", "la introducción", "el resumen", "lo seleccionado",
             "el primer capítulo"],
}
for cat, frames in FILE_FRAMES.items():
    for fmt, _ in frames:
        fam_block(f"y_{cat}_{fmt[:6].strip()}", C, "archivo" if cat in ("open", "save", "print", "export") else ("lectura" if cat == "read" else "buscar"),
                  [fmt.format(f) for f in FILE_FILL[cat]], UNS, size=8)
NAV = ["al índice", "a la bibliografía", "al apéndice", "al glosario", "al prólogo",
       "a los agradecimientos", "a la primera nota", "al último cuadro"]
for f in ["Ve {}", "Salta {}", "Desplázate {}", "Baja {}"]:
    fam_block(f"y_nav_{f.split()[0]}", C, "navegacion", [f.format(n) + "." for n in NAV], UNS, size=8)
SEL2 = ["la tabla", "el gráfico", "el recuadro", "la imagen", "el diagrama", "el mapa"]
for f in ["Selecciona {}", "Marca {} completo", "Elige {} por favor", "Resalta {}"]:
    fam_block(f"y_sel_{f.split()[0]}", C, "seleccion", [f.format(s) + "." for s in SEL2], SUP, size=6)
CP = ["este párrafo", "la dirección", "el teléfono", "la referencia", "el enlace"]
for v, cat in [("Copia", "copy"), ("Corta", "cut"), ("Pega", "paste"), ("Duplica", "copy")]:
    fam_block(f"y_cp_{v}", C, cat, [f"{v} {o}." for o in CP] + [f"{v} {o} por favor." for o in CP[:3]], UNS, size=8)
UNDO2 = ["el formato aplicado", "la inserción", "el pegado", "la sustitución",
         "el borrado accidental", "el cambio de estilo"]
for f in ["Deshaz {}", "Revierte {}", "Anula {}"]:
    fam_block(f"y_un_{f.split()[0]}", C, "undo", [f.format(u) + "." for u in UNDO2], SUP, size=6)

NCONV = [
    ["Está lloviendo otra vez.", "Qué calor hace hoy.", "El tráfico está imposible.",
     "Se fue la luz un rato.", "Ya casi es quincena.", "El lunes es festivo.",
     "Hace frío esta mañana.", "El metro va llenísimo.", "Qué largo estuvo el día.",
     "Por fin es viernes."],
    ["Compré pan dulce.", "Se acabó el café.", "Hay pozole el domingo.",
     "La salsa quedó picosa.", "El pastel es de tres leches.", "Cenamos tacos al pastor.",
     "El caldo está caliente.", "Faltan tortillas.", "El postre es flan.", "Qué rico huele."],
    ["Mi mamá llamó ayer.", "El bebé ya camina.", "Mi hermano se casa en junio.",
     "La abuela cumplió noventa.", "El primo vive en Monterrey.", "Mi tía cocina delicioso.",
     "El sobrino perdió un diente.", "La familia se reúne en diciembre.",
     "Mi papá arregló el coche.", "La prima estudia medicina."],
    ["Ganó el América.", "El partido quedó empatado.", "Hubo remontada histórica.",
     "El clásico es el domingo.", "Nuestro equipo va de líder.", "El penal fue dudoso.",
     "La final será en diciembre.", "El portero atajó todo.", "Qué golazo metió.",
     "El árbitro pitó el final."],
    ["Hay que barrer el patio.", "Toca lavar los trastes.", "El baño necesita limpieza.",
     "Dobla tu ropa.", "Tiende la cama.", "Riega las macetas.", "Saca al perro.",
     "Trapea la cocina.", "Limpia los vidrios.", "Ordena tu cuarto."],
    ["El examen es mañana.", "La tarea es para el viernes.", "Hay junta a las tres.",
     "El curso empieza en agosto.", "La clase se movió al salón dos.",
     "El proyecto se entrega hoy.", "Hay ensayo general.", "El taller cuesta quinientos.",
     "La beca ya salió.", "El diplomado dura un año."],
]
for i, block in enumerate(NCONV):
    fam_block(f"n_cot_{i:02d}", N, "conversacion", block)
NIMP = [
    ["Cierra la ventana.", "Apaga el ventilador.", "Prende la luz del patio.",
     "Abre la puerta trasera.", "Baja las persianas.", "Sube el volumen.",
     "Baja el volumen.", "Apaga la tele.", "Prende el boiler.", "Cierra la llave."],
    ["Cruza con cuidado.", "Espera el verde.", "Toma la ruta larga.",
     "Baja dos cuadras.", "Sube al puente.", "Evita el centro.",
     "Toma un atajo.", "Sigue derecho.", "Da vuelta aquí.", "Estaciónate allá."],
    ["Tómate la medicina.", "Guarda reposo.", "Toma muchos líquidos.",
     "Abrígate bien.", "Come a tus horas.", "Duerme ocho horas.",
     "Camina diario.", "Respira profundo.", "Relaja los hombros.", "Descansa la vista."],
    ["Felicita a tu hermana.", "Agradece el favor.", "Pide disculpas.",
     "Saluda al llegar.", "Despídete bien.", "Presenta a tus amigos.",
     "Invita a tus primos.", "Visita a los abuelos.", "Llama a tu mamá.",
     "Escríbele pronto."],
    ["No llegues tarde.", "No olvides las llaves.", "No dejes la estufa prendida.",
     "No hables con extraños.", "No cruces en rojo.", "No tires basura.",
     "No desperdicies agua.", "No dejes luces prendidas.", "No ronques tan fuerte.",
     "No te desveles hoy."],
    ["Cuida a tu hermanito.", "Alimenta al gato.", "Pasea al perro.",
     "Riega el jardín.", "Podas las rosas.", "Limpia la pecera.",
     "Cepilla al conejo.", "Dale agua a las plantas.", "Recoge las hojas.",
     "Guarda la bicicleta."],
]
for i, block in enumerate(NIMP):
    fam_block(f"n_impc_{i:02d}", N, "imperative-like", block)

DACAD = ["El censo contó millones de viviendas.", "La sequía afectó tres estados.",
         "El sismo se sintió en la capital.", "La cosecha superó lo esperado.",
         "El eclipse será visible al norte.", "La vacuna llegó a las clínicas.",
         "El censo será en marzo próximo.", "La tormenta derribó varios árboles.",
         "El rescate duró toda la noche.", "La campaña vacunó a miles.",
         "El incendio consumió dos hectáreas.", "El desfile reunió multitudes.",
         "La obra durará dieciocho meses.", "El túnel conecta dos valles.",
         "La presa alcanzó su nivel máximo.", "El puerto recibe cruceros.",
         "El aeropuerto estrenó terminal.", "La carretera quedó bloqueada.",
         "El volcán registra actividad leve.", "El río creció con las lluvias."]
fam_block("d_news", D, "general", DACAD)
DHARD = ["Guardar agua en tinacos previene escasez.", "Abrir segundos frentes divide recursos.",
         "Imprimir boletas electorales exige seguridad.", "Buscar agua subterránea requiere estudios.",
         "Copiar recetas antiguas preserva sabores.", "Pegar carteles anima las calles.",
         "Leer mapas topográficos orienta excursiones.", "Exportar aguacate genera divisas.",
         "Seleccionar jueces independientes fortalece la corte.", "Borrar deudas viejas alivia finanzas.",
         "Cambiar focos públicos ahorra millones.", "Poner topes reduce accidentes.",
         "Deshacer entuertos antiguos dignifica.", "Rehacer vialidades tarda sexenios."]
fam_block("d_hard_news", D, "hard-mixto", DHARD)

# ================= EXPANSIÓN 3 (D y N) =================
S3 = ["El observatorio", "El taller literario", "La mesa de diálogo", "El coro mixto",
      "La brigada", "El colectivo", "La asamblea vecinal", "El patronato",
      "La fundación", "El fideicomiso", "La cooperativa", "El sindicato"]
P3 = ["sesiona cada quince días.", "publicó su informe anual.", "renovó su directiva.",
      "organizó una colecta.", "repartió despensas.", "pintó la fachada.",
      "sembró árboles nativos.", "limpió el canal.", "abrió un comedor.",
      "becó a diez jóvenes.", "editó una memoria.", "cumplió veinte años."]
z = []
for s in S3:
    for p in P3[:5]:
        z.append(f"{s} {p}")
fam_block("d_org_a", D, "general", z)
z = []
for s in S3:
    for p in P3[5:]:
        z.append(f"{s} {p}")
fam_block("d_org_b", D, "general", z)
S4 = ["La gaceta oficial", "El diario matutino", "El semanario cultural",
      "La revista científica", "El boletín sindical", "El pasquín universitario"]
P4 = ["destacó la nota roja.", "entrevistó al rector.", "cubrió la marcha.",
      "reseñó la temporada.", "denunció el ecocidio.", "premió la crónica."]
z = []
for s in S4:
    for p in P4:
        z.append(f"{s} {p}")
fam_block("d_prensa", D, "general", z)
for v in ["guardar", "abrir", "imprimir", "buscar", "firmar", "archivar", "ordenar", "clasificar"]:
    fam_block(f"d_hf2_{v}", D, "hard-archivo", [
        f"{v.capitalize()} con método ahorra horas cada semana.",
        f"Quien sabe {v} bien rinde el doble.",
        f"Conviene {v} antes de que anochezca.",
        f"Me enseñaron a {v} desde chico."], size=4)
for v in ["mover", "quitar", "poner", "sacar", "meter", "subir", "bajar", "cruzar"]:
    fam_block(f"d_hi2_{v}", D, "hard-infinitivo", [
        f"{v.capitalize()} con cuidado evita accidentes.",
        f"Hay que {v} sin prisas.",
        f"Dicen que {v} de a poco sale mejor.",
        f"Conviene {v} solo si hace falta."], size=4)
DCIT = ['El lema reza "trabajo y constancia".',
        'La lápida dice "siempre en lucha".',
        'El grafiti grita "ni perdón ni olvido".',
        'La manta exige "agua para todos".',
        'El volante anuncia "gran kermés".',
        'La convocatoria llama "a defender el barrio".',
        'El himno canta "victoria o muerte".',
        'El pregón ofrece "tamales oaxaqueños".']
fam_block("d_cita3", D, "hard-cita", DCIT)
DMET = ["El prefijo re- indica repetición.",
        "El sufijo -ero denota oficio.",
        "Guardar es verbo irregular en su uso pronominal.",
        "Abrir rige la preposición a veces.",
        "El participio impreso alterna con imprimido.",
        "Buscar se conjuga regularmente.",
        "El gerundio copiando exige tilde.",
        "Pegar como verbo admite varios sentidos."]
fam_block("d_meta3", D, "hard-metalenguaje", DMET)
NCONV2 = [
    ["Ya merito.", "Ya casi queda.", "En eso ando.", "Ahorita te digo.",
     "Aguanta vara.", "No te awites.", "Échale ganas.", "Tú puedes.",
     "Ánimo, campeón.", "Vas muy bien."],
    ["Qué onda.", "Cómo andas.", "Cuánto tiempo.", "Qué milagro.",
     "Pásale.", "Siéntete en casa.", "La casa invita.", "Sírvete algo.",
     "Ponte cómodo.", "Bienvenido seas."],
    ["Con permiso.", "Disculpe usted.", "Perdón por llegar tarde.",
     "Gracias por todo.", "Muy amable.", "Qué detallazo.",
     "Te debo una.", "Estamos en contacto.", "Nos escribimos.",
     "Salúdame a todos."],
    ["Ya es tarde.", "Se hizo de noche.", "Amaneció nublado.",
     "Atardeció hermoso.", "Cayó granizo.", "Escampó al fin.",
     "Refrescó bastante.", "Caló fuerte el sol.", "Llovizna apenas.",
     "Granizó en el norte."],
]
for i, block in enumerate(NCONV2):
    fam_block(f"n_cot2_{i:02d}", N, "conversacion", block)
NIMP2 = [
    ["Tiende la ropa.", "Dobla las sábanas.", "Sacude los tapetes.",
     "Lava el baño.", "Trapea bien.", "Enciende el boiler.",
     "Apaga las luces.", "Desconecta la plancha.", "Guarda los trastes.",
     "Barre debajo de la cama."],
    ["Paga la luz.", "Deposita la renta.", "Retira efectivo.",
     "Checa tu saldo.", "Ahorra cada mes.", "Aparta para emergencias.",
     "Paga puntual.", "Evita deudas.", "Compara precios.", "Pide factura."],
    ["Estudia diario.", "Repasa apuntes.", "Haz resúmenes.",
     "Subraya ideas.", "Pregunta dudas.", "Entrega a tiempo.",
     "Asiste siempre.", "Participa en clase.", "Lee el capítulo.", "Memoriza fechas."],
    ["Come verduras.", "Toma agua.", "Duerme temprano.",
     "Haz ejercicio.", "Camina diario.", "Evita refrescos.",
     "Desayuna bien.", "Cena ligero.", "Lávate las manos.", "Abrígate hoy."],
]
for i, block in enumerate(NIMP2):
    fam_block(f"n_impc2_{i:02d}", N, "imperative-like", block)

with open(HERE / "pool.csv", "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f)
    w.writerow(["text", "label", "category", "family_id", "scope"])
    for t, l, c, fid, sc in rows:
        w.writerow([t, l, c, fid, sc])

n_c = sum(1 for r in rows if r[1] == C)
n_d = sum(1 for r in rows if r[1] == D)
n_n = len(rows) - n_c - n_d
print(f"pool: {len(rows)} C={n_c} D={n_d} N={n_n} fam={len({r[3] for r in rows})}", file=sys.stderr)
