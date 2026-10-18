# Clave

Kit de práctica musical gratuito, sin anuncios, sin cuenta y sin internet: afinador cromático, metrónomo, bordón con teclado y acordes, grabadora y registro de práctica. Una sola app para lo que las referencias de pago reparten en cinco o seis.

## Qué trae la v1

| Herramienta | Funciones |
|---|---|
| Afinador | Cromático de Do0 a Do8 con nota, cents y Hz · La4 ajustable en pasos de 0,1 Hz · temperamentos igual, justo, pitagórico, mesotónico y propio (editor por grado) · transposición (Si♭, Mi♭, Fa, La…) y capo · notación solfeo, inglesa, alemana e india (con la nota de Sa a elegir) · gráfica de estabilidad · perfiles con cuerdas (guitarra, bajo, ukelele, tiple colombiano con sus cuerdas a la octava, requinto colombiano, bandola andina, cuatro, charango, requinto de guitarra, mandolina, banjo, violín, viola, violonchelo, contrabajo) con detección automática del orden o cuerda fijada · tolerancia y amortiguación ajustables · escucha solo con su pestaña a la vista |
| Metrónomo | 20–400 BPM, tap tempo, indicación italiana · compás de 1 a 16 pulsos sobre 2, 4, 8 o 16 · subdivisiones (corcheas, tresillos, semicorcheas, seisillos) con swing · los cambios en marcha rigen desde el pulso siguiente · editor de pulsos (acento, normal, silencio, solo subdivisión) · 12 sonidos sintetizados con tres variantes cada uno · entrenador de tempo por pasos · compases mudos · péndulo o número grande, destello y vibración atados al audio que se oye · retraso del audio con calibración por toques (audífonos Bluetooth) · conteo hablado · preajustes y setlists exportables en JSON, con canción anterior y siguiente |
| Tono y teclado | Bordón con quinta pura opcional, 4 formas de onda sin aliasing y volumen · teclado de 8 octavas con sostener · acordes sostenidos (M, m, 7, M7, m7, dim, aug, sus2, sus4, 5) · todo sigue la referencia y el temperamento del afinador |
| Grabadora | Tomas ilimitadas en AAC, WAV o FLAC · carpetas, búsqueda, notas, instrumento y BPM de la toma · reproducción a 0,5–1,5x · compartir · una toma que quedó a medias al cerrarse la app se rescata |
| Práctica | Registro automático mientras suena el metrónomo, el bordón o el teclado, mientras se graba y mientras el afinador oye tu instrumento · metas diaria y semanal · racha de días con 5 minutos o más, con un día de descanso de cada siete · minutos por día (7/14/30) · desglose por instrumento y herramienta |

Los textos están en español y en inglés (la primera vez, en el idioma del teléfono). Los datos quedan en el dispositivo.

- Código: Apache-2.0. Motor de audio: [flutter_soloud](https://pub.dev/packages/flutter_soloud) (MIT). Sin muestras de terceros: todos los sonidos se sintetizan.
- Decisiones de diseño y correcciones de la auditoría: `docs/DECISIONES.md`.
- Ícono generado con `tools/gen_clave_assets.py`.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```
