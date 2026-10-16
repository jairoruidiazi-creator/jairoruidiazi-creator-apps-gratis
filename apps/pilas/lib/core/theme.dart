import 'package:flutter/material.dart';

/// Colores y estilos de Pilas: fondos cálidos, botones grandes y texto legible.
class PilasColors {
  PilasColors._();

  static const Color fondo = Color(0xFFFFF8EC);
  static const Color fondoOscuro = Color(0xFFFFEFD0);
  static const Color tarjeta = Color(0xFFFFFFFF);
  static const Color tinta = Color(0xFF1F2954);
  static const Color tintaSuave = Color(0xFF5B6386);
  static const Color amarillo = Color(0xFFFFD166);
  static const Color naranja = Color(0xFFFF7A00);
  static const Color verde = Color(0xFF2E9E5B);
  static const Color verdeClaro = Color(0xFFDDF5E6);
  static const Color azul = Color(0xFF2979FF);
  static const Color azulClaro = Color(0xFFDDE8FF);
  static const Color rosa = Color(0xFFE91E63);
  static const Color morado = Color(0xFF7C4DFF);
  static const Color rojoSuave = Color(0xFFFFE0E0);
  static const Color borde = Color(0xFFE8DFC8);
}

class PilasTheme {
  PilasTheme._();

  static ThemeData light({bool highContrast = false, bool dyslexiaFont = false}) {
    final Color tinta = highContrast ? Colors.black : PilasColors.tinta;
    final Color fondo = highContrast ? Colors.white : PilasColors.fondo;
    final String familia = dyslexiaFont ? 'Andika' : 'Lexend';
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: PilasColors.azul,
      primary: PilasColors.azul,
      secondary: PilasColors.naranja,
      surface: fondo,
      onSurface: tinta,
    );
    final TextTheme base = ThemeData.light().textTheme.apply(
          fontFamily: familia,
          bodyColor: tinta,
          displayColor: tinta,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: fondo,
      fontFamily: familia,
      textTheme: base.copyWith(
        displayLarge: base.displayLarge?.copyWith(fontWeight: FontWeight.w700),
        headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 30),
        headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 24),
        titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 22),
        titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 18),
        bodyLarge: base.bodyLarge?.copyWith(fontSize: 18, height: 1.4),
        bodyMedium: base.bodyMedium?.copyWith(fontSize: 16, height: 1.4),
        labelLarge: base.labelLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: fondo,
        foregroundColor: tinta,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(fontFamily: familia, fontSize: 22, fontWeight: FontWeight.w700, color: tinta),
      ),
      cardTheme: CardThemeData(
        color: PilasColors.tarjeta,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: PilasColors.borde, width: 2),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 60),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: TextStyle(fontFamily: familia, fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          side: BorderSide(color: tinta, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: TextStyle(fontFamily: familia, fontSize: 18, fontWeight: FontWeight.w600),
          foregroundColor: tinta,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: TextStyle(fontFamily: familia, fontSize: 18, fontWeight: FontWeight.w600),
          foregroundColor: tinta,
        ),
      ),
      switchTheme: const SwitchThemeData(),
      sliderTheme: const SliderThemeData(trackHeight: 8),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
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
}
