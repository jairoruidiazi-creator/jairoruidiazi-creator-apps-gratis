# Pilas: respuestas para Google Play Console y App Store Connect

Respuestas verificadas contra el código de la versión 1.0.0 (build 1). Pilas es
una app para niños: cualquier cambio de permisos, red, anuncios o datos exige
revisar este archivo, la política de privacidad y las reglas de familias de
las dos tiendas antes de publicar.

## Datos de la ficha

| Campo | Valor |
| --- | --- |
| Paquete / Bundle ID | `co.appsgratis.pilas` |
| Categoría | Google Play: Educación · App Store: Educación (secundaria: Juegos), categoría Niños |
| Idioma de la ficha y de la app | Español (Google Play es-419, App Store es-MX). La app no tiene inglés todavía, así que no se publica ficha en inglés para no prometer un idioma que no trae. |
| Política de privacidad | `https://github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis/blob/main/apps/pilas/assets/legal/privacy_es.md` (también dentro de la app, tras la puerta parental) |
| Soporte | `https://github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis/blob/main/docs/SOPORTE.md` |
| Precio | Gratis, sin compras dentro de la app |

## Google Play Console

**Acceso a la app:** toda la funcionalidad está disponible sin acceso especial. Las zonas de adultos piden resolver una multiplicación (puerta parental), no una cuenta.

**Anuncios:** la app no contiene anuncios.

**Público objetivo y contenido:** franjas "5 años o menos", "6 a 8 años" y "9 a 12 años". Al incluir niños, la app entra al programa **Diseñada para familias** y debe cumplir la política de Familias:

| Requisito de Familias | Cómo lo cumple Pilas |
| --- | --- |
| Sin anuncios o solo SDK de anuncios certificados | No hay anuncios ni SDK de anuncios |
| No recopilar identificadores ni ubicación de niños | No usa internet, ni ubicación, ni el ID de publicidad; la CI prohíbe `AD_ID`, ubicación, cámara, micrófono, contactos y estado del teléfono (`tools/store/android.json`) |
| Política de privacidad y Data safety coherentes | Ver abajo |
| Contenido apropiado para niños | Contenido propio y Twemoji; sin enlaces externos, chats ni contenido de usuarios |
| Funciones para adultos detrás de una puerta | Ajustes, informes, modo docente, compartir, más tiempo y la política de privacidad piden la puerta parental |

**Clasificación de contenido (IARC):** categoría "Juego" o "Educación" según el formulario. Violencia, miedo, sexo, lenguaje, sustancias, apuestas, interacción entre usuarios, compras digitales, ubicación compartida y acceso a internet: **No**. Resultado esperado: PEGI 3 / ESRB Everyone / Todos.

**Funciones financieras:** "Mi app no ofrece funciones financieras" (el juego "La tienda" usa dinero de juguete).

**Apps de salud, noticias, COVID-19, gobierno:** No.

**Seguridad de los datos (Data safety):** ¿Recopila o comparte datos? **No.** Perfiles, avance, dibujos e informes se guardan solo en el dispositivo; no hay conexión a internet. Lo que un adulto comparte desde la hoja del sistema es una transferencia iniciada por el usuario.

**Permisos:** ninguno (la CI exige una lista vacía). Las voces son las del sistema (`TextToSpeech` declarado en `<queries>`).

**Programa "Aprobada por docentes" (opcional):** se puede postular después del lanzamiento desde la sección Familias de la consola.

## App Store Connect

**Categoría Niños (Made for Kids):** sí, franja de edad **6 a 8 años**. Pilas cubre de 3 a 11 años en cuatro tramos; la App Store permite elegir una sola franja y 6 a 8 es el centro del rango. Requisitos de la guía 1.3 y 5.1.4:

- Sin enlaces fuera de la app ni oportunidades de compra para los niños: no hay enlaces; compartir y la política están tras la puerta parental.
- Sin analítica ni publicidad de terceros: ninguno.
- La puerta parental pide escribir el resultado de una multiplicación de dos cifras por una, que un niño pequeño no resuelve.

**Privacidad de la app:** "Datos no recopilados". `PrivacyInfo.xcprivacy`: sin rastreo, sin dominios, sin datos recopilados, UserDefaults con motivo CA92.1.

**Clasificación por edad:** todas las preguntas en "Ninguno"/"No". Resultado: 4+ (obligatorio en la categoría Niños).

**Cifrado (exportación):** `ITSAppUsesNonExemptEncryption = NO`: la app no cifra datos ni se conecta a internet.

**Notas para la revisión:** `fastlane/metadata/ios/review_information/notes.txt`.
