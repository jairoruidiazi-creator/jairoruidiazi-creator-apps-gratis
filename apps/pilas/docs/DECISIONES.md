# Pilas: decisiones de diseño y producto

Registro de las decisiones tomadas durante el desarrollo, con su razón. Se actualiza con cada entrega.

## Producto

- **Nombre de trabajo: Pilas.** Corto, en español, con sentido en Colombia ("ponte pilas" = estar atento, con energía). Se puede cambiar antes de publicar; el identificador de paquete (`co.appsgratis.pilas`) sí debe quedar fijo antes de la primera subida a las tiendas.
- **Una app para dos públicos (3 a 6 y 7 a 11).** La interfaz se adapta por tramo: de 3 a 6 años todo se dice en voz alta y las opciones son dibujos; de 7 a 11 hay texto y opciones escritas. Así una familia con hijos de distintas edades usa una sola app y un docente una sola instalación.
- **Cuatro tramos de edad (3-4, 5-6, 7-8, 9-11)**, los mismos que la categoría Kids de Apple, para que la ficha de la tienda y los niveles coincidan.
- **Currículo genérico latinoamericano**, por decisión del proyecto (15-10-2026): habilidades por edad con referencia a los DBA de Colombia y a Common Core K-5, sin atarse a un país.
- **Sin cuenta, sin internet, sin anuncios y sin recopilación de datos.** Es la única forma de cumplir a la vez la categoría Kids de Apple, la política de Familias de Google Play, la COPPA 2025 y el artículo 7 de la Ley 1581 sin consentimiento parental verificable.
- **Puerta parental por multiplicación** (dos cifras por una) delante del panel de adultos, de crear o borrar perfiles y de compartir fuera de la app, como exige la pauta 1.3 de App Store.

## Pedagogía (según la evaluación docente del análisis)

- **Regla de dominio 3 de 4**: tres aciertos en las últimas cuatro rondas abren el siguiente nivel; dos ventanas seguidas con un acierto o menos bajan un nivel sin anunciarlo (`engine/mastery.dart`).
- **El error es información**: primer error, pista y segunda oportunidad; segundo error, respuesta explicada en voz alta y siguiente ronda. No hay sonidos de derrota ni puntos negativos (`engine/round_engine.dart`).
- **Sin reloj antes de los 8 años**; la carrera de cálculo competirá solo contra la marca propia.
- **Recompensas por habilidad, no por tiempo**: una pegatina por nivel completado y una habilidad del mapa al dominar el último nivel del tramo. Las pegatinas no se pierden y no hay rachas.
- **Juegos generados por reglas** (no listas fijas de preguntas) para que las rondas no se repitan y el catálogo crezca con datos (vocabulario, situaciones) en lugar de código.
- **Tiempo de sesión** configurable (20 minutos por defecto) con pantalla de descanso; un adulto puede dar 10 minutos más tras la puerta parental.

## Técnica

- **Flutter con un mínimo de paquetes de terceros**: `flutter_svg`, `flutter_tts`, `audioplayers`, `path_provider`, `shared_preferences`, `pdf`, `printing`, `share_plus`. Sin Riverpod, go_router ni Drift: el estado cabe en un `ChangeNotifier` con un `InheritedNotifier`, la navegación es `Navigator.push` y los datos son archivos JSON con escritura atómica. Menos dependencias = app más liviana y menos riesgo de incompatibilidades.
- **Textos en clases Dart** (`core/strings.dart`) en lugar de ARB + gen-l10n en esta versión: evita un paso de generación; cuando entre el inglés (v2) se convierte en una interfaz con dos implementaciones.
- **Voz del sistema** (`flutter_tts`) con preferencia es-CO, es-MX, es-US, es-ES. Si el dispositivo no tiene voz en español, la app sigue con texto en pantalla. Se nombra el sonido de la letra ("mmm"), no su nombre ("eme").
- **Pictogramas de Twemoji (CC BY 4.0)** copiados al paquete (solo los usados, unos 270 SVG) y tipografías **Lexend** y **Andika** (SIL OFL). Sin descargas en tiempo de ejecución.
- **Láminas para colorear propias**, generadas con `tools/gen_pilas_coloring.py` como JSON con paths SVG; el relleno por zonas usa un parser de paths propio (`content/svg_path.dart`) y prueba de pertenencia con `Path.contains`.
- **Sonidos sintetizados** con `tools/gen_pilas_assets.py` (numpy); sin muestras de terceros. Sin música de fondo en la v1.
- **Informes en PDF** con los paquetes `pdf` y `printing` (compartir o imprimir); **exportación e importación** de perfiles y progreso en JSON para pasar datos entre tabletas sin servidor.
- **Carpetas `android/` e `ios/` generadas en la CI** con `flutter create` (flujo `bootstrap-platforms`) y ajustadas con `tools/patch_platforms.py`, porque el entorno de desarrollo no tiene Flutter. La CI (`.github/workflows/pilas.yml`) analiza, prueba, compila el APK y la versión de iOS sin firma.
- **minSdk 24** en Android (Android 7, 2016) para cubrir tabletas de colegio antiguas sin perder paquetes.

## Pendiente de decidir con el proyecto

- Nombre definitivo, dominio y cuenta de organización en las tiendas (ver el análisis).
- Locuciones humanas en lugar de la voz del sistema (v1.1).
- Ilustrador para los personajes propios.
