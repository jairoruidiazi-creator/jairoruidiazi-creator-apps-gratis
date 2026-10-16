# Sello

Cámara de campo gratuita, sin anuncios, sin cuenta y sin servidor: cada foto sale con un sello (fecha y hora, coordenadas en el formato que elijas, altitud, precisión, rumbo, dirección, proyecto, campos y notas) dibujado en la imagen y escrito en el EXIF. Pensada para obras, interventorías, catastro, inspecciones, agro y trabajo de campo en Colombia, con los formatos que las apps de pago cobran aparte.

## Qué trae la v1

| Bloque | Funciones |
|---|---|
| Cámara | Vista previa con el sello en vivo · zoom 1–8x · enfoque y exposición por toque · compensación de exposición · flash y linterna · temporizador 3/10 s · rejilla de tercios · nivel (horizonte e inclinación) · cámara frontal con sello · filtro rojo para trabajo nocturno · pantalla encendida opcional |
| Ubicación | Coordenadas en grados decimales, GMS, grados y minutos, UTM, MGRS, Plus Code y, en Colombia, **Origen Nacional (CTM12, EPSG:9377)** y **zonas MAGNA-SIRGAS** (Bogotá, Este, Oeste…), calculadas en el teléfono con precisión milimétrica · precisión del GPS · altitud sobre el nivel del mar (geoide EGM96 incluido, sin internet) o elipsoidal · promedio de lecturas y bloqueo de la posición para interiores · posición manual · dirección aproximada con el geocodificador del sistema |
| Brújula | Rumbo de la cámara con norte verdadero: la declinación magnética se calcula con el modelo WMM2025 a partir del GPS (o se fija a mano) · punto cardinal · fachada fotografiada · inclinación · rosa de los vientos dibujada en el sello |
| Sello | Plantillas con los datos que quieras, en el orden del sello, con rótulos o sin ellos · posición (esquinas o franja inferior) · tamaño, color y fondo · formato de fecha · segundo formato de coordenadas · logo con tamaño, opacidad y posición · vista previa en vivo en el editor |
| Proyectos | Carpetas con nombre, emoji, descripción, plantilla propia, patrón de nombre de archivo y campos personalizados que se piden antes de cada foto (Lote, Inspector, Elemento…) · notas y etiquetas por foto |
| Archivos | Original sin sello (opcional) y copia sellada en alta resolución · EXIF con GPS, rumbo, fecha, descripción en UTF-8 (tildes y ñ) y comentario para Windows · copia en la fototeca del teléfono (álbum "Sello") · en iOS la carpeta de la app se ve en Archivos |
| Galería | Cuadrícula por día, proyecto, lugar o distancia · búsqueda en notas, dirección, etiquetas y campos · filtros por proyecto y etiqueta · selección múltiple con edición en lote (proyecto, etiquetas), compartir y borrar · detalle con todos los datos copiables, sellada u original, re-sellado con la plantilla actual, compartir con o sin EXIF, abrir en mapas y cómo llegar |
| Mapa | Fotos sobre OpenStreetMap con color por proyecto, posición actual con su precisión, encuadre automático, distancia hasta cada foto e indicaciones |
| Exportar | CSV (con UTM, MGRS, Plus Code, CTM12, MAGNA, dirección, campos…) · KML · KMZ con las fotos incrustadas · ZIP con fotos selladas u originales + CSV + KML · **informe PDF** por proyecto con resumen, tabla y una ficha por foto |

Interfaz en español e inglés. Las fotos y los datos quedan en el teléfono; solo salen cuando los compartes. La única conexión que usa la app es para las teselas del mapa y la dirección aproximada (ambas opcionales).

## Cuidados

- El sello informa; no prueba. La hora y el GPS de un teléfono se pueden alterar, y la app no pretende valor probatorio.
- La ubicación se pide solo mientras se usa la app. No se pide acceso amplio a la galería: la app guarda en su propia carpeta y copia a la fototeca con el permiso mínimo.
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
- Decisiones de diseño: `docs/DECISIONES.md`.
