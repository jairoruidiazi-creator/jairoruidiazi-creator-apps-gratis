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
- **El inicio efectivo es el primer registro con valor** (hecho o a medias) si se anotó antes de la fecha de inicio, para que el historial cargado a mano no quede fuera de la racha. Una nota o un día saltado solos no adelantan el inicio: si lo hicieran, partirían de nuevo los bloques de «cada N días» y cambiarían estados pasados.
- **Cambiar la frecuencia o la meta rige desde hoy.** La regla anterior se guarda con su último día (`rules` en el JSON) y los días pasados se siguen evaluando con ella: pasar de lunes a viernes a todos los días no convierte los fines de semana pasados en fallados ni borra la racha, y subir la meta de 8 a 10 vasos no deshace los días con 8. Dos reglas seguidas con la misma estructura (por ejemplo, de 3 a 4 veces por semana) comparten periodos; si cambia la estructura, el periodo partido por el cambio queda excusado. El editor lo dice antes de guardar.
- **El tipo de un hábito no cambia si ya tiene días anotados con valor**, porque cambiaría lo que significan los datos (veces, segundos o recaídas): 600 s de meditación no son 600 vasos ni 600 recaídas. El editor solo muestra el tipo actual, lo explica y ofrece «Crear un hábito nuevo» con el mismo nombre, ícono, color y avisos; el de antes se queda con su historia. Sin valores anotados (solo notas o días saltados) el tipo se puede cambiar.
- **Archivar guarda el día** (`archivedAt`): desde ahí sus periodos no cuentan como fallados ni aparecen en el resumen. Al recuperarlo, el tramo archivado queda como pausa (`pauses`) y tampoco falla. Los archivados de versiones anteriores, sin fecha, toman el día siguiente a su último registro.
- **Saltar un día lo saca de «Por hacer»** (sección «Saltados»), y en los hábitos por semana, mes o bloque, lo hecho más lo saltado que ya cubre el periodo también; tampoco se avisa de ellos.
- **Cumplimiento = periodos cumplidos sobre periodos cerrados**, sin contar los excusados ni el periodo en curso; así el porcentaje no baja a media mañana.
- **Los hábitos con tiempo usan el temporizador de la app:** al terminar se suma la meta del día; si se detiene antes, se suma lo hecho (desde 5 s) al día en que empezó.
- En español los días van con las iniciales de los calendarios (L M X J V S D).

## Recordatorios

- **Cada recordatorio guarda solo su ocurrencia actual.** Al marcar hecho uno que se repite pasa a la siguiente ocurrencia después de ahora; si no se marcó y llega la siguiente, pasa a la más reciente (las perdidas no se acumulan, como en un despertador).
- **Reglas de calendario:** mensual el día 29 a 31 cae el último día de los meses que no lo tienen y vuelve a su día al mes siguiente; el anual del 29 de febrero cae el 28 en los años no bisiestos.
- **La regla guarda su hora y su día.** La hora y el minuto van en la regla (`hour`, `minute`) y cada ocurrencia se arma con ellos, no con la anterior: el día del cambio de horario en que las 2:30 no existen suena a la hora que da el sistema (3:30) y al día siguiente vuelve a las 2:30. Las reglas viejas sin hora toman la del recordatorio al leerse. El editor toma el día y el mes de la regla, no de la ocurrencia actual: abrir «el 31 de cada mes» el 30 de noviembre y guardar sigue siendo del 31, y el cumpleaños del 29 de febrero sigue en el 29. Solo cambian si se elige otra fecha.
- **Guardar sin tocar la fecha, la hora ni la regla** (por ejemplo, para cambiar el título) no mueve la ocurrencia actual ni quita lo pospuesto, aunque esté vencida.
- **Insistencia:** el aviso se repite cada 1 a 60 minutos y nunca más allá de la siguiente ocurrencia. Cuánto se puede programar de antemano está en «Notificaciones».
- **Posponer cambia la hora del aviso, no la del recordatorio,** y solo se ofrece para lo que ya sonó o suena dentro de una hora: en uno de dentro de días lo haría sonar antes. Se cuenta desde la hora del aviso si todavía no llega, y nunca queda antes de la hora del recordatorio, así que marcarlo hecho nunca se salta la ocurrencia real. «Mañana a las 9:00» pospone hasta esa hora exacta.
- **Las notificaciones viejas no tocan la ocurrencia de ahora.** La carga útil lleva la ocurrencia a la que pertenece; si «Hecho» o «Posponer» llegan desde el aviso de una vez anterior (por ejemplo, el de ayer que quedó en el panel), solo se quita ese aviso y la app lo dice. Al marcar hecho, posponer o borrar, se quitan del panel todos los avisos del recordatorio, también los de ocurrencias anteriores: la app anota en `avisos.json` lo que programó y ya sonó (15 días).
- **La cuenta regresiva rápida es un recordatorio de una vez** que guarda su duración (para repetirla) e insiste cada minuto por defecto (ajustable en Ajustes). Se puede renombrar como cualquier recordatorio. Mientras suena dice «Sonando desde las 18:33», con la hora y no con un tiempo relativo.

## Notificaciones

- **El plan es una función pura** (`logic/notice_plan.dart`): cada aviso tiene una clave estable (hash FNV-1a de 31 bits, el mismo en todas las versiones de Dart) y su carga útil lleva la ruta, la ocurrencia, la hora y una firma de lo que se ve y de cómo se programa (también si es una alarma exacta). Se replanifica al abrir, al volver, al pasar a segundo plano y medio segundo después de cada cambio.
- **Cupo por prioridades.** iOS guarda 64 notificaciones programadas por app (se usan 60) y en Android se limita a 240. Antes se ordenaba todo por hora y se cortaba, y las repeticiones del aviso más próximo dejaban sin programar casi todo lo demás. Ahora el cupo se reparte así: (1) con un entrenamiento en segundo plano, sus cambios de intervalo; (2) los primeros avisos de cada ocurrencia de los próximos 3 días (iOS) o 7 días (Android) y las solicitudes que se repiten; (3) por orden de hora, las repeticiones de la ocurrencia más próxima de cada recordatorio o hábito —como mucho 6 en iOS y 30 en Android— y los primeros avisos posteriores. Solo insiste la ocurrencia más próxima de cada elemento.
- **Cuando la ocurrencia ya sonó, su insistencia es una sola solicitud que se repite** (`periodicallyShowWithDuration`: `UNTimeIntervalNotificationTrigger` con `repeats` en iOS, alarma repetida en Android) y ocupa un solo lugar del cupo hasta que se marca hecho. Con la app abierta, al sonar el primer aviso se vuelve a planear para pasar a esa solicitud; si la app no está abierta cuando suena, quedan las repeticiones sueltas que caben (hasta 6 o 30). Los hábitos no la usan: su insistencia termina sola en el siguiente aviso del día o a medianoche. Los textos lo dicen así.
- **Cobertura honesta.** Si algún primer aviso no cabe, el último lugar del cupo es un aviso a la hora del primero que se quedó afuera: «Abre Rutinas para que este y tus próximos avisos sigan llegando», y nada se programa después de él. La app guarda hasta cuándo llega lo programado: Ajustes lo muestra siempre que no cabe todo, y la pestaña de avisos lo advierte si no llega a tres días. Con los datos de la demo de la tienda, iOS cubre casi 6 días (hasta el martes siguiente a las 18:00) y Android todo el horizonte; un usuario típico (dos hábitos y un recordatorio diario) cubre todo en las dos plataformas. Las pruebas usan los topes reales (60 y 240), la demo, un usuario típico y uno intenso.
- **`timeoutAfter` se calcula sobre lo que de verdad se programa:** cada aviso se borra del panel al llegar el siguiente del mismo elemento, y el último que cabe se queda.
- Horizonte de 14 días para recordatorios y 7 para hábitos.
- **En Android no se le cree a la lista de pendientes del plugin.** `pendingNotificationRequests()` en Android es una lista que el plugin guarda en sus preferencias y no se entera cuando el sistema borra las alarmas: «forzar detención», un ahorrador de batería, quitar el permiso de alarmas exactas o una copia de Google restaurada en otro teléfono. Por eso en Android la primera sincronización de cada proceso cancela todo y vuelve a programar el plan entero; después, en el mismo proceso, se aplica por diferencias. También se reprograma todo al restaurar una copia, al cambiar el permiso de alarmas exactas (se comprueba al volver a la app) y al cambiar el idioma. En iOS se compara con el estado real de `UNUserNotificationCenter`. El doble de pruebas separa lo programado de verdad de la lista del plugin para poder simular esos casos.
- **Copia de Google (Android):** viajan los datos y los ajustes, pero no la lista de avisos del plugin (`scheduled_notifications.xml`), el registro de avisos (`avisos.json`) ni las copias exportadas (`data_extraction_rules.xml` para Android 12 o superior y `backup_rules.xml` antes). Las alarmas no viajan con los datos y la app las vuelve a programar al abrirse.
- **Las horas se programan como instantes en UTC** (`TZDateTime.from(…, UTC)`): cada ocurrencia se calcula en hora local y no hace falta cargar la base de zonas horarias.
- **Alarmas exactas solo con permiso.** Android 14 no lo concede de entrada a las apps nuevas; sin él se programan alarmas inexactas, que en Android 12 o superior pueden llegar hasta una hora tarde con la pantalla apagada. Ajustes, la pestaña de avisos y la pantalla del temporizador lo dicen así, con un botón para concederlo, y la primera vez que se empieza un temporizador se explica antes de ofrecerlo. Al concederlo, todo lo ya programado pasa a ser exacto. No se usa `USE_EXACT_ALARM`, que Google Play reserva a despertadores y calendarios.
- **Canales de Android** por sonido y por vibración (recordatorios, cuentas regresivas, hábitos y, para el temporizador, cada sonido con y sin vibración, solo vibración y sin nada), en dos grupos, porque el sonido y la vibración de un canal no se pueden cambiar después de creado. Así los ajustes «Sonidos» y «Vibración» también se respetan con la pantalla apagada. Los del temporizador y las cuentas regresivas suenan por el volumen de alarma. En iOS los sonidos se copian a `Library/Sounds`.
- **iOS «sensible al tiempo».** Recordatorios, cuentas regresivas y cambios de intervalo se marcan `timeSensitive` (con el permiso `com.apple.developer.usernotifications.time-sensitive` en `Runner.entitlements`): pasan por encima de los modos de concentración y del resumen programado si el usuario lo permite. Los hábitos no, para no molestar. No traspasan el interruptor de silencio (para eso harían falta alertas críticas, que Apple reserva a salud y seguridad): con el iPhone en silencio llegan sin sonido, y Ajustes y la ficha lo dicen.
- **El idioma de los avisos sigue al de la app:** al cambiarlo se renombran los canales de Android, se vuelven a registrar los botones de iOS y se reprograma todo con los textos nuevos.
- **Los botones de las notificaciones abren la app** (`showsUserInterface` / opción de primer plano) y la acción se aplica allí: el mismo código en Android e iOS, sin trabajo en segundo plano.

## Temporizador

- **Sin servicio en primer plano.** El estado sale del reloj (inicio, pausas acumuladas y saltos), nunca de contar ticks. Al pasar a segundo plano se programa una notificación con el sonido de cada cambio de intervalo que falta y una al terminar; al volver se cancelan y la pantalla muestra el tiempo exacto. En segundo plano no hay voz ni «3, 2, 1»: solo los sonidos de las notificaciones. Un servicio en primer plano daría precisión en Android, pero pide un permiso que Google Play revisa (`FOREGROUND_SERVICE_*` con declaración de uso) y no existe en iOS; la pantalla encendida durante el entrenamiento (activada por defecto) y las alarmas exactas cubren el caso normal.
- **Lo que pasa con la pantalla bloqueada se dice antes de bloquearla.** La primera vez que se empieza un temporizador en Android 12 o superior sin alarmas exactas, la app explica que los cambios pueden llegar hasta una hora tarde y ofrece el permiso; la pantalla del temporizador lo sigue advirtiendo mientras falte. Los cambios del temporizador van primero en el cupo; si aun así no caben (el Tabata de 4 series tiene 64 intervalos y en iOS caben 59), la pantalla dice hasta qué intervalo y a qué hora llegan los avisos, y el último que cabe pide abrir la app.
- **Los intervalos sin nombre se anuncian con su tipo** («Trabajo», «Descanso»), como se ven en la pantalla.
- **Vibración propia:** un canal nativo (`rutinas/vibracion`) usa el motor de vibración (Android) o la vibración del sistema (iOS), que se siente aunque el usuario haya apagado la respuesta táctil; si no está, se usa la respuesta táctil de Flutter.
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
- **Restaurar es todo o nada.** El archivo se lee entero con los mismos lectores de la app en almacenes en memoria, se valida (identificadores, fechas entre los años 2000 y 2199) y solo si todo salió bien reemplaza lo que hay; un archivo malformado no toca nada y se dice por qué. Las claves de día fuera de ese rango no se leen, y una fecha de inicio absurda cae en la fecha de creación. Restaurar quita el aviso de archivo dañado de Ajustes, que también se puede ocultar a mano.
- Ajustes en `shared_preferences`; viajan en la copia de seguridad, salvo los permisos.

## Interfaz y accesibilidad

- **Riel lateral con ancho de 600 dp o más y alto de 520 o más** (tabletas); en un teléfono acostado sigue la barra inferior, porque cinco destinos no caben a lo alto. Contenido limitado a 720 dp de ancho.
- **Los teléfonos van en vertical** (Info.plist en iPhone y `SystemChrome` en Android); las tabletas giran libremente. La pantalla del temporizador tiene su propio diseño apaisado.
- **TalkBack y VoiceOver:** cada fila se anuncia como una sola frase (nombre, avance y racha) y sus botones por separado; los contadores son valores ajustables que también se pueden escribir (tocar el número abre un campo). Los días de la semana de los editores se anuncian con su nombre completo y tienen su acción de toque, que usan TalkBack, VoiceOver, Switch Access y Voice Access. Las pruebas verifican objetivos de 48 dp con nombre (también en los editores y en la hoja del día), ejecutan la acción de toque de los lectores de pantalla, texto ×2 sin desbordes y contraste AA de la paleta.
- **La hora se muestra igual en toda la app:** en español en 24 horas («18:30», como el selector de hora de Material en español); en inglés en 12 horas salvo que el teléfono use 24 horas.
- **«Nuevo hábito» va arriba, en la barra**, y no como botón flotante: abajo tapaba el botón de hecho del último hábito a la vista, que es lo que más se toca en esa lista.
- **Tocar una notificación** lleva a su pestaña y cierra lo que está abierto encima, salvo una pantalla con cambios sin guardar (editor de entrenamientos), que se queda.
- **Tableta:** la barra del temporizador en marcha deja el margen de la barra del sistema cuando no hay barra de navegación debajo.
- **Pantalla del temporizador:** el tiempo crece hasta llenar el espacio libre y los controles quedan fijos abajo, siempre a la vista; si el texto es muy grande, lo que se desplaza es la información de la ronda.
- **Avisos inferiores (SnackBar) dentro de cada pestaña:** cada pestaña tiene su propio `ScaffoldMessenger`, así el aviso sube el botón flotante de la pestaña en vez de taparlo.
- **Pestañas del temporizador** («Intervalos», «Cronómetro», «Cuenta regresiva») a lo ancho cuando sus nombres caben; con el texto muy grande, la barra se desplaza.
- **Español de Latinoamérica:** «cuenta regresiva» y no «cuenta atrás», y «Configuración» para los ajustes del sistema. La pestaña de la app se sigue llamando «Ajustes», que es corta y se entiende en toda la región.
- Las etiquetas de la barra inferior van a 11 sp para que «Hábitos», «Resumen» y los demás quepan enteros en 360 dp. Fuente de respaldo «Simbolos» (subconjunto de DejaVu Sans) para flechas y marcas que Roboto no trae.

## Tiendas

- **Ícono adaptativo de Android:** el primer plano se dibuja a 1,15 (`tools/gen_rutinas_assets.py`); con el margen del 16 % que pone flutter_launcher_icons, el anillo mide unos 58 dp de los 108, dentro del círculo de 66 dp que se ve.
- **Capturas:** la barra de estado dice 18:40, la hora de la escena (`status_time` en `store/screenshots.json`). El titular de los recordatorios dice que vuelven a sonar si no se marcan, sin prometer que insisten para siempre.

- **Categorías:** Productividad en Google Play; en la App Store, Productividad con Salud y forma física como secundaria.
- **Declaración de apps de salud de Google Play:** se declara «Actividad física y fitness» por el temporizador de entrenamientos, aunque la app no lea sensores ni datos de salud; es la respuesta prudente.
- **Público de 13 años o más:** es una herramienta para público general y no se inscribe en Diseñada para familias.

## Pendiente de decidir con el proyecto

- Nombre definitivo e ícono ilustrado.
- Si la v1.1 suma widgets de pantalla de inicio y la integración con Salud / Health Connect (pediría permisos nuevos y cambiaría las respuestas de privacidad).
