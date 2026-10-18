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
| Idioma de la ficha y de la app | Español (Google Play es-419, App Store es-MX). La app no tiene inglés: no se publica ficha en inglés y el paquete de iOS declara solo español (`CFBundleLocalizations = [es]`) y solo lleva la carpeta `es.lproj` (la CI de iOS lo comprueba en el paquete compilado). |
| Política de privacidad | `https://github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis/blob/main/apps/pilas/assets/legal/privacy_es.md` (también dentro de la app, en el panel de adultos) |
| Soporte | `https://github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis/blob/main/docs/SOPORTE.md` (reportes de GitHub, que sirven desde Android, iPhone o un computador, y un canal para asuntos privados) |
| Precio | Gratis, sin compras dentro de la app |

## Países donde se publica

Pilas solo está en español y se publica **en los países de habla hispana de América Latina y en España**:
Argentina, Bolivia, Chile, Colombia, Costa Rica, Ecuador, El Salvador, España, Guatemala, Honduras, México, Nicaragua, Panamá, Paraguay, Perú, República Dominicana, Uruguay y Venezuela (18 países; Cuba no tiene ninguna de las dos tiendas).

**No se publica en Estados Unidos (ni en Puerto Rico, que es territorio de EE. UU.).** Las leyes estatales de "App Store Accountability" obligan a los desarrolladores de apps a verificar, con datos que entrega la tienda, la categoría de edad de cada usuario y si hay consentimiento parental, a avisar a la tienda de cada "cambio significativo" para que se renueve ese consentimiento y a borrar esos datos después de usarlos:
- **Texas, SB 2420:** debía regir desde el 1 de enero de 2026; un juez federal la suspendió a finales de 2025 y el Quinto Circuito suspendió esa medida mientras se resuelve la apelación, así que hoy se puede hacer cumplir. Multas de hasta 10.000 USD por infracción.
- **Utah, SB 142:** obligaciones de los desarrolladores desde el 7 de mayo de 2026, con acción privada de los padres (1.000 USD por infracción).
- **Luisiana, HB 570:** desde el 1 de julio de 2026.
- **California, AB 1043:** desde el 1 de enero de 2027 pide pedir la señal de edad de la tienda al instalar y abrir la app.

Pilas no tiene conexión ni usa las API de señales de edad (Declared Age Range de Apple, Play Age Signals de Google); cumplir esas leyes exigiría integrarlas y mantener un flujo de consentimiento. Como la app es solo en español para América Latina y España, se excluye EE. UU. **(decisión del proyecto)**. Si algún día se publica allí, hay que evaluar primero esas API.

Fuentes: [Morrison Foerster, actualización sobre la ley de Texas](https://www.mofo.com/resources/insights/251111-texas-targets-app-stores-with-new-accountability-law), [Squire Patton Boggs en The National Law Review](https://natlawreview.com/article/app-store-age-verification-laws-your-questions-answered), [Bass, Berry & Sims](https://www.bassberry.com/news/apps-and-minors-new-compliance-frontiers-and-risks-in-louisiana-utah-and-texas/).

**En las consolas:**
- Google Play Console › Prueba y publicación › Producción › Países o regiones: agregar solo los 18 países de la lista (y los mismos en cada pista de prueba).
- App Store Connect › la app › Precios y disponibilidad › Disponibilidad de la app: «Todos los países o regiones» desactivado y marcados solo los 18 países.

## La puerta para adultos

Pide escribir el resultado de una multiplicación de dos números de dos cifras, los dos de 13 a 39 y ninguno múltiplo de 5, escrita en palabras, por ejemplo "¿Cuánto es veintitrés por diecisiete?". La puerta dice que es una tarea para adultos y que se puede usar la calculadora del teléfono. La app sí entrena multiplicaciones con números de dos cifras (la tienda multiplica precios redondos por 2 a 12; la carrera, por una cifra o por 12), pero la puerta descarta todos esos pares: ninguna de sus operaciones sale en un juego. "Otra operación" cuenta como intento fallido. Los dos primeros intentos fallidos seguidos no tienen espera; desde el tercero hay que esperar 60 s, luego 120 s, 240 s… hasta 15 minutos. El contador vuelve a cero con un acierto o tras 15 minutos sin errores. La voz solo dice "Esto es para un adulto" (no lee la pregunta), y el campo de respuesta no tiene menú de texto, así que no ofrece "Buscar en la web".

Protege: el panel de adultos (ajustes, informes, modo docente, guía para familias, política de privacidad, créditos), crear un perfil (también el primero), editar o borrar perfiles, compartir dibujos, informes o datos, importar datos, dar más tiempo y cambiar de jugador mientras otro está en su descanso.

## Google Play Console

**Acceso a la app:** toda la funcionalidad está disponible sin acceso especial. Las zonas de adultos piden la puerta descrita arriba, no una cuenta.

**Anuncios:** la app no contiene anuncios.

**Público objetivo y contenido:** franjas "5 años o menos", "6 a 8 años" y "9 a 12 años". Al incluir niños, la app entra al programa **Diseñada para familias** y debe cumplir la política de Familias:

| Requisito de Familias | Cómo lo cumple Pilas |
| --- | --- |
| Sin anuncios o solo SDK de anuncios certificados | No hay anuncios ni SDK de anuncios |
| No recopilar identificadores ni ubicación de niños | No usa internet, ni ubicación, ni el ID de publicidad; la CI prohíbe `AD_ID`, ubicación, cámara, micrófono, contactos y estado del teléfono (`tools/store/android.json`) |
| Política de privacidad y Data safety coherentes | Ver abajo |
| Contenido apropiado para niños | Contenido propio y Twemoji; sin enlaces externos, chats ni contenido de usuarios |
| Funciones para adultos detrás de una puerta | Ver "La puerta para adultos" |

**Clasificación de contenido (IARC):** categoría "Juego" o "Educación" según el formulario. Violencia, miedo, sexo, lenguaje, sustancias, apuestas, interacción entre usuarios, compras digitales, ubicación compartida y acceso a internet: **No**. Resultado esperado: PEGI 3 / ESRB Everyone / Todos.

**Funciones financieras:** "Mi app no ofrece funciones financieras" (el juego "La tienda" usa dinero de juguete).

**Apps de salud, noticias, COVID-19, gobierno:** No.

**Seguridad de los datos (Data safety):** ¿Recopila o comparte datos? **No.** Perfiles, avance, dibujos e informes se guardan solo en el dispositivo; no hay conexión a internet. Lo que un adulto comparte desde la hoja del sistema es una transferencia iniciada por el usuario, y el archivo que importa lo elige él mismo con el selector del sistema y se lee solo en el dispositivo.

**Permisos:** ninguno (la CI exige una lista vacía). Las voces son las del sistema (`TextToSpeech` declarado en `<queries>`); el manifiesto no declara `PROCESS_TEXT`. Importar datos usa el selector de documentos del sistema, que no pide permiso de almacenamiento.

**Programa "Aprobada por docentes" (opcional):** se puede postular después del lanzamiento desde la sección Familias de la consola.

## App Store Connect

**Categoría Niños (Made for Kids):** sí, franja de edad **6 a 8 años**. Pilas cubre de 3 a 11 años en cuatro tramos; la App Store permite elegir una sola franja y 6 a 8 es el centro del rango. Requisitos de las guías 1.3 y 5.1.4:

- Sin enlaces fuera de la app ni oportunidades de compra para los niños: no hay enlaces; compartir, importar y la política están tras la puerta para adultos, y los campos de texto no ofrecen "Buscar en la web".
- Sin analítica ni publicidad de terceros: ninguna.
- Puerta para adultos con una tarea de adulto: ver arriba.

**Contacto de soporte (guía 1.5):** la página de soporte remite a los reportes de GitHub, que funcionan desde el iPhone o el iPad, y explica cómo pedir un contacto privado.

**Permisos de iOS:** solo `NSPhotoLibraryAddUsageDescription` (agregar a Fotos, sin leer la fototeca). Aparece únicamente si un adulto, al compartir un dibujo, elige "Guardar imagen" en la hoja del sistema. Pilas no pide cámara, micrófono, ubicación ni contactos.

**Privacidad de la app:** "Datos no recopilados". `PrivacyInfo.xcprivacy`: sin rastreo, sin dominios, sin datos recopilados, UserDefaults con motivo CA92.1.

**Clasificación por edad:** todas las preguntas de contenido en "Ninguno"/"No". En las preguntas de funciones:
- **Controles parentales: Sí.** Apple los define como herramientas para que los padres "monitor, manage, or restrict" el uso, e incluye "setting usage limits". Pilas tiene un límite de tiempo por sesión que solo un adulto cambia tras la puerta, y un informe para la familia.
- **Verificación de edad (Age Assurance): No.** Pilas no usa la API Declared Age Range ni verifica edades: el tramo lo elige un adulto en el perfil.
- Contenido generado por usuarios, mensajes, publicidad, compras: No.

Resultado: 4+ (obligatorio en la categoría Niños; los controles parentales no suben la clasificación). Fuente: [App Store Connect Help, Age ratings](https://developer.apple.com/help/app-store-connect/reference/age-ratings).

**Cifrado (exportación):** `ITSAppUsesNonExemptEncryption = NO`: la app no cifra datos ni se conecta a internet.

**Notas para la revisión:** `fastlane/metadata/ios/review_information/notes.txt`.
