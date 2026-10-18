import 'package:flutter/material.dart';

/// Colores de marca de Clave: azul noche y ámbar.
class ClaveColors {
  ClaveColors._();

  static const Color noche = Color(0xFF14213D);
  static const Color ambar = Color(0xFFFCA311);
}

/// Colores con significado (afinado, cerca, lejos, acento y grabar) para
/// cada tema. Los del tema claro tienen un contraste de al menos 5:1 sobre
/// las superficies claras y los del oscuro, de al menos 5:1 sobre las
/// oscuras: sirven como texto y como indicador (prueba en test/a11y_test.dart).
@immutable
class ClavePalette extends ThemeExtension<ClavePalette> {
  const ClavePalette({required this.inTune, required this.near, required this.far, required this.accent, required this.onAccent, required this.record, required this.onRecord});

  final Color inTune;
  final Color near;
  final Color far;

  /// Ámbar para textos e indicadores (el de la marca solo en el tema oscuro).
  final Color accent;
  final Color onAccent;
  final Color record;
  final Color onRecord;

  static const ClavePalette light = ClavePalette(
    inTune: Color(0xFF146C2E),
    near: Color(0xFF7A4F00),
    far: Color(0xFFA8231B),
    accent: Color(0xFF8B5000),
    onAccent: Color(0xFFFFFFFF),
    record: Color(0xFFA8231B),
    onRecord: Color(0xFFFFFFFF),
  );

  static const ClavePalette dark = ClavePalette(
    inTune: Color(0xFF4ADE80),
    near: Color(0xFFF4D03F),
    far: Color(0xFFFF8A80),
    accent: ClaveColors.ambar,
    onAccent: Color(0xFF1B1B1F),
    record: Color(0xFFFF8A80),
    onRecord: Color(0xFF1B1B1F),
  );

  static ClavePalette of(BuildContext context) => Theme.of(context).extension<ClavePalette>() ?? (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  ClavePalette copyWith({Color? inTune, Color? near, Color? far, Color? accent, Color? onAccent, Color? record, Color? onRecord}) {
    return ClavePalette(
      inTune: inTune ?? this.inTune,
      near: near ?? this.near,
      far: far ?? this.far,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      record: record ?? this.record,
      onRecord: onRecord ?? this.onRecord,
    );
  }

  @override
  ClavePalette lerp(covariant ThemeExtension<ClavePalette>? other, double t) {
    if (other is! ClavePalette) {
      return this;
    }
    return ClavePalette(
      inTune: Color.lerp(inTune, other.inTune, t)!,
      near: Color.lerp(near, other.near, t)!,
      far: Color.lerp(far, other.far, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      record: Color.lerp(record, other.record, t)!,
      onRecord: Color.lerp(onRecord, other.onRecord, t)!,
    );
  }
}

class ClaveTheme {
  ClaveTheme._();

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness b) {
    final ColorScheme scheme = ColorScheme.fromSeed(seedColor: ClaveColors.noche, brightness: b);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Signos musicales, flechas y marcas (subconjunto de DejaVu Sans).
      fontFamilyFallback: const <String>['Simbolos'],
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: const AppBarTheme(centerTitle: false),
      cardTheme: CardThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(56, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
      segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(shape: WidgetStatePropertyAll<OutlinedBorder>(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
      sliderTheme: const SliderThemeData(showValueIndicator: ShowValueIndicator.onDrag),
      extensions: <ThemeExtension<dynamic>>[b == Brightness.dark ? ClavePalette.dark : ClavePalette.light],
    );
  }
}

/// Color según la desviación en cents.
Color colorForCents(ClavePalette p, double cents, double tolerance) {
  final double a = cents.abs();
  if (a <= tolerance) {
    return p.inTune;
  }
  if (a <= tolerance * 3) {
    return p.near;
  }
  return p.far;
}
