# Clave: decisiones de diseño y producto

Registro de las decisiones tomadas durante el desarrollo, con su razón. La segunda parte recoge las correcciones de la auditoría (hallazgos B, G y M) y cómo se verifican.

## Producto

- **Nombre de trabajo: Clave.** Corto, en español, con doble sentido musical (la clave como figura rítmica e instrumento, y "estar en clave" = afinado y a tiempo). Identificador de paquete `co.appsgratis.clave`.
- **Una sola app con cinco herramientas** (afinador, metrónomo, tono/teclado, grabadora, práctica): las referencias de pago las venden por separado o detrás de compras internas.
- **Idioma y notación siguen al teléfono la primera vez**: español y Do-Re-Mi si el teléfono está en un locale `es*`; inglés y C-D-E en cualquier otro. Después manda lo que la persona elija en Ajustes, y el cambio rehace toda la interfaz, también la barra de pestañas (`MaterialApp` cambia de `locale` y todo lo que usa `t()` depende de él).
- **Sin cuenta, sin anuncios, sin servidor.** Preajustes y setlists se exportan como JSON por la hoja de compartir y se importan desde Archivos; es la forma de pasar datos entre Android e iOS sin nube propia.
- **Quedan para después**: estrobo virtual y filtros, timbres de instrumentos reales, programa de compases con ritardando, polirritmos, caja de ritmos, modo escenario, video, análisis rítmico y de afinación sobre la grabación, Ableton Link, MIDI, recordatorios y sincronización en la nube del usuario. Nada de eso se anuncia.

## Instrumentos (G8, G9)

Los perfiles guardan, por cada **orden** de cuerdas, su altura nominal y las cuerdas que suenan a la octava. La detección de la cuerda acepta cualquiera de las alturas del orden, y con la cuerda fijada la meta es la altura del orden (o su octava) más cercana a lo que suena.

- **Tiple colombiano** (afinación en Do, del 4.º al 1.er orden): Re4, Sol4, Si4 y Mi4. El 1.er orden lleva tres Mi4 al unísono; en los órdenes 2.º a 4.º las dos cuerdas lisas van en la altura nominal y la central, entorchada, una octava más grave (Re3, Sol3, Si3).
- **Requinto colombiano** (tiple requinto): los mismos cuatro órdenes Re4-Sol4-Si4-Mi4, con las tres cuerdas de cada orden al unísono y sin entorchadas. Algunas fuentes lo ubican en Si♭ (todo un tono abajo); se eligió la afinación en Do, la misma del tiple, y quien lo afine en Si♭ puede usar la transposición o el capo.
- **Bandola andina**: seis órdenes dobles al unísono, por cuartas (Fa♯3-Si3-Mi4-La4-Re5-Sol5).
- **Requinto (guitarra)**: el perfil de seis cuerdas que antes se llamaba "Requinto" es la guitarra requinto (La2-Re3-Sol3-Do4-Mi4-La4); se renombró para no confundirlo con el colombiano.
- **Capo**: las metas y los nombres de las cuerdas suben los trastes del capo (con capo en el 2.º traste, la quinta de la guitarra es un Si2). La nota que se oye se nombra como suena: el capo no la transpone. La transposición, en cambio, sí cambia el nombre (instrumentos en Si♭, Mi♭, Fa…).

Fuentes consultadas:
- «Identificación de instrumentos musicales de cuerdas pulsadas de la región andina colombiana en solo, mediante técnicas de aprendizaje de máquina», artículo en Redalyc, pp. 183-184: https://www.redalyc.org/journal/1492/149259394012/149259394012.pdf (tiple con el 1.er orden al unísono y la cuerda central de los otros tres una octava abajo; requinto con cuatro órdenes triples al unísono; bandola con seis órdenes dobles al unísono por cuartas).
- Wikipedia en español, "Tiple colombiano": https://es.wikipedia.org/wiki/Tiple_colombiano (Re4-Sol4-Si4-Mi4 y la cuerda central una octava abajo).
- Wikipedia en inglés, "Colombian tiple" y "Requinto": https://en.wikipedia.org/wiki/Colombian_tiple, https://en.wikipedia.org/wiki/Requinto (requinto colombiano Re4-Sol4-Si4-Mi4 al unísono).
- Trabajo de grado sobre el requinto en el repositorio de la UNAD, pp. 35-36: https://repository.unad.edu.co/bitstream/handle/10596/65864/raardilac.pdf (afinaciones en Do y en Si♭).
- Ministerio de Cultura, cartillas del Plan Nacional de Música "Viva quien toca" (requinto en Si♭ o en Do).
- Wikipedia en español, "Requinto (cordófono)": https://es.wikipedia.org/wiki/Requinto_(cord%C3%B3fono) (inconsistente entre secciones; no se usó como fuente única).

## Audio

### Metrónomo

- **El metrónomo no usa el `Timer` de Dart para sonar.** Genera el audio por bloques (2048 muestras) y lo empuja a un flujo PCM de SoLoud adelantándose 180 ms al consumo. Los golpes se colocan a la muestra exacta, así que el tempo es estable aunque la interfaz se trabe.
- **Cambios en marcha (G1).** Tempo, compás, subdivisión, swing y pulsos cambiados con el metrónomo sonando rigen desde el **pulso siguiente**: el pulso en curso termina con su rejilla y el siguiente empieza exactamente donde le toca (la rejilla de pulsos no se corre). Un compás más corto que el pulso en curso abre un compás nuevo. Las pruebas miden las muestras exactas (`test/sequencer_test.dart`).
- **Valores imposibles (G11).** Todo ritmo pasa por `RhythmConfig.sanitized()`: BPM finito entre 20 y 400, 1 a 16 pulsos, figuras 2/4/8/16, subdivisiones 1/2/3/4/6, swing 0 a 1, entrenador y compases mudos acotados. El planificador además entrega como mucho 4096 golpes por llamada.
- **La animación va atada al audio que se oye.** El péndulo, los puntos del compás, el número grande, el destello y la vibración leen el audio ya consumido por el mezclador.
- **Retraso del audio (G2).** Ajustes › Retraso del audio, de 0 a 400 ms. Convención: positivo = el sonido llega tarde (salida del teléfono, audífonos Bluetooth), así que la animación y la vibración se retrasan esa misma cantidad para ir con lo que se oye. El tempo del clic no cambia. **Calibrar con toques**: suena un clic a 90 BPM y se toca un círculo al ritmo de lo que se oye; cada toque se compara con su clic en la línea de tiempo del audio consumido, se toma la mediana tras descartar los toques a más de 60 ms de ella y hacen falta al menos 8 toques, con al menos 6 (y el 60 %) parejos. El valor medido incluye la pequeña latencia del toque, que en la práctica se compensa con la tendencia a adelantarse al pulso.
- **Péndulo (M3).** Va y viene alternando con cada pulso contado desde el arranque (no con el número de pulso dentro del compás), así que no salta en 3/4, 5/8 o 7/8; su fase es la del pulso completo (inicio y duración del pulso), también con swing.
- **Número grande (G10).** Además del péndulo, el metrónomo muestra el pulso en curso como número grande con el compás; se cambia con el botón de la esquina y se recuerda.
- **Vibración (G3).** En Android, `Vibrator` con `VibrationEffect.createOneShot` a través del paquete mantenido `vibration` (45 ms y amplitud máxima en el acento, 25 ms y media en los demás pulsos, si el motor admite amplitud); usa el permiso `VIBRATE`. En iOS, el generador de impacto del sistema (`HapticFeedback.heavyImpact`/`lightImpact`). Para que se sienta también con el afinador escuchando, la sesión de grabación de iOS se abre con `allowHapticsAndSystemSoundsDuringRecording`.
- **Todos los clics se sintetizan** (tono amortiguado con armónicos, ruido filtrado, barridos): 12 familias × 3 variantes, sin muestras de terceros.
- **Conteo hablado (M13).** Usa la voz del sistema del idioma de la app: se elige una voz instalada (preferencia es-CO, es-419, es-US, es-MX, es-ES; en inglés en-US, en-GB, en-AU, en-CA; si no, cualquiera del idioma) y se comprueba que `setLanguage` la aceptó. Si el teléfono no tiene voz de ese idioma, la app lo avisa y el metrónomo suena sin conteo.
- **Lo último que se usó se recuerda (M11).** El ritmo del metrónomo se guarda (con 600 ms de espera para no escribir en cada toque) y la setlist en uso muestra la canción actual con "anterior" y "siguiente".

### Afinador

- **Detector (B1)** (`audio/pitch_detector.dart`), verificado de Do0 (16,35 Hz) a Do8 (4186 Hz):
  1. Nivel mínimo y resta de la media.
  2. Graves: filtro antialias FIR (Blackman, 63 coeficientes, corte en 2 kHz) y diezmado por 4; YIN de 15,5 a 1100 Hz.
  3. Agudos: paso bajo Butterworth de 6.º orden en 5 kHz y YIN a tasa completa de 600 a 4500 Hz (ventana de 2048).
  4. Verificación del candidato con la autocorrelación normalizada (NSDF) a tasa completa: si un subarmónico del periodo (T/2 … T/8) tiene NSDF ≥ 0,9 y no peor que T, se toma la frecuencia mayor; si un múltiplo (2T … 4T) es claramente mejor (+0,06), la menor (voces con fundamental fuerte que YIN confunde con la octava).
  5. Afinado fino: YIN con interpolación parabólica alrededor del periodo y, desde 120 Hz, refinamiento espectral (DTFT con ventana de Hann y búsqueda de sección áurea) solo si hay un pico con al menos el 5 % de la energía en la fundamental y cae a menos de 1,5 bins del valor de YIN.
  Validado primero con un port literal en Python y después en Dart (`test/pitch_detector_test.dart`): senos de Do0 a Do8 con fases y niveles al azar (< 1 cent; el peor, 0,01), violín de 10 armónicos de Sol3 a Do8, sierra, fundamental a −30 dB, guitarra y bajo con el paso alto de un micrófono, flauta, voz cantada con cinco vocales, vibrato, ruido blanco y rosa (sin notas falsas), guitarra con ruido a 20 y 10 dB, y cada cuerda de cada perfil. **Límite conocido:** en las cuerdas muy graves y rígidas del piano (inarmonía B ≈ 3·10⁻⁴ en La0) el valor sale hasta ~11 cents alto, porque los armónicos de esa cuerda están realmente desplazados; los afinadores de piano usan curvas de estiramiento que Clave no tiene, y el perfil de piano no se anuncia como afinador de piano.
- **Micrófono solo a la vista (B2).** El afinador escucha únicamente con su pestaña visible, sin otra pantalla encima (ajustes, hojas, diálogos), con la app en `resumed` y sin la grabadora usando el micrófono; en cualquier otro caso suelta la captura, y al volver la abre otra vez (si la persona no la apagó con su botón). Los cambios llegan en cola, así que una ráfaga de cambios termina en el último estado pedido.
- **Permiso (M6).** Antes del diálogo del sistema, el afinador muestra una tarjeta que explica para qué es el micrófono y el botón "Permitir micrófono"; la grabadora muestra un diálogo con la misma explicación. Si el permiso se niega, hay un botón "Abrir ajustes" (paquete `app_settings`). Al volver de los ajustes se revisa de nuevo.
- **Búfer viejo (M1).** Si dejan de llegar muestras (500 ms) o el sistema pausa la captura (llamada, Siri), se borra la lectura y se descarta el búfer: al volver se espera un búfer entero de sonido nuevo.
- **Cuerda fijada (M2).** Los cents se miden contra esa cuerda (o su octava) hasta ±200 cents y la aguja se amortigua igual que en modo automático.
- **La referencia La4 se mantiene exacta en todos los temperamentos**; la tónica del temperamento define la escala y los demás grados se desplazan respecto a La. La tónica se elige con los nombres que muestra el afinador (con la transposición del instrumento) y se guarda como altura real (M5). En la notación india se elige la nota de Sa.
- **Captura con `record` en modo flujo (PCM 16 bits, 44,1 kHz, mono)** sin control automático de ganancia ni supresión de ruido; en Android con la fuente de reconocimiento de voz, que no los aplica.

### Bordón, teclado y acordes (M4, M5)

- La **quinta del bordón es pura** (3:2 sobre la nota del bordón), sin temperamento; las demás notas siguen la referencia y el temperamento del afinador, y todo lo que suena se reafina al cambiarlos.
- **Sin aliasing**: sierra y cuadrada usan los osciladores de banda limitada de SoLoud (`fSaw`, `fSquare`) y pasan a seno donde sus armónicos se doblarían (sierra sobre 1500 Hz, cuadrada sobre 1000 Hz, triángulo desde 3000 Hz).
- **La ganancia se reparte** entre las voces que suenan (la quinta pesa 0,7): bordón, quinta, teclas y acorde juntos nunca suenan más fuerte que el bordón solo, así que no saturan.
- Notas, teclas y acordes se muestran en **altura escrita** (con la transposición, como el afinador) y suenan en altura real.
- **Teclado**: muestra una ventana de teclas blancas enteras de al menos 48 dp (en un teléfono de 360 dp cabe una octava); las flechas la mueven una octava o, en pantallas más angostas, la ventana menos una tecla, para que ninguna negra quede siempre partida en el borde. Cada tecla tiene nombre para el lector de pantalla y un área de al menos 48 × 48 dp, también las negras; con el lector, tocar una tecla la hace sonar un momento.

### Sesión de audio (M9, G4)

Pensada para tocar encima de la música de otra app (una pista de acompañamiento): nada de Clave detiene esa música.

- **iOS, sin micrófono:** categoría `playback` con `mixWithOthers`, puesta por la app al arrancar (`AudioPlayer.global.setAudioContext`). SoLoud (flutter_soloud ≥ 5.1) deja la sesión a la app. El metrónomo, el bordón y las tomas suenan con el interruptor de silencio puesto y siguen con la pantalla bloqueada (`UIBackgroundModes: audio`).
- **iOS, con el micrófono abierto** (afinador o grabadora): `record` pasa a `playAndRecord` con `defaultToSpeaker`, `allowBluetoothA2DP`, `mixWithOthers` y `allowHapticsAndSystemSoundsDuringRecording`, **sin `allowBluetooth`**: con audífonos Bluetooth el sonido sigue en A2DP con calidad completa (no baja a HFP, "calidad de llamada") y se escucha el micrófono del teléfono. Al soltar el micrófono la app vuelve a `playback` (en `playAndRecord` el altavoz suena más bajo en varios iPhone).
- **Android:** no se pide el foco de audio: SoLoud no lo pide, las tomas se reproducen con `AndroidAudioFocus.none` y la captura usa `AudioInterruptionMode.none` y `manageBluetooth: false` (sin enlace SCO, que bajaría el sonido a calidad de llamada).
- **Interrupciones:** en iOS una llamada o Siri pausan la captura; el afinador lo muestra y se reanuda solo, y una toma en curso se cierra y se guarda con lo grabado (avisando).
- **Segundo plano en Android:** la v1 no tiene un servicio en primer plano (exige otro permiso y una notificación permanente). Por eso, al salir de la app se detienen de forma explícita el metrónomo, el bordón y el teclado, y una toma en curso se cierra y se guarda; al volver se avisa. En vez de grabar silencio o cortarse a medias, el comportamiento es predecible. "Mantener la pantalla encendida" (por defecto activo) cubre el afinador, el metrónomo y el tono, y la grabadora mientras graba.

## Grabadora (M7)

- La duración es el tiempo grabado sin pausas; si el sistema pausa la toma (llamada, Siri), la toma se cierra y se guarda.
- Mientras se graba queda un marcador (`recordings/pending.json`) con el archivo, la hora, la carpeta y el instrumento. Si la app se cierra de golpe, al abrirla se rescata la toma (y cualquier archivo de la carpeta que no esté en la lista) como "Toma N" marcada como rescatada; los archivos vacíos se borran. La duración de una toma rescatada se completa al reproducirla. Límite: una toma AAC cortada de golpe puede no reproducirse, porque el contenedor M4A se cierra al final de la grabación; WAV y FLAC se leen hasta donde llegaron. Si no se puede reproducir, la app lo dice y la toma se puede borrar.
- "Toma N" usa un contador guardado que nunca retrocede: borrar tomas no repite números.
- Compartir una toma prepara una copia con su nombre (sin caracteres que los sistemas de archivos no aceptan) en `export/`, que se vacía al abrir la app; la hoja de compartir sale del botón tocado (necesario en iPad y en iOS 26) y un error se avisa (B4).
- Formatos por idioma: "44,1 kHz" en español y "44.1 kHz" en inglés; fecha y hora con el formato del idioma de la app.

## Datos y práctica

- **Registro por intervalos (B3, M12).** Cada herramienta abre y cierra intervalos: el metrónomo mientras corre; el bordón, el teclado y los acordes mientras suenan; la grabadora mientras graba; el afinador mientras oye un **tono estable de instrumento** (claridad ≥ 0,85, al menos 400 ms en la misma nota, sin envolvente de golpe y que no sea un sonido de la propia app: las alturas del clic que suena y las del bordón, también a la octava, no cuentan). Un intervalo del afinador termina en el último tono estable si pasan 2 s sin otro.
  - Dos intervalos de la misma herramienta separados por menos de 2 s se unen (las notas cortas del teclado forman un solo intervalo); un instante suelto de menos de 1 s no se guarda.
  - El total de un día es la **unión** de los intervalos (dos herramientas a la vez no cuentan doble); el desglose por herramienta suma el tiempo de cada una. Un intervalo que cruza la medianoche se reparte entre los dos días, y las fechas se calculan por calendario (no restando 24 h), así que el horario de verano no las corre.
  - Lo que está en curso cuenta en la pantalla Práctica, que se actualiza cada segundo con la pestaña a la vista, y en los desgloses. Se guarda cada 30 s y al pasar a segundo plano; si el sistema cierra la app, se pierde como mucho ese tramo.
  - Se conserva un año de historial.
- **Racha (G10).** Cuenta los días seguidos con al menos 5 minutos. Hoy no la rompe mientras el día no termina, y se puede descansar **un día de cada siete** sin perderla (dos descansos dentro de la racha deben estar a siete días o más, y nunca dos días seguidos). La regla está escrita en la pantalla Práctica.
- **Archivos JSON con escritura atómica (M8).** Cada ruta tiene su cola de escrituras; cada escritura va a un temporal con nombre único y se renombra encima del original, que antes se copia a `.bak`; el original nunca se borra antes de tener el nuevo. Un JSON dañado no se pisa: se aparta como `<archivo>.danado-<fecha>`, se recupera el `.bak` si sirve y la app avisa al abrir.
- **Todo lo que llega de un archivo se valida (G11):** preajustes, setlists, grabaciones, práctica y ajustes guardados pasan por lectores que comprueban el tipo y acotan cada valor (textos con largo máximo, identificadores con formato, rutas de grabación dentro de su carpeta, intervalos de práctica coherentes). Un archivo importado que no es de Clave se rechaza con un aviso.
- **Ajustes (M10).** Solo se escriben las claves que cambiaron, y solo el idioma y el tema rehacen la app entera; el resto avisa a las pantallas que los usan.
- **Borrar se puede deshacer.** Borrar un preajuste o una setlist no pide confirmación: se borra al momento y un aviso ofrece "Deshacer", que lo devuelve a su lugar (el preajuste, también a sus setlists; la setlist, también como la activa del metrónomo si lo era). Una toma de la grabadora sí pide confirmación, porque su audio se borra del disco.

## Accesibilidad (G7)

- Todos los botones de ícono tienen nombre (también los de reproducir, cerrar, octavas, pulsos y tempo); los botones con semántica propia conservan su acción de tocar.
- Los deslizadores leen su valor con unidades (BPM, Hz, ms, cents, %).
- El afinador anuncia en una región en vivo la nota y si está afinado, alto o bajo, solo al cambiar de nota o al entrar o salir de "afinado", con al menos 1,1 s entre avisos.
- Pulsos del metrónomo de 48 × 56 dp, cuerdas del afinador y teclas del teclado de al menos 48 dp.
- Colores del tema claro elegidos para contraste de 4,5:1 en texto y 3:1 en indicadores (verde `#146C2E`, ámbar `#7A4F00`/`#8B5000`, rojo `#A8231B`); en el tema oscuro se usan tonos claros de la marca.
- Las pruebas recorren cada pantalla principal en los dos temas con `androidTapTargetGuideline`, `iOSTapTargetGuideline`, `labeledTapTargetGuideline` y `textContrastGuideline`, y las pantallas en 360 × 640 y 375 × 667 con texto × 1 y × 1,3.

## Técnica

- **Flutter con `flutter_soloud` 5.2, `record` 7.1, `audioplayers` 6, `flutter_tts`, `share_plus` 13.3.1 o superior, `file_selector`, `wakelock_plus` 1.8, `vibration` 3.2, `app_settings` 9, `shared_preferences`, `path_provider` y `clock`.**
- **Versiones mínimas (M14).** El `environment` declara Dart ≥ 3.13 y Flutter ≥ 3.47: es lo que la CI compila y prueba (Flutter 3.47.7 con Dart 3.13.5); las dependencias exigen al menos Flutter 3.44 / Dart 3.12 (`wakelock_plus` 1.8) y `flutter_soloud` usa los "native assets" de Flutter.
- **Motor de audio detrás de una interfaz (`AudioEngine`)**, y micrófono, captura de tomas, vibración y acciones del sistema (compartir, elegir archivo, abrir ajustes) detrás de las suyas: las pruebas usan dobles y cablean los servicios igual que la app (`core/service_links.dart`).
- **Sin paquetes GPL** en ninguna plataforma.
- **CI**: análisis, pruebas, APK y AAB de Android, iOS sin firma y capturas de tienda; carpetas de plataforma generadas con `flutter create` y ajustadas con `tools/patch_platforms.py` (permisos `RECORD_AUDIO` y `VIBRATE`, texto de uso del micrófono, modo audio en segundo plano, minSdk 24).

## Pendiente de decidir con el proyecto

- Nombre definitivo e ícono ilustrado.
- Un servicio en primer plano en Android (con `audio_service`) para que el metrónomo y el bordón sigan con la app en segundo plano.
- Si una versión futura añade Ableton Link solo en iOS (LinkKit gratuito) o también en Android (licencia de Ableton o GPL en una compilación separada).
