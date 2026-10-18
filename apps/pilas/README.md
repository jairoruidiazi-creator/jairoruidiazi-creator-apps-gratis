# Pilas

Juegos didácticos gratuitos para niños de 3 a 11 años: lógica, números, letras, ciencias, arte y emociones. Sin anuncios, sin suscripciones, sin cuenta y sin internet. Los datos de los niños quedan solo en el dispositivo.

## Los 26 juegos

Cada niño ve los juegos de su edad: 17 de 3 a 4 años, 25 de 5 a 6, 23 de 7 a 8 y 21 de 9 a 11.

| Área | Juegos |
|---|---|
| Razonamiento y lógica | Parejas y memoria · ¿Qué sigue? · El intruso · Laberintos · Rompecabezas · Sudoku |
| Matemáticas | La tienda · Carrera de cálculo · El reloj · Cocina de medidas · Figuras y medidas |
| Lenguaje y lectura | Sonidos y letras · Trazo de letras · Cuentos con voz · Arma la palabra · Ordena la oración |
| Ciencias y entorno | Clasifica seres vivos · El cuerpo humano · Laboratorio guiado |
| Creatividad y motricidad | Colorear · Colorear por números · Dibujo y sellos · Pixel art |
| Emociones y hábitos | ¿Qué siento? · Tablero de rutinas · Historias con decisiones |

Cada juego declara en `lib/engine/game_registry.dart` los tramos de edad que cubre (3-4, 5-6, 7-8, 9-11), la habilidad del mapa que evalúa en cada tramo, una actividad para seguir en casa sin pantalla y una pregunta para conversar. Colorear y Dibujo y sellos son juego libre: no tienen niveles ni habilidades.

- Decisiones de diseño, reglas de evaluación y revisión del vocabulario: `docs/DECISIONES.md`.
- Respuestas para las consolas de las tiendas: `store/COMPLIANCE.md`.
- Código: Apache-2.0. Contenido propio: CC BY 4.0. Pictogramas: Twemoji (CC BY 4.0). Tipografías: Lexend y Andika (SIL OFL).
- Recursos generados: `tools/gen_pilas_assets.py` (ícono, sonidos, pictogramas, tipografías) y `tools/gen_pilas_coloring.py` (láminas).

## Compilar y probar

Hace falta Flutter 3.47 o posterior (Dart 3.13). Las versiones de los paquetes están fijadas en `pubspec.lock`.

```bash
flutter pub get
flutter analyze
flutter test --exclude-tags screenshots   # lógica, contenido y pantallas
flutter test --tags screenshots           # capturas de tienda (las genera la CI)
flutter run
```

La CI (`.github/workflows/pilas.yml`) analiza, prueba, compila el APK, el AAB y la versión de iOS sin firma, y genera las capturas de tienda.
