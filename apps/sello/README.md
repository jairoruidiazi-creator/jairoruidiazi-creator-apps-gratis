# Sello

Cámara de campo gratuita, sin anuncios, sin cuenta y sin servidor: cada foto sale con un sello (fecha y hora, coordenadas en el formato que elijas, altitud, precisión, rumbo, dirección, proyecto, campos y notas) dibujado en la imagen y escrito en el EXIF. Pensada para obras, interventorías, catastro, inspecciones, agro y trabajo de campo en Colombia, con los formatos que las apps de pago cobran aparte.

## Qué trae la v1

| Bloque | Funciones |
|---|---|
| Cámara | Vista previa con el sello en vivo · fotos en vertical u horizontal según cómo se sostenga el teléfono (la captura sigue la orientación física; el sello y los íconos giran) · zoom 1–8x · enfoque y exposición por toque · compensación de exposición · flash y linterna · temporizador 3/10 s (se cancela tocando el obturador) · rejilla de tercios · nivel (horizonte e inclinación) · cámara frontal con sello · filtro rojo para trabajo nocturno · pantalla encendida opcional (solo en la cámara) |
| Ubicación | Coordenadas en grados decimales, GMS, grados y minutos, UTM, MGRS, Plus Code y, en Colombia, **Origen Nacional (CTM12, EPSG:9377)** y **zonas MAGNA-SIRGAS** (Bogotá, Este, Oeste…), calculadas en el teléfono (las proyecciones coinciden con PROJ al milímetro; la posición tiene la precisión del GPS) · precisión del GPS · altitud sobre el nivel del mar (geoide EGM96 incluido, sin internet) o elipsoidal, desconocida si el GPS no la mide · promedio de lecturas que queda fijado, bloqueo de la posición para interiores y posición manual (sin precisión ni altitud inventadas) · aviso de lectura vieja · dirección aproximada con el geocodificador del sistema, solo si corresponde al lugar de la foto |
| Brújula | Rumbo del eje de la cámara con norte verdadero: en Android, acelerómetro y magnetómetro con la declinación del modelo WMM2025; en iPhone, la orientación calibrada del sistema (Core Motion y Core Location, con su precisión y su norte verdadero) · sin posición todavía, el rumbo se marca como magnético · punto cardinal · fachada fotografiada · inclinación · rosa de los vientos dibujada en el sello |
| Sello | Plantillas con los datos que elijas (en el orden fijo del sello), con rótulos o sin ellos · posición (esquinas o franja inferior) · tamaño, color y fondo · formato de fecha · segundo formato de coordenadas · logo con tamaño, opacidad y posición · vista previa en vivo en el editor · texto nítido: la capa se dibuja al tamaño real de la foto |
| Proyectos | Carpetas con nombre, emoji, descripción, plantilla propia, patrón de nombre de archivo y campos personalizados (Lote, Inspector, Elemento…) que se llenan en la cámara y se conservan en las fotos siguientes hasta cambiarlos o cambiar de proyecto · notas y etiquetas por foto |
| Archivos | Original sin sello (opcional) y copia sellada en alta resolución (hasta 26 MP) · EXIF nuevo con GPS, altitud sobre el nivel del mar, rumbo (verdadero o magnético), fecha con su zona horaria, descripción en UTF-8 (tildes y ñ) y comentario para Windows, sin la miniatura de la cámara · copia en la fototeca del teléfono (álbum "Sello" en Android, app Fotos en iPhone) · en iOS la carpeta de la app se ve en Archivos · índice guardado con escritura atómica, copia anterior y recuperación desde la carpeta de fotos |
| Galería | Cuadrícula por día, proyecto, lugar o distancia · búsqueda en notas, dirección, etiquetas y campos · filtros por proyecto y etiqueta · selección múltiple con edición en lote (proyecto, etiquetas), compartir y borrar · detalle con todos los datos copiables, sellada u original, re-sellado con la plantilla actual, compartir con o sin EXIF, abrir en mapas y cómo llegar · fotos pendientes o fallidas marcadas, con "Reintentar" |
| Mapa | Fotos sobre OpenStreetMap con color por proyecto (se carga al abrir su pestaña), atribución siempre visible, posición actual con su precisión, encuadre automático, distancia hasta cada foto e indicaciones |
| Exportar | CSV (con UTM, MGRS, Plus Code, CTM12, MAGNA, dirección y campos con su nombre; en español con punto y coma y coma decimal) · KML · KMZ con las fotos incrustadas · ZIP con fotos selladas u originales + CSV + KML · **informe PDF** por proyecto con resumen, tabla y una ficha por foto · todo en segundo plano, con avance y cancelar |
| Copia de seguridad | Copia completa en un ZIP (fotos, fichas, proyectos, plantillas y logos) para pasar todo a otro teléfono · restaurar agrega lo que falta sin borrar nada |

Interfaz en español e inglés. Las fotos y los datos quedan en el teléfono; solo salen cuando los compartes. La única conexión que usa la app es para las teselas del mapa (al abrir la pestaña Mapa) y la dirección aproximada (ambas opcionales).

## Cuidados

- El sello informa; no prueba. La hora y el GPS de un teléfono se pueden alterar, y la app no pretende valor probatorio.
- La ubicación se pide solo mientras se usa la app, y después del permiso de cámara (nunca los dos a la vez). No se pide acceso amplio a la galería: la app guarda en su propia carpeta y la copia a la fototeca usa el permiso mínimo de cada sistema (en iPhone, solo "agregar a Fotos"; en Android 11 o superior, ninguno; hasta Android 10, el de almacenamiento). El permiso se pide al activar la copia o, si ya venía activada, en la primera foto.
- Las coordenadas se escriben en WGS84 tal como las da el GPS; CTM12 y las zonas MAGNA se calculan sobre esas coordenadas sin transformar el datum (WGS84 y MAGNA-SIRGAS difieren unos decímetros, menos que el error del GPS de un teléfono).
- Mapa: © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors (ODbL).

## Desarrollo

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

- Código: Apache-2.0. Sin paquetes GPL.
- Datos incluidos: coeficientes WMM2025 (NOAA/NCEI y BGS, dominio público) en `lib/geo/wmm.dart`; rejillas del geoide EGM96 (NGA, dominio público) en `assets/geoid/`, generadas con `tools/gen_sello_geoid.py`.
- Ícono generado con `tools/gen_sello_assets.py`.
- Código nativo propio (ver `native/`): en Android, la altura elipsoidal del GPS (canal `co.appsgratis.sello/altitude`) y las reglas de copia de seguridad; en iPhone, el rumbo calibrado del sistema (canal `co.appsgratis.sello/heading`). Las carpetas `android/` e `ios/` del repositorio ya los llevan; si se regeneran con `flutter create`, `tools/patch_platforms.py` debe volver a copiarlos.
- El iOS para la tienda debe compilarse con `BYPASS_PERMISSION_LOCATION_ALWAYS=1 flutter build ipa` (la variable también en el `xcodebuild archive` de la firma): así `geolocator_apple` no enlaza la petición de ubicación "siempre", que Sello no usa, y App Store Connect no exige su texto de uso.
- Decisiones de diseño: `docs/DECISIONES.md`.
