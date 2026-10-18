# Plata: respuestas para Google Play Console y App Store Connect

Respuestas verificadas contra el código de la versión 1.0.0 (build 1). Si una
versión nueva cambia permisos, red o datos, se revisa este archivo junto con la
política de privacidad (`assets/legal/privacy_*.md`).

## Datos de la ficha

| Campo | Valor |
| --- | --- |
| Paquete / Bundle ID | `co.appsgratis.plata` |
| Categoría | Google Play: Finanzas · App Store: Finanzas (secundaria: Productividad) |
| Idiomas de la ficha | Google Play: es-419 y en-US · App Store: es-MX y en-US |
| Política de privacidad | es: `https://github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis/blob/main/apps/plata/assets/legal/privacy_es.md` · en: `.../privacy_en.md` |
| Soporte | `https://github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis/blob/main/docs/SOPORTE.md` |
| Precio | Gratis, sin compras dentro de la app |

## Google Play Console

**Acceso a la app:** toda la funcionalidad está disponible sin acceso especial (no hay cuentas ni inicio de sesión).

**Anuncios:** la app no contiene anuncios.

**Clasificación de contenido (cuestionario IARC):** categoría "Utilidades, productividad, comunicación u otra". Violencia, sexo, lenguaje, sustancias, apuestas, interacción entre usuarios, compras digitales, ubicación compartida y acceso libre a internet: **No** en todo. Resultado esperado: PEGI 3 / ESRB Everyone / Todos.

**Público objetivo:** 18 años o más. La app no está diseñada para niños ni les resulta atractiva (finanzas personales).

**Declaración de funciones financieras:** "Servicios de soporte › Otro", con la descripción: *"Registro personal de gastos, ingresos y presupuestos que el usuario lleva en su teléfono. No mueve dinero, no se conecta con bancos, no ofrece créditos, inversiones ni asesoría."* No aplica ninguna licencia porque no hay préstamos. (Alternativa defendible: "Mi app no ofrece funciones financieras"; se eligió declarar "Otro" para no ocultar que es una app de finanzas.)

**Apps de salud, noticias, COVID-19, gobierno:** No.

**Seguridad de los datos (Data safety):**

- ¿Recopila o comparte alguno de los tipos de datos requeridos? **No.**
- Motivo, para la revisión: los datos financieros, las fotos de recibos y las notificaciones bancarias se procesan y guardan solo en el teléfono, cifrados (los avisos que llegan con la app cerrada esperan cifrados con AES-GCM y una llave del Keystore, y se borran al apagar la lectura). La única conexión descarga tasas de cambio de datos.gov.co, api.frankfurter.dev y open.er-api.com, y esas consultas no llevan datos del usuario. Las copias y exportaciones salen del teléfono solo cuando el usuario las comparte con la hoja del sistema (transferencia iniciada por el usuario, que Google no cuenta como compartir).

**Permisos y accesos especiales:**

| Permiso | Uso | Declaración |
| --- | --- | --- |
| `INTERNET` | Tasas de cambio | — |
| `POST_NOTIFICATIONS` | Recordatorios de anotar y de pagos | — |
| `RECEIVE_BOOT_COMPLETED` | Volver a programar los recordatorios tras reiniciar | — |
| `USE_BIOMETRIC` / `USE_FINGERPRINT` | Desbloqueo con huella o rostro | — |
| `VIBRATE` | Vibración de las notificaciones | — |
| `BIND_NOTIFICATION_LISTENER_SERVICE` (acceso a notificaciones, opcional) | Leer avisos de las 11 apps de bancos y billeteras de la lista para sugerir movimientos | No hay formulario propio; la app muestra un **aviso destacado** antes de abrir el ajuste (Más › Avisos bancarios). Al apagar la lectura en la app, el servicio deja de leer aunque el permiso siga concedido, y la app ofrece abrir el ajuste para quitarlo |

No usa alarmas exactas, ubicación, contactos, SMS, ni `READ_MEDIA_*` (las fotos de recibos se eligen con el selector de fotos del sistema). Con clave de acceso, la ventana usa `FLAG_SECURE` (no requiere permiso). La CI verifica la lista de permisos en cada compilación (`tools/store/android.json`).

**Copias de seguridad de Android:** `allowBackup=false` y reglas de extracción que excluyen todos los datos (la llave del Keystore no viaja; la CI lo verifica en el manifiesto compilado).

## App Store Connect

**Privacidad de la app:** "Datos no recopilados" (Data Not Collected), por las mismas razones de arriba. El manifiesto `ios/Runner/PrivacyInfo.xcprivacy` declara: sin rastreo, sin dominios de rastreo, sin tipos de datos recopilados y el uso de UserDefaults con el motivo CA92.1.

**Clasificación por edad (cuestionario de 2025):** todas las preguntas en "Ninguno"/"No" (sin violencia, contenido sexual, apuestas, contenido médico, acceso web libre, contenido generado por usuarios ni chats). Resultado esperado: 4+.

**Cifrado (exportación):** el Info.plist declara `ITSAppUsesNonExemptEncryption = YES` porque la app cifra sus propios datos con ChaCha20-Poly1305 (algoritmo estándar, distinto del cifrado del sistema). Respuestas en App Store Connect:

1. ¿Usa cifrado? **Sí.**
2. ¿Cumple alguna exención de la Categoría 5, Parte 2 del EAR? **No** (criterio conservador).
3. ¿Implementa algoritmos de cifrado propietarios o no aceptados como estándar? **No.**
4. ¿Implementa algoritmos estándar en vez de, o además de, los del sistema operativo de Apple? **Sí.**
5. ¿Se distribuye en Francia? Si se marca Francia, Apple pide la declaración de importación de cifrado de la ANSSI. **Decisión:** en la primera versión Plata se publica sin Francia; se puede agregar después presentando esa declaración.

Desde 2021, el software de mercado masivo con cifrado estándar (5D992.c) no necesita el informe anual de autoclasificación ante el BIS de EE. UU.

**Notas para la revisión:** `fastlane/metadata/ios/review_information/notes.txt` (en inglés). El nombre, el teléfono y el correo del contacto de revisión los llena el titular de la cuenta en App Store Connect.

**Funciones solo de Android:** los avisos bancarios no existen en iOS; la ficha de la App Store no los menciona y la app no los muestra en iPhone.

## Fichas y textos

- **Tarjetas de crédito:** la app, la guía, el recordatorio y las fichas dicen que el estado de cuenta es *capital estimado, sin intereses ni cuota de manejo* y remiten al extracto del banco; ningún texto promete "cuánto pagar".
- **Bancos:** la ficha de Google Play no usa marcas de bancos (dice cuántas apps se leen y que Plata no está afiliada a ningún banco); la app y la política nombran las 11 apps porque el usuario elige con ellas el banco de cada cuenta. La lista está comprobada en Google Play (ver `docs/DECISIONES.md`).
- **Tasas:** ExchangeRate-API exige atribución en su acceso abierto: la pantalla de monedas muestra «Rates By Exchange Rate API» con enlace a exchangerate-api.com cuando alguna tasa viene de ahí.
- **Llave en archivo:** la ficha de Google Play aclara que, si el teléfono no ofrece el Keystore, la llave queda en la carpeta privada de la app; la política dice lo mismo.
- **Contacto:** la política remite a la página de soporte (`docs/SOPORTE.md`), que no depende del correo de la ficha.
