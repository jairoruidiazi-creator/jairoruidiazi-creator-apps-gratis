import 'package:flutter/material.dart';

import 'catalog.dart';

/// Tema de Rutinas: Material 3 con el color de acento elegido, claro u oscuro.
class RutinasTheme {
  RutinasTheme._();

  static Color accentColor(int index) => kAccents[index.clamp(0, kAccents.length - 1)].color;

  static ThemeData build(Brightness brightness, int accent) {
    final ColorScheme scheme = ColorScheme.fromSeed(seedColor: accentColor(accent), brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Flechas y marcas que Roboto no trae (subconjunto de DejaVu Sans).
      fontFamilyFallback: const <String>['Simbolos'],
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: const AppBarTheme(centerTitle: false),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(64, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48, 48))),
      chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(shape: WidgetStatePropertyAll<OutlinedBorder>(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
      sliderTheme: const SliderThemeData(showValueIndicator: ShowValueIndicator.onDrag),
      listTileTheme: const ListTileThemeData(minVerticalPadding: 10),
      // Cinco destinos en 360 dp: las etiquetas van un punto más pequeñas para
      // que quepan enteras también con el texto agrandado (hasta 1,3).
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((Set<WidgetState> states) {
          final bool selected = states.contains(WidgetState.selected);
          return TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? scheme.onSurface : scheme.onSurfaceVariant);
        }),
      ),
    );
  }
}
