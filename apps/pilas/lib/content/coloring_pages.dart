import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;

import 'svg_path.dart';

/// Una zona que se puede pintar.
class ColoringRegion {
  ColoringRegion({required this.id, required this.path, required this.number, required this.targetColor});

  final String id;
  final Path path;

  /// Número de la zona en el modo "por números".
  final int number;

  /// Color sugerido en el modo "por números".
  final Color targetColor;
}

/// Trazos decorativos que se dibujan encima (ojos, bocas, detalles).
class ColoringLine {
  ColoringLine({required this.path, required this.width});

  final Path path;
  final double width;
}

class ColoringPage {
  ColoringPage({required this.id, required this.nombre, required this.viewBox, required this.regions, required this.lines, required this.minBand});

  final String id;
  final String nombre;
  final Rect viewBox;
  final List<ColoringRegion> regions;
  final List<ColoringLine> lines;

  /// Índice del tramo mínimo (0 = 3 a 4 años).
  final int minBand;

  /// Colores distintos de la lámina, numerados en orden de aparición.
  List<Color> get palette {
    final List<Color> out = <Color>[];
    for (final ColoringRegion r in regions) {
      if (!out.contains(r.targetColor)) {
        out.add(r.targetColor);
      }
    }
    return out;
  }

  static ColoringPage fromJson(Map<String, dynamic> json) {
    final List<dynamic> vb = (json['vb'] as List<dynamic>?) ?? <dynamic>[0, 0, 100, 100];
    final List<dynamic> regs = (json['regions'] as List<dynamic>?) ?? <dynamic>[];
    final List<dynamic> lines = (json['lines'] as List<dynamic>?) ?? <dynamic>[];
    return ColoringPage(
      id: json['id'] as String,
      nombre: (json['nombre'] as String?) ?? '',
      viewBox: Rect.fromLTWH((vb[0] as num).toDouble(), (vb[1] as num).toDouble(), (vb[2] as num).toDouble(), (vb[3] as num).toDouble()),
      regions: regs.map((dynamic e) {
        final Map<String, dynamic> m = e as Map<String, dynamic>;
        return ColoringRegion(
          id: m['id'] as String,
          path: parseSvgPath(m['d'] as String),
          number: (m['n'] as num?)?.toInt() ?? 1,
          targetColor: parseHexColor((m['c'] as String?) ?? '#FFD166'),
        );
      }).toList(),
      lines: lines.map((dynamic e) {
        final Map<String, dynamic> m = e as Map<String, dynamic>;
        return ColoringLine(path: parseSvgPath(m['d'] as String), width: ((m['w'] as num?) ?? 1.5).toDouble());
      }).toList(),
      minBand: (json['minBand'] as num?)?.toInt() ?? 0,
    );
  }
}

Color parseHexColor(String hex) {
  String h = hex.replaceAll('#', '');
  if (h.length == 6) {
    h = 'FF$h';
  }
  return Color(int.parse(h, radix: 16));
}

/// Carga las láminas desde assets/coloring/index.json.
class ColoringLibrary {
  ColoringLibrary._();

  static List<ColoringPage>? _cache;

  static Future<List<ColoringPage>> load() async {
    final List<ColoringPage>? c = _cache;
    if (c != null) {
      return c;
    }
    final String indexText = await rootBundle.loadString('assets/coloring/index.json');
    final Map<String, dynamic> index = jsonDecode(indexText) as Map<String, dynamic>;
    final List<dynamic> files = (index['pages'] as List<dynamic>?) ?? <dynamic>[];
    final List<ColoringPage> pages = <ColoringPage>[];
    for (final dynamic f in files) {
      final String text = await rootBundle.loadString('assets/coloring/$f');
      pages.add(ColoringPage.fromJson(jsonDecode(text) as Map<String, dynamic>));
    }
    _cache = pages;
    return pages;
  }
}
