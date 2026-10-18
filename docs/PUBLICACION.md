# Cómo publicar Pilas, Clave, Sello, Plata y Rutinas

Esta guía junta lo que ya está hecho en el repositorio y lo que solo puede
hacer el titular de las cuentas de desarrollador. Las respuestas exactas de
cada formulario de las tiendas están en `apps/<app>/store/COMPLIANCE.md`.

## Lo que ya está listo

| Pieza | Dónde |
| --- | --- |
| Código, pruebas y compilación de Android (APK y AAB firmados) e iOS en cada cambio | `.github/workflows/<app>.yml` y `app-ci.yml` |
| SDK objetivo 36, páginas de 16 KB, permisos permitidos, firma y manifiesto de privacidad de iOS, revisados por la CI | `tools/ci/check_android_package.py`, `tools/store/android.json` |
| Textos de las fichas (Google Play es-419/en-US, App Store es-MX/en-US; Pilas solo en español) y notas para la revisión de Apple | `apps/<app>/fastlane/metadata/` |
| Revisión automática de los textos (límites, palabras prohibidas, URL, versión) | `tools/store/check_metadata.py` |
| Capturas de las dos tiendas, gráfico de funciones e ícono de 512 px, generados con pantallas reales | trabajo "Capturas de tienda" de la CI (artefacto `<app>-capturas-tienda`) |
| Política de privacidad en español e inglés, dentro de cada app y publicada en el repositorio | `apps/<app>/assets/legal/privacy_*.md` |
| Página de soporte | `docs/SOPORTE.md` |
| Respuestas de Data safety, privacidad de Apple, clasificación, público, cifrado | `apps/<app>/store/COMPLIANCE.md` |
| Flujo para compilar, firmar y subir | `.github/workflows/release.yml` ("Publicar en las tiendas") |

## Lo que solo puede hacer el titular

1. **Cuenta de Google Play Console** (pago único de 25 USD y verificación de identidad).
   Las cuentas personales creadas desde noviembre de 2023 deben hacer una **prueba
   cerrada con al menos 12 personas durante 14 días seguidos** antes de pedir acceso a
   producción; conviene empezarla apenas esté la primera versión.
2. **Apple Developer Program** (99 USD al año). Para publicar como empresa, Apple pide el
   número D-U-N-S.
3. **Datos públicos del desarrollador:** nombre que verán los usuarios, correo de contacto
   (Google Play lo muestra en la ficha; las políticas remiten a él) y, si se quiere, sitio
   web. La página de soporte usa el repositorio de GitHub; si se prefiere un correo, se
   agrega en `docs/SOPORTE.md`.
4. **Nombres disponibles:** confirmar en cada consola que los nombres de la ficha están
   libres ("Plata: finanzas personales", "Clave: afinador y metrónomo", "Sello: cámara GPS de
   campo", "Pilas: juegos para aprender", "Rutinas: hábitos e intervalos"). Si alguno está
   tomado, se cambia en `fastlane/metadata/*/title.txt` y `name.txt`; `check_metadata.py`
   vigila los límites.
5. **Identificadores:** las apps usan `co.appsgratis.<app>`. Si se prefiere otro prefijo,
   hay que cambiarlo **antes de la primera subida** (después no se puede): `applicationId`
   en `apps/<app>/android/app/build.gradle.kts`, `PRODUCT_BUNDLE_IDENTIFIER` en
   `apps/<app>/ios/Runner.xcodeproj/project.pbxproj` y la variable `PKG`/`app_identifier`
   de `release.yml`. El paquete de Kotlin de Plata (`co.appsgratis.plata`) puede quedarse
   igual: Android permite que difiera del `applicationId`.

## Android, paso a paso

1. **Llave de subida** (una para todas las apps o una por app; guárdala con copia):

   ```bash
   keytool -genkeypair -v -keystore upload.jks -keyalg RSA -keysize 4096 -validity 10000 -alias upload
   base64 -w0 upload.jks > upload.jks.b64   # en macOS: base64 -i upload.jks -o upload.jks.b64
   ```

2. **Secretos del repositorio** (GitHub › Settings › Secrets and variables › Actions):
   `ANDROID_UPLOAD_KEYSTORE_BASE64` (contenido de `upload.jks.b64`),
   `ANDROID_UPLOAD_KEYSTORE_PASSWORD`, `ANDROID_UPLOAD_KEY_ALIAS` (`upload`) y
   `ANDROID_UPLOAD_KEY_PASSWORD`.
3. **Crear cada app en Play Console:** nombre, idioma predeterminado español
   (Latinoamérica), app, gratis. Dejar activada la firma de apps de Google Play.
4. **Primera versión a mano** (Google no deja crear la primera versión por la API): en
   Actions › "Publicar en las tiendas", elegir la app, Android, sin "Subir". Descargar el
   artefacto `<app>-aab-real` y subirlo en Play Console › Pruebas › Prueba interna.
5. **Contenido de la app** (Política › Contenido de la app): copiar las respuestas de
   `COMPLIANCE.md` (privacidad, anuncios, acceso, clasificación, público objetivo,
   funciones financieras, Data safety).
6. **Ficha de Play Store:** se puede llenar a mano con los textos de
   `fastlane/metadata/android/<idioma>/` y las imágenes del artefacto `<app>-ficha`, o
   dejar que el paso 8 la suba.
7. **Acceso por API para las siguientes versiones:** en Google Cloud, crear una cuenta de
   servicio con una llave JSON; en Play Console › Usuarios y permisos, invitar el correo de
   esa cuenta con permiso para publicar en estas apps. Guardar el JSON completo en el
   secreto `PLAY_SERVICE_ACCOUNT_JSON`.
8. **Cada versión nueva:** subir la versión en `apps/<app>/pubspec.yaml` (por ejemplo
   `1.0.1+2`, el número después de `+` es el versionCode), actualizar
   `apps/<app>/lib/core/app_info.dart` (la CI lo exige), escribir las notas en
   `fastlane/metadata/android/<idioma>/changelogs/<versionCode>.txt` y lanzar el flujo con
   "Subir". Mientras la app no tenga ninguna versión publicada, Google exige el estado
   `draft`; después se puede usar `completed` para la prueba interna.

## iOS, paso a paso

1. **Clave de API de App Store Connect** (Usuarios y acceso › Integraciones › App Store
   Connect API) con rol **Administrador** (la firma automática en la nube lo necesita).
   Descargar el `.p8` y guardar los secretos `ASC_KEY_ID`, `ASC_ISSUER_ID`,
   `ASC_KEY_P8_BASE64` (el `.p8` en base64) y `APPLE_TEAM_ID`.
2. **Crear cada app en App Store Connect:** plataforma iOS, idioma principal español
   (México), bundle ID `co.appsgratis.<app>` (si no aparece, se registra en Certificates,
   Identifiers & Profiles › Identifiers; no necesita capacidades especiales), SKU libre.
3. **Subir la versión y la ficha:** Actions › "Publicar en las tiendas", la app, iOS y
   "Subir". El flujo archiva y firma con la firma automática de Xcode, sube el build a
   App Store Connect (queda en TestFlight) y sube textos y capturas.
4. **En App Store Connect:** privacidad de la app, clasificación por edad, precio
   gratis y disponibilidad según `COMPLIANCE.md` (Plata: sin Francia en la primera
   versión; Pilas: categoría Niños, 6 a 8 años), contacto para la revisión (nombre,
   teléfono, correo) y enviar a revisión.
5. **Cada versión nueva:** el número de build de iOS es el mismo de `pubspec.yaml` (el que
   va después de `+`) y no se puede repetir.

## Antes de cada publicación

- [ ] Versión y build subidos en `pubspec.yaml` y `app_info.dart`.
- [ ] CI de la app en verde (análisis, pruebas, Android, iOS y capturas).
- [ ] Si cambió la forma de manejar datos o permisos: política de privacidad (con fecha
      nueva), `COMPLIANCE.md` y las respuestas de las consolas.
- [ ] Capturas revisadas en el artefacto `<app>-capturas-tienda`.
- [ ] Notas de la versión en `changelogs/` (Google Play) y, desde la segunda versión,
      `release_notes.txt` (App Store).
