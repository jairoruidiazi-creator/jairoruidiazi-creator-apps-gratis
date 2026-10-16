# Clave: decisiones de diseño y producto

Registro de las decisiones tomadas durante el desarrollo, con su razón.

## Producto

- **Nombre de trabajo: Clave.** Corto, en español, con doble sentido musical (la clave como figura rítmica e instrumento, y "estar en clave" = afinado y a tiempo). Identificador de paquete `co.appsgratis.clave`.
- **Una sola app con cinco herramientas** (afinador, metrónomo, tono/teclado, grabadora, práctica), como propone el estudio: las referencias de pago las venden por separado o detrás de compras internas.
- **Español y solfeo (Do-Re-Mi) por defecto**, con inglés y las notaciones inglesa, alemana e india a un toque. Los instrumentos colombianos (tiple, bandola andina, cuatro, requinto) van en el mismo selector que la guitarra, no en una sección aparte.
- **Sin cuenta, sin anuncios, sin servidor.** Preajustes y setlists se exportan como JSON por la hoja de compartir y se importan desde Archivos; es la forma de pasar datos entre Android e iOS sin nube propia.
- **La v1 incluye funciones que el estudio marcaba como v1.1** porque salieron baratas con la arquitectura elegida: reproducción lenta de las grabaciones (0,5–1,5x) y vibración por pulso. Quedan para después: estrobo virtual y filtros, timbres de instrumentos reales, programa de compases con ritardando, polirritmos, caja de ritmos, modo escenario, video, análisis rítmico y de afinación sobre la grabación, FFT, Ableton Link, MIDI, relojes y sincronización en la nube del usuario.

## Audio

- **El metrónomo no usa el `Timer` de Dart para sonar.** Genera el audio por bloques (2048 muestras) y lo empuja a un flujo PCM de SoLoud (`BufferingType.released`) adelantándose 180 ms al consumo. Los golpes se colocan a la muestra exacta, así que el tempo es estable aunque la interfaz se trabe.
- **La animación va atada al audio consumido**, no a un reloj aparte: el péndulo, los puntos del compás, el destello y la vibración leen `getStreamTimeConsumed` del flujo. Un ajuste de **desfase visual** (−200 a +400 ms) compensa la latencia de salida y los audífonos Bluetooth, como pide el estudio ("calibración manual del desfase").
- **Los cambios de tempo o compás en caliente se aplican desde la siguiente subdivisión**; el entrenador y los compases mudos se calculan en el mismo planificador (`audio/sequencer.dart`).
- **Todos los clics se sintetizan** (tono amortiguado con armónicos, ruido filtrado, barridos): 12 familias × 3 variantes. Sin muestras descargadas ni de terceros, y la app pesa menos.
- **Afinador con YIN propio en dos pasos** (`audio/pitch_detector.dart`): primero sobre la señal diezmada por 4 (así un búfer de 8192 muestras cubre varios periodos de 16 Hz) y luego afinado en una banda estrecha sobre la señal completa, con interpolación parabólica. Error menor de 1 cent en senos puros de Do1 a La6 (prueba `music_test.dart`). No se implementó MPM además de YIN: la segunda pasada estrecha cumple el mismo papel con menos código.
- **Cuerda fijada**: cuando el usuario fija una cuerda, los cents se miden contra esa cuerda hasta ±200 cents y la escala del medidor cambia, para guiar el giro de la clavija aunque la nota esté lejos.
- **La referencia La4 se mantiene exacta en todos los temperamentos**; la tónica del temperamento define la escala y los demás grados se desplazan respecto a La. Es la convención de TonalEnergy y la que menos sorprende al afinar con otros instrumentos.
- **Captura con `record` en modo flujo (PCM 16 bits, 44,1 kHz, mono)** sin control automático de ganancia ni supresión de ruido, que distorsionan la medición. El micrófono se pide solo al abrir el afinador o grabar, y el afinador lo suelta mientras se graba o se reproduce.
- **Bordón y teclado con los osciladores de SoLoud** (`loadWaveform` + `setWaveformFreq`), una fuente por voz, con entrada y salida suaves para evitar chasquidos.
- **Segundo plano**: en iOS se declara `UIBackgroundModes: audio` para que el metrónomo siga con la pantalla bloqueada; en Android la v1 mantiene la pantalla encendida en el afinador y el metrónomo (`wakelock_plus`) en lugar de un servicio en primer plano, que queda para la v1.1 junto con `audio_service`.

## Datos y práctica

- **Registro automático de práctica**: cada herramienta "toca" el registro mientras está en uso (afinador con señal, metrónomo sonando, tono activo, grabadora grabando). Una sesión se cierra tras 90 segundos sin actividad y se guarda si duró al menos 10 segundos. No hay botón de "empezar práctica": lo que se usa, cuenta.
- **Racha sin castigo**: cuenta días seguidos con 5 minutos o más, y descansar un día solo la reinicia, no quita nada. No hay notificaciones en la v1 (evitan un permiso más y el riesgo de molestar); el recordatorio diario entra en la v1.1.
- **Archivos JSON locales con escritura atómica** (igual que en Pilas) para preajustes, setlists, grabaciones y práctica; las grabaciones se guardan en la carpeta de documentos de la app.

## Técnica

- **Flutter con `flutter_soloud` 5.2, `record` 7.2, `audioplayers`, `flutter_tts`, `share_plus`, `file_selector`, `wakelock_plus`, `shared_preferences`, `path_provider`.** `flutter_soloud` compila su parte nativa con el sistema de "native assets" de Flutter (SDK ≥ 3.11 / Flutter ≥ 3.41), por eso el `environment` del `pubspec` es más nuevo que el de Pilas.
- **Motor de audio detrás de una interfaz (`AudioEngine`)** con una implementación muda para las pruebas de widgets y para equipos sin audio.
- **Sin paquetes GPL** en ninguna plataforma (descartados `mic_stream` y `f_link`), como pide el estudio.
- **CI igual a la de Pilas**: análisis, pruebas, APK y compilación de iOS sin firma; carpetas de plataforma generadas con `flutter create` y ajustadas con `tools/patch_platforms.py` (permiso de micrófono, texto de uso, modo audio en segundo plano, minSdk 24).

## Pendiente de decidir con el proyecto

- Nombre definitivo e ícono ilustrado.
- Si la v1.1 añade Ableton Link solo en iOS (LinkKit gratuito) o también en Android (licencia de Ableton o GPL en una compilación separada).
