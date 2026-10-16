# Sello: decisiones de diseño y producto

Registro de las decisiones tomadas durante el desarrollo, con su razón.

## Producto

- **Nombre de trabajo: Sello.** Dice lo que hace (sellar la foto) en una palabra corta y en español. Identificador de paquete `co.appsgratis.sello`.
- **Colombia primero, sin dejar de servir en cualquier país.** Es la primera cámara de campo con la proyección oficial colombiana (Origen Nacional CTM12, Resolución IGAC 471 de 2020) y las zonas MAGNA-SIRGAS clásicas, además de UTM, MGRS y Plus Code. Los formatos colombianos solo aparecen dentro del rectángulo que contiene al país (incluidas San Andrés y Providencia); fuera de él se ocultan porque no significan nada.
- **Sin cuenta, sin anuncios, sin servidor, sin marca de agua.** Lo único que usa internet es el mapa (teselas de OpenStreetMap) y la dirección aproximada (geocodificador del sistema), y ambos se pueden apagar. Las fotos y los datos viven en la carpeta de la app; se exportan por la hoja de compartir.
- **Qué entró en la v1 además de lo que el estudio pedía**: el informe PDF por proyecto, la altitud sobre el nivel del mar sin internet, el norte verdadero automático, el nivel en pantalla, el orden por lugar y distancia, la edición en lote y la copia sin EXIF, porque salieron baratos con las piezas ya hechas. **Quedan para la v1.1**: video con sello, HEIC, obturador silencioso, minimapa y clima en el sello, galería anotable, distancias y áreas, importación de KML, bitácora, barómetro para la altitud, fuente del sello configurable y guardado automático en Drive. **Para la v2**: mapas sin conexión (PMTiles), telémetro y herramientas de campo, capas de realidad aumentada, reloj, Mac y Vision Pro.
- **No se promete valor probatorio.** El README y la pantalla "Acerca de" lo dicen: la hora y el GPS de un teléfono se pueden alterar.

## Geodesia (todo en Dart, validado contra PROJ, mgrs y Open Location Code)

- **Una sola proyección transversa de Mercator (serie de Krüger–Karney, orden 6)** sirve para UTM, para CTM12 y para las cinco zonas MAGNA-SIRGAS. Las pruebas comparan con PROJ (`pyproj`) en catorce puntos de Colombia y del mundo: diferencias menores de un milímetro. No se usaron `proj4dart` ni `mgrs_dart` (que el estudio sugería) porque la app solo necesita proyectar en una dirección y así no hay dependencias ni tablas de datums.
- **MGRS y Plus Code propios**, probados contra las implementaciones de referencia (`mgrs` de Python y la de Google), incluidos los casos de zona par e impar del MGRS y los códigos de 10 y 11 caracteres.
- **Altitud sobre el nivel del mar con el geoide EGM96 incluido.** Android entrega la altura sobre el elipsoide WGS84 (puede diferir 5–30 m del nivel del mar en Colombia) y iOS la del nivel del mar; la app muestra las dos y el usuario elige cuál va en el sello. Se incluyen dos rejillas generadas del modelo público de la NGA: Colombia a 5' (exacta respecto al modelo, 106 KB) y el mundo a 30' (error típico < 0,3 m, 508 KB). El barómetro para suavizar la altitud queda para la v1.1.
- **Norte verdadero sin internet.** El rumbo se calcula con la matriz de rotación de Android (acelerómetro + magnetómetro, en Dart, igual en iOS) y la declinación magnética con el modelo WMM2025 (coeficientes de dominio público de NOAA/BGS), recalculada cuando el usuario se mueve más de ~1 km. En Colombia la declinación va hoy de −6° a −11°, demasiado para ignorarla. Si el usuario prefiere, la fija a mano. Las pruebas comparan la declinación con la implementación de referencia de NOAA en diez puntos (error < 0,001°).
- **El rumbo es el del eje de la cámara**, no el del borde superior del teléfono, salvo cuando el teléfono está plano (±31° de la horizontal), que es cuando una brújula clásica tiene sentido. La "fachada fotografiada" es el rumbo más 180°, como en Solocator.
- **Promedio ponderado de lecturas (1/σ²) y bloqueo manual** para interiores y bajo techo; la precisión del promedio es sqrt(1/Σw) y se escribe en el sello ("promedio de 12").

## Sello e imagen

- **El sello se dibuja una sola vez con el mismo código** para la vista previa y para la foto: un `CustomPainter` cuya unidad es el 1 % del ancho, así el texto guarda la misma proporción en la pantalla y en la foto de 12 o 50 MP.
- **Composición en Dart con el paquete `image`, en un isolate.** El estudio proponía composición nativa (Bitmap/Core Graphics por Pigeon); se eligió Dart puro para la v1 porque es idéntico en Android e iOS, se prueba en la CI sin dispositivo y basta para fotos de 12–16 MP (2–5 s en un teléfono medio, en segundo plano, con contador en pantalla). La capa del sello se dibuja a 2000 px de ancho y se escala al tamaño real; la orientación EXIF se "hornea" antes de componer. La composición nativa para 50 MP y el video quedan para la v1.1.
- **Calidad JPEG 92 y submuestreo 4:2:0** por defecto, ajustable de 60 a 100. El original se conserva por defecto (desactivable) porque permite volver a sellar con otra plantilla.
- **EXIF escrito con valores explícitos**: el paquete `image` solo convierte tipos simples en las etiquetas con tipo declarado y las de GPS no lo tienen, así que se construyen a mano (latitud/longitud en racionales, altitud, rumbo verdadero, fecha, versión). La descripción va en UTF-8 dentro de `ImageDescription` (es lo que leen Android, Lightroom y exiftool), con copia en `UserComment` y en `XPComment`/`XPTitle` (UTF-16) para el Explorador de Windows.
- **Compartir sin EXIF** quita los segmentos APP1/APP13/COM sin recomprimir la imagen; el sello dibujado se conserva. Es la opción de privacidad que pedía el estudio.
- **Plantillas con los datos en el orden fijo del sello** (fecha, coordenadas, altitud, precisión, rumbo, fachada, velocidad, dirección, proyecto, campos, notas, rosa de los vientos), con o sin rótulos. No hay editor de orden libre en la v1: el orden fijo evita sellos ilegibles y simplifica las pruebas.
- **Logo dentro de la app**: se copia el archivo elegido (PNG/JPG) a la carpeta de la app y se guarda la ruta relativa, porque en iOS la ruta absoluta del contenedor cambia entre versiones.

## Datos, galería y exportación

- **Un proyecto activo que agrupa las fotos y define los campos** (se piden antes de cada foto y se recuerdan hasta cambiar de proyecto). Los campos van al sello, al EXIF (en la descripción), al CSV, al KML y al PDF.
- **Galería propia** sobre la carpeta de la app, sin leer la fototeca del teléfono (Play lo restringe desde mayo de 2025 y no hace falta). Copia a la fototeca con `gal` en el álbum "Sello" si el usuario lo deja activado.
- **Exportaciones generadas en el teléfono**: CSV con BOM (para Excel), KML, KMZ con las fotos, ZIP y PDF (`pdf`, Dart puro). El PDF usa las fuentes incorporadas (Latin-1): los emojis de los nombres de proyecto se omiten y los signos tipográficos se sustituyen.
- **Edición de datos sin tocar la imagen**: notas, etiquetas, campos y proyecto se cambian en los datos y las exportaciones; "Volver a sellar" regenera la copia sellada desde el original con la plantilla actual del proyecto.
- **JSON locales con escritura atómica** (igual que en Pilas y Clave) para proyectos, plantillas y el índice de fotos.

## Técnica

- **Flutter con `camera`, `geolocator`, `geocoding`, `sensors_plus`, `image`, `flutter_map` + `latlong2`, `gal`, `archive`, `pdf`, `share_plus`, `url_launcher`, `file_selector`, `wakelock_plus`, `shared_preferences`, `path_provider`.** Se descartó `maplibre_gl` para la v1 (necesita JDK 21 y pesa) a favor de `flutter_map` con teselas ráster de OpenStreetMap y su atribución; los mapas vectoriales y sin conexión entran con PMTiles en la v2. `flutter_compass` se descartó por abandono; el rumbo es propio.
- **Pruebas sin dispositivo**: geodesia contra valores de referencia, brújula con vectores de gravedad y campo construidos a mano, composición con un JPEG sintético (incluida orientación EXIF 6), exportaciones (CSV, KML, KMZ, ZIP, PDF) y una prueba de widgets que recorre toda la app con la cámara desactivada y el mapa sin teselas.
- **Permisos mínimos**: cámara, ubicación mientras se usa, vibración e internet; `WRITE_EXTERNAL_STORAGE` solo hasta Android 10 por `gal`. En iOS, textos de uso de cámara, ubicación y fototeca, y la carpeta de la app visible en Archivos (`UIFileSharingEnabled`).
- **CI igual a la de Pilas y Clave**: análisis, pruebas, APK y compilación de iOS sin firma; plataformas generadas con `flutter create` y ajustadas con `tools/patch_platforms.py`.

## Pendiente de decidir con el proyecto

- Nombre definitivo e ícono ilustrado.
- Si el minimapa dentro de la foto (v1.1) usa OpenStreetMap ráster con atribución en el sello o un mapa vectorial propio.
- Si el informe PDF debe llevar logo y firma del inspector (campos de proyecto) en la cabecera.
