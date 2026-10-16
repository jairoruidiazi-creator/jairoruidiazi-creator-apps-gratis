import 'package:flutter/material.dart';

/// Paleta de Clave: azul noche, ámbar y verde "afinado".
class ClaveColors {
  ClaveColors._();

  static const Color noche = Color(0xFF14213D);
  static const Color ambar = Color(0xFFFCA311);
  static const Color afinado = Color(0xFF2ECC71);
  static const Color cerca = Color(0xFFF4D03F);
  static const Color lejos = Color(0xFFE74C3C);
  static const Color plata = Color(0xFFE5E5E5);
}

class ClaveTheme {
  ClaveTheme._();

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness b) {
    final ColorScheme scheme = ColorScheme.fromSeed(seedColor: ClaveColors.noche, brightness: b, secondary: ClaveColors.ambar);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(centerTitle: false),
      cardTheme: CardThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(56, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
      segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(visualDensity: VisualDensity.compact, shape: WidgetStatePropertyAll<OutlinedBorder>(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
      sliderTheme: const SliderThemeData(showValueIndicator: ShowValueIndicator.onDrag),
    );
  }
}

/// Color según la desviación en cents.
Color colorForCents(double cents, double tolerance) {
  final double a = cents.abs();
  if (a <= tolerance) {
    return ClaveColors.afinado;
  }
  if (a <= tolerance * 3) {
    return ClaveColors.cerca;
  }
  return ClaveColors.lejos;
}
