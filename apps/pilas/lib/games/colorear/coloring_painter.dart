import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../content/coloring_pages.dart';

/// Calcula, para cada zona, un punto visible donde poner su número.
class ColoringLayout {
  ColoringLayout(this.page) {
    _labelPoints = <String, Offset>{};
    for (int i = 0; i < page.regions.length; i++) {
      _labelPoints[page.regions[i].id] = _labelPoint(i);
    }
  }

  final ColoringPage page;
  late final Map<String, Offset> _labelPoints;

  Offset labelPoint(ColoringRegion r) => _labelPoints[r.id] ?? r.path.getBounds().center;

  Offset _labelPoint(int index) {
    final ColoringRegion r = page.regions[index];
    final Rect b = r.path.getBounds();
    final Offset center = b.center;
    Offset? best;
    double bestDist = double.infinity;
    const int n = 14;
    for (int i = 1; i < n; i++) {
      for (int j = 1; j < n; j++) {
        final Offset p = Offset(b.left + b.width * i / n, b.top + b.height * j / n);
        if (!r.path.contains(p)) {
          continue;
        }
        bool covered = false;
        for (int k = index + 1; k < page.regions.length; k++) {
          if (page.regions[k].path.contains(p)) {
            covered = true;
            break;
          }
        }
        if (covered) {
          continue;
        }
        final double d = (p - center).distanceSquared;
        if (d < bestDist) {
          bestDist = d;
          best = p;
        }
      }
    }
    return best ?? center;
  }

  /// Zona tocada en coordenadas de la lámina (la de más arriba gana).
  ColoringRegion? hitTest(Offset p) {
    for (int i = page.regions.length - 1; i >= 0; i--) {
      if (page.regions[i].path.contains(p)) {
        return page.regions[i];
      }
    }
    return null;
  }

  /// Transformación de la lámina al lienzo: ajuste proporcional centrado.
  static Matrix4 fit(Rect viewBox, Size size) {
    final double scale = (size.width / viewBox.width) < (size.height / viewBox.height) ? size.width / viewBox.width : size.height / viewBox.height;
    final double dx = (size.width - viewBox.width * scale) / 2 - viewBox.left * scale;
    final double dy = (size.height - viewBox.height * scale) / 2 - viewBox.top * scale;
    return Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  static Offset toPage(Rect viewBox, Size size, Offset local) {
    final double scale = (size.width / viewBox.width) < (size.height / viewBox.height) ? size.width / viewBox.width : size.height / viewBox.height;
    final double dx = (size.width - viewBox.width * scale) / 2 - viewBox.left * scale;
    final double dy = (size.height - viewBox.height * scale) / 2 - viewBox.top * scale;
    return Offset((local.dx - dx) / scale, (local.dy - dy) / scale);
  }
}

/// Dibuja la lámina con los colores puestos hasta ahora.
class ColoringPainter extends CustomPainter {
  ColoringPainter({
    required this.layout,
    required this.fills,
    required this.showNumbers,
    this.highlight,
  });

  final ColoringLayout layout;
  final Map<String, Color> fills;
  final bool showNumbers;

  /// Zona que se resalta un momento (al tocar con el color equivocado).
  final String? highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final ColoringPage page = layout.page;
    canvas.save();
    canvas.transform(ColoringLayout.fit(page.viewBox, size).storage);
    final Paint fill = Paint()..style = PaintingStyle.fill;
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF263238)
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round;
    for (final ColoringRegion r in page.regions) {
      fill.color = fills[r.id] ?? Colors.white;
      canvas.drawPath(r.path, fill);
    }
    for (final ColoringRegion r in page.regions) {
      canvas.drawPath(r.path, stroke);
    }
    for (final ColoringLine l in page.lines) {
      final Paint lp = Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFF263238)
        ..strokeWidth = l.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(l.path, lp);
    }
    if (highlight != null) {
      for (final ColoringRegion r in page.regions) {
        if (r.id == highlight) {
          final Paint hp = Paint()
            ..style = PaintingStyle.stroke
            ..color = const Color(0xFFFF7A00)
            ..strokeWidth = 3;
          canvas.drawPath(r.path, hp);
        }
      }
    }
    if (showNumbers) {
      for (final ColoringRegion r in page.regions) {
        if (fills.containsKey(r.id)) {
          continue;
        }
        final Offset p = layout.labelPoint(r);
        const double fontSize = 6.5;
        final ui.ParagraphBuilder pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: fontSize, fontFamily: 'Lexend', fontWeight: FontWeight.w700))
          ..pushStyle(ui.TextStyle(color: const Color(0xFF263238), fontSize: fontSize, fontWeight: FontWeight.w700))
          ..addText('${r.number}');
        final ui.Paragraph para = pb.build()..layout(const ui.ParagraphConstraints(width: 20));
        const double bgR = fontSize * 0.75;
        canvas.drawCircle(p, bgR, Paint()..color = Colors.white.withValues(alpha: 0.85));
        canvas.drawParagraph(para, Offset(p.dx - 10, p.dy - para.height / 2));
      }
    }
    canvas.restore();
    // Un marco fino alrededor del área útil.
    final Rect area = MatrixUtils.transformRect(ColoringLayout.fit(page.viewBox, size), page.viewBox);
    canvas.drawRRect(
      RRect.fromRectAndRadius(area.deflate(0.5), const Radius.circular(2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFFE8DFC8)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant ColoringPainter oldDelegate) {
    return oldDelegate.fills != fills || oldDelegate.showNumbers != showNumbers || oldDelegate.highlight != highlight || oldDelegate.layout != layout;
  }
}
