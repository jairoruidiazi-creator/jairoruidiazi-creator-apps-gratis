# Pilas

Juegos didácticos gratuitos para niños de 3 a 11 años: lógica, números, letras, ciencias, arte y emociones. Sin anuncios, sin suscripciones, sin cuenta y sin internet. Los datos de los niños quedan solo en el dispositivo.

## Los 26 juegos de la v1

| Área | Juegos |
|---|---|
| Razonamiento y lógica | Parejas y memoria · ¿Qué sigue? · El intruso · Laberintos · Tangram y rompecabezas · Sudoku de figuras |
| Matemáticas | La tienda · Carrera de cálculo · El reloj · Cocina de medidas · Constructor de figuras |
| Lenguaje y lectura | Sonidos y letras · Trazo de letras · Cuentos con voz · Arma la palabra · Ordena la oración |
| Ciencias y entorno | Clasifica seres vivos · Arma el cuerpo · Laboratorio guiado |
| Creatividad y motricidad | Colorear · Colorear por números · Dibujo y sellos · Pixel art |
| Emociones y hábitos | ¿Qué siento? · Tablero de rutinas · Historias con decisiones |

Cada juego declara en `lib/engine/game_registry.dart` los tramos de edad que cubre (3-4, 5-6, 7-8, 9-11), la habilidad del mapa que trabaja en cada tramo, una actividad para seguir en casa sin pantalla y una pregunta para conversar.

- Código: Apache-2.0. Contenido propio: CC BY 4.0. Pictogramas: Twemoji (CC BY 4.0). Tipografías: Lexend y Andika (SIL OFL).
- Decisiones de diseño: `docs/DECISIONES.md`.
- Recursos generados: `tools/gen_pilas_assets.py` (ícono, sonidos, pictogramas, tipografías) y `tools/gen_pilas_coloring.py` (láminas).

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```
