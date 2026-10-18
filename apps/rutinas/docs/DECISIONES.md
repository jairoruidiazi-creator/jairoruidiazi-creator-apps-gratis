# Rutinas: decisiones de diseño y producto

Registro de las decisiones tomadas durante el desarrollo, con su razón.

## Producto

- **Nombre: Rutinas.** Corto, en español, describe las tres partes (hábitos, recordatorios y entrenamientos). Identificador de paquete `co.appsgratis.rutinas`. En las tiendas: «Rutinas: hábitos e intervalos» / «Rutinas: Habit Tracker & Timer» (el límite de 30 caracteres deja fuera «temporizador»; el subtítulo de iOS lo recupera).
- **Una app con cinco pestañas** (Hábitos, Avisos, Tiempo, Resumen y Ajustes) en lugar de cuatro apps de pago: Streaks y (Not Boring) Habits para los hábitos, Due para los recordatorios y Seconds Pro para el temporizador.
- **Sin cuenta, sin anuncios, sin servidor y sin el permiso de internet.** La forma de cambiar de teléfono es una copia de seguridad en JSON por la hoja de compartir, que se restaura eligiendo el archivo.
- **Idioma inicial: el del teléfono** (español si está en español; si no, inglés) y se puede cambiar en Ajustes. La semana empieza el lunes por defecto, como en Colombia.
- **Fuera de la v1:** widgets de pantalla de inicio, relojes (Apple Watch, Wear OS), Salud y Health Connect, listas o subtareas dentro de un recordatorio, recordatorios por ubicación, sincronización entre dispositivos y música dentro del temporizador. Ninguna se anuncia en las fichas.

## Hábitos y rachas

- **La racha se cuenta por periodos, no por días sueltos:** días para los diarios y los de días de la semana, bloques de N días para «cada N días» (bloques fijos desde el inicio, no «N días desde la última vez», para que el calendario sea predecible) y semanas o meses para «N veces por semana/mes». Cada periodo queda cumplido, excusado, fallado o en curso.
- **Lo que no rompe la racha:** los días que no tocan (no son periodos), los días saltados a propósito (cubren lo que falta del periodo: dos hechos y uno saltado cumplen «3 por semana» como excusado, que ni suma ni rompe) y el periodo de hoy mientras no termine. La primera semana o el primer mes a medias, si el hábito empezó a mitad de camino, tampoco falla.
- **«Dejar de…» cuenta días completos sin recaer:** el día que se empieza o se recae la racha es 0; hoy no cuenta hasta que termina. Varias recaídas en un día cuentan como un día con recaída.
- **El inicio efectivo es el primer registro** si se anotaron días anteriores a la fecha de inicio, para que el historial cargado a mano no quede fuera de la racha.
- **Cumplimiento = periodos cumplidos sobre periodos cerrados**, sin contar los excusados ni el periodo en curso; así el porcentaje no baja a media mañana.
- **Los hábitos con tiempo usan el temporizador de la app:** al terminar se suma la meta del día; si se detiene antes, se suma lo hecho (desde 5 s) al día en que empezó.
- En español los días van con las iniciales de los calendarios (L M X J V S D).

## Recordatorios

- **Cada recordatorio guarda solo su ocurrencia actual.** Al marcar hecho uno que se repite pasa a la siguiente ocurrencia después de ahora; si no se marcó y llega la siguiente, pasa a la más reciente (las perdidas no se acumulan, como en un despertador).
- **Reglas de calendario:** mensual el día 29 a 31 cae el último día de los meses que no lo tienen y vuelve a su día al mes siguiente; el anual del 29 de febrero cae el 28 en los años no bisiestos. Los días de la semana y la serie de «cada N días» conservan la hora del ancla.
- **Insistencia:** el aviso se repite cada 1 a 60 minutos, como mucho 60 veces y nunca más allá de la siguiente ocurrencia. En Android cada repetición quita la anterior del panel (`timeoutAfter`) para no llenarlo.
- **Posponer cambia la hora del aviso, no la del recordatorio:** la serie sigue igual.
- **La cuenta regresiva rápida es un recordatorio de una vez** que guarda su duración (para repetirla) e insiste cada minuto por defecto (ajustable en Ajustes). Se puede renombrar como cualquier recordatorio.

## Notificaciones

- **El plan es una función pura** (`logic/notice_plan.dart`) que se aplica por diferencias: cada aviso tiene una clave estable (hash FNV-1a de 31 bits, el mismo en todas las versiones de Dart) y su carga útil lleva la hora y el texto; solo se programa o cancela lo que cambió. Se replanifica al abrir, al volver, al pasar a segundo plano y medio segundo después de cada cambio.
- **Topes:** iOS guarda 64 notificaciones programadas por app (se usan 60) y en Android se limita a 240; se quedan las más cercanas. Horizonte de 14 días para recordatorios y 7 para hábitos: abrir la app una vez por semana basta para que nada se pierda.
- **Las horas se programan como instantes en UTC** (`TZDateTime.from(…, UTC)`): cada ocurrencia se calcula en hora local y no hace falta cargar la base de zonas horarias.
- **Alarmas exactas solo con permiso.** Android 14 lo niega de entrada; sin él se programan alarmas inexactas (pueden llegar unos minutos tarde con la pantalla apagada) y Ajustes y la pestaña de avisos lo explican con un botón para concederlo. No se usa `USE_EXACT_ALARM`, que Google Play reserva a despertadores y calendarios.
- **Un canal de Android por sonido** (recordatorios, cuentas regresivas, hábitos y uno por sonido del temporizador), porque el sonido de un canal no se puede cambiar después de creado. En iOS los sonidos se copian a `Library/Sounds`.
- **Los botones de las notificaciones abren la app** (`showsUserInterface` / opción de primer plano) y la acción se aplica allí: el mismo código en Android e iOS, sin trabajo en segundo plano.

## Temporizador

- **Sin servicio en primer plano.** El estado sale del reloj (inicio, pausas acumuladas y saltos), nunca de contar ticks. Al pasar a segundo plano se programa una notificación con el sonido de cada cambio de intervalo que falta y una al terminar; al volver se cancelan y la pantalla muestra el tiempo exacto. En segundo plano no hay voz ni «3, 2, 1»: solo los sonidos de las notificaciones.
- **Sin ráfagas al volver:** el seguimiento de avisos se sincroniza con el estado actual y solo anuncia lo que viene.
- **«3, 2, 1» en los intervalos de 5 s o más.** Si la voz está apagada o el teléfono no tiene voz en el idioma de la app, suenan pitidos.
- **Bloques anidados hasta tres niveles** y como mucho 3000 intervalos desplegados. Por defecto se omite el descanso final de la última vuelta de cada bloque (como en un Tabata), y se puede apagar por bloque. Las vueltas se nombran Ronda, Serie y Bloque de adentro hacia afuera, o con el nombre que se les dé.
- **«Anterior»** vuelve al inicio del intervalo actual; si empezó hace menos de 2 s, al anterior.
- **Colores por tipo de intervalo con contraste AA** para el texto blanco encima; cada intervalo puede tener color propio de la misma paleta.
- **Historial:** se guardan los entrenamientos terminados y los interrumpidos después de 30 s, con el tiempo en marcha sin pausas.
- **Candado:** un toque bloquea los controles y se desbloquea manteniendo presionado, para que un roce con el teléfono en el brazo no pause.
- **Audio:** los sonidos se mezclan con la música del usuario sin pausarla; la voz la baja un momento mientras habla. Todos los sonidos se sintetizan con `tools/gen_rutinas_sounds.py` (numpy, semilla fija) y quedan en el repositorio.
- **Pantalla encendida** solo mientras corre un temporizador con la app a la vista (activado por defecto, se apaga en Ajustes).

## Resúmenes

- **Un periodo de un hábito cuenta en el resumen si termina dentro del rango** (y el periodo en curso, si cae en el rango, aparece como en curso, nunca como fallado). Así una semana de «3 veces por semana» que cruza el cambio de mes cuenta una sola vez.
- **Mejor día:** el de más hábitos hechos (el primero si hay empate). **Día más constante** (mes y año): el día de la semana con más hábitos hechos en promedio.
- **Entrenamientos hechos** cuenta los terminados; el tiempo entrenado suma también los interrumpidos.

## Datos

- **Un archivo JSON por dominio** (`habits.json`, `reminders.json`, `timers.json`) en la carpeta privada de la app, con escritura síncrona y atómica (archivo temporal y renombrado) 300 ms después del último cambio y al pasar a segundo plano. Un archivo que no se puede leer se aparta con otro nombre en vez de sobrescribirse, y Ajustes lo avisa.
- **La copia de seguridad no lleva el temporizador en marcha ni el cronómetro**; restaurar reemplaza todo lo demás y los conserva. La copia exportada se borra de la carpeta de la app la siguiente vez que se abre (ya se compartió).
- Ajustes en `shared_preferences`; viajan en la copia de seguridad, salvo los permisos.

## Interfaz y accesibilidad

- **Riel lateral con ancho de 600 dp o más y alto de 520 o más** (tabletas); en un teléfono acostado sigue la barra inferior, porque cinco destinos no caben a lo alto. Contenido limitado a 720 dp de ancho.
- **Los teléfonos van en vertical** (Info.plist en iPhone y `SystemChrome` en Android); las tabletas giran libremente. La pantalla del temporizador tiene su propio diseño apaisado.
- **TalkBack y VoiceOver:** cada fila se anuncia como una sola frase (nombre, avance y racha) y sus botones por separado; los contadores son valores ajustables. Las pruebas verifican objetivos de 48 dp con nombre, texto ×2 sin desbordes y contraste AA de la paleta.
- **Pantalla del temporizador:** el tiempo crece hasta llenar el espacio libre y los controles quedan fijos abajo, siempre a la vista; si el texto es muy grande, lo que se desplaza es la información de la ronda.
- **Avisos inferiores (SnackBar) dentro de cada pestaña:** cada pestaña tiene su propio `ScaffoldMessenger`, así el aviso sube el botón flotante de la pestaña en vez de taparlo.
- **Pestañas del temporizador** («Intervalos», «Cronómetro», «Cuenta atrás») a lo ancho cuando sus nombres caben; con el texto muy grande, la barra se desplaza.
- Las etiquetas de la barra inferior van a 11 sp para que «Hábitos», «Resumen» y los demás quepan enteros en 360 dp. Fuente de respaldo «Simbolos» (subconjunto de DejaVu Sans) para flechas y marcas que Roboto no trae.

## Tiendas

- **Categorías:** Productividad en Google Play; en la App Store, Productividad con Salud y forma física como secundaria.
- **Declaración de apps de salud de Google Play:** se declara «Actividad física y fitness» por el temporizador de entrenamientos, aunque la app no lea sensores ni datos de salud; es la respuesta prudente.
- **Público de 13 años o más:** es una herramienta para público general y no se inscribe en Diseñada para familias.

## Pendiente de decidir con el proyecto

- Nombre definitivo e ícono ilustrado.
- Si la v1.1 suma widgets de pantalla de inicio y la integración con Salud / Health Connect (pediría permisos nuevos y cambiaría las respuestas de privacidad).
