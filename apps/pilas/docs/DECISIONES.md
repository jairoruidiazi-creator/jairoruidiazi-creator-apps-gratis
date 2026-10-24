# Pilas: decisiones de diseño y producto

Registro de las decisiones tomadas durante el desarrollo, con su razón. Se actualiza con cada entrega. La última revisión (18-10-2026) recoge las correcciones de las dos rondas de la auditoría independiente; las decisiones que esa corrección dejó abiertas o que se tomaron sin instrucción expresa están marcadas con **(decisión propia)**.

## Producto

- **Nombre de trabajo: Pilas.** Corto, en español, con sentido en Colombia ("ponte pilas" = estar atento, con energía). Se puede cambiar antes de publicar; el identificador de paquete (`co.appsgratis.pilas`) sí debe quedar fijo antes de la primera subida a las tiendas.
- **Una app para dos públicos (3 a 6 y 7 a 11).** De 3 a 6 años todo se dice en voz alta y las opciones son dibujos; de 7 a 11 hay texto y opciones escritas. Una familia con hijos de distintas edades usa una sola app y un docente una sola instalación.
- **Cuatro tramos de edad (3-4, 5-6, 7-8, 9-11)**, los mismos de la categoría Niños de la App Store. El tramo sale de la fecha de nacimiento y un adulto lo puede fijar en el perfil.
- **26 juegos, y cada niño ve los de su edad**: 17 de 3 a 4 años, 25 de 5 a 6, 23 de 7 a 8 y 21 de 9 a 11. La ficha dice "26 juegos" y "cada niño ve los de su edad"; no promete que todos estén en todos los tramos.
- **Nombres que dicen lo que el juego hace** (auditoría G18): "Rompecabezas" (encajar figuras por forma y tamaño de 3 a 6 años; armar imágenes intercambiando fichas de 7 a 11), "Sudoku" (con dibujos o números), "Figuras y medidas" (es un juego de preguntas, no un constructor) y "El cuerpo humano" (preguntas, no armar un cuerpo). No hay tangram: las piezas no giran, y prometerlo sería falso. Una prueba (`test/skills_coverage_test.dart`) impide volver a usar "tangram", "constructor" o "arma el cuerpo".
- **Currículo genérico latinoamericano**, por decisión del proyecto (15-10-2026): habilidades por edad con referencia a los DBA de Colombia y a Common Core K-5, sin atarse a un país. El mapa completo está en el anexo B.
- **Sin cuenta, sin internet, sin anuncios y sin recopilación de datos.** Es la única forma de cumplir a la vez la categoría Niños de Apple, la política de Familias de Google Play, la COPPA y el artículo 7 de la Ley 1581 sin consentimiento parental verificable.
- **Solo en español.** La app, la voz, la ficha y la política para niños están en español; la política tiene una traducción al inglés para las tiendas. En iOS el paquete declara solo español (`CFBundleLocalizations = [es]` y región de desarrollo `es`) y solo lleva la carpeta `es.lproj`: `en.lproj` ya no existe y la CI de iOS lo comprueba en el paquete compilado.

## Puerta para adultos

- **Qué protege:** el panel de adultos (ajustes, informes, modo docente, guía, política y créditos), crear un perfil (también el primero, auditoría M1), editar y borrar perfiles, compartir o exportar cualquier cosa, importar datos, dar más tiempo y cambiar de jugador mientras otro está en su descanso.
- **Qué pide** (decisión definitiva del proyecto tras la tercera ronda de la auditoría, G1): una multiplicación de dos números de dos cifras, los dos de 13 a 39 y ninguno múltiplo de 5, escrita en palabras ("¿Cuánto es veintitrés por diecisiete?") y con la respuesta tecleada. El resultado nunca termina en 0 y no hay atajos (la versión anterior usaba 15 o 25 como factor y se resolvía con trucos que la app misma enseña). La puerta dice que es una tarea para adultos y que se puede usar la calculadora del teléfono: es una "adult-level task", como la llama Apple. El enunciado no se lee en voz alta; la voz solo dice "Esto es para un adulto".
- **Qué entrena la app y qué no**: la app sí multiplica números de dos cifras. La tienda multiplica precios redondos por 2 a 12 (1.500 × 12 es 15 × 12 en centenas) y la carrera multiplica por una cifra o por 12. La puerta descarta todo par con un factor de 12 o menos o múltiplo de 5 (`GateChallenge.entrenado`), así que ninguna multiplicación de la puerta sale en un juego; `test/ui_flows_test.dart` lo comprueba con un barrido de miles de rondas de la tienda y la carrera, y mide que los 22 factores salgan parejo.
- **Errores y otra operación**: "Otra operación" cuenta como intento fallido, para que no se puedan pedir operaciones hasta que salga una fácil. La operación que se mostró queda guardada hasta que se responde: cerrar la puerta (con "Cancelar" o tocando fuera) y volver a abrirla muestra la misma, así que tampoco así se cambia (auditoría M1 de la cuarta ronda). Los dos primeros intentos fallidos seguidos no tienen espera; desde el tercero hay que esperar 60 s, luego 120 s, 240 s… hasta 15 minutos. El contador vuelve a cero con un acierto o tras 15 minutos sin errores. Dos toques seguidos en "Entrar" cuentan una sola vez (auditoría M3 de la tercera ronda).
- **Con el teclado abierto** (auditoría M4 de la cuarta ronda): la puerta es un diálogo que se desplaza entero y "Entrar" va junto al campo, no fijo abajo. En iPhone el teclado numérico no tiene tecla de enviar; así "Entrar" se alcanza también acostado y con la letra al doble. En Android, "Listo" del teclado también envía. "Cancelar" y "Entrar" van a la derecha, como en los demás diálogos.
- **Sin salida a la web desde los campos de texto** (auditoría G15): la respuesta de la puerta y el nombre del perfil no tienen menú contextual ni selección de texto (en iOS ese menú ofrece "Buscar en la web"), y el manifiesto de Android no declara `PROCESS_TEXT`.

## Evaluación, niveles y habilidades

- **Solo cuenta el primer intento** (auditoría G4). Si el niño falla, arriba aparece una pista y puede intentarlo otra vez: esa segunda oportunidad sirve para aprender, pero la ronda queda como no acertada. Con solo dos opciones no hay segunda oportunidad (se acertaría siempre): se muestra la respuesta explicada.
- **Las pistas nunca descartan opciones.** Los bancos de preguntas (cuerpo, laboratorio, decisiones) tienen una pista general por tramo que orienta sin decir cuál no es.
- **Reglas de dominio** (`engine/mastery.dart`), contadas sobre la ventana de las últimas rondas:
  - juegos de elegir: 5 aciertos al primer intento en 6 rondas suben de nivel; con 3 o más se mantiene; dos ventanas seguidas con menos de 3 bajan un nivel sin anunciarlo;
  - juegos de ordenar y el trazo: 4 de 5 suben, con 2 o más se mantiene;
  - tableros (memoria, laberintos, sudoku, rompecabezas, pixel art, colorear por números): 2 tableros resueltos con eficiencia de 3 suben, con 1 se mantiene.
- **Un jugador que toca al azar no avanza**: la probabilidad de subir de nivel tocando al azar es menor del 5 % en todos los juegos de elegir, de ordenar y de tablero (`test/random_player_test.dart` lo calcula con la cola binomial de cada regla y el número de opciones de las rondas que de verdad genera cada nivel; en los tableros simula miles de partidas al azar de memoria, laberintos, rompecabezas y sudoku, y acota colorear por números y pixel art). Por eso (auditoría M1 de la segunda ronda) la memoria de 3 a 4 años empieza con cuatro parejas y no con dos (con dos, voltear al azar era igual de eficaz que recordar), el primer laberinto de 3 a 4 años es de 4 × 4 y no de 3 × 3, y al encajar figuras siempre sobra alguna pieza.
- **Eficiencia en los tableros.** El tablero siempre se termina (un tablero a medio hacer frustra más que una ronda perdida) y cuenta como acierto si se resolvió con eficiencia:
  - memoria: con cuatro parejas, como mucho tres fallos; desde cinco parejas, como mucho una más que el número de parejas. Quien recuerda cada carta vista lo logra siempre; al azar, en menos del 12 % de los tableros. De 3 a 4 años: 4, 4, 4 y 5 parejas, con vista previa de 4 s y 3 s en los dos primeros niveles;
  - laberinto: pasos ≤ 1,6 × el camino mínimo + 2;
  - sudoku: como mucho 1 choque en 4×4, 2 en 6×6 y 3 en 9×9 **(decisión propia)**;
  - encajar figuras: como mucho un error; armar una imagen: intercambios ≤ los mínimos + el lado del tablero;
  - pixel art: la primera comparación ya bien, con 1 casilla de tolerancia en 10×10 y 2 en 12×12 **(decisión propia)**;
  - colorear por números: como mucho dos colores equivocados **(decisión propia)**.
- **Juegos libres sin evaluación**: Colorear, Dibujo y sellos y el modo libre del pixel art no tienen niveles, no dan habilidades y no suman aciertos. "Listo" o "Terminé" con la lámina o el lienzo en blanco no hace nada, y nunca se guarda un dibujo vacío.
- **Habilidades** (auditoría G5): 76 en el mapa (15, 23, 20 y 18 por tramo). Cada habilidad la evalúa exactamente un juego de su tramo y de su área, y se logra al dominar el último nivel de ese juego. Las que ningún juego medía salieron del mapa o quedaron dentro de la habilidad del juego que de verdad las practica (vocabulario, números hasta 100, sinónimos, decimales y gráficas, resumen y escritura; "más y menos" pasó a "Contar y comparar", las tablas a "Cálculo hasta 100 y tablas" y el trabajo en equipo a "Equipo, pantallas y seguridad en línea"), y se corrigieron las asignaciones que no correspondían a lo jugado: el reloj, el rompecabezas y las parejas de 9 a 11 evalúan ahora lo que practican, colorear libre ya no da habilidades y colorear por números solo evalúa la suya de 5 a 6 años. Lo comprueba `test/skills_coverage_test.dart`.
- **El informe cuenta por tramo**: "logradas de posibles" usa siempre las habilidades del tramo actual del niño. "Aciertos al primer intento" excluye los juegos libres. "Últimos 7 días" son los siete días anteriores, no la semana del calendario (auditoría M14).
- **Recompensas por habilidad, no por tiempo**: una pegatina por nivel completado. Las pegatinas no se pierden y no hay rachas.
- **Marca de la carrera**: una carrera sin aciertos se guarda como marca, pero no se celebra como «¡Nueva marca!» (auditoría M2 de la tercera ronda).
- **Sin reloj antes de los 8 años.** La carrera de cálculo no tiene cronómetro: compite contra la marca propia de aciertos de cada niño en cada tramo, que se guarda y se muestra al final.

## Contenido de los juegos

- **Juegos generados por reglas** (no listas fijas de preguntas) para que las rondas no se repitan y el catálogo crezca con datos (vocabulario, situaciones) en lugar de código.
- **Varias palabras modelo por sonido y por letra** (auditorías M8 de la tercera ronda y M2 de la cuarta): cada sonido tiene al menos dos palabras modelo que empiezan con su letra (con la u, uvas, uñas, unicornio y uniforme; con la ch, chocolate, chaqueta y chancla; con la i, isla, imán e iglesia), y la palabra modelo cambia de una ronda a otra. Así ningún sonido ni ninguna letra tiene una sola respuesta posible; `test/fonemas_cuentos_test.dart` lo exige en cada sonido, cada letra, cada tramo y cada nivel.
- **Sonidos como suenan en Colombia** (auditoría G7): las rondas de sonido inicial comparan el fonema, no la letra. Con seseo, *c* (ante e, i), *s* y *z* suenan igual; con yeísmo, *ll* y *y*; *b* y *v* suenan igual; la *h* no suena (hormiga empieza con el sonido o); *c* (ante a, o, u), *qu* y *k* son el mismo sonido, y *g* ante e, i suena como *j*. Las rondas de letra solo usan letras cuyo sonido inicial no cambia. La voz nombra el sonido ("mmm"), no la letra ("eme").
- **Etiquetas semánticas separadas** (auditoría G8): el vocabulario (223 palabras con pictograma) separa categoría, grupo de animal, hábitat, movimiento, medio de transporte, uso de la ropa y familia de instrumento. Un distractor nunca cumple también el criterio de la pregunta: si un animal vive en dos lugares o el movimiento es dudoso, queda fuera de esa pregunta. Hay sabana (el león ya no vive en la selva). Twemoji no tiene un pictograma fiel de la sabana, así que ese lugar solo sale en las preguntas escritas de 9 a 11 años, con todas las opciones en texto; las preguntas con dibujos de 3 a 6 años usan los demás lugares (auditoría M9 de la tercera ronda). Las tablas completas, para la revisión de un docente, están en el anexo A; `test/semantica_test.dart` genera miles de rondas de cada tipo de pregunta y comprueba cada distractor contra esas etiquetas.
- **El intruso no admite dos respuestas**: se descarta cualquier grupo en el que otra opción también quede sola por otra propiedad sencilla (categoría, grupo de animal, hábitat, medio; en los números, par e impar, tablas y "mayores que"). En "¿Cuál es diferente?" de 3 a 4 años las figuras del grupo son copias iguales a propósito.
- **Emociones con género y sin falsos errores** (auditoría G9): el nombre de la emoción concuerda con quien la siente ("Sofía está avergonzada"), y un distractor nunca es una emoción que también valdría en la situación.
- **Español revisado por pruebas** (auditoría G10): contracciones (*al*, *del*), género y número (con los sustantivos que van en plural, como *tijeras*, *uvas* o *gafas de sol*: "Las tijeras cuestan…"), tildes de los números, "es la una / son las dos", *e* ante *i* y *u* ante *o*, mayúsculas y signos. `test/grammar_test.dart` revisa miles de rondas de todos los juegos, los cuentos y los textos fijos. En la segunda ronda de la auditoría (G2) se sumaron el demostrativo según el género ("Esta es la estrella", no "Este es la estrella") y el artículo ante *a* tónica ("el águila", "un ave", "al águila", pero "las águilas" y "la abeja"), que `core/es.dart` aplica solo con `Es.aTonica`; la prueba revisa además el artículo y el demostrativo de cada sustantivo conocido (vocabulario, figuras, objetos y grupos de animales) y barre todos los textos escritos en el código, no solo los que producen los generadores.
- **Datos verificados** (auditoría G11): la señal de pare es un octágono; la luna llena usa el pictograma de la luna llena; la *i* es de isla, la *ñ* de piña y la *x* de taxi; la *a* y la *o* minúsculas se trazan en sentido contrario a las manecillas, como en la escuela; los pictogramas de las rutinas muestran lo que dicen.
- **Contar con dibujos que se pueden contar** (auditoría G3 de la segunda ronda): cuando una ronda dibuja varias copias de un pictograma para que el niño las cuente, cada pictograma muestra exactamente un objeto entero. La lista de los permitidos (`Vocab.unObjeto`) se revisó rasterizando cada SVG; quedan fuera las cerezas (el dibujo trae dos; la palabra pasó a plural, "las cerezas", como "las uvas"), las uvas, la sandía y la pizza (tajadas), el coco, el kiwi y el aguacate (partidos), el pollo (una presa), el queso, la lechuga, el melón, el rompecabezas y los libros. La cocina de 3 a 6 cuenta huevos (antes, tazas de té que no eran tazas de harina). `test/conteo_test.dart` dibuja miles de rondas de contar y comprueba que se ven exactamente las que dice la respuesta, con pictogramas de la lista.
- **Pictogramas fieles** (auditoría M9 de la tercera ronda): la receta de la cocina usa bananos, huevos, cucharadas de azúcar y vasos de leche, que tienen dibujo propio (no hay uno de una taza de harina); la semilla salió del vocabulario (Twemoji solo tiene una castaña) y la rutina de sembrar y la pregunta de ciencias usan fríjoles, que sí son semillas y tienen dibujo.
- **Plantillas revisadas** (auditoría M1 de la tercera ronda): las reglas de las series dicen "La regla es: …" y las multiplicaciones van con espacios ("1 × 1"), para que se lean bien y la voz diga "por". `test/grammar_test.dart` detecta el × sin espacios y "la regla" seguida de algo que no encaja.
- **Cuentos**: 12 cuentos originales (tres por tramo) ambientados en Colombia y América Latina, con tres preguntas que van de lo literal a la inferencia. Las opciones se barajan en cada pregunta (auditoría G6). El juego tiene un solo nivel: el tramo ya elige los cuentos, y con tres por tramo inventar niveles sería falso. Para los que no leen, la voz lee también las opciones. Si el texto dice cuántos hay de algo, la escena muestra esos mismos (la gallina Pepa tiene tres pollitos en el texto y en el dibujo, y en la página en que los tapa con las alas ya no aparece un paraguas, que era una de las respuestas equivocadas); las opciones de "¿Cuántos pollitos tenía Pepa?" muestran el número.
- **Bancos de preguntas con nivel** para ciencias y socioemocional: cada pregunta declara tramo y nivel 1 a 4. Los tramos que no leen siempre tienen pictogramas en las opciones.
- **Historias con decisiones**: hay una opción claramente buena y la explicación dice por qué cuida a uno y a los demás; las otras no son buenas ideas (no se promete "una buena, una regular y una mala", auditoría M20). En seguridad (7-8) la regla fija es "no, me alejo y le cuento a un adulto de confianza".
- **Órdenes válidos** (auditoría M7): las rutinas y las oraciones aceptan todos los órdenes que también son correctos (vestirse antes o después de desayunar; "Cuando llueve, cantan las ranas toda la noche").
- **La tienda con precios creíbles**: cada producto tiene un rango de precio razonable en pesos colombianos (una fresa no cuesta catorce mil pesos ni un libro doscientos), y cada ronda elige un producto que de verdad podría costar el precio sorteado **(decisión propia)**. Los billetes y monedas son los colombianos.
- **Arma la palabra**: en 7-8 los distractores son letras que se confunden (b y v, ll y y, h, c, s y z, g y j); en 9-11 los niveles 1 a 3 usan palabras con tilde y el 4 palabras largas con o sin tilde, y la bandeja siempre trae una vocal con tilde de más o la misma vocal sin tilde (auditoría M20).
- **El reloj**: las opciones de "¿qué hora es?" van en formato digital porque los de 5 a 6 reconocen numerales aunque no lean; las de elegir el reloj muestran relojes. Los números de los minutos van dentro de la esfera y más grandes (auditoría M22).
- **Trazo de letras** (auditoría M8): 56 plantillas propias (pre-escritura, mayúsculas, minúsculas y dígitos) con punto de inicio, número de orden y flecha. Se evalúa cuánto de la guía quedó cubierta (≥ 72 %), cuánto del trazo cayó cerca (≥ 55 %), el orden de las líneas y su dirección (por dónde empieza cada línea; en las cerradas, hacia qué lado gira). La tolerancia es mayor de 3 a 4 años. No se usan los glifos de la fuente porque no traen orden de trazo.
- **Rompecabezas sin fichas iguales** (auditoría G19): cada imagen se usa solo en los tamaños en que todas sus fichas se ven distintas; una prueba rasteriza cada imagen y compara las fichas.
- **Colorear por números** (auditorías B2 y G20): el blanco es un color más y borrar se hace con la goma, en los dos modos. Las zonas llevan números de 5 a 6 años y letras desde los 7, igual que la paleta. Las 12 láminas se terminan en pantalla en las pruebas.
- **Sudoku sin callejones mudos** (auditoría M17): si una casilla vacía ya no admite nada, parpadea y se marcan las casillas que no van, para borrarlas y pensar otra vez. Los choques se avisan al instante y se cuentan como error, pero nada se corrige solo.
- **Pixel art** (auditorías G18 y M17): cada nivel agranda la cuadrícula (6, 8, 10 y 12 de 7 a 8 años; 8, 10 y 12 de 9 a 11). Comparar nunca borra lo pintado: marca las casillas por arreglar. En una pantalla donde las casillas quedarían de menos de 24 dp (teléfono pequeño con letra grande) se usa la cuadrícula más grande que cabe **(decisión propia)**.
- **Laberintos perfectos a partir de 7 años; con paredes abiertas de más entre 3 y 6** para que haya varios caminos y menos callejones. Desde 7-8 nivel 3 hay que recoger una llave antes de la meta. El más grande (9-11, nivel 4) mide 16 × 12 para que las casillas no bajen de 24 dp en un teléfono **(decisión propia)**.

## Tiempo de juego y descanso

- **Tiempo por sesión, por niño** (auditoría G1). Solo cuenta el tiempo con Pilas abierta en pantalla; la sesión termina tras 10 minutos sin jugar y la siguiente empieza de cero. Hay una sola fuente de verdad para el tiempo (`AppState`), probada con un reloj falso.
- **Descanso de 10 minutos** al cumplirse el tiempo. Se guarda hasta cuándo dura, así que cerrar y abrir la app no lo salta; si el reloj del teléfono se atrasa, el descanso no se alarga. No se cierra con el botón atrás de Android ni con el gesto de iOS (auditoría G2). Para cambiar a otro jugador mientras alguien descansa hace falta la puerta para adultos, y el jugador que descansa ve su descanso al entrar.
- **Más tiempo**: un adulto da 10 minutos más tras la puerta. Por defecto el límite es de 20 minutos; se puede quitar.
- **La voz se calla al salir de un juego**, con la X o con atrás (auditoría M6).

## Accesibilidad y pantalla

- **Alto contraste en toda la app** (auditoría G17): fondo blanco, texto negro y bordes marcados también dentro de los juegos; las figuras de colores llevan además una marca propia de cada color. `test/palette_test.dart` exige contraste de 4,5:1 en texto y 3:1 en gráficos, en las dos paletas.
- **Modo zurdo** (en el perfil): los botones y las herramientas de los juegos pasan al lado izquierdo, y en los trazos de pre-escritura las líneas acostadas empiezan por la derecha.
- **Texto grande**: multiplica la letra del sistema por 1,25, con un tope del doble (×2). El tope era 1,5 y recortaba la letra de quien la tiene al 200 % en el teléfono; ×2 es lo que pide la WCAG (1.4.4) y el máximo de Android 14 (auditoría M11 de la segunda ronda). `test/texto_grande_test.dart` abre con la letra al doble, en 360 × 740 y 740 × 360, las pantallas fuera de los juegos, la puerta para adultos, el descanso, el informe del niño y el resumen de la carrera. También comprueba que el número de pegatinas de las tarjetas del inicio no se corta (la fila crece con la letra) y que la puerta, con el teclado abierto, deja tocar «Entrar» (auditoría M3 y M4 de la cuarta ronda).
- **Todo cabe** (auditoría G13): `test/games_smoke_test.dart` abre cada juego en cada tramo y nivel en 360 × 740, 740 × 360 y 1024 × 768 con letra ×1, ×1,3, ×1,5 y ×2, y comprueba que no haya desbordes, que todas las opciones se vean y reciban toques, que las casillas de los tableros midan 24 dp o más (hasta ×1,3) y que la pista no tape nada. La pista va en la barra de la instrucción, arriba (auditoría G12). En el inicio de los niños los pictogramas miden 56 dp o más.
- **Toques** (auditoría M11): botones y herramientas de 48 dp o más. Las casillas de los tableros se aceptan desde 24 dp **(decisión propia)**: se pintan o recorren arrastrando el dedo, y un 12 × 12 con casillas de 48 dp no cabe en un teléfono.
- **Lector de pantalla** (auditoría M12): avatares con nombre, casillas del sudoku que dicen su dibujo, acciones para mover el personaje del laberinto sin arrastrar, y opciones que se nombran con su color y su forma.
- **Sin voz en español** (auditoría M19): el inicio de los niños de 3 a 6 años lo avisa en cuanto la voz del sistema termina de cargar.
- **Descanso** (auditoría M4 y M5 de la segunda ronda): mientras el niño descansa, la voz no lee nada del juego que quedó debajo; al volver dice la última pregunta que se calló. El lector de pantalla anuncia los minutos que faltan, no cada segundo.
- **Letra Andika** (auditoría M10 de la segunda ronda): el ajuste se llama "Letra para los que empiezan a leer". Andika es una tipografía de SIL pensada para lectores principiantes; no se anuncia como ayuda para la dislexia, porque los estudios no encuentran que las tipografías "para dislexia" mejoren la lectura.

## Privacidad y datos

- **La voz no recibe datos de los niños.** Lo que se lee son textos de los juegos; el saludo es "¡Hola!" y no el nombre del niño, porque algunos motores de voz del sistema pueden funcionar en línea **(decisión propia)**.
- **Compartir** (auditoría B3): con `share_plus` 13.3.1 y siempre con el rectángulo del botón tocado como origen (lo exigen el iPad y el iPhone compilado con Xcode 26). Si la hoja no se abre, la app lo avisa. Los archivos que se preparan para compartir se guardan en una carpeta propia que se vacía al abrir la app. El PDF del informe se comparte por la misma hoja (se quitó el paquete `printing`).
- **Fotos en iOS** (auditoría M21): `NSPhotoLibraryAddUsageDescription` explica que el permiso solo aparece si un adulto, al compartir un dibujo, elige guardarlo en Fotos. La app no lee la fototeca.
- **Importar datos** (auditoría M16): con el selector de archivos del sistema (`file_selector`, sin permisos) o pegando el texto. Un archivo que no sirve muestra un aviso. Lo importado se junta con lo que ya hay sin borrar ni inflar nada: de cada juego queda el registro más avanzado (no se suman, porque el archivo suele traer también lo que ya había aquí), y las sesiones, pegatinas y habilidades se juntan sin repetir. Importar dos veces el mismo archivo no cambia nada **(decisión propia)**. Los ids de perfiles y grupos del archivo deben tener la forma que crea la app (minúsculas y cifras, `^[0-9a-z]{1,32}$`); si alguno no la tiene ("", "..", "ab.json"), no se importa nada, porque los ids forman rutas de archivos y borrar ese perfil podría borrar datos de otros (N4).
- **Lo que dice la app al importar** (auditoría M3 de la segunda ronda): el modo docente ya no dice que el avance "se suma"; dice lo que hace: las sesiones, pegatinas y habilidades de las dos tabletas quedan todas, y de cada juego queda el nivel más avanzado.
- **CSV para Excel** (auditoría M15): con BOM, separado por punto y coma; los nombres de archivo se limpian de barras y tildes.
- **Borrar un perfil** borra su nombre, avatar y año y mes de nacimiento, su avance, sus dibujos y su lugar en los grupos (auditoría M3). La copia de respaldo de la lista de perfiles, de grupos y de avisos también se reescribe, así que el perfil borrado no queda en ningún `.bak` ni puede volver al recuperar un archivo dañado (auditoría M7 de la tercera ronda). También se borran las copias dañadas apartadas de su avance, las de la lista de perfiles o de grupos que lo incluyan (con un aviso) y los avisos del panel que son de ese perfil (auditoría M5 de la cuarta ronda). Se borra todo lo que empieza por el archivo de su avance (también las copias del respaldo apartadas, `.json.bak.corrupto-*`), y los avisos se reescriben siempre sin dejar respaldo. Cada aviso guarda el id del perfil del que habla; los avisos viejos sin id se reconocen por la frase exacta que genera la app, así que borrar a «Ana» no quita los avisos de «Ana María» (comprobación final, N1 y N2). Las copias dañadas de los avisos (`avisos.json.corrupto-*` y `avisos.json.bak.corrupto-*`) se borran siempre que se borra un perfil: no se pueden leer, ya se avisó de ellas y pueden nombrarlo (N3). La política dice exactamente esto.
- **Una sesión, una sola vez** (auditoría M6 de la tercera ronda): si se importa un archivo exportado durante la sesión que sigue abierta, no se duplica; de las dos copias de una misma sesión queda la más larga.
- **CSV del modo docente** (auditoría M11 de la tercera ronda): las columnas dicen "Rondas jugadas" y "Rondas acertadas al primer intento" (un conteo, no el porcentaje del informe).

## Técnica

- **Flutter con pocos paquetes de terceros**: `flutter_svg`, `flutter_tts`, `audioplayers`, `path_provider`, `shared_preferences`, `pdf`, `share_plus`, `file_selector`, `clock` y `collection`. Sin Riverpod, go_router ni Drift: el estado cabe en un `ChangeNotifier` con un `InheritedNotifier`, la navegación es `Navigator.push` y los datos son archivos JSON.
- **Todo el avance se lee al abrir la app** (auditoría B1): `load()` carga el progreso de todos los perfiles, y pedir el de un perfil que no existe no crea nada que se pueda guardar encima del verdadero.
- **Guardado atómico** (auditoría G3): una cola por archivo, un temporal con nombre único, `rename` sin borrar antes, copia `.bak` del último archivo sano y recuperación desde ella. Un archivo dañado nunca se pisa en silencio: se aparta como `.corrupto-<fecha>` y el panel de adultos muestra un aviso. La app arranca aunque un archivo esté dañado.
- **Compilación reproducible** (auditoría M4): `pubspec.lock` está en el repositorio (`apps/pilas/.gitignore` lo exceptúa de la regla general) y `pubspec.yaml` declara las versiones mínimas reales de Dart y Flutter.
- **Textos en clases Dart** (`core/strings.dart` y `core/es.dart`, con las ayudas de gramática) en lugar de ARB: evita un paso de generación mientras la app tenga un solo idioma.
- **Voz del sistema** (`flutter_tts`) con preferencia es-CO, es-MX, es-US, es-ES; en Android se elige una voz instalada en el teléfono si la hay. Si el dispositivo no tiene voz en español, la app sigue con texto en pantalla. Antes de hablar, los precios, porcentajes, medidas y signos de las cuentas se pasan a palabras ("$ 3.500" se dice "tres mil quinientos pesos", no "dólares"; "12 m²", "doce metros cuadrados") **(decisión propia)**. En pantalla, el número y el % van con un espacio que no se corta de línea.
- **Pictogramas de Twemoji (CC BY 4.0)** copiados al paquete (solo los usados, 411 SVG; el pollito de frente `1f425`, las uñas `1f485`, el uniforme `1f94b`, los fríjoles `1fad8`, la chancla `1fa74` y la iglesia `26ea` vienen del paquete `@twemoji/svg` 15.0.0, el mismo dibujo en SVG optimizado) y tipografías **Lexend** y **Andika** (SIL OFL). Sin descargas en tiempo de ejecución.
- **Láminas para colorear propias**, generadas con `tools/gen_pilas_coloring.py` como JSON con paths SVG; el relleno por zonas usa un parser de paths propio (`content/svg_path.dart`). La geometría de cada lámina se calcula una vez y se reutiliza (auditoría M13).
- **Sonidos sintetizados** con `tools/gen_pilas_assets.py`; sin muestras de terceros ni música de fondo.
- **Un toque doble no abre dos veces** un juego ni un perfil (auditoría M5).
- **Carpetas `android/` e `ios/`** generadas con `flutter create` y ajustadas con `tools/patch_platforms.py`. La CI (`.github/workflows/pilas.yml`) analiza, prueba, compila el APK, el AAB y la versión de iOS sin firma, y genera las capturas de tienda.
- **minSdk 24** en Android (Android 7) para cubrir tabletas de colegio antiguas.

## Pendiente de decidir con el proyecto

- Nombre definitivo, dominio y cuenta de organización en las tiendas.
- Locuciones humanas en lugar de la voz del sistema (v1.1).
- Ilustrador para personajes propios.

## Anexo A. Revisión de etiquetas del vocabulario

Así está clasificado cada elemento del vocabulario que usan El intruso y Clasifica seres vivos. Un docente puede revisar aquí cada dato. Reglas: "Dónde vive" es la lista completa (si un lugar no está, el animal no sale como respuesta de ese lugar); "Se mueve así" es un movimiento característico y "Claramente no", uno que no hace. Lo dudoso no lleva ninguna de las dos, y por eso el animal no sale en las preguntas de ese movimiento. "También" son lugares en los que vive aunque no se pregunte por ellos (por ejemplo, el delfín de río): ahí nunca sale como distractor.

### A.1 Animales (62)

| Animal | Grupo | Dónde vive | Se mueve así | Claramente no | También |
| --- | --- | --- | --- | --- | --- |
| gato | mamífero | casa, granja | camina, trepa | vuela, repta | — |
| perro | mamífero | casa, granja | camina | vuela, repta, trepa | — |
| vaca | mamífero | granja | camina | vuela, salta, repta, trepa | — |
| cerdo | mamífero | granja | camina | vuela, salta, repta, trepa | — |
| gallina | ave | granja | camina | nada, repta, trepa | — |
| gallo | ave | granja | camina | nada, repta, trepa | — |
| pollito | ave | granja | camina | vuela, nada, repta, trepa | — |
| oveja | mamífero | granja | camina | vuela, repta, trepa | — |
| cabra | mamífero | granja, montaña | camina, trepa | vuela, repta | — |
| caballo | mamífero | granja | camina | vuela, repta, trepa | — |
| pato | ave | granja, río | nada, vuela, camina | repta, trepa | — |
| conejo | mamífero | granja, casa, bosque | salta | vuela, repta, trepa | — |
| ratón | mamífero | casa, granja, bosque | camina, trepa | vuela | — |
| burro | mamífero | granja | camina | vuela, repta, trepa | — |
| pavo | ave | granja | camina | nada, repta, trepa | — |
| león | mamífero | sabana | camina | vuela, repta | — |
| tigre | mamífero | selva, bosque | camina, nada | vuela, repta | — |
| elefante | mamífero | sabana, selva | camina | vuela, salta, repta, trepa | — |
| jirafa | mamífero | sabana | camina | vuela, repta, trepa | — |
| mono | mamífero | selva | trepa | vuela, repta | — |
| cebra | mamífero | sabana | camina | vuela, repta, trepa | — |
| oso | mamífero | bosque, montaña | camina | vuela, repta | — |
| panda | mamífero | bosque, montaña | camina, trepa | vuela, repta | — |
| koala | mamífero | bosque | trepa | vuela, repta | — |
| zorro | mamífero | bosque | camina | vuela, repta | — |
| lobo | mamífero | bosque, montaña | camina | vuela, repta, trepa | — |
| venado | mamífero | bosque | camina | vuela, repta, trepa | — |
| serpiente | reptil | selva, desierto, bosque, sabana, jardín | repta | vuela, camina, salta | — |
| tortuga | reptil | mar, río | camina, nada | vuela, salta, trepa | — |
| lagartija | reptil | desierto, selva, jardín, bosque | camina, trepa | vuela | — |
| cocodrilo | reptil | río | nada, camina | vuela, trepa | — |
| rana | anfibio | río, selva | salta, nada | vuela | — |
| perezoso | mamífero | selva | trepa | vuela, salta | — |
| llama | mamífero | montaña | camina | vuela, repta, trepa | — |
| murciélago | mamífero | selva, bosque | vuela | nada, repta | — |
| canguro | mamífero | — | salta | vuela, repta, trepa | — |
| hipopótamo | mamífero | río, sabana | camina | vuela, salta, repta, trepa | — |
| rinoceronte | mamífero | sabana | camina | vuela, salta, repta, trepa | — |
| camello | mamífero | desierto | camina | vuela, repta, trepa | — |
| erizo | mamífero | bosque, jardín | camina | vuela | — |
| nutria | mamífero | río | nada | vuela | — |
| pez | pez | mar, río | nada | vuela, camina, trepa | — |
| delfín | mamífero | mar | nada | vuela, camina, trepa | río |
| ballena | mamífero | mar | nada | vuela, camina, trepa | — |
| tiburón | pez | mar | nada | vuela, camina, salta, trepa | — |
| pulpo | — | mar | nada | vuela, salta | — |
| cangrejo | — | mar | camina | vuela | río |
| camarón | — | mar | nada | vuela | río |
| caracol | — | jardín | repta | vuela, nada, salta, camina | — |
| foca | mamífero | mar, polo | nada | vuela, trepa | — |
| pingüino | ave | mar, polo | nada, camina | vuela, trepa | — |
| águila | ave | montaña, bosque | vuela | nada, trepa | — |
| búho | ave | bosque | vuela | nada | — |
| loro | ave | selva | vuela, trepa | nada | — |
| pájaro | ave | jardín, bosque | vuela | nada, repta | — |
| flamenco | ave | — | vuela, camina | repta, trepa | — |
| pavo real | ave | — | camina | nada, repta | — |
| mariposa | insecto | jardín, selva | vuela | nada, repta | — |
| abeja | insecto | jardín | vuela | nada | — |
| mariquita | insecto | jardín | vuela | nada | — |
| hormiga | insecto | jardín, selva, bosque | camina | repta | — |
| araña | — | casa, jardín | camina, trepa | vuela | — |

### A.2 Vehículos y medios (15)

| Vehículo | Va por | Otras etiquetas |
| --- | --- | --- |
| carro | tierra | — |
| bus | tierra | — |
| bicicleta | tierra | — |
| moto | tierra | — |
| tren | tierra | — |
| helicóptero | aire | — |
| avión | aire | — |
| cohete | aire | — |
| velero | agua | — |
| barco | agua | — |
| carro de bomberos | tierra | — |
| ambulancia | tierra | — |
| tractor | tierra | — |
| patineta | tierra | juguete |
| camión | tierra | — |

### A.3 Ropa (15)

| Prenda | Para |
| --- | --- |
| camiseta | calor |
| uniforme | — (no entra en las preguntas de uso) |
| chancla | calor |
| pantalón | — (no entra en las preguntas de uso) |
| vestido | — (no entra en las preguntas de uso) |
| zapato | — (no entra en las preguntas de uso) |
| tenis (plural) | — (no entra en las preguntas de uso) |
| gorra | calor |
| medias (plural) | — (no entra en las preguntas de uso) |
| guantes (plural) | frío |
| bufanda | frío |
| sombrero | calor |
| botas (plural) | lluvia |
| gafas de sol (plural) | calor |
| chaqueta | frío |

### A.4 Instrumentos (8)

| Instrumento | Familia |
| --- | --- |
| guitarra | cuerdas |
| tambor | percusión |
| trompeta | viento |
| violín | cuerdas |
| piano | teclado |
| acordeón | viento |
| maracas | percusión |
| flauta | viento |

### A.5 Comida y el resto del vocabulario

- **Frutas:** manzana, banano, naranja, uvas (pl.), fresa, sandía, piña, mango, pera, limón, cereza, coco, kiwi, durazno, melón.
- **Verduras:** zanahoria, cebolla, brócoli, lechuga, berenjena, pepino.
- **Dulces:** helado, galleta, torta, chocolate, miel.
- **Bebidas:** leche, jugo.
- **Otras comidas:** maíz, tomate, papa, ají, aguacate, pan, queso, huevo, arroz, pollo, pizza, sopa, arepa.
- **Plantas:** árbol, pino, palmera, cactus, flor, girasol, rosa, tulipán, trébol.
- **Naturaleza:** sol, luna, estrella, nube, lluvia, tormenta, arcoíris, nieve, ola, fuego, hongo, hoja, piedra, montaña, volcán, isla, planeta Tierra.
- **Partes del cuerpo:** oreja, nariz, uñas (pl.), ojo, boca, lengua, diente, mano, pie, pierna, brazo, cerebro, corazón, pulmones (pl.), hueso.
- **Cosas de la casa:** puerta, silla, cama, sofá, ventana, llave, reloj, bombillo, balde, escoba, teléfono, computador, televisor, cámara.
- **Cocina:** plato, cuchara, tenedor, olla, tetera.
- **Baño:** cepillo de dientes, jabón, bañera.
- **Escuela:** libros (pl.), lápiz, regla, tijeras (pl.), crayón, libro, pincel, maleta.
- **Juguetes:** balón, oso de peluche, cometa, globo, rompecabezas, dado, yoyó.
- **Otros objetos:** imán.
- **Lugares:** casa, iglesia.
- **Fantasía:** unicornio.

## Anexo B. Mapa de habilidades

Cada habilidad la evalúa un solo juego de su tramo y se logra al dominar el último nivel de ese juego.

**De 3-4 años (15 habilidades).**

| Área | Habilidad | La evalúa | Qué mide |
| --- | --- | --- | --- |
| Razonamiento y lógica | Emparejar y recordar | Parejas y memoria | Encuentra parejas iguales entre ocho y diez cartas recordando dónde estaban. |
| Razonamiento y lógica | Secuencias | ¿Qué sigue? | Continúa patrones de colores y figuras como rojo, azul, rojo, azul. |
| Razonamiento y lógica | Clasificar | El intruso | Encuentra el que no va con los demás por su color, su forma o el tipo de cosa que es. |
| Razonamiento y lógica | Seguir un camino | Laberintos | Lleva a un personaje por un laberinto pequeño hasta la meta. |
| Razonamiento y lógica | Encajar formas | Rompecabezas | Coloca cada figura en su silueta. |
| Matemáticas | Contar y comparar | La tienda | Cuenta hasta diez, paga con monedas iguales y dice dónde hay más y dónde hay menos. |
| Matemáticas | Formas básicas | Figuras y medidas | Reconoce el círculo, el cuadrado, el triángulo y otras formas, y cuenta sus lados. |
| Lenguaje y lectura | Sonido inicial | Sonidos y letras | Reconoce las palabras que empiezan con el mismo sonido de vocal. |
| Lenguaje y lectura | Escuchar cuentos | Cuentos con voz | Sigue un cuento corto y responde qué pasó. |
| Lenguaje y lectura | Trazos y primeras letras | Trazo de letras | Sigue con el dedo líneas, vocales y números en el orden y la dirección de la guía. |
| Ciencias y entorno | Animales y dónde viven | Clasifica seres vivos | Reconoce animales y dónde viven: la granja, el mar, la selva y otros lugares. |
| Ciencias y entorno | Partes del cuerpo | El cuerpo humano | Nombra partes del cuerpo y dice para qué sirven. |
| Ciencias y entorno | Día, noche y naturaleza | Laboratorio guiado | Relaciona el día y la noche, el agua, el sol y las plantas con lo que pasa a su alrededor. |
| Emociones y hábitos | Emociones básicas | ¿Qué siento? | Reconoce la alegría, la tristeza, el enojo y el miedo en caras y situaciones. |
| Emociones y hábitos | Rutinas | Tablero de rutinas | Ordena los pasos de las rutinas de aseo, comida y sueño. |

**De 5-6 años (23 habilidades).**

| Área | Habilidad | La evalúa | Qué mide |
| --- | --- | --- | --- |
| Razonamiento y lógica | Memoria de trabajo | Parejas y memoria | Recuerda la posición de hasta doce cartas para formar parejas. |
| Razonamiento y lógica | Patrones de tres y cuatro | ¿Qué sigue? | Continúa patrones de tres y cuatro elementos y series que cuentan de 1 en 1, de 2 en 2 y de 10 en 10. |
| Razonamiento y lógica | Qué sobra | El intruso | Encuentra el que no pertenece al grupo: por dónde vive, cómo se mueve o para qué sirve. |
| Razonamiento y lógica | Laberintos | Laberintos | Planea un camino con desvíos y callejones sin salida. |
| Razonamiento y lógica | Formas y tamaños | Rompecabezas | Encaja figuras en su silueta fijándose en la forma y en el tamaño. |
| Razonamiento y lógica | Sudoku de 4 por 4 | Sudoku | Completa cuadrículas de 4 por 4 donde nada se repite en una fila, una columna ni una región. |
| Matemáticas | Monedas y precios | La tienda | Paga precios exactos con monedas y billetes de hasta 2.000 pesos y suma dos precios. |
| Matemáticas | Sumas y restas hasta 20 | Carrera de cálculo | Suma y resta hasta 20 contando hacia adelante y hacia atrás. |
| Matemáticas | Reloj en punto y media | El reloj | Lee las horas en punto y las medias en un reloj de manecillas. |
| Matemáticas | Medidas comparadas | Cocina de medidas | Compara cuánto hay en un vaso, cuenta los huevos de una receta y lee una balanza. |
| Matemáticas | Lados y longitudes | Figuras y medidas | Cuenta lados, compara longitudes y cuenta los cuadritos de una figura. |
| Lenguaje y lectura | Conciencia fonológica | Sonidos y letras | Reconoce el sonido inicial de las palabras y la letra con la que empiezan, y cuenta sílabas. |
| Lenguaje y lectura | Comprensión de cuentos | Cuentos con voz | Responde qué pasó, por qué y qué podría pasar en un cuento escuchado. |
| Lenguaje y lectura | Letras y sílabas | Arma la palabra | Arma palabras letra por letra, sílaba por sílaba. |
| Lenguaje y lectura | Frases cortas | Ordena la oración | Ordena las palabras de oraciones cortas con apoyo de la voz. |
| Lenguaje y lectura | Trazo de letras | Trazo de letras | Traza letras y números en el orden y la dirección del trazo escolar. |
| Ciencias y entorno | Hábitats y grupos | Clasifica seres vivos | Dice dónde viven los animales y si son mamíferos, aves, peces, reptiles, anfibios o insectos. |
| Ciencias y entorno | Los cinco sentidos | El cuerpo humano | Relaciona cada sentido con su órgano y con lo que nos permite saber. |
| Ciencias y entorno | Observar y predecir | Laboratorio guiado | Predice qué pasará en experimentos sencillos: flotar, imanes, mezclas y luz. |
| Creatividad | Colorear por números | Colorear por números | Relaciona cada zona con su número y termina la lámina. |
| Emociones y hábitos | Qué hacer con una emoción | ¿Qué siento? | Nombra la emoción de una situación y elige una forma sana de calmarse. |
| Emociones y hábitos | Pasos de la vida diaria | Tablero de rutinas | Ordena los pasos de rutinas y tareas de la casa más largas. |
| Emociones y hábitos | Turnos y acuerdos | Historias con decisiones | Elige qué hacer cuando hay que esperar, compartir o resolver un desacuerdo. |

**De 7-8 años (20 habilidades).**

| Área | Habilidad | La evalúa | Qué mide |
| --- | --- | --- | --- |
| Razonamiento y lógica | Memoria con conceptos | Parejas y memoria | Une cada grupo con su ejemplo y cada operación con su resultado recordando dónde está cada carta. |
| Razonamiento y lógica | Patrones numéricos | ¿Qué sigue? | Descubre la regla de una serie de números: sumar, restar, duplicar o seguir una tabla. |
| Razonamiento y lógica | Clasificar con criterios | El intruso | Encuentra el intruso por grupo de animal, familia de instrumento, medio de transporte o propiedad de los números. |
| Razonamiento y lógica | Planificar la ruta | Laberintos | Recorre laberintos grandes, algunos con una llave que hay que recoger antes de la meta. |
| Razonamiento y lógica | Armar imágenes | Rompecabezas | Arma imágenes de 9 y de 16 fichas intercambiándolas con pocos movimientos. |
| Razonamiento y lógica | Sudoku de 6 por 6 | Sudoku | Deduce los números que faltan en cuadrículas de 6 por 6. |
| Matemáticas | Dinero en pesos | La tienda | Paga con billetes, calcula las vueltas y multiplica precios. |
| Matemáticas | Cálculo hasta 100 y tablas | Carrera de cálculo | Suma y resta hasta 100 con llevadas, usa las tablas de multiplicar y divide sin resto. |
| Matemáticas | Reloj con minutos | El reloj | Lee cuartos y minutos de cinco en cinco y calcula cuánto falta. |
| Matemáticas | Fracciones simples | Cocina de medidas | Reconoce medios, tercios y cuartos, compara fracciones y ajusta una receta. |
| Matemáticas | Perímetro | Figuras y medidas | Calcula el perímetro contando lados en una cuadrícula, con medidas y en figuras en L. |
| Lenguaje y lectura | Lectura con comprensión | Cuentos con voz | Responde qué pasó, por qué y qué se puede inferir de un texto corto. |
| Lenguaje y lectura | Ortografía | Arma la palabra | Escribe palabras con letras que se confunden: b y v, ll y y, c, s y z, g y j, h. |
| Lenguaje y lectura | Oraciones con sentido | Ordena la oración | Ordena oraciones con sujeto, verbo y complementos. |
| Ciencias y entorno | Grupos de animales | Clasifica seres vivos | Clasifica animales por su grupo y por cómo se mueven. |
| Ciencias y entorno | Órganos del cuerpo | El cuerpo humano | Ubica los órganos principales y sabe para qué sirven. |
| Ciencias y entorno | Materia y energía | Laboratorio guiado | Explica los cambios de estado, las mezclas y cómo pasa el calor. |
| Creatividad | Pixel art y coordenadas | Pixel art | Copia modelos casilla por casilla y completa figuras en espejo. |
| Emociones y hábitos | Emociones en situaciones | ¿Qué siento? | Reconoce el orgullo, la vergüenza o los nervios en situaciones y elige qué ayuda. |
| Emociones y hábitos | Seguridad en casa, en la calle y en internet | Historias con decisiones | Reconoce situaciones de riesgo y pide ayuda a un adulto de confianza. |

**De 9-11 años (18 habilidades).**

| Área | Habilidad | La evalúa | Qué mide |
| --- | --- | --- | --- |
| Razonamiento y lógica | Memoria con operaciones | Parejas y memoria | Une multiplicaciones, divisiones y dobles con su resultado entre hasta veinte cartas. |
| Razonamiento y lógica | Series con dos reglas | ¿Qué sigue? | Continúa series con pasos que crecen, cuadrados, alternancias y multiplicaciones. |
| Razonamiento y lógica | Estrategia en laberintos | Laberintos | Planea la ruta completa en laberintos grandes con llave, sin dar vueltas de más. |
| Razonamiento y lógica | Rompecabezas grandes | Rompecabezas | Arma imágenes de 9 a 25 fichas con pocos movimientos. |
| Razonamiento y lógica | Sudoku de 9 por 9 | Sudoku | Resuelve sudokus de 6 por 6 y de 9 por 9. |
| Matemáticas | Presupuesto | La tienda | Planea compras con un presupuesto, calcula el precio por unidad y los descuentos. |
| Matemáticas | Operaciones | Carrera de cálculo | Multiplica por una cifra, divide con resto, suma decimales y calcula fracciones de una cantidad. |
| Matemáticas | Tiempo y duraciones | El reloj | Lee cualquier hora, calcula cuánto falta y a qué hora termina una actividad. |
| Matemáticas | Fracciones equivalentes | Cocina de medidas | Reconoce fracciones equivalentes, suma fracciones de igual denominador y compara fracciones distintas. |
| Matemáticas | Área y perímetro | Figuras y medidas | Calcula áreas contando, con medidas y en figuras compuestas, y distingue el área del perímetro. |
| Lenguaje y lectura | Comprensión de textos | Cuentos con voz | Infiere ideas que el texto no dice de forma directa. |
| Lenguaje y lectura | Tildes | Arma la palabra | Escribe palabras con tilde y con letras que se confunden. |
| Lenguaje y lectura | Oraciones complejas | Ordena la oración | Ordena oraciones con conectores como porque, pero, cuando y aunque. |
| Ciencias y entorno | Clasificación de seres vivos | Clasifica seres vivos | Clasifica animales por grupo y por ecosistema, también los que confunden, como la ballena o el murciélago. |
| Ciencias y entorno | Sistemas del cuerpo | El cuerpo humano | Relaciona órganos con sistemas y con los hábitos que cuidan la salud. |
| Ciencias y entorno | Método científico | Laboratorio guiado | Formula hipótesis, identifica variables y saca conclusiones con evidencia. |
| Creatividad | Copiar y reflejar figuras | Pixel art | Copia modelos grandes casilla por casilla y completa en espejo la mitad que falta. |
| Emociones y hábitos | Equipo, pantallas y seguridad en línea | Historias con decisiones | Decide bien en trabajos en grupo, con las pantallas, las compras en los juegos y los riesgos de internet. |
