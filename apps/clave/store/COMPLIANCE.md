# Clave: respuestas para Google Play Console y App Store Connect

Respuestas verificadas contra el código de la versión 1.0.0 (build 1).

## Datos de la ficha

| Campo | Valor |
| --- | --- |
| Paquete / Bundle ID | `co.appsgratis.clave` |
| Categoría | Google Play: Música y audio · App Store: Música (secundaria: Educación) |
| Idiomas de la ficha | Google Play: es-419 y en-US · App Store: es-MX y en-US |
| Política de privacidad | es: `https://github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis/blob/main/apps/clave/assets/legal/privacy_es.md` · en: `.../privacy_en.md` |
| Soporte | `https://github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis/blob/main/docs/SOPORTE.md` |
| Precio | Gratis, sin compras dentro de la app |

## Google Play Console

**Acceso a la app:** toda la funcionalidad está disponible sin acceso especial.

**Anuncios:** la app no contiene anuncios.

**Público objetivo:** 13 años o más (13-15, 16-17 y 18+). La app no está dirigida a niños; quien practica música de menor edad puede usarla con su familia, pero no se inscribe en Diseñada para familias.

**Clasificación de contenido (IARC):** categoría "Utilidades, productividad, comunicación u otra". Todas las preguntas de contenido: **No**. Interacción entre usuarios, compras digitales, ubicación y acceso a internet: **No**. Resultado esperado: PEGI 3 / ESRB Everyone / Todos.

**Funciones financieras:** "Mi app no ofrece funciones financieras".

**Apps de salud, noticias, COVID-19, gobierno:** No.

**Seguridad de los datos (Data safety):** ¿Recopila o comparte datos? **No.** El sonido del micrófono se analiza en tiempo real en el teléfono y no se guarda ni se envía; las grabaciones quedan en el almacenamiento privado de la app y solo salen cuando el usuario las comparte con la hoja del sistema. La app no usa internet (no declara el permiso `INTERNET`).

**Segundo plano en Android:** no hay servicio en primer plano; al salir de la app se detienen el metrónomo y el bordón, y una toma en curso se cierra y se guarda.

**Permisos:**

| Permiso | Uso |
| --- | --- |
| `RECORD_AUDIO` | Afinador (solo con su pestaña a la vista y la app al frente) y grabadora (mientras graba). Se pide al usarlos, con una explicación previa; sin él el resto funciona |
| `VIBRATE` | Pulso del metrónomo en vibración, si se activa (paquete `vibration`, `VibrationEffect`) |

## App Store Connect

**Privacidad de la app:** "Datos no recopilados". `PrivacyInfo.xcprivacy`: sin rastreo, sin dominios, sin datos recopilados, UserDefaults con motivo CA92.1.

**Modos en segundo plano:** `audio`, para que el metrónomo, el bordón y una toma en curso sigan con la pantalla bloqueada. La nota para la revisión lo explica.

**Clasificación por edad:** todas las preguntas en "Ninguno"/"No". Resultado esperado: 4+.

**Cifrado (exportación):** `ITSAppUsesNonExemptEncryption = NO`: no cifra datos ni usa la red.

**Notas para la revisión:** `fastlane/metadata/ios/review_information/notes.txt`.
