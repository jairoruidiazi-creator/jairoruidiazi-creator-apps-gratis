import 'package:flutter/material.dart';

import '../model/area.dart';

/// Respaldo para flechas y marcas que Lexend y Andika no traen o que conviene
/// ver igual en todos los teléfonos (subconjunto de DejaVu Sans, ver
/// tools/gen_symbols_font.py).
const List<String> kFontFallback = <String>['Simbolos'];

/// Colores fijos de la marca, solo para adornos (nunca para texto ni para
/// algo que haya que distinguir). Lo que comunica algo sale de [PilasPalette].
class PilasColors {
  PilasColors._();

  static const Color fondo = Color(0xFFFFF8EC);
  static const Color tinta = Color(0xFF1F2954);
  static const Color amarillo = Color(0xFFFFD166);
  static const Color naranja = Color(0xFFFF7A00);
  static const Color verde = Color(0xFF2E9E5B);
  static const Color azul = Color(0xFF2979FF);
  static const Color rosa = Color(0xFFE91E63);
  static const Color morado = Color(0xFF7C4DFF);
}

/// Paleta de Pilas, normal o de alto contraste. Todas las pantallas y los
/// juegos la leen con [PilasPalette.of], así que el alto contraste llega a
/// toda la app. test/palette_test.dart calcula los contrastes: en la normal,
/// el texto tiene al menos 4,5:1 y los objetos gráficos que informan (guía del
/// trazo, siluetas, cuadrículas, bordes de controles) al menos 3:1; en la de
/// alto contraste, 7:1 y 4,5:1.
@immutable
class PilasPalette extends ThemeExtension<PilasPalette> {
  const PilasPalette({
    required this.altoContraste,
    required this.fondo,
    required this.fondoSuave,
    required this.tarjeta,
    required this.tinta,
    required this.tintaSuave,
    required this.borde,
    required this.bordeFuerte,
    required this.acento,
    required this.sobreAcento,
    required this.acentoClaro,
    required this.correcto,
    required this.correctoClaro,
    required this.error,
    required this.errorClaro,
    required this.pista,
    required this.pistaClaro,
    required this.destacado,
    required this.guia,
    required this.silueta,
    required this.cuadricula,
    required this.inactivo,
    required this.areasTexto,
  });

  final bool altoContraste;

  /// Fondo de las pantallas.
  final Color fondo;

  /// Fondo de pantallas tranquilas (descanso).
  final Color fondoSuave;

  /// Tarjetas, opciones y tableros.
  final Color tarjeta;

  /// Texto principal.
  final Color tinta;

  /// Texto secundario.
  final Color tintaSuave;

  /// Bordes de adorno.
  final Color borde;

  /// Bordes que delimitan algo que hay que ver (casillas, controles).
  final Color bordeFuerte;

  /// Botones principales y selección.
  final Color acento;
  final Color sobreAcento;
  final Color acentoClaro;

  /// Acierto (borde y texto) y su fondo.
  final Color correcto;
  final Color correctoClaro;

  /// Error (borde y texto) y su fondo.
  final Color error;
  final Color errorClaro;

  /// Pista (borde, ícono) y su fondo.
  final Color pista;
  final Color pistaClaro;

  /// Relleno amarillo de los botones de voz (adorno; el texto encima es tinta).
  final Color destacado;

  /// Guía del trazo de letras.
  final Color guia;

  /// Siluetas de encajar figuras.
  final Color silueta;

  /// Líneas de cuadrícula (pixel art, sudoku, figuras).
  final Color cuadricula;

  /// Puntos de progreso todavía vacíos.
  final Color inactivo;

  /// Color del texto de cada área, en el orden de [Area.values].
  final List<Color> areasTexto;

  Color areaTexto(Area a) => areasTexto[a.index];

  static const PilasPalette normal = PilasPalette(
    altoContraste: false,
    fondo: Color(0xFFFFF8EC),
    fondoSuave: Color(0xFFFFEFD0),
    tarjeta: Color(0xFFFFFFFF),
    tinta: Color(0xFF1F2954),
    tintaSuave: Color(0xFF5B6386),
    borde: Color(0xFFE8DFC8),
    bordeFuerte: Color(0xFF8A8478),
    acento: Color(0xFF1A5FD6),
    sobreAcento: Color(0xFFFFFFFF),
    acentoClaro: Color(0xFFDDE8FF),
    correcto: Color(0xFF1B7A43),
    correctoClaro: Color(0xFFDDF5E6),
    error: Color(0xFFA35200),
    errorClaro: Color(0xFFFFE0E0),
    pista: Color(0xFFB45309),
    pistaClaro: Color(0xFFFFF4D6),
    destacado: Color(0xFFFFD166),
    guia: Color(0xFF8A8478),
    silueta: Color(0xFF8A8478),
    cuadricula: Color(0xFF938C7D),
    inactivo: Color(0xFFE3DCCB),
    areasTexto: <Color>[Color(0xFF6236D9), Color(0xFF1A5FD6), Color(0xFFB84A00), Color(0xFF1B7A43), Color(0xFFC2185B), Color(0xFF00695C)],
  );

  static const PilasPalette alto = PilasPalette(
    altoContraste: true,
    fondo: Color(0xFFFFFFFF),
    fondoSuave: Color(0xFFFFFFFF),
    tarjeta: Color(0xFFFFFFFF),
    tinta: Color(0xFF000000),
    tintaSuave: Color(0xFF3D3D3D),
    borde: Color(0xFF000000),
    bordeFuerte: Color(0xFF000000),
    acento: Color(0xFF0047B3),
    sobreAcento: Color(0xFFFFFFFF),
    acentoClaro: Color(0xFFE3EEFF),
    correcto: Color(0xFF005A26),
    correctoClaro: Color(0xFFE0F5E7),
    error: Color(0xFF7F2F00),
    errorClaro: Color(0xFFFFE5D6),
    pista: Color(0xFF6B3A00),
    pistaClaro: Color(0xFFFFF7E0),
    destacado: Color(0xFFFFD166),
    guia: Color(0xFF595959),
    silueta: Color(0xFF595959),
    cuadricula: Color(0xFF595959),
    inactivo: Color(0xFFBDBDBD),
    areasTexto: <Color>[Color(0xFF4B2BB5), Color(0xFF0047B3), Color(0xFF8A3300), Color(0xFF005A26), Color(0xFF9B1046), Color(0xFF004D40)],
  );

  static PilasPalette of(BuildContext context) => Theme.of(context).extension<PilasPalette>() ?? normal;

  @override
  PilasPalette copyWith() => this;

  @override
  PilasPalette lerp(covariant ThemeExtension<PilasPalette>? other, double t) {
    if (other is! PilasPalette) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}

class PilasTheme {
  PilasTheme._();

  static ThemeData light({bool highContrast = false, bool dyslexiaFont = false}) {
    final PilasPalette pal = highContrast ? PilasPalette.alto : PilasPalette.normal;
    final Color tinta = pal.tinta;
    final Color fondo = pal.fondo;
    final String familia = dyslexiaFont ? 'Andika' : 'Lexend';
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: pal.acento,
      primary: pal.acento,
      onPrimary: pal.sobreAcento,
      secondary: pal.error,
      surface: fondo,
      onSurface: tinta,
      onSurfaceVariant: pal.tintaSuave,
      outline: pal.bordeFuerte,
    );
    final TextTheme base = ThemeData.light().textTheme.apply(
          fontFamily: familia,
          bodyColor: tinta,
          displayColor: tinta,
        );
    final BorderSide lado = BorderSide(color: highContrast ? pal.bordeFuerte : pal.borde, width: 2);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: fondo,
      fontFamily: familia,
      // Flechas y marcas que Lexend no trae (subconjunto de DejaVu Sans).
      fontFamilyFallback: kFontFallback,
      extensions: <ThemeExtension<dynamic>>[pal],
      textTheme: base.copyWith(
        displayLarge: base.displayLarge?.copyWith(fontWeight: FontWeight.w700),
        headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 30),
        headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 24),
        titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 22),
        titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 18),
        bodyLarge: base.bodyLarge?.copyWith(fontSize: 18, height: 1.4),
        bodyMedium: base.bodyMedium?.copyWith(fontSize: 16, height: 1.4),
        bodySmall: base.bodySmall?.copyWith(color: pal.tintaSuave),
        labelLarge: base.labelLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: fondo,
        foregroundColor: tinta,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(fontFamily: familia, fontFamilyFallback: kFontFallback, fontSize: 22, fontWeight: FontWeight.w700, color: tinta),
      ),
      cardTheme: CardThemeData(
        color: pal.tarjeta,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: lado),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: ListTileThemeData(textColor: tinta, iconColor: tinta),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: pal.acento,
          foregroundColor: pal.sobreAcento,
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: TextStyle(fontFamily: familia, fontFamilyFallback: kFontFallback, fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          side: BorderSide(color: tinta, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: TextStyle(fontFamily: familia, fontFamilyFallback: kFontFallback, fontSize: 18, fontWeight: FontWeight.w600),
          foregroundColor: tinta,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: TextStyle(fontFamily: familia, fontFamilyFallback: kFontFallback, fontSize: 18, fontWeight: FontWeight.w600),
          foregroundColor: highContrast ? pal.acento : tinta,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: tinta)),
      sliderTheme: const SliderThemeData(trackHeight: 8),
      dialogTheme: DialogThemeData(
        backgroundColor: pal.tarjeta,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28), side: highContrast ? lado : BorderSide.none),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: pal.tarjeta,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: pal.bordeFuerte, width: 1.5)),
      ),
      chipTheme: ChipThemeData(labelStyle: TextStyle(color: tinta, fontFamily: familia), side: BorderSide(color: pal.bordeFuerte)),
    );
  }
}

/// Tamaños comunes.
class Dim {
  Dim._();

  static const double gap = 12;
  static const double gap2 = 20;
  static const double gap3 = 32;
  static const double tapMin = 64;
  static const double radio = 24;

  /// Tope del tamaño de letra: escala del sistema por la de la app. Es el
  /// 200 % que pide la WCAG (1.4.4) y el máximo de la letra de Android 14;
  /// test/games_smoke_test.dart y test/texto_grande_test.dart comprueban que
  /// con ×2 nada se desborda en un teléfono de 360 dp.
  static const double maxTextScale = 2.0;

  /// Lado mínimo de una casilla de tablero en un teléfono.
  static const double minCell = 24;
}
