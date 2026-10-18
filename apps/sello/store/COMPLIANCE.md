# Sello: respuestas para Google Play Console y App Store Connect

Respuestas verificadas contra el código de la versión 1.0.0 (build 1).

## Datos de la ficha

| Campo | Valor |
| --- | --- |
| Paquete / Bundle ID | `co.appsgratis.sello` |
| Categoría | Google Play: Fotografía · App Store: Foto y video (secundaria: Productividad) |
| Idiomas de la ficha | Google Play: es-419 y en-US · App Store: es-MX y en-US |
| Política de privacidad | es: `https://github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis/blob/main/apps/sello/assets/legal/privacy_es.md` · en: `.../privacy_en.md` |
| Soporte | `https://github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis/blob/main/docs/SOPORTE.md` |
| Precio | Gratis, sin compras dentro de la app |

## Google Play Console

**Acceso a la app:** toda la funcionalidad está disponible sin acceso especial.

**Anuncios:** la app no contiene anuncios.

**Público objetivo:** 18 años o más (herramienta de trabajo de campo).

**Clasificación de contenido (IARC):** categoría "Utilidades, productividad, comunicación u otra". Contenido: **No** en todo. ¿Comparte la ubicación del usuario con otros usuarios? **No** (las coordenadas solo salen en las fotos que el usuario comparte). Interacción entre usuarios y compras: **No**. Resultado esperado: PEGI 3 / ESRB Everyone / Todos.

**Funciones financieras:** "Mi app no ofrece funciones financieras".

**Apps de salud, noticias, COVID-19, gobierno:** No.

**Seguridad de los datos (Data safety):** criterio conservador, porque dos funciones opcionales envían coordenadas a terceros.

| Pregunta | Respuesta |
| --- | --- |
| ¿Recopila o comparte datos? | **Sí, recopila** |
| Tipo de dato | Ubicación › **Ubicación precisa** y **Ubicación aproximada** |
| ¿Se comparte? | **No** (va a los servicios que prestan la función: el geocodificador del sistema y los servidores de teselas de OpenStreetMap; no se vende ni se usa para otra cosa) |
| ¿Se procesa de forma efímera? | No (los terceros pueden guardar registros de las peticiones) |
| ¿Es obligatoria? | **No, opcional:** Ajustes › Dirección aproximada y Ajustes › Mapa en línea se pueden apagar |
| Finalidad | Funcionalidad de la app |
| ¿Cifrado en tránsito? | Sí (HTTPS) |
| ¿Se puede pedir el borrado? | No: el desarrollador no guarda esos datos; el usuario borra sus fotos y datos en la app |

Las fotos, proyectos y notas no salen del teléfono salvo que el usuario los comparta.

**Permisos:**

| Permiso | Uso |
| --- | --- |
| `CAMERA` | Tomar las fotos |
| `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` | Coordenadas del sello mientras se usa la app (sin ubicación en segundo plano) |
| `INTERNET` | Teselas del mapa y dirección aproximada |
| `WRITE_EXTERNAL_STORAGE` y `READ_EXTERNAL_STORAGE`, ambos con `maxSdkVersion` 29 (la CI lo verifica) | Copia opcional en la galería en Android 10 o anterior; desde Android 11 no se pide nada |
| `VIBRATE` | Aviso al tomar la foto |

El permiso de micrófono que declara el complemento de cámara se elimina del manifiesto (`tools:node="remove"`) y la CI verifica que no aparezca.

## App Store Connect

**Privacidad de la app:** "Datos recopilados" › **Ubicación precisa** › finalidad **Funcionalidad de la app**, **no vinculada** a la identidad del usuario y **no usada para rastreo**. Coincide con `ios/Runner/PrivacyInfo.xcprivacy` (`NSPrivacyCollectedDataTypePreciseLocation`, sin rastreo).

**Clasificación por edad:** todas las preguntas en "Ninguno"/"No". Resultado esperado: 4+.

**Cifrado (exportación):** `ITSAppUsesNonExemptEncryption = NO`: solo usa HTTPS del sistema.

**Textos de permisos (Info.plist, español e inglés):** cámara, ubicación mientras se usa, movimiento y fototeca. De la fototeca solo se pide "agregar a Fotos" (sin álbum propio, porque crear un álbum exige acceso completo); el texto de acceso completo está porque la biblioteca `gal` enlaza esa API, pero la app nunca lo solicita.

**Notas para la revisión:** `fastlane/metadata/ios/review_information/notes.txt`.
