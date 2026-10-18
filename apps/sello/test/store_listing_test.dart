import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// G12: la ficha (y el README) solo dicen lo que la app hace. Frases que en
/// su momento prometían funciones que no existían y no deben volver.
void main() {
  const List<String> texts = <String>[
    'fastlane/metadata/android/es-419/full_description.txt',
    'fastlane/metadata/android/en-US/full_description.txt',
    'fastlane/metadata/android/es-419/short_description.txt',
    'fastlane/metadata/android/en-US/short_description.txt',
    'fastlane/metadata/ios/es-MX/description.txt',
    'fastlane/metadata/ios/en-US/description.txt',
    'fastlane/metadata/ios/es-MX/promotional_text.txt',
    'fastlane/metadata/ios/en-US/promotional_text.txt',
    'README.md',
  ];
  final List<RegExp> falseClaims = <RegExp>[
    // No hay editor de orden: los datos salen en un orden fijo.
    RegExp(r'en el orden que quieras', caseSensitive: false),
    RegExp(r'in the order you want', caseSensitive: false),
    // Los campos no se piden antes de cada foto: se llenan en la cámara y se conservan.
    RegExp(r'antes de cada foto', caseSensitive: false),
    RegExp(r'before each photo', caseSensitive: false),
    // El PDF pone varias fichas por página.
    RegExp(r'one page per photo', caseSensitive: false),
    RegExp(r'una página por foto', caseSensitive: false),
    // La posición del GPS no es milimétrica (lo es el cálculo de las proyecciones).
    RegExp(r'precisión milimétrica', caseSensitive: false),
    RegExp(r'millimet(er|re) accuracy', caseSensitive: false),
    // El KML lleva solo los puntos; las fotos van en el KMZ (M13).
    RegExp(r'KML y KMZ con las fotos', caseSensitive: false),
    RegExp(r'KML and KMZ with the photos', caseSensitive: false),
    RegExp(r'KML con (las )?fotos', caseSensitive: false),
    RegExp(r'KML with (the )?photos', caseSensitive: false),
  ];

  test('Ninguna frase promete algo que la app no hace', () {
    for (final String path in texts) {
      final String text = File(path).readAsStringSync();
      for (final RegExp claim in falseClaims) {
        expect(claim.hasMatch(text), isFalse, reason: '$path: "${claim.pattern}"');
      }
    }
  });

  test('La ficha de Android no habla del iPhone ni la de iOS de Android', () {
    for (final String path in texts.where((String p) => p.contains('/android/'))) {
      expect(RegExp(r'\b(iPhone|iPad|iOS|App Store)\b').hasMatch(File(path).readAsStringSync()), isFalse, reason: path);
    }
    for (final String path in texts.where((String p) => p.contains('/ios/'))) {
      expect(RegExp(r'\b(Android|Google Play)\b').hasMatch(File(path).readAsStringSync()), isFalse, reason: path);
    }
  });
}
