#!/usr/bin/env python3
"""Pool action-classifier. 15 labels, familias troceadas. Seed 42."""
import csv
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
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

RN, DL, RP, RW, FM = "RENAME_TITLE", "DELETE_SELECTION", "REPLACE_SELECTION", "REWRITE_SELECTION", "FORMAT_SELECTION"
UN, RD, SL, FN, SV, OP, EX = "UNDO", "REDO", "SELECT_TEXT", "FIND_TEXT", "SAVE_DOCUMENT", "OPEN_DOCUMENT", "EXPORT_DOCUMENT"
US, NA, MU = "UNSUPPORTED", "NO_ACTION", "MULTI_ACTION"

# ---------- RENAME_TITLE ----------
RT = ["Metodología", "Resultados", "Discusión", "Conclusiones", "Evaluación",
      "Resumen", "Antecedentes", "Propuesta", "Hallazgos", "Síntesis",
      "Marco teórico", "Trabajo futuro", "Balance anual", "Acuerdos mayo"]
tt = []
for t in RT:
    tt += [f"Cambia el título a {t}.", f"Pon como título {t}.", f"Titula esto como {t}.",
           f"Actualiza el título a {t}."]
fam("a_rn_a", RN, "titulo", tt)
tt = []
for t in RT[:10]:
    tt += [f"Cámbiale el título a {t}.", f"Ponle de título {t}.", f"El nuevo título será {t}.",
           f"Quiero que cambies el título a {t}."]
fam("a_rn_b", RN, "titulo", tt)
fam("a_rn_c", RN, "titulo", [
    "¿Puedes ponerle título al documento?", "Reescribe el título descriptivo.",
    "Corrige el título con errata.", "Haz el título más corto.",
    "Renombra el documento como Proyecto final.", "El encabezado dirá Cierre.",
    "Bautiza el archivo como Entrega.", "Nombra la versión final.",
    "Actualiza la carátula.", "El rótulo será Acta.", "Titula la minuta.",
    "Cambia el encabezado principal.", "Modifica el rótulo.", "Pon membrete nuevo.",
    "El título cámbialo ya.", "Reescribe la portada.", "Ajusta el encabezado.",
    "Define el título del informe.", "Fija el nombre del capítulo."])

# ---------- DELETE_SELECTION ----------
DOBJ = ["esto", "eso", "esta parte", "esta oración", "este párrafo", "este texto",
        "la última frase", "esta palabra", "lo seleccionado", "esa sección",
        "el borrador", "la cita", "el ejemplo", "la nota", "el encabezado",
        "el renglón", "la tabla", "el recuadro", "el inciso", "el fragmento"]
dd = []
for o in DOBJ:
    dd += [f"Borra {o}.", f"Elimina {o}.", f"Quita {o}."]
fam("a_dl_a", DL, "borrar", dd)
dd = []
for o in DOBJ[:12]:
    dd += [f"Suprime {o}.", f"Descarta {o}.", f"Tacha {o}."]
fam("a_dl_b", DL, "borrar", dd)
fam("a_dl_c", DL, "borrar", [
    "¿Puedes quitar esta parte?", "Esto mejor elimínalo.", "Suprime la sección.",
    "Corta esta parte.", "Descarta el último cambio.", "Borra hasta el final.",
    "Elimina lo de paréntesis.", "Quita espacios duplicados.", "Limpia el párrafo.",
    "Vacía la sección.", "Anula este renglón.", "Remueve la dedicatoria.",
    "Retira la cita.", "Tacha el duplicado.", "Corta el epígrafe.", "Haz que esto desaparezca.",
    "Desaparece este bloque.", "Fúmate esta línea.", "Quita de en medio esto."])
fam("a_dl_short", DL, "corto", [
    "Bórralo.", "Borralo.", "Elimínalo.", "Quítalo.", "Táchalo.", "Córtalo.",
    "Suprímelo.", "Descártalo.", "Anúlalo.", "Límpialo.", "Vacíalo.", "Ráelo."])

# ---------- REPLACE_SELECTION ----------
PAIRS = [("error", "errata"), ("problema", "dificultad"), ("uso", "utilización"),
         ("cosa", "elemento"), ("parte", "sección"), ("título", "encabezado"),
         ("inicio", "comienzo"), ("fin", "cierre"), ("imagen", "figura"),
         ("autor", "autora"), ("nota", "aclaración"), ("resumen", "síntesis")]
rr = []
for a, b in PAIRS:
    rr += [f"Cambia {a} por {b}.", f"Sustituye {a} por {b}.", f"Reemplaza {a} por {b}.",
           f"Donde dice {a} pon {b}."]
fam("a_rp_a", RP, "reemplazar", rr)
WORDS = ["dificultades", "interfaz", "accesibilidad", "sistema", "diseño", "término",
         "expresión", "palabra", "concepto", "párrafo", "encabezado"]
rw = []
for w in WORDS:
    rw += [f"Cambia esta palabra por {w}.", f"Reemplaza esta palabra por {w}."]
fam("a_rp_b", RP, "reemplazar", rw)
fam("a_rp_c", RP, "reemplazar", [
    "Sustituye esa expresión por algo claro.", "Reemplaza el término en todo el texto.",
    "Pon dificultades donde dice problemas.", "Intercambia estos dos párrafos.",
    "Cambia comillas inglesas por latinas.", "Sustituye números por letras.",
    "Corrige el nombre del modelo.", "Troca pesos por dólares.",
    "Escribe Ñoño con eñe.", "Pon 2026 donde dice 2025.", "Cambia Ana por Anita.",
    "Reemplaza esta frase.", "Sustituye esto por una expresión diferente.",
    "Cambia la última palabra.", "Sustituye esa expresión.", "Troca error por errata aquí."])

# ---------- REWRITE_SELECTION ----------
RI = ["más corto", "más formal", "más claro", "menos absoluto", "más breve",
      "más directo", "más sencillo", "más académico", "más persuasivo", "más neutro",
      "más conciso", "más crítico", "menos técnico", "más ameno", "más riguroso"]
wr = []
for inst in RI:
    wr += [f"Hazlo {inst}.", f"Haz este párrafo {inst}.", f"Reescribe lo seleccionado {inst}."]
fam("a_rw_a", RW, "reformular", wr)
fam("a_rw_b", RW, "reformular", [
    "Reescribe esto con tono formal.", "Dale otra redacción a esta parte.",
    "Mejora la redacción.", "Suaviza el tono.", "Endurece la conclusión.",
    "Acorta este párrafo.", "Condensa estas frases.", "Explícalo mejor.",
    "Haz este párrafo más claro.", "Reduce esta sección.", "Reformula esta oración.",
    "Dale más claridad a esto.", "Ponlo más formal.", "Hazlo menos absoluto.",
    "Simplifica la explicación.", "Desarrolla el nudo.", "Expón el petitorio.",
    "Aclara el acuerdo.", "Abrevia el proemio.", "Desenreda la trama."])
fam("a_rw_c", RW, "reformular", [
    "Quita las repeticiones de este párrafo.", "Quita muletillas de aquí.",
    "Quita lo redundante.", "Saca lo que sobre.", "Recorta lo innecesario.",
    "Poda los adjetivos.", "Corta los adverbios.", "Limpia este texto."])

# ---------- FORMAT_SELECTION ----------
ff = []
for fmt in ["negritas", "cursivas"]:
    for det in ["esto", "este texto", "lo seleccionado", "esta frase", "el título", "la conclusión"]:
        ff.append(f"Pon {det} en {fmt}.")
fam("a_fm_a", FM, "formato", ff)
fam("a_fm_b", FM, "formato", [
    "Subraya esto.", "Subraya esta parte.", "Quita las negritas.",
    "Pon el título en mayúsculas.", "Convierte esto en una lista.",
    "Centra el encabezado.", "Ponlo en negritas.", "Marca esto como importante.",
    "Hazlo cursiva.", "Subraya esto.", "Aplica subrayado.", "Remarca en negrita.",
    "Cursiva los títulos.", "Negrita los montos.", "Resalta el acuerdo."])
fam("a_fm_short", FM, "corto", [
    "Subráyalo.", "Subrayalo.", "Negrítalo.", "Ennegrita.", "Cursívalo.", "Márcalo."])

# ---------- UNDO (150+) ----------
fam("a_un_a", UN, "undo", [
    "Deshaz el último cambio.", "Deshaz eso.", "Vuelve a como estaba.",
    "No, déjalo como estaba.", "Revierte lo último.", "Cancela la última edición.",
    "Anula lo que hiciste.", "Regresa al estado anterior.", "Échalo para atrás.",
    "Vuelve atrás.", "Deshaz lo último.", "Anula la modificación.",
    "Recupera la versión previa.", "Da un paso atrás.", "Cancela lo anterior.",
    "Retrocede un cambio.", "Deshaz la edición.", "Vuelve al borrador.",
    "Devuélveme al estado previo.", "Regrésame a como estaba.",
    "Desarma el cambio.", "Echa atrás lo de hoy.", "Anula el reemplazo.",
    "Cancela el borrado.", "Revierte lo movido.", "Deshaz lo pegado.",
    "Quita lo último que puse.", "Borra mi edición reciente.",
    "Deshaz el formato.", "Anula la sustitución.", "Revierte el pegado."])
fam("a_un_b", UN, "undo", [
    "Olvida lo que acabo de hacer.", "Como si no hubiera pasado.",
    "Déjalo como estaba antes.", "Restaura lo anterior.", "Vuelve al punto previo.",
    "Deshaz esta mañana.", "Anula lo de ayer.", "Cancela el envío.",
    "Revierte la firma.", "Echa para atrás la compra.", "Anula el trato.",
    "Deshaz el nudo.", "Vuelve sobre tus pasos.", "Retorna al inicio.",
    "Recupera lo perdido.", "Recompon lo roto.", "Arregla mi error.",
    "Corrige lo que hice mal.", "Enmienda el cambio.", "Repara la edición.",
    "Vuelve a empezar de cero.", "Reinicia el documento.", "Carga el respaldo.",
    "Abre la versión anterior.", "Quiero mi texto de antes.", "Necesito lo previo.",
    "Pon todo como estaba.", "Haz como si nada.", "Ignora mi última orden.",
    "Perdona el cambio.", "Retira lo puesto.", "Saca lo agregado."])
fam("a_un_short", UN, "corto", [
    "Deshazlo.", "Deshazlo", "Anúlalo.", "Reviértelo.", "Cancélalo.", "Vuelve atrás.",
    "Para atrás.", "Atrás.", "Como estaba.", "Como antes.", "Igual que antes.",
    "Déjalo así.", "Ya no.", "Mejor no.", "Olvídalo.", "Ni modo."])

# ---------- REDO (150+) ----------
fam("a_rd_a", RD, "redo", [
    "Rehaz el cambio.", "Rehaz eso.", "Vuelve a aplicar lo anterior.",
    "Repite la acción.", "Recupera lo deshecho.", "Deshaz el deshacer.",
    "Rehaz la edición.", "Adelante con el cambio.", "Reaplica el cambio.",
    "Rehaz lo anterior.", "Restaura el cambio deshecho.", "Vuelve a hacer lo anterior.",    "Repite lo anulado.", "Restaura lo anulado.", "Vuelve a quitar lo puesto.",
    "Repite el deshacer.", "Reaplica lo cancelado.", "Restaura lo revertido.",
    "Vuelve a anular lo activo.", "Regresa atrás otra vez.", "Devuelve el cambio previo.",
    "Retorna al estado anterior.", "Deshaz lo último otra vez.", "Cancela de nuevo.",
    "Rehaz una vez más.", "Otra vez rehacer.", "Restaurar lo deshecho ya.",
    "Recuperar lo anterior ya.", "Repite el pegado.", "Rehaz el centrado.",
    "Restaura el interlineado.", "Vuelve a justificar.", "Reaplica el título.",
    "Repite el borrado.", "Restaura el formato.", "Vuelve a centrar.",
    "Rehaz la sangría.", "Reaplica el estilo.", "Restaura el margen."])
fam("a_rd_b", RD, "redo", [
    "Hazlo de nuevo.", "Otra vez lo mismo.", "Repite lo de antes.",
    "Vuelve a intentarlo.", "Reincide en el cambio.", "Reedita lo editado.",
    "Reelabora lo anterior.", "Recomponlo otra vez.", "Repite la jugada.",
    "Segunda vuelta al cambio.", "Reactivar lo desactivado.", "Reabrir lo cerrado.",
    "Regresar al futuro.", "Avanzar de nuevo.", "Proseguir con lo previo.",
    "Continuar donde estabas.", "Retomar el cambio.", "Reanudar la edición.",
    "Reemprender lo anterior.", "Rehacer lo rehecho.", "Volver a volver.",
    "Otra ronda.", "De nuevo.", "Una vez más.", "Como la vez pasada.",
    "Igual que antes.", "Tal como estaba planeado.", "Según lo acordado.",
    "Como habíamos dicho.", "Tal cual lo dejaste.", "Mismo cambio otra vez."])
fam("a_rd_short", RD, "corto", [
    "Rehazlo.", "Rehazlo", "Reaplica.", "Repite.", "Restaura.", "Recupera.",
    "Otra vez.", "De nuevo.", "Igual.", "Lo mismo.", "Como antes.", "Ya.",
    "Dale.", "Sigue.", "Otra.", "Re.", "Va de nuevo.", "Rehaz."])

# ---------- SELECT_TEXT ----------
SEL = ["el segundo párrafo", "la última sección", "el primer capítulo",
       "toda la página", "la cita", "el ejemplo", "el título", "este bloque",
       "la tabla", "el altri pormenores"]
ss = []
for s in SEL:
    ss += [f"Selecciona {s}.", f"Marca {s}.", f"Elige {s}."]
fam("a_sl_a", SL, "seleccion", ss)
fam("a_sl_b", SL, "seleccion", [
    "Selecciona todo el documento.", "Marca todo lo que sigue.",
    "Amplía la selección.", "Reduce la selección.", "Selecciona la palabra accesibilidad.",
    "Marca esta frase.", "Elige el tercer párrafo.", "Selecciona desde aquí al final.",
    "Selecciona la palabra metodología.", "Marca el recuadro gris.",
    "Toma el mapa anexo.", "Aparta el gráfico.", "Señala la imagen.",
    "Aísla el cómputo.", "Delimita el extracto.", "Enfoca el inciso.",
    "Apunta al anexo.", "Ubica la rúbrica.", "Localiza el otrosí.",
    "Elige la tabla.", "Marca el diagrama.", "Resalta el acuerdo."])
fam("a_sl_cf", SL, "confusion", [
    "Marca la palabra metodología.", "Selecciona accesibilidad aquí.",
    "Marca este título para buscarlo.", "Elige el término y encuéntralo.",
    "Selecciona la cita para revisarla.", "Marca la fecha y localízala."])

# ---------- FIND_TEXT ----------
ff = []
for q in ["la palabra accesibilidad", "Metodología", "el folio 042", "conclusiones",
          "TDAH", "la ñ faltante", "el IHC mal escrito", "la sigla INEGI"]:
    ff += [f"Busca {q}.", f"Encuentra {q}.", f"Localiza {q}.", f"Halla {q}."]
fam("a_fn_a", FN, "buscar", ff)
fam("a_fn_b", FN, "buscar", [
    "Detecta dobles espacios.", "Caza erratas.", "Rastrea el término accesibilidad cognitiva.",
    "Ubica comillas simples.", "Halla Diseño con mayúscula.", "Encuentra el guion largo.",
    "Ubica la palabra metodología.", "Localiza dónde aparece TDAH.",
    "Dale más claridad buscando ejemplos.", "Encuentra el nombre del modelo.",
    "Busca comas mal puestas.", "Ubica la fecha de entrega.",
    "Rastrea el 10%.", "Detecta el guion.", "Caza la errata.", "Persigue el error."])
fam("a_fn_cf", FN, "confusion", [
    "Busca la palabra metodología.", "Encuentra accesibilidad en el texto.",
    "Localiza esta expresión.", "Halla el término y márcalo.",
    "Busca el título para cambiarlo.", "Encuentra la cita y revísala."])

# ---------- SAVE_DOCUMENT ----------
fam("a_sv_a", SV, "guardar", [
    "Guarda el documento.", "Guarda los cambios.", "Guarda una copia.",
    "Guarda antes de salir.", "Guarda el archivo.", "Guarda el progreso.",
    "Guarda el informe.", "Guarda esta versión.", "Guarda la carta.", "Guarda el acta.",
    "Respalda el avance.", "Archiva el tanto.", "Consigna el legajo.",
    "Asienta los cambios.", "Preserva esta redacción.", "Asegura el archivo.",
    "Fija esta versión.", "Congela el borrador.", "Salvaguarda lo escrito.",
    "Registra el progreso.", "Deposita el tanto.", "Custodia el original.",
    "Pon a salvo el texto.", "Deja todo guardado.", "Guarda el tanto.",
    "Archiva el oficio.", "Consigna el avance.", "Guarda una versión anterior."])
fam("a_sv_short", SV, "corto", [
    "Guárdalo.", "Guardalo.", "Archívalo.", "Respáldalo.", "Fíjalo.", "Guarda.",
    "Guarda ya.", "Salva.", "Asegura.", "Fija.", "Deposita.", "Consigna."])

# ---------- OPEN_DOCUMENT ----------
fam("a_op_a", OP, "abrir", [
    "Abre el archivo anterior.", "Abre el documento adjunto.", "Abre la carpeta.",
    "Abre el último borrador.", "Abre el pdf.", "Abre una ventana nueva.",
    "Abre el contrato.", "Abre la tesis.", "Abre el manual.", "Abre el informe.",
    "Recupera el acta vieja.", "Desempolva el expediente.", "Reabre la minuta.",
    "Carga el informe 2024.", "Jala el archivo.", "Trae el contrato.",
    "Muéstrame la tesis.", "Presenta el Balance.", "Desarchiva el legajo.",
    "Recobra el borrador.", "Vuelve a abrir el anexo.", "Retoma el acta.",
    "Exhibe el padrón.", "Despliega el mapa.", "Proyecta la tabla.",
    "Recupera el expediente.", "Reabre el acta.", "Abre el anexo."])
fam("a_op_short", OP, "corto", [
    "Ábrelo.", "Abrelo.", "Muéstralo.", "Cárgalo.", "Tráelo.", "Jálalo.",
    "Desarchiva.", "Recupera.", "Reabre.", "Exhibe.", "Despliega.", "Abre."])

# ---------- EXPORT_DOCUMENT ----------
fam("a_ex_a", EX, "exportar", [
    "Exporta el documento.", "Exporta como pdf.", "Exporta a texto plano.",
    "Genera el pdf.", "Convierte a Word.", "Exporta la presentación.",
    "Exporta la tesis.", "Exporta el manual.", "Exporta el folleto.",
    "Exporta el informe final.", "Saca el acta en pdf.", "Baja el txt plano.",
    "Genera rtf.", "Vierte a docx.", "Rinde el borrador.", "Produce el pdf final.",
    "Emite copia enriquecida.", "Migra el tanto a Word.", "Funde el pdf maestro.",
    "Extrae el puro texto.", "Publica la versión rica.", "Guarda copia plana aparte.",
    "Entrega versión con formato.", "Rinde el texto sin formato.",
    "Saca el informe en pdf.", "Baja el acta en texto.", "Guárdalo como archivo Word.",
    "Exporta una copia en texto plano."])
fam("a_ex_cf", EX, "confusion", [
    "Guarda una copia como PDF.", "Guarda el acta en pdf.",
    "Archiva una copia en Word.", "Imprime en pdf virtual.",
    "Convierte y guarda en pdf.", "Respalda en formato pdf."])

# ---------- UNSUPPORTED (600+) ----------
fam("a_us_firmar", US, "unsup-firmar", [
    "Firma el documento.", "Firma este archivo.", "Firma el convenio.",
    "Firma aquí abajo.", "Firma con rúbrica.", "Firma el acta.",
    "Firma digitalmente.", "Estampa tu firma.", "Rúbrica el oficio.",
    "Fírmalo al calce.", "Firma de conformidad.", "Firma el contrato.",
    "Pon tu firma.", "Autografía el libro.", "Valida con tu firma.",
    "Certifica firmando.", "Sella y firma.", "Firma el pagaré.",
    "Endosa el cheque.", "Suscribe el acuerdo."])
fam("a_us_traducir", US, "unsup-traducir", [
    "Traduce esto al inglés.", "Traduce este párrafo.", "Traduce el acta.",
    "Pásalo al inglés.", "Vierte al español.", "Traduce la minuta.",
    "Interpreta este texto.", "Traduce al portugués.", "Ponlo en francés.",
    "Traduce el abstract.", "Versiona al inglés.", "Traslada el sentido.",
    "Traduce palabra por palabra.", "Haz una traducción libre.",
    "Traduce el contrato.", "Pásame esto a inglés.", "Traduce el informe.",
    "Convierte al inglés.", "Traduce la carta.", "Traduce el manual."])
fam("a_us_correo", US, "unsup-correo", [
    "Mándalo por correo.", "Envía esto por mensaje.", "Comparte esto por correo.",
    "Manda el informe por email.", "Envía la minuta.", "Comparte el archivo.",
    "Mándalo por paquetería.", "Envía por valija.", "Difunde el boletín.",
    "Publica en el blog.", "Sube el documento a Drive.", "Comparte en la nube.",
    "Envía por mensajería.", "Manda copia al equipo.", "Reenvía el correo.",
    "Adjunta el informe.", "Manda el acta.", "Comparte la carpeta.",
    "Envía el tanto.", "Difunde el aviso."])
fam("a_us_agenda", US, "unsup-agenda", [
    "Agenda una revisión.", "Agéndame cita mañana.", "Programa un recordatorio.",
    "Fija la reunión.", "Aplaza la junta.", "Adelanta la entrega.",
    "Convoca a junta.", "Cita a las partes.", "Programa el envío.",
    "Recuérdame mañana.", "Avisa con tiempo.", "Coordina horarios.",
    "Reserva la sala.", "Aparta fecha.", "Calendariza la revisión.",
    "Reagenda lo de hoy.", "Pospón la audiencia.", "Anticipa el taller.",
    "Organiza el evento.", "Planea la semana."])
fam("a_us_imprimir", US, "unsup-imprimir", [
    "Imprime el documento.", "Imprime una copia.", "Imprime a doble cara.",
    "Imprime en color.", "Imprime el acta.", "Manda a imprimir.",
    "Saca una impresión.", "Imprime el informe.", "Imprime el contrato.",
    "Imprime la tesis.", "Imprime el manual.", "Imprime el folleto.",
    "Saca copias.", "Fotocopia el legajo.", "Imprime el acuse.",
    "Imprime el comprobante.", "Saca la constancia.", "Imprime el diploma."])
fam("a_us_cifrar", US, "unsup-cifrar", [
    "Cifra el documento.", "Cifra el archivo.", "Ponle contraseña.",
    "Bloquea con clave.", "Protege el informe.", "Encripta el acta.",
    "Codifica el mensaje.", "Cifra la carpeta.", "Ponle candado digital.",
    "Asegura con contraseña.", "Cifra de extremo a extremo.",
    "Encripta la copia.", "Protege con PIN.", "Bloquea el acceso.",
    "Oculta con clave.", "Cifra el respaldo.", "Encripta el envío.",
    "Ponle huella.", "Activa el bloqueo.", "Cifra el tanto."])
fam("a_us_comprimir", US, "unsup-comprimir", [
    "Comprime el documento.", "Comprime el archivo.", "Comprime en zip.",
    "Reduce el tamaño.", "Compacta la carpeta.", "Empaqueta el informe.",
    "Zipéalo.", "Comprímelo ya.", "Achica el pdf.", "Comprime el anexo.",
    "Empaca los archivos.", "Comprime la tesis.", "Reduce el peso.",
    "Optimiza el tamaño.", "Comprime las imágenes.", "Aligera el archivo.",
    "Comprime el video.", "Empaqueta el legajo.", "Zipéa el tanto.",
    "Comprime el respaldo."])
fam("a_us_codigo", US, "unsup-codigo", [
    "Ejecuta este código.", "Corre el script.", "Compila el programa.",
    "Despliega a producción.", "Reinicia el servidor.", "Formatea el disco.",
    "Instala el paquete.", "Ejecuta la prueba.", "Corre las pruebas.",
    "Depura el error.", "Optimiza la consulta.", "Refactoriza el módulo.",
    "Haz commit.", "Sube el cambio.", "Fusiona la rama.", "Revierte el deploy.",
    "Reinicia el servicio.", "Monitorea el uso.", "Escala el servicio.",
    "Respalda la base."])
fam("a_us_convertir", US, "unsup-convertir", [
    "Convierte esto en una presentación.", "Convierte a mayúsculas todo.",
    "Convierte en tabla.", "Convierte a video.", "Convierte a audio.",
    "Convierte el texto en voz.", "Pasa a diapositivas.", "Haz una infografía.",
    "Convierte en pdf interactivo.", "Transforma en formulario.",
    "Convierte a epub.", "Pasa a markdown.", "Convierte en hoja de cálculo.",
    "Haz un diagrama.", "Convierte en mapa mental.", "Pasa a línea de tiempo.",
    "Convierte en encuesta.", "Haz un cuestionario.", "Convierte en examen.",
    "Transforma en resumen ejecutivo."])
fam("a_us_varios", US, "unsup-varios", [
    "Comparte pantalla.", "Graba la reunión.", "Toma captura.",
    "Dicta el siguiente párrafo.", "Lee este mensaje.", "Llama a soporte.",
    "Pide ayuda.", "Abre el navegador.", "Busca en internet.",
    "Reproduce el audio.", "Sube el volumen.", "Baja el brillo.",
    "Activa el wifi.", "Apaga el bluetooth.", "Carga la batería.",
    "Actualiza el sistema.", "Sincroniza el reloj.", "Cambia el fondo.",
    "Pon modo oscuro.", "Activa el dictado.", "Calibra el micrófono.",
    "Prueba el audio.", "Ajusta el micrófono.", "Silencia todo.",
    "Graba una nota de voz.", "Transcribe el audio.", "Subtitula el video.",
    "Recorta el audio.", "Normaliza el volumen.", "Elimina el ruido."])
fam("a_us_hard", US, "unsup-duro", [
    "Firma el documento final.", "Guarda y firma el acta.",
    "Traduce y guarda el informe.", "Imprime y firma las copias.",
    "Comparte y archiva el tanto.", "Agenda y confirma la junta.",
    "Cifra y respalda el archivo.", "Comprime y envía el informe.",
    "Convierte y exporta el acta.", "Ejecuta y guarda el reporte."])

# ---------- NO_ACTION (400+) ----------
fam("a_na_conv", NA, "conversacion", [
    "Déjame pensarlo.", "No estoy seguro.", "Hmm.", "Espera un momento.",
    "Bueno.", "Tal vez.", "Así está bien.", "Hmm, no.", "No sé.", "A ver.",
    "Ya veo.", "Entiendo.", "De acuerdo.", "Interesante.", "Vaya.", "Mmm.",
    "Vale.", "Ni idea.", "Puede ser.", "Ya.", "Listo.", "Siguiente.",
    "Continúa.", "Te escucho.", "Dime.", "Un momento.", "Pausa.", "Sigo.",
    "Adelante.", "Ya merito queda.", "Aguanta vara.", "No te awites.",
    "Échale ganas.", "Qué onda.", "Con permiso, voy pasando.",
    "Se hizo de noche.", "Escampó al fin.", "Permíteme un segundo.",
    "Dame chance.", "Aguántame tantito.", "Ahorita lo veo.", "Al rato lo checamos.",
    "Luego lo platicamos.", "Mañana lo decidimos.", "Casi, casi.",
    "Ahí va quedando.", "Va tomando forma.", "Pinta bien.", "Huele a éxito.",
    "Tiene potencial.", "Le falta sazón.", "Ya madurará.", "Dale tiempo.",
    "Sin prisa.", "Paso a paso.", "Ahí la llevamos.", "El examen me dejó pensando.",
    "La junta se alargó.", "Traigo sueño.", "Ando desvelado.", "Me duele la espalda.",
    "Tengo hambre.", "Muero de sed.", "Mi equipo perdió.", "El celular se traba.",
    "Se acabó la pila.", "No hay señal.", "El internet está lento.",
    "Se cayó el sistema.", "Olvidé mi contraseña.", "El coche no arranca."])
fam("a_na_imp", NA, "imperative-like", [
    "Mira, no estoy seguro.", "Espera, todavía no termino.",
    "Pon atención a lo que diré.", "Déjalo, luego vemos.",
    "Olvida eso por ahora.", "Dame un segundo.", "Aguanta un momento.",
    "Escucha, falta una parte.", "Piensa antes de responder.", "Respira hondo.",
    "Calma, hay tiempo.", "Tranquilo todo saldrá bien.", "Frena el ritmo.",
    "Baja la voz.", "Abre bien los ojos.", "Cierra la puerta al salir.",
    "Apaga la luz.", "Tiende tu cama.", "Barre la entrada.", "Riega las plantas.",
    "Saca la basura.", "Haz la tarea.", "Estudia para el examen.",
    "Corre tres kilómetros.", "Cruza por el puente.", "Toma el camión.",
    "No llegues tarde.", "No olvides las llaves.", "No tires la toalla.",
    "No pierdas la calma.", "No te rindas.", "Cuida a tu hermanito.",
    "Alimenta al gato.", "Pasea al perro.", "Limpia la pecera.", "Recoge las hojas.",
    "Guarda la bicicleta.", "Tiende la ropa.", "Dobla las sábanas.",
    "Lava el baño.", "Enciende el boiler.", "Paga la luz.", "Deposita la renta.",
    "Ahorra cada mes.", "Come verduras.", "Toma agua.", "Duerme temprano.",
    "Pela las papas.", "Pica la cebolla.", "Calienta las tortillas.",
    "Sirve la sopa.", "Tapa la olla.", "Bate los huevos.", "Cuela el café.",
    "Lava las verduras.", "Limpia el refri.", "Aspira la sala.",
    "Abre las ventanas.", "Ventila el cuarto.", "Apaga el clima.",
    "Riega el pasto.", "Barre la banqueta.", "Lava el coche.", "Saca el bote."])
fam("a_na_dict", NA, "dictado", [
    "Borrar información accidentalmente afecta la experiencia.",
    "Guardar documentos automáticamente reduce pérdidas.",
    "La frase \"guarda el documento\" es un ejemplo.",
    "Deshacer una acción debería ser sencillo.",
    "Imprimir documentos consume papel.",
    "El editor cambia el título desde la barra.",
    "La función deshacer recupera contenido.",
    "El usuario borra oraciones con el teclado.",
    "Seleccionar texto requiere práctica.",
    "El sistema reemplaza palabras solo.",
    "Se explica cambiar el formato.",
    "Los usuarios ponen negritas para resaltar.",
    "El comando borrar elimina lo seleccionado.",
    "Abrir archivos grandes consume memoria.",
    "Buscar información toma tiempo.",
    "Copiar texto introduce duplicados.",
    "Leer en voz alta apoya la revisión.",
    "Guardar silencio también comunica.",
    "Abrir debate enriquece la clase.",
    "Imprimir carteles difunde eventos.",
    "Buscar consenso llevó la tarde.",
    "La interacción humano computadora estudia sistemas.",
    "Guardar cambios evita perder trabajo.",
    "Buscar información requiere tiempo.",
    "Imprimir documentos consume papel.",
    "Leer párrafos ayuda a revisar.",
    "Abrir ventanas ventila cuartos.",
    "Copiar citas exige referenciar.",
    "Pegar sin revisar arrastra errores.",
    "Exportar en pdf congela formatos.",
    "Seleccionar todo simplifica.",
    "Deshacer rápido evita arrepentimientos.",
    "Rehacer tareas cansa.",
    "Subrayar todo pierde sentido.",
    "Cambiar de tema distrae.",
    "Borrar borradores libera espacio.",
    "Mover muebles lesiona espaldas.",
    "Firmar rápido trae problemas.",
    "Revisar dos veces evita errores.",
    "Aceptar culpas desgasta.",
    "Separar residuos ayuda.",
    "Navegar con niebla es peligroso.",
    "Sincronizar agendas cuesta.",
    "Renombrar calles confunde.",
    "Duplicar recetas une.",
    "Traducir poesía pierde rimas.",
    "Contar ovejas no duerme.",
    "Ordenar cajones relaja.",
    "Insertar pausas mejora discursos.",
    "Combinar colores alegra.",
    "Archivar facturas evita multas.",
    "La tesis analiza barreras.",
    "El estudio muestra mejoras.",
    "Mi proyecto propone un editor.",
    "Los resultados sugieren avances."])

# ---------- MULTI_ACTION (300+) ----------
MU_A = ["Cambia el título y guarda el documento.", "Ponlo en negritas y guárdalo.",
        "Borra esto y deshaz el cambio.", "Busca accesibilidad y selecciona el primero.",
        "Reemplaza esto y guarda copia.", "Hazlo breve y exporta en pdf.",
        "Subraya el monto y archiva.", "Deshaz el pegado y rehace la numeración.",
        "Selecciona la tabla y ponla en negritas.", "Cursiva la cita y guarda.",
        "Resume la minuta y titula Síntesis.", "Troca pesos y archiva el tanto.",
        "Abre el acta y busca el folio.", "Carga el informe y selecciona la tabla.",
        "Trae el contrato y ponlo en negritas.", "Desarchiva y numera las fojas.",
        "Borra el renglón, deshazlo y guarda.", "Pon Claridad, subraya y exporta.",
        "Busca IHC, selecciona y pon cursivas.", "Cambia CDMX, guarda y exporta.",
        "Hazlo breve, titula y archiva.", "Tacha y pon en negritas.",
        "Endereza y centra el título.", "Limpia y guarda el acta.",
        "Pule y exporta en pdf.", "Retoca y archiva el legajo.",
        "Enmarca y subraya al deudor.", "Colorea y guarda el informe.",
        "Grafica y exporta en Word.", "Tabula y guarda la minuta.",
        "Anota al margen y guarda.", "Glosa y subraya la fecha.",
        "Firma, sella y archiva.", "Digitaliza y escanea a color.",
        "Engrapa, perfora y archiva.", "Recorta, dobla y ensobra.",
        "Turna, firma y archiva.", "Recaba firmas y guarda."]
fam("a_mu_a", MU, "multi", MU_A)
MU_B = ["Guarda el informe y envíalo por correo.", "Abre el contrato y revísalo.",
        "Imprime el acta y fírmala.", "Busca el folio y márcalo.",
        "Exporta el pdf y compártelo.", "Lee el párrafo y corrígelo.",
        "Selecciona todo y cópialo.", "Encuentra el error y bórralo.",
        "Cambia el título y avisa al equipo.", "Pon negritas y subraya el total.",
        "Hazlo corto y tradúcelo.", "Resume y envía la minuta.",
        "Reemplaza el término y guarda versión.", "Formatea y exporta el informe.",
        "Deshazlo, reházlo y guarda.", "Abre, lee y archiva el oficio.",
        "Busca, selecciona y elimina duplicados.", "Copia, pega y guarda copia.",
        "Revisa, firma y envía el acta.", "Numera, imprime y archiva fojas."]
fam("a_mu_b", MU, "multi", MU_B)

with open(HERE / "pool.csv", "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f)
    w.writerow(["text", "label", "category", "family_id"])
    for t, l, c, fid in rows:
        w.writerow([t, l, c, fid])

from collections import Counter
print(f"pool: {len(rows)}", dict(Counter(r[1] for r in rows)), f"fams={len({r[3] for r in rows})}", file=sys.stderr)

# ================= EXPANSIÓN frames x fillers =================
XT = ["Metodología", "Resultados", "Discusión", "Conclusiones", "Evaluación",
      "Resumen", "Anexos", "Propuesta", "Hallazgos", "Síntesis", "Balance",
      "Minuta", "Acta", "Informe", "Prólogo", "Epílogo", "Glosario", "Índice"]
for t in XT:
    fam(f"x_rn_{t[:4]}", RN, "titulo", [
        f"El título será {t}.", f"Pon de nombre {t}.", f"Llama a esto {t}.",
        f"Denomina el archivo {t}.", f"Intitula como {t}.", f"Encabeza con {t}."])
XD = ["el párrafo", "la frase", "el bloque", "la columna", "el recuadro", "la viñeta"]
for o in XD:
    fam(f"x_dl_{o.split()[-1]}", DL, "borrar", [
        f"Borra {o} completo.", f"Elimina {o} ya.", f"Quita {o} por favor.",
        f"Deshazte de {o}.", f"Suprime {o} ahora."])
XRP = [("título", "nombre"), ("fecha", "día"), ("firma", "rúbrica"), ("sello", "timbre"),
       ("folio", "número"), ("anexo", "apéndice"), ("cita", "referencia"), ("monto", "cantidad")]
for a, b in XRP:
    fam(f"x_rp_{a[:4]}", RP, "reemplazar", [
        f"Cambia {a} por {b}.", f"Pon {b} en vez de {a}.", f"Sustituye {a} con {b}.",
        f"Troca {a} a {b}."])
XRI = ["más sobrio", "más vivo", "más breve aún", "menos largo", "más elegante",
       "más simple", "más potente", "más cálido", "más seco", "más redondo"]
for inst in XRI:
    fam(f"x_rw_{inst.split()[-1]}", RW, "reformular", [
        f"Déjalo {inst}.", f"Vuelve esto {inst}.", f"Transfórmalo a {inst}.",
        f"Adáptalo a {inst}."])
XFM = ["el subtítulo", "la cifra", "el nombre", "la fecha", "el total", "el fallo",
       "la firma", "el acuerdo", "el matiz", "el considerando"]
for o in XFM:
    fam(f"x_fm_{o.split()[-1]}", FM, "formato", [
        f"Marca {o} en negritas.", f"Pon {o} en cursivas.", f"Subraya {o}.",
        f"Destaca {o} con formato."])
XUN = ["el pegado de hoy", "la firma puesta", "el borrado útil", "el cambio bueno",
       "la sustitución", "el formato nuevo", "la numeración", "el centrado"]
for o in XUN:
    fam(f"x_un_{o.split()[1]}", UN, "undo", [
        f"Deshaz {o}.", f"Anula {o}.", f"Revierte {o}.", f"Cancela {o}."])
XRD = ["el deshecho de ayer", "lo anulado", "lo revertido", "lo cancelado",
       "el borrado útil", "el formato previo", "la versión buena", "el cambio"]
for o in XRD:
    fam(f"x_rd_{o.split()[1]}", RD, "redo", [
        f"Rehaz {o}.", f"Reaplica {o}.", f"Restaura {o}.", f"Repite {o}."])
XSL = ["el mapa", "la gráfica", "el diagrama", "la imagen", "el recuadro",
       "la foja", "el inciso", "el artículo", "el anexo", "la rúbrica"]
for o in XSL:
    fam(f"x_sl_{o.split()[1]}", SL, "seleccion", [
        f"Selecciona {o} completo.", f"Marca {o} entero.", f"Toma {o} todo.",
        f"Aísla {o}."])
XFN = ["el término", "la fecha", "el monto", "el nombre", "el folio",
       "la cita", "el error", "la sigla", "el símbolo", "el porcentaje"]
for o in XFN:
    fam(f"x_fn_{o.split()[1]}", FN, "buscar", [
        f"Busca {o} exacto.", f"Encuentra {o} ya.", f"Localiza {o} ahora.",
        f"Halla {o} rápido."])
XSV = ["el tanto", "el oficio", "el legajo", "el acta", "la minuta", "el informe",
       "el expediente", "el acuse", "el comprobante", "el respaldo"]
for o in XSV:
    fam(f"x_sv_{o.split()[1]}", SV, "guardar", [
        f"Guarda {o} ya.", f"Archiva {o} por favor.", f"Consigna {o} ahora.",
        f"Registra {o}."])
XOP = ["el legajo viejo", "el acta pasada", "la minuta anterior", "el informe 2023",
       "el contrato base", "la tesis digital", "el manual impreso", "el padrón"]
for o in XOP:
    fam(f"x_op_{o.split()[1]}", OP, "abrir", [
        f"Abre {o}.", f"Recupera {o}.", f"Carga {o} ahora.", f"Desarchiva {o}."])
XEX = ["el dictamen", "la resolución", "el laudo", "el convenio", "el contrato",
       "el informe", "la minuta", "el acta", "el anexo", "el padrón"]
for o in XEX:
    fam(f"x_ex_{o.split()[1]}", EX, "exportar", [
        f"Exporta {o} en pdf.", f"Saca {o} en texto.", f"Genera {o} en Word.",
        f"Rinde {o} final."])
XUS = ["Pide un taxi.", "Ordena cena.", "Reserva hotel.", "Compra regalos.",
       "Riega el jardín.", "Pasea al perro.", "Lava el auto.", "Cocina pasta.",
       "Llama al doctor.", "Agenda dentista.", "Paga la renta.", "Riega plantas.",
       "Tiende la cama.", "Barre el patio.", "Saca la basura.", "Lava trastes.",
       "Plancha camisas.", "Cose el botón.", "Pinta la cerca.", "Repara la silla."]
for u in XUS:
    fam(f"x_us_{u.split()[0]}", US, "unsup-vida", [u, u.replace(".", ", por favor.")])
XNA = ["El parte meteorológico anuncia lluvia.", "La cartelera renueva estrenos.",
       "El mercado abrió con alzas.", "La liga empieza en agosto.",
       "El censo contará viviendas.", "La feria será en octubre.",
       "El desfile pasa al mediodía.", "La verbena cierra tarde.",
       "El concierto cambió de sede.", "La obra extiende temporada.",
       "El museo abre sala nueva.", "El curso inicia el lunes.",
       "La beca cubre colegiatura.", "El taller cuesta mil.", "El diplomado dura un año.",
       "Traigo prisa hoy.", "Ando cansado.", "Hace calor aquí.", "Ya es noche.",
       "Mañana será otro día."]
for u in XNA:
    fam(f"x_na_{u.split()[0]}", NA, "conversacion", [u, "Pues " + u[0].lower() + u[1:]])
XMU = ["Titula y guarda.", "Borra y archiva.", "Busca y marca.",
       "Copia y pega.", "Lee y corrige.", "Abre y revisa.",
       "Resume y titula.", "Formatea y exporta.", "Deshaz y guarda.",
       "Selecciona y subraya.", "Encuentra y elimina.", "Numeray archiva.",
       "Centra y guarda.", "Firma y sella.", "Escanea y archiva.",
       "Recorta y pega.", "Justifica y exporta.", "Sangra y numera.",
       "Cursiva y guarda.", "Subraya y archiva."]
for u in XMU:
    fam(f"x_mu_{u.split()[0]}", MU, "multi", [u, u.replace(".", " ahora.")])

# ================= EXPANSIÓN 2 =================
YT = ["Prontuario", "Memorial", "Expediente", "Legajo", "Foja", "Otrosí",
      "Considerando", "Resolutivo", "Laudo", "Convenio", "Contrato", "Acta",
      "Minuta", "Oficio", "Circular", "Boletín", "Gaceta", "Diario"]
for t in YT:
    fam(f"y_rn_{t[:4]}", RN, "titulo", [
        f"Ponle {t} de nombre.", f"Titúlalo {t}.", f"Denomínalo {t}.",
        f"Rotúlalo como {t}."])
YD = ["el altri", "el otrosí", "la foja", "el legajo", "la minuta", "el oficio",
      "la circular", "el boletín", "la gaceta", "el considerando"]
for o in YD:
    fam(f"y_dl_{o.split()[-1]}", DL, "borrar", [
        f"Borra {o} ya.", f"Quita {o} ahora.", f"Elimina {o} por favor.",
        f"Tacha {o}."])
YRP = [("acta", "minuta"), ("oficio", "circular"), ("foja", "hoja"), ("legajo", "fajo"),
       ("considerando", "visto"), ("resolutivo", "fallo"), ("laudo", "sentencia"),
       ("convenio", "pacto")]
for a, b in YRP:
    fam(f"y_rp_{a[:4]}", RP, "reemplazar", [
        f"Cambia {a} por {b}.", f"Sustituye {a} por {b}.", f"Pon {b} en lugar de {a}."])
YRI = ["más breve todavía", "menos enredado", "más claro aún", "más ligero",
       "más contundente", "más tibio", "más filoso", "más plano", "más hondo",
       "más ágil"]
for inst in YRI:
    fam(f"y_rw_{inst.split()[-1]}", RW, "reformular", [
        f"Ponlo {inst}.", f"Hazlo {inst} ya.", f"Déjalo {inst}."])
YFM = ["el altri", "el otrosí", "la foja", "el legajo", "la minuta", "el oficio",
       "la rúbrica", "el sello", "el folio", "la firma"]
for o in YFM:
    fam(f"y_fm_{o.split()[-1]}", FM, "formato", [
        f"Resalta {o} en negritas.", f"Pon {o} en cursiva.", f"Subraya {o} ya."])
YUN = ["lo de ayer", "lo anterior", "el último paso", "la última línea",
       "el párrafo nuevo", "la tabla nueva", "el título nuevo", "el envío"]
for o in YUN:
    fam(f"y_un_{o.split()[1]}", UN, "undo", [
        f"Deshaz {o}.", f"Cancela {o}.", f"Anula {o}."])
YRD = ["lo deshecho hoy", "lo anulado", "lo revertido", "lo cancelado",
       "lo borrado", "lo movido", "lo pegado", "lo centrado"]
for o in YRD:
    fam(f"y_rd_{o.split()[1]}", RD, "redo", [
        f"Rehaz {o}.", f"Repite {o}.", f"Restaura {o}."])
YSL = ["el otrosí", "la foja", "el legajo", "la minuta", "el oficio",
       "la circular", "el boletín", "la rúbrica", "el sello", "el folio"]
for o in YSL:
    fam(f"y_sl_{o.split()[1]}", SL, "seleccion", [
        f"Elige {o}.", f"Aparta {o}.", f"Marca {o} ya."])
YFN = ["el altri", "el otrosí", "la foja", "el legajo", "la minuta",
       "el oficio", "la rúbrica", "el sello", "el folio", "la firma"]
for o in YFN:
    fam(f"y_fn_{o.split()[1]}", FN, "buscar", [
        f"Halla {o}.", f"Ubica {o}.", f"Encuentra {o} ya."])
YSV = ["el altri", "el otrosí", "la foja", "el legajo", "la minuta",
       "el oficio", "la circular", "el boletín", "el acuse", "el tanto"]
for o in YSV:
    fam(f"y_sv_{o.split()[1]}", SV, "guardar", [
        f"Archiva {o}.", f"Guarda {o} bien.", f"Consigna {o}."])
YOP = ["el altri", "el otrosí", "la foja", "el legajo", "la minuta",
       "el oficio", "la circular", "el boletín", "el padrón", "el mapa"]
for o in YOP:
    fam(f"y_op_{o.split()[1]}", OP, "abrir", [
        f"Recupera {o}.", f"Desarchiva {o}.", f"Abre {o} ya."])
YEX = ["el altri", "el otrosí", "la foja", "el legajo", "la minuta",
       "el oficio", "la circular", "el boletín", "el acta", "el informe"]
for o in YEX:
    fam(f"y_ex_{o.split()[1]}", EX, "exportar", [
        f"Saca {o} en pdf.", f"Rinde {o} en texto.", f"Genera {o} en Word."])
YUS = ["Barre el taller.", "Trapea el local.", "Lava la banqueta.", "Riega el patio.",
       "Poda el árbol.", "Corta el pasto.", "Pinta la reja.", "Repara la chapa.",
       "Cambia el foco.", "Destapa el baño.", "Arregla la llave.", "Lija la mesa.",
       "Ensambla el mueble.", "Cuelga el cuadro.", "Clava el clavito.",
       "Atornilla la repisa.", "Mide la ventana.", "Corta la tabla.",
       "Pega el póster.", "Enmarca el diploma."]
for u in YUS:
    fam(f"y_us_{u.split()[0]}", US, "unsup-hogar", [u, "Por favor, " + u[0].lower() + u[1:]])
YUSC = ["Firma la lista.", "Traduce el menú.", "Comparte el wifi.", "Imprime el mapa.",
        "Agenda el servicio.", "Cifra el respaldo.", "Comprime fotos.", "Ejecuta el test.",
        "Convierte el audio.", "Envía la ubicación.", "Sube la foto.", "Baja la app.",
        "Actualiza el perfil.", "Cambia el avatar.", "Silencia el grupo.",
        "Fija el mensaje.", "Reenvía el meme.", "Guarda el sticker.",
        "Crea el grupo.", "Elimina el chat."]
for u in YUSC:
    fam(f"y_usc_{u.split()[0]}", US, "unsup-cercano", [u, u.replace(".", " ya.")])
YNA = ["El tianguis abre temprano.", "La feria cierra tarde.", "El desfile pasa a las diez.",
       "La verbena sigue en pie.", "El concierto se pospone.", "La obra sigue en cartel.",
       "El museo cierra lunes.", "El curso abre inscripciones.", "La beca ya salió.",
       "El taller cambió de sede.", "Traigo sueño ligero.", "Ando medio enfermo.",
       "Hace un calorón.", "Ya merito es quincena.", "Mañana no hay clases.",
       "El camión tarda horas.", "La fila avanza lento.", "El trámite es rápido.",
       "La cita quedó agendada.", "El doctor atiende tarde."]
for u in YNA:
    fam(f"y_na_{u.split()[0]}", NA, "conversacion", [u, "Oye, " + u[0].lower() + u[1:]])
YMU = ["Titula, guarda y exporta.", "Borra, deshaz y archiva.", "Busca, marca y subraya.",
       "Lee, corrige y guarda.", "Abre, revisa y firma.", "Resume, titula y envía.",
       "Formatea, guarda y comparte.", "Selecciona, copia y pega.",
       "Encuentra, reemplaza y guarda.", "Numera, imprime y archiva.",
       "Centra, justifica y exporta.", "Recorta, pega y guarda.",
       "Firma, sella y envía.", "Escanea, guarda y comparte.",
       "Anota, subraya y archiva.", "Glosa, exporta y guarda.",
       "Digitaliza, nombra y archiva.", "Folía, sella y guarda.",
       "Turna, recaba y archiva.", "Revisa, rubrica y envía."]
for u in YMU:
    fam(f"y_mu_{u.split()[0]}", MU, "multi", [u, u.replace(".", " por favor.")])

# ================= EXPANSIÓN 3 =================
ZT = ["Resolutivo", "Visto", "Resultando", "Considerando", "Por tanto",
      "Anexo", "Apéndice", "Adenda", "Fe de erratas", "Colofón",
      "Epígrafe", "Exordio", "Peroración", "Coda", "Interludio"]
for t in ZT:
    fam(f"z_rn_{t[:4]}", RN, "titulo", [
        f"Pon {t} de título.", f"Titula este bloque {t}.", f"Encabeza así: {t}.",
        f"El rótulo dirá {t}."])
ZFM = ["el considerando", "el resolutivo", "el altri", "el otrosí", "la foja",
       "el legajo", "la minuta", "el oficio", "el visto", "el resultando",
       "el exordio", "la coda", "el interludio", "la peroración", "la adenda"]
for o in ZFM:
    fam(f"z_fm_{o.split()[-1]}", FM, "formato", [
        f"Pon {o} en negritas.", f"Pon {o} en cursivas.", f"Subraya {o} por favor."])
for o in ZFM[:10]:
    fam(f"z_fm2_{o.split()[-1]}", FM, "formato", [
        f"Aplica negritas a {o}.", f"Marca {o} en cursiva.", f"Resalta {o}."])
ZUN = ["la sangría", "el interlineado", "la justificación", "la numeración",
       "el centrado", "el subrayado", "la cursiva", "el pegado de hoy",
       "la firma puesta", "el borrado útil", "la tabla nueva", "el título nuevo",
       "el envío", "la sustitución", "el formato nuevo"]
for o in ZUN:
    fam(f"z_un_{o.split()[1]}", UN, "undo", [
        f"Deshaz {o} ya.", f"Anula {o} por favor.", f"Echa atrás {o}."])
ZRD = ["la sangría rehecha", "el interlineado", "la justificación", "la numeración",
       "el centrado", "el subrayado", "la cursiva", "el pegado de hoy",
       "la firma puesta", "el borrado útil", "la tabla nueva", "el título nuevo",
       "el envío", "la sustitución", "el formato nuevo"]
for o in ZRD:
    fam(f"z_rd_{o.split()[1]}", RD, "redo", [
        f"Rehaz {o} ya.", f"Reaplica {o} por favor.", f"Restaura {o}."])
ZSL = ["el considerando", "el resolutivo", "el visto", "el resultando",
       "el exordio", "la coda", "el interludio", "la peroración", "la adenda",
       "el fe de erratas", "el colofón", "el epígrafe", "la foja", "el legajo",
       "la minuta"]
for o in ZSL:
    fam(f"z_sl_{o.split()[1]}", SL, "seleccion", [
        f"Selecciona {o} ya.", f"Marca {o} completo.", f"Elige {o} por favor."])
ZFN = ["el considerando", "el resolutivo", "el visto", "el resultando",
       "el exordio", "la coda", "el interludio", "la peroración", "la adenda",
       "el colofón", "el epígrafe", "la foja", "el legajo", "la minuta",
       "el oficio"]
for o in ZFN:
    fam(f"z_fn_{o.split()[1]}", FN, "buscar", [
        f"Busca {o} ya.", f"Encuentra {o} por favor.", f"Localiza {o}."])
ZSV = ["el considerando", "el resolutivo", "el visto", "el resultando",
       "el exordio", "la coda", "el interludio", "la peroración", "la adenda",
       "el colofón", "el epígrafe", "la foja", "el legajo", "la minuta",
       "el oficio"]
for o in ZSV:
    fam(f"z_sv_{o.split()[1]}", SV, "guardar", [
        f"Guarda {o} ya.", f"Archiva {o} por favor.", f"Registra {o}."])
ZOP = ["el considerando", "el resolutivo", "el visto", "el resultando",
       "el exordio", "la coda", "el interludio", "la peroración", "la adenda",
       "el colofón", "el epígrafe", "la foja", "el legajo", "la minuta",
       "el oficio"]
for o in ZOP:
    fam(f"z_op_{o.split()[1]}", OP, "abrir", [
        f"Abre {o} ya.", f"Recupera {o} por favor.", f"Carga {o}."])
ZEX = ["el considerando", "el resolutivo", "el visto", "el resultando",
       "el exordio", "la coda", "el interludio", "la peroración", "la adenda",
       "el colofón", "el epígrafe", "la foja", "el legajo", "la minuta",
       "el oficio"]
for o in ZEX:
    fam(f"z_ex_{o.split()[1]}", EX, "exportar", [
        f"Exporta {o} en pdf.", f"Saca {o} en texto.", f"Rinde {o} en Word."])
ZRP = [("visto", "considerando"), ("resultando", "visto"), ("coda", "final"),
       ("exordio", "inicio"), ("peroración", "cierre"), ("adenda", "anexo"),
       ("colofón", "cierre"), ("epígrafe", "cita"), ("interludio", "pausa"),
       ("fe", "constancia")]
for a, b in ZRP:
    fam(f"z_rp_{a[:4]}", RP, "reemplazar", [
        f"Cambia {a} por {b}.", f"Pon {b} en vez de {a}."])
ZRW = ["más breve aún", "menos florido", "más llano", "más grave",
       "más leve", "más denso", "más fluido", "más cortante", "más dulce",
       "más áspero"]
for inst in ZRW:
    fam(f"z_rw_{inst.split()[-1]}", RW, "reformular", [
        f"Ponlo {inst}.", f"Hazlo {inst}."])
ZDL = ["el considerando", "el resolutivo", "el visto", "el resultando",
       "el exordio", "la coda", "el interludio", "la peroración", "la adenda",
       "el colofón"]
for o in ZDL:
    fam(f"z_dl_{o.split()[-1]}", DL, "borrar", [
        f"Borra {o} ya.", f"Quita {o}."])
ZUS = ["Lustra los zapatos.", "Asea la sala.", "Ordena el closet.", "Dobla la ropa.",
       "Guarda los juguetes.", "Recoge el reguero.", "Trapea el pasillo.",
       "Sacude los muebles.", "Limpia los espejos.", "Desempolva repisas.",
       "Riega macetas.", "Abona rosales.", "Trasplanta helechos.", "Poda bugambilias.",
       "Cosecha limones.", "Recoge mangos.", "Junta las hojas.", "Barre el frente.",
       "Trapea la cochera.", "Lava el patio."]
for u in ZUS:
    fam(f"z_us_{u.split()[0]}", US, "unsup-hogar2", [u, u.replace(".", " por favor.")])
ZUSC = ["Memoriza el discurso.", "Ensaya la presentación.", "Repasa la lección.",
        "Estudia el examen.", "Practica el informe.", "Prepara la junta.",
        "Organiza el archivo.", "Clasifica facturas.", "Ordena recibos.",
        "Digitaliza fotos.", "Etiqueta carpetas.", "Archiva correos.",
        "Responde mensajes.", "Devuelve llamadas.", "Confirma asistencia.",
        "Reprograma la cita.", "Cancela el pedido.", "Rastrea el paquete.",
        "Recoge el encargo.", "Deja las llaves."]
for u in ZUSC:
    fam(f"z_usc_{u.split()[0]}", US, "unsup-cercano2", [u, u.replace(".", " ya.")])
ZUSD = ["Sella el sobre.", "Timbra la carta.", "Franquea el paquete.",
        "Certifica el acta.", "Apostilla el título.", "Fedata la copia.",
        "Protocoliza el poder.", "Testimonia la firma.", "Coteja el original.",
        "Rubrica la foja.", "Folia el tanto.", "Legaja el oficio.",
        "Turna el asunto.", "Radica la demanda.", "Emplaza al tercero.",
        "Notifica el acuerdo.", "Desahoga la prueba.", "Formula alegatos.",
        "Dicta sentencia.", "Ejecuta el laudo."]
for u in ZUSD:
    fam(f"z_usd_{u.split()[0]}", US, "unsup-admin", [u, "Por favor, " + u[0].lower() + u[1:]])
ZNA = ["El mercado cierra temprano.", "La ruta cambia los lunes.", "El puente estará cerrado.",
       "La obra termina en junio.", "El parque abre tarde.", "El museo es gratis hoy.",
       "La biblioteca presta tablets.", "El curso es en línea.", "La clase será híbrida.",
       "El examen es oral.", "Traigo hueva hoy.", "Ando crudo.", "Hace un friazo.",
       "Ya casi es hora.", "Mañana descansamos.", "El tráfico fluye bien.",
       "La fila avanza rápido.", "El trámite quedó listo.", "La cita se movió.",
       "El doctor canceló."]
for u in ZNA:
    fam(f"z_na_{u.split()[0]}", NA, "conversacion", [u, "Bueno, " + u[0].lower() + u[1:]])
ZMU = ["Titula, numera y archiva.", "Borra, firma y sella.", "Busca, copia y archiva.",
       "Lee, rubrica y turna.", "Abre, folía y sella.", "Resume, firma y envía.",
       "Formatea, imprime y archiva.", "Selecciona, firma y turna.",
       "Encuentra, cita y archiva.", "Centra, sella y guarda.",
       "Recorta, engrapa y archiva.", "Justifica, folía y turna.",
       "Sangra, numera y archiva.", "Cursiva, firma y sella.",
       "Subraya, rubrica y turna.", "Anota, folía y archiva.",
       "Glosa, sella y turna.", "Digitaliza, nombra y turna.",
       "Turna, firma y archiva.", "Revisa, sella y envía."]
for u in ZMU:
    fam(f"z_mu_{u.split()[0]}", MU, "multi", [u, u.replace(".", " ahora mismo.")])

# ================= EXPANSIÓN 4 =================
WDL = ["el membrete", "el sello", "la firma", "el folio", "la rúbrica",
       "el acuse", "el comprobante", "el recibo", "la factura", "el vale",
       "el pagaré", "el contrato", "el convenio", "el anexo", "el apéndice"]
for o in WDL:
    fam(f"w_dl_{o.split()[-1]}", DL, "borrar", [
        f"Borra {o} del tanto.", f"Quita {o} ya.", f"Elimina {o}."])
WRP = [("firma", "rúbrica"), ("sello", "timbre"), ("folio", "número"), ("vale", "recibo"),
       ("factura", "nota"), ("recibo", "comprobante"), ("anexo", "apéndice"),
       ("minuta", "acta"), ("oficio", "memorando"), ("tanto", "ejemplar")]
for a, b in WRP:
    fam(f"w_rp_{a[:4]}", RP, "reemplazar", [
        f"Cambia {a} por {b}.", f"Sustituye {a} por {b}."])
WRW = ["más ejecutivo", "menos florido", "más cálido", "más frío",
       "más cercano", "más distante", "más alegre", "más sobrio",
       "más urgente", "más pausado", "más firme", "más suave",
       "más optimista", "más prudente", "más audaz"]
for inst in WRW:
    fam(f"w_rw_{inst.split()[-1]}", RW, "reformular", [
        f"Ponlo {inst}.", f"Hazlo {inst}.", f"Déjalo {inst}."])
WFM = ["el membrete", "el sello", "la firma", "el folio", "la rúbrica",
       "el acuse", "el comprobante", "el recibo", "la factura", "el vale",
       "el pagaré", "el contrato", "el convenio", "el anexo", "el apéndice"]
for o in WFM:
    fam(f"w_fm_{o.split()[-1]}", FM, "formato", [
        f"Marca {o} en negritas.", f"Subraya {o}."])
WUN = ["la rúbrica", "el sello", "el folio", "la firma", "el acuse",
       "el comprobante", "el recibo", "la factura", "el vale", "el pagaré",
       "el contrato", "el convenio", "el anexo", "el apéndice", "la minuta"]
for o in WUN:
    fam(f"w_un_{o.split()[1]}", UN, "undo", [
        f"Deshaz {o} puesto.", f"Anula {o} ya."])
WRD = ["la rúbrica", "el sello", "el folio", "la firma", "el acuse",
       "el comprobante", "el recibo", "la factura", "el vale", "el pagaré",
       "el contrato", "el convenio", "el anexo", "el apéndice", "la minuta"]
for o in WRD:
    fam(f"w_rd_{o.split()[1]}", RD, "redo", [
        f"Rehaz {o} puesto.", f"Repite {o} ya."])
WSL = ["el membrete", "el sello", "la firma", "el folio", "la rúbrica",
       "el acuse", "el comprobante", "el recibo", "la factura", "el vale",
       "el pagaré", "el contrato", "el convenio", "el anexo", "el apéndice"]
for o in WSL:
    fam(f"w_sl_{o.split()[1]}", SL, "seleccion", [
        f"Elige {o} ya.", f"Marca {o}."])
WFN = ["el membrete", "el sello", "la firma", "el folio", "la rúbrica",
       "el acuse", "el comprobante", "el recibo", "la factura", "el vale",
       "el pagaré", "el contrato", "el convenio", "el anexo", "el apéndice"]
for o in WFN:
    fam(f"w_fn_{o.split()[1]}", FN, "buscar", [
        f"Halla {o} ya.", f"Ubica {o}."])
WSV = ["el altri", "el otrosí", "el acuse", "el comprobante", "el recibo",
       "la factura", "el vale", "el pagaré", "el contrato", "el convenio",
       "el anexo", "el apéndice", "la minuta", "el oficio", "el tanto"]
for o in WSV:
    fam(f"w_sv_{o.split()[1]}", SV, "guardar", [
        f"Deposita {o}.", f"Custodia {o}."])
WOP = ["el acuse", "el comprobante", "el recibo", "la factura", "el vale",
       "el pagaré", "el contrato", "el convenio", "el anexo", "el apéndice",
       "la minuta", "el oficio", "el tanto", "el legajo", "la foja"]
for o in WOP:
    fam(f"w_op_{o.split()[1]}", OP, "abrir", [
        f"Exhibe {o}.", f"Presenta {o}."])
WEX = ["el acuse", "el comprobante", "el recibo", "la factura", "el vale",
       "el pagaré", "el contrato", "el convenio", "el anexo", "el apéndice",
       "la minuta", "el oficio", "el tanto", "el legajo", "la foja"]
for o in WEX:
    fam(f"w_ex_{o.split()[1]}", EX, "exportar", [
        f"Emite {o} en pdf.", f"Produce {o} final."])
WUS = ["Lava el garaje.", "Pinta el portón.", "Repara la bicicleta.", "Infla las llantas.",
       "Cambia el aceite.", "Afinar el motor.", "Lava el motor.", "Encerar el coche.",
       "Aspira interiores.", "Limpia tapicería.", "Revisa frenos.", "Checa niveles.",
       "Rota llantas.", "Alinea dirección.", "Balancea ruedas.", "Cambia bujías.",
       "Limpia inyectores.", "Revisa suspensión.", "Checa batería.", "Pasa corriente."]
for u in WUS:
    fam(f"w_us_{u.split()[0]}", US, "unsup-auto", [u, u.replace(".", " por favor.")])
WUSC = ["Hornea el pastel.", "Bate la mezcla.", "Decora con betún.", "Enfría el flan.",
        "Derrite chocolate.", "Monta la nata.", "Espolvorea canela.", "Ralla limón.",
        "Exprime naranjas.", "Licua el mango.", "Cuela el jugo.", "Sirve frío.",
        "Calienta la cena.", "Recalienta el guiso.", "Tapa la cazuela.", "Destapa la olla.",
        "Prueba la sal.", "Rectifica sazón.", "Apaga la lumbre.", "Deja reposar."]
for u in WUSC:
    fam(f"w_usc_{u.split()[0]}", US, "unsup-cocina", [u, u.replace(".", " ya.")])
WNA = ["El partido empieza tarde.", "La final será pareja.", "El clásico llena estadios.",
       "El maratón cierra calles.", "La carrera es el domingo.", "El torneo da puntos.",
       "El equipo viaja mañana.", "El técnico renunció.", "El estadio estrena pasto.",
       "La afición exige triunfos.", "El refuerzo llega lesionado.", "El juvenil debuta hoy.",
       "La porra anima siempre.", "El himno sonó fuerte.", "El penal se repite.",
       "El gol fue anulado.", "La tarjeta era roja.", "El fuera de lugar dudoso.",
       "El alargue define todo.", "Los penales deciden."]
for u in WNA:
    fam(f"w_na_{u.split()[0]}", NA, "conversacion", [u, "Dicen que " + u[0].lower() + u[1:]])
WMU = ["Titula, rubrica y turna.", "Borra, folía y archiva.", "Busca, rubrica y sella.",
       "Lee, folía y turna.", "Abre, rubrica y archiva.", "Resume, sella y turna.",
       "Formatea, folía y archiva.", "Selecciona, rubrica y turna.",
       "Encuentra, sella y guarda.", "Centra, folía y archiva.",
       "Recorta, sella y turna.", "Justifica, rubrica y envía.",
       "Sangra, folía y archiva.", "Cursiva, sella y turna.",
       "Subraya, rubrica y archiva.", "Anota, sella y turna.",
       "Glosa, folía y archiva.", "Digitaliza, sella y turna.",
       "Turna, rubrica y archiva.", "Revisa, folía y envía."]
for u in WMU:
    fam(f"w_mu_{u.split()[0]}", MU, "multi", [u, u.replace(".", " ahora.")])

# ================= EXPANSIÓN 5 (cierre) =================
VRP = [("vale", "pagaré"), ("nota", "factura"), ("tanto", "copia"), ("fajo", "legajo"),
       ("rúbrica", "firma"), ("timbre", "sello"), ("número", "folio"), ("ejemplar", "tanto")]
for a, b in VRP:
    fam(f"v_rp_{a[:4]}", RP, "reemplazar", [
        f"Pon {b} donde dice {a}.", f"Troca {a} por {b} ya."])
VRW = ["más claro todavía", "menos enredado aún", "más amable", "más formal todavía",
       "más corto ya", "más directo ya", "más simple aún", "más elegante"]
for inst in VRW:
    fam(f"v_rw_{inst.split()[-1]}", RW, "reformular", [
        f"Déjalo {inst}.", f"Ponlo {inst}."])
VSV = ["el pagaré", "el vale", "la factura", "el recibo", "el comprobante",
       "el acuse", "el convenio", "el contrato"]
for o in VSV:
    fam(f"v_sv_{o.split()[1]}", SV, "guardar", [
        f"Guarda {o} en orden.", f"Archiva {o} ya."])
VOP = ["el pagaré", "el vale", "la factura", "el recibo", "el comprobante",
       "el acuse", "el convenio", "el contrato"]
for o in VOP:
    fam(f"v_op_{o.split()[1]}", OP, "abrir", [
        f"Muestra {o} ya.", f"Presenta {o}."])
VEX = ["el pagaré", "el vale", "la factura", "el recibo", "el comprobante",
       "el acuse", "el convenio", "el contrato"]
for o in VEX:
    fam(f"v_ex_{o.split()[1]}", EX, "exportar", [
        f"Saca {o} en pdf ya.", f"Rinde {o} final."])
VUS = ["Planta el árbol.", "Riega el huerto.", "Cosecha el maíz.", "Guarda la semilla.",
       "Limpia el granero.", "Repara la cerca.", "Cuenta el ganado.", "Marca las reses.",
       "Vacuna los pollos.", "Recoge los huevos.", "Ordeña temprano.", "Pastorear al atardecer.",
       "Carga el costal.", "Muele el nixtamal.", "Amasa la harina.", "Hornea el pan.",
       "Prende el horno.", "Apaga la brasa.", "Abanica el fuego.", "Sopla las brasas."]
for u in VUS:
    fam(f"v_us_{u.split()[0]}", US, "unsup-rural", [u, u.replace(".", " por favor.")])
VUSC = ["Bordar servilletas.", "Tejer bufandas.", "Coser dobladillos.", "Zurcir calcetines.",
        "Remendar pantalones.", "Plisado de faldas.", "Bastilla cortinas.", "Forrar botones.",
        "Pegar cierres.", "Entretelar cuellos.", "Hilvanar piezas.", "Cortar patrones.",
        "Marcar la tela.", "Probar el vestido.", "Ajustar la cintura.", "Alargar el ruedo.",
        "Recoger mangas.", "Poner hombreras.", "Quitar pelusa.", "Planchar cuellos."]
for u in VUSC:
    fam(f"v_usc_{u.split()[0]}", US, "unsup-costura", [u if u.endswith(".") else u + ".", (u if u.endswith(".") else u + ".").replace(".", " ya.")])
VNA = ["La rosca partió plaza.", "El encierro abarrota calles.", "La verbena sigue hasta tarde.",
       "El baile cierra feria.", "La kermés juntó fondos.", "El jaripeo llena lienzos.",
       "La charreada puntúa suertes.", "El coleadero levanta polvo.", "La escaramuza galopa.",
       "El mariachi calla al final.", "La banda retumba lejos.", "El norteño cuenta penas.",
       "La cumbia mueve caderas.", "La salsa calienta pistas.", "El danzón ordena parejas.",
       "El mambo acelera pies.", "El chachachá marca compás.", "La guaracha alegra barrios.",
       "El son istmeño enamora.", "La chilena prende fandangos."]
for u in VNA:
    fam(f"v_na_{u.split()[0]}", NA, "conversacion", [u, "Mira, " + u[0].lower() + u[1:]])
VMU = ["Rubrica, folía y turna.", "Sella, firma y archiva.", "Folía, rubrica y envía.",
       "Turna, sella y guarda.", "Recaba, folía y turna.", "Revisa, sella y turna.",
       "Anota, rubrica y archiva.", "Glosa, folía y envía.", "Digitaliza, sella y archiva.",
       "Escanea, folía y turna.", "Engrapa, sella y envía.", "Perfora, folía y archiva.",
       "Recorta, sella y turna.", "Dobla, ensobra y envía.", "Franquea, sella y despacha.",
       "Certifica, sella y archiva.", "Apostilla, folía y turna.", "Fedata, sella y guarda.",
       "Protocoliza, sella y archiva.", "Testimonia, folía y turna."]
for u in VMU:
    fam(f"v_mu_{u.split()[0]}", MU, "multi", [u, u.replace(".", " por favor.")])

# dedupe global (conserva primera aparición) y reescribe
seen, uniq = set(), []
for t, l, c, fid in rows:
    if t in seen:
        continue
    seen.add(t)
    uniq.append((t, l, c, fid))
rows = uniq

with open(HERE / "pool.csv", "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f)
    w.writerow(["text", "label", "category", "family_id"])
    for t, l, c, fid in rows:
        w.writerow([t, l, c, fid])

from collections import Counter
print(f"pool: {len(rows)}", dict(Counter(r[1] for r in rows)), f"fams={len({r[3] for r in rows})}", file=sys.stderr)
