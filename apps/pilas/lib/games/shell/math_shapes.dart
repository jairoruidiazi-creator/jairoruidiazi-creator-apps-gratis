import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Pastel de fracciones: [num] porciones sombreadas de [den].
class FractionPie extends StatelessWidget {
  const FractionPie({super.key, required this.num, required this.den, this.size = 96, this.color = PilasColors.naranja});

  final int num;
  final int den;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(size, size), painter: _PiePainter(num: num, den: den, color: color));
  }
}

class _PiePainter extends CustomPainter {
  const _PiePainter({required this.num, required this.den, required this.color});

  final int num;
  final int den;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    canvas.drawOval(r, Paint()..color = Colors.white);
    final double sweep = 2 * math.pi / den;
    for (int i = 0; i < num; i++) {
      canvas.drawArc(r, -math.pi / 2 + i * sweep, sweep, true, Paint()..color = color);
    }
    final Paint line = Paint()
      ..color = PilasColors.tinta
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawOval(r, line);
    if (den > 1) {
      final Offset c = r.center;
      for (int i = 0; i < den; i++) {
        final double a = -math.pi / 2 + i * sweep;
        canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * (r.width / 2), line);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) => old.num != num || old.den != den || old.color != color;
}

/// Barra de fracciones (chocolatina): [num] cuadros sombreados de [den].
class FractionBar extends StatelessWidget {
  const FractionBar({super.key, required this.num, required this.den, this.width = 160, this.height = 40, this.color = PilasColors.morado});

  final int num;
  final int den;
  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Row(
        children: <Widget>[
          for (int i = 0; i < den; i++)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: i < num ? color : Colors.white,
                  border: Border.all(color: PilasColors.tinta, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Vaso con un nivel de líquido entre 0 y 1.
class GlassFill extends StatelessWidget {
  const GlassFill({super.key, required this.level, this.size = 96, this.color = PilasColors.naranja});

  final double level;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(size * 0.7, size), painter: _GlassPainter(level: level, color: color));
  }
}

class _GlassPainter extends CustomPainter {
  const _GlassPainter({required this.level, required this.color});

  final double level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Path glass = Path()
      ..moveTo(size.width * 0.08, 2)
      ..lineTo(size.width * 0.92, 2)
      ..lineTo(size.width * 0.82, size.height - 2)
      ..lineTo(size.width * 0.18, size.height - 2)
      ..close();
    canvas.save();
    canvas.clipPath(glass);
    final double top = size.height - level.clamp(0.0, 1.0) * (size.height - 6) - 2;
    canvas.drawRect(Rect.fromLTRB(0, top, size.width, size.height), Paint()..color = color.withValues(alpha: 0.85));
    canvas.restore();
    canvas.drawPath(
      glass,
      Paint()
        ..color = PilasColors.tinta
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _GlassPainter old) => old.level != level || old.color != color;
}

/// Figura sobre cuadrícula: celdas rellenas (x, y) en unidades. Sirve para
/// perímetro y área. Si [labels] trae lados, se escriben las medidas.
class GridFigure extends StatelessWidget {
  const GridFigure({super.key, required this.cells, this.cols = 8, this.rows = 6, this.size = 220, this.color = PilasColors.verde, this.showGrid = true, this.labels = const <String, String>{}});

  final List<Offset> cells;
  final int cols;
  final int rows;
  final double size;
  final Color color;
  final bool showGrid;

  /// Etiquetas: 'top', 'bottom', 'left', 'right' → texto.
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    final double unit = size / cols;
    return CustomPaint(size: Size(size, unit * rows), painter: _GridPainter(cells: cells, cols: cols, rows: rows, color: color, showGrid: showGrid, labels: labels));
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.cells, required this.cols, required this.rows, required this.color, required this.showGrid, required this.labels});

  final List<Offset> cells;
  final int cols;
  final int rows;
  final Color color;
  final bool showGrid;
  final Map<String, String> labels;

  @override
  void paint(Canvas canvas, Size size) {
    final double u = size.width / cols;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    if (showGrid) {
      final Paint grid = Paint()
        ..color = const Color(0xFFE3DED2)
        ..strokeWidth = 1;
      for (int i = 0; i <= cols; i++) {
        canvas.drawLine(Offset(i * u, 0), Offset(i * u, size.height), grid);
      }
      for (int j = 0; j <= rows; j++) {
        canvas.drawLine(Offset(0, j * u), Offset(size.width, j * u), grid);
      }
    }
    final Set<String> filled = cells.map((Offset c) => '${c.dx.toInt()},${c.dy.toInt()}').toSet();
    final Paint fill = Paint()..color = color.withValues(alpha: 0.75);
    final Paint edge = Paint()
      ..color = PilasColors.tinta
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (final Offset c in cells) {
      final Rect r = Rect.fromLTWH(c.dx * u, c.dy * u, u, u);
      canvas.drawRect(r, fill);
    }
    // Bordes exteriores (donde no hay celda vecina).
    for (final Offset c in cells) {
      final int x = c.dx.toInt();
      final int y = c.dy.toInt();
      if (!filled.contains('$x,${y - 1}')) {
        canvas.drawLine(Offset(x * u, y * u), Offset((x + 1) * u, y * u), edge);
      }
      if (!filled.contains('$x,${y + 1}')) {
        canvas.drawLine(Offset(x * u, (y + 1) * u), Offset((x + 1) * u, (y + 1) * u), edge);
      }
      if (!filled.contains('${x - 1},$y')) {
        canvas.drawLine(Offset(x * u, y * u), Offset(x * u, (y + 1) * u), edge);
      }
      if (!filled.contains('${x + 1},$y')) {
        canvas.drawLine(Offset((x + 1) * u, y * u), Offset((x + 1) * u, (y + 1) * u), edge);
      }
    }
    if (labels.isNotEmpty && cells.isNotEmpty) {
      double minX = cols.toDouble();
      double maxX = 0;
      double minY = rows.toDouble();
      double maxY = 0;
      for (final Offset c in cells) {
        minX = math.min(minX, c.dx);
        maxX = math.max(maxX, c.dx + 1);
        minY = math.min(minY, c.dy);
        maxY = math.max(maxY, c.dy + 1);
      }
      void label(String? text, Offset at) {
        if (text == null) {
          return;
        }
        final TextPainter tp = TextPainter(
          text: TextSpan(text: text, style: TextStyle(fontSize: u * 0.5, fontWeight: FontWeight.w700, color: PilasColors.tinta, fontFamily: 'Lexend')),
          textDirection: TextDirection.ltr,
        )..layout();
        final Rect bg = Rect.fromCenter(center: at, width: tp.width + 8, height: tp.height + 2);
        canvas.drawRRect(RRect.fromRectAndRadius(bg, const Radius.circular(6)), Paint()..color = Colors.white.withValues(alpha: 0.9));
        tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
      }

      label(labels['top'], Offset((minX + maxX) / 2 * u, minY * u - u * 0.35));
      label(labels['bottom'], Offset((minX + maxX) / 2 * u, maxY * u + u * 0.35));
      label(labels['left'], Offset(minX * u - u * 0.45, (minY + maxY) / 2 * u));
      label(labels['right'], Offset(maxX * u + u * 0.45, (minY + maxY) / 2 * u));
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.cells != cells || old.color != color || old.labels != labels;
}

/// Balanza con dos platillos y un lado más pesado (-1 izquierda, 0 igual, 1 derecha).
class Balance extends StatelessWidget {
  const Balance({super.key, required this.heavier, required this.left, required this.right, this.width = 240});

  final int heavier;
  final Widget left;
  final Widget right;
  final double width;

  @override
  Widget build(BuildContext context) {
    final double tilt = heavier == 0 ? 0 : (heavier < 0 ? -0.12 : 0.12);
    return SizedBox(
      width: width,
      height: width * 0.6,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned(bottom: 0, child: Container(width: width * 0.3, height: 8, decoration: BoxDecoration(color: PilasColors.tinta, borderRadius: BorderRadius.circular(4)))),
          Positioned(bottom: 6, child: Container(width: 8, height: width * 0.3, color: PilasColors.tinta)),
          Transform.rotate(
            angle: tilt,
            child: SizedBox(
              width: width,
              height: width * 0.4,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Container(width: width * 0.9, height: 6, decoration: BoxDecoration(color: PilasColors.tinta, borderRadius: BorderRadius.circular(3))),
                  Positioned(left: 0, top: 0, child: _plate(left, width)),
                  Positioned(right: 0, top: 0, child: _plate(right, width)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _plate(Widget child, double width) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(width: width * 0.3, height: width * 0.22, child: Center(child: child)),
        Container(width: width * 0.32, height: 6, decoration: BoxDecoration(color: PilasColors.tintaSuave, borderRadius: BorderRadius.circular(3))),
      ],
    );
  }
}
