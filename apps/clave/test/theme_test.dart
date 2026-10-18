// Contraste de los colores propios de Clave en los dos temas (G7).

import 'dart:math' as math;

import 'package:clave/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Relación de contraste de WCAG entre dos colores.
double contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final bool dark in <bool>[false, true]) {
    test('Colores de afinación, acento y grabación con contraste suficiente en el tema ${dark ? 'oscuro' : 'claro'} (G7)', () {
      final ThemeData theme = dark ? ClaveTheme.dark() : ClaveTheme.light();
      final ClavePalette p = theme.extension<ClavePalette>()!;
      final ColorScheme cs = theme.colorScheme;
      final Map<String, Color> colors = <String, Color>{'afinado': p.inTune, 'cerca': p.near, 'lejos': p.far, 'acento': p.accent, 'grabar': p.record};
      for (final MapEntry<String, Color> e in colors.entries) {
        // Como texto (la nota, los cents, el tempo del entrenador): 4,5:1.
        expect(contrast(e.value, cs.surface), greaterThanOrEqualTo(4.5), reason: '${e.key} sobre el fondo');
        // Como indicador sobre una tarjeta (aguja, barras, bordes): 3:1.
        expect(contrast(e.value, cs.surfaceContainerHighest), greaterThanOrEqualTo(3), reason: '${e.key} sobre una tarjeta');
      }
      expect(contrast(p.onAccent, p.accent), greaterThanOrEqualTo(4.5));
      expect(contrast(p.onRecord, p.record), greaterThanOrEqualTo(4.5));
    });
  }
}
