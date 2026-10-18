# Rutinas: respuestas para Google Play Console y App Store Connect

Respuestas verificadas contra el código de la versión 1.0.0 (build 1). Si una
versión nueva cambia permisos, red o datos, se revisa este archivo junto con la
política de privacidad (`assets/legal/privacy_*.md`).

## Datos de la ficha

| Campo | Valor |
| --- | --- |
| Paquete / Bundle ID | `co.appsgratis.rutinas` |
| Categoría | Google Play: Productividad · App Store: Productividad (secundaria: Salud y forma física) |
| Idiomas de la ficha | Google Play: es-419 y en-US · App Store: es-MX y en-US |
| Política de privacidad | es: `https://github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis/blob/main/apps/rutinas/assets/legal/privacy_es.md` · en: `.../privacy_en.md` |
| Soporte | `https://github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis/blob/main/docs/SOPORTE.md` |
| Precio | Gratis, sin compras dentro de la app |

## Google Play Console

**Acceso a la app:** toda la funcionalidad está disponible sin acceso especial (no hay cuentas ni inicio de sesión).

**Anuncios:** la app no contiene anuncios.

**Público objetivo:** 13 años o más (13-15, 16-17 y 18+). La app es una herramienta de hábitos, recordatorios y entrenamiento para público general; no está dirigida a niños ni se inscribe en Diseñada para familias.

**Clasificación de contenido (cuestionario IARC):** categoría "Utilidades, productividad, comunicación u otra". Violencia, sexo, lenguaje, sustancias, apuestas, interacción entre usuarios, compras digitales, ubicación compartida y acceso libre a internet: **No** en todo. Resultado esperado: PEGI 3 / ESRB Everyone / Todos.

**Funciones financieras:** "Mi app no ofrece funciones financieras".

**Apps de salud:** se declara la función **"Actividad física y fitness"**, por el temporizador de entrenamientos por intervalos (HIIT, Tabata, circuitos). La app no lee sensores ni Health Connect, no registra datos médicos y no hace afirmaciones de salud. Noticias, COVID-19 y gobierno: No.

**Seguridad de los datos (Data safety):**

- ¿Recopila o comparte alguno de los tipos de datos requeridos? **No.**
- Motivo, para la revisión: hábitos, registros, recordatorios, entrenamientos y ajustes se guardan solo en el almacenamiento privado de la app. La app no tiene permiso de internet (la CI verifica que el APK no declare `INTERNET`). La copia de seguridad sale del teléfono solo cuando el usuario la comparte con la hoja del sistema (transferencia iniciada por el usuario, que Google no cuenta como compartir). La copia automática de Android, si el usuario la tiene activa, va a su cuenta de Google y no llega al desarrollador.

**Permisos:**

| Permiso | Uso | Declaración |
| --- | --- | --- |
| `POST_NOTIFICATIONS` | Avisos de hábitos y recordatorios, cuentas regresivas y cambios de intervalo con la pantalla apagada (se pide la primera vez que hace falta) | — |
| `SCHEDULE_EXACT_ALARM` | Que esos avisos lleguen a la hora exacta con la pantalla apagada. Desde Android 14 está negado de entrada: el usuario lo concede en el ajuste del sistema «Alarmas y recordatorios», que la app abre desde Ajustes › Permisos, donde también muestra si está concedido. Sin él se programan alarmas inexactas y la app lo explica | No hay formulario: el formulario de alarmas exactas es para `USE_EXACT_ALARM`, que la app no usa |
| `RECEIVE_BOOT_COMPLETED` | Volver a programar los avisos al reiniciar el teléfono o actualizar la app | — |
| `VIBRATE` | Vibración de los avisos y de los cambios de intervalo | — |

No usa servicios en primer plano, intents de pantalla completa, ubicación, cámara, micrófono, contactos ni el identificador de publicidad. El manifiesto consulta el servicio de voz del sistema (`TTS_SERVICE` en `<queries>`) para anunciar los intervalos. La CI verifica la lista de permisos en cada compilación (`tools/store/android.json`).

## App Store Connect

**Privacidad de la app:** "Datos no recopilados" (Data Not Collected), por las mismas razones de arriba. El manifiesto `ios/Runner/PrivacyInfo.xcprivacy` declara: sin rastreo, sin dominios de rastreo, sin tipos de datos recopilados y el uso de UserDefaults con el motivo CA92.1.

**Modos en segundo plano:** ninguno. Con la pantalla bloqueada, el temporizador no corre en segundo plano: su estado sale del reloj y los cambios de intervalo que faltan se programan como notificaciones locales con sonido, que se cancelan al volver a la app.

**Notificaciones:** se piden con alerta y sonido (sin globos de número). Los sonidos propios se copian a `Library/Sounds` para que las notificaciones los usen.

**Clasificación por edad:** todas las preguntas en "Ninguno"/"No" (sin violencia, contenido sexual, apuestas, contenido médico, acceso web libre, contenido generado por usuarios ni chats). Resultado esperado: 4+.

**Cifrado (exportación):** `ITSAppUsesNonExemptEncryption = NO`: la app no cifra datos ni usa la red.

**Notas para la revisión:** `fastlane/metadata/ios/review_information/notes.txt` (en inglés). El nombre, el teléfono y el correo del contacto de revisión los llena el titular de la cuenta en App Store Connect.
