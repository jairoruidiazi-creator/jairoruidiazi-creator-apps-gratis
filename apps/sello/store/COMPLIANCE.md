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

**Seguridad de los datos (Data safety):** criterio conservador (ver `docs/DECISIONES.md`), porque dos funciones opcionales envían ubicación a terceros: el geocodificador del sistema recibe las coordenadas de la foto y los servidores de teselas de la Fundación OpenStreetMap reciben las teselas de la zona que se muestra cuando el usuario abre la pestaña Mapa. La Fundación no es un proveedor contratado, así que se declara como compartida.

| Pregunta | Respuesta |
| --- | --- |
| ¿Recopila o comparte datos? | **Sí** |
| Tipo de dato | Ubicación › **Ubicación precisa** y **Ubicación aproximada** |
| ¿Se recopila? | **Sí** (sale del teléfono hacia los servicios de las dos funciones) |
| ¿Se comparte? | **Sí**: con el geocodificador del sistema (Google en Android) y con la Fundación OpenStreetMap (teselas del mapa). No se vende ni se usa para publicidad |
| ¿Se procesa de forma efímera? | No (los terceros pueden guardar registros de las peticiones) |
| ¿Es obligatoria? | **No, opcional:** Ajustes › Dirección aproximada y Ajustes › Mapa en línea se pueden apagar |
| Finalidad | Funcionalidad de la app (en recopilación y en uso compartido) |
| ¿Cifrado en tránsito? | Sí (HTTPS) |
| ¿Se puede pedir el borrado? | No: el desarrollador no guarda esos datos; el usuario borra sus fotos y datos en la app |

Las fotos, proyectos y notas no salen del teléfono salvo que el usuario los comparta o guarde una copia completa donde quiera.

**Copias de Google:** las reglas de copia (`native/android/data_extraction_rules.xml` y `backup_rules.xml`) dejan fuera de la copia en la nube las fotos y su índice (no caben en los 25 MB por app) y llevan los proyectos, las plantillas, los logos y los ajustes; el traspaso directo a un teléfono nuevo lleva todo. Ninguna de las dos es del desarrollador. Para pasar las fotos está la copia completa de la app.

**Permisos:**

| Permiso | Uso |
| --- | --- |
| `CAMERA` | Tomar las fotos |
| `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` | Coordenadas del sello mientras se usa la app (sin ubicación en segundo plano) |
| `INTERNET` | Teselas del mapa y dirección aproximada |
| `WRITE_EXTERNAL_STORAGE` y `READ_EXTERNAL_STORAGE`, ambos con `maxSdkVersion` 29 (la CI lo verifica) | Copia opcional en la galería en Android 10 o anterior; desde Android 11 no se pide nada |
| `VIBRATE` | Aviso al tomar la foto |

El permiso de micrófono que declara el complemento de cámara se elimina del manifiesto (`tools:node="remove"`) y la CI verifica que no aparezca.

**Funciones de hardware:** Sello es una cámara y Google Play solo la ofrece a equipos con cámara y ubicación: el APK exige `android.hardware.camera.any` (lo declara CameraX) y `android.hardware.location` (implícito en el permiso de ubicación), como muestra el badging de la CI. Lo demás se declara con `android:required="false"` para no excluir equipos por eso: cámara trasera, enfoque automático, brújula y GPS. Sin brújula la foto sale sin rumbo y sin GPS la posición se escribe a mano (coordenadas) en la hoja del GPS de la cámara, con el rótulo "posición manual".

## App Store Connect

**Privacidad de la app:** "Datos recopilados" › **Ubicación precisa** › finalidad **Funcionalidad de la app**, **no vinculada** a la identidad del usuario y **no usada para rastreo**. Cubre también la zona que reciben los servidores de teselas de OpenStreetMap (menos precisa). Coincide con `ios/Runner/PrivacyInfo.xcprivacy` (`NSPrivacyCollectedDataTypePreciseLocation`, sin rastreo).

**Clasificación por edad:** todas las preguntas en "Ninguno"/"No". Resultado esperado: 4+.

**Cifrado (exportación):** `ITSAppUsesNonExemptEncryption = NO`: solo usa HTTPS del sistema.

**Textos de permisos (Info.plist, español e inglés):** cámara, ubicación mientras se usa (también da el norte verdadero de la brújula), movimiento, fototeca y micrófono. De la fototeca solo se pide "agregar a Fotos" (sin álbum propio, porque crear un álbum exige acceso completo); el texto de acceso completo está porque la biblioteca `gal` enlaza esa API, pero la app nunca lo solicita. El del micrófono está porque el complemento de cámara enlaza la grabación de audio (sin el texto, App Store Connect devuelve ITMS-90683); la cámara se abre sin audio y Sello nunca lo pide. Para no necesitar el texto de ubicación "siempre", el iOS se compila con la variable de entorno `BYPASS_PERMISSION_LOCATION_ALWAYS=1` (así lo hacen la CI y el flujo de publicación, en `flutter build` y en el `xcodebuild archive` de la firma), que quita del binario la petición de ese permiso en `geolocator_apple`; sin ella, App Store Connect devolvería ITMS-90683 por falta de ese texto.

**Notas para la revisión:** `fastlane/metadata/ios/review_information/notes.txt`.
