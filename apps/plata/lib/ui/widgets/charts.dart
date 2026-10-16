import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class PieSlice {
  const PieSlice({required this.value, required this.color, required this.label});

  final double value;
  final Color color;
  final String label;
}

/// Dona con etiqueta central.
class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.slices, this.size = 180, this.centerTitle = '', this.centerSubtitle = '', this.selected});

  final List<PieSlice> slices;
  final double size;
  final String centerTitle;
  final String centerSubtitle;
  final int? selected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CustomPaint(size: Size.square(size), painter: _DonutPainter(slices: slices, track: cs.surfaceContainerHighest, selected: selected)),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(centerTitle, style: TextStyle(fontSize: size * 0.1, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
              if (centerSubtitle.isNotEmpty) Text(centerSubtitle, style: TextStyle(fontSize: size * 0.065, color: cs.onSurface.withValues(alpha: 0.6)), textAlign: TextAlign.center),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices, required this.track, this.selected});

  final List<PieSlice> slices;
  final Color track;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final double total = slices.fold<double>(0, (double s, PieSlice p) => s + (p.value > 0 ? p.value : 0));
    final Rect rect = Rect.fromLTWH(size.width * 0.1, size.height * 0.1, size.width * 0.8, size.height * 0.8);
    final double stroke = size.width * 0.14;
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, 0, math.pi * 2, false, p..color = track);
    if (total <= 0) {
      return;
    }
    double start = -math.pi / 2;
    for (int i = 0; i < slices.length; i++) {
      final PieSlice s = slices[i];
      if (s.value <= 0) {
        continue;
      }
      final double sweep = s.value / total * math.pi * 2;
      final bool sel = selected == i;
      final Rect r = sel ? rect.inflate(size.width * 0.03) : rect;
      canvas.drawArc(r, start, math.max(sweep - 0.02, 0.005), false, p..color = s.color..strokeWidth = sel ? stroke * 1.15 : stroke);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.slices != slices || old.selected != selected;
}

class BarGroup {
  const BarGroup({required this.label, required this.values});

  final String label;

  /// Una barra por valor (por ejemplo ingresos y gastos).
  final List<double> values;
}

/// Barras agrupadas con eje de valores.
class BarsChart extends StatelessWidget {
  const BarsChart({super.key, required this.groups, required this.colors, this.height = 180, this.formatValue, this.highlight});

  final List<BarGroup> groups;
  final List<Color> colors;
  final double height;
  final String Function(double)? formatValue;
  final int? highlight;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _BarsPainter(groups: groups, colors: colors, grid: cs.outlineVariant, text: cs.onSurface, formatValue: formatValue ?? _defaultFormat, highlight: highlight)),
    );
  }

  static String _defaultFormat(double v) => v >= 1000000 ? '${(v / 1000000).toStringAsFixed(1)}M' : (v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toStringAsFixed(0));
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.groups, required this.colors, required this.grid, required this.text, required this.formatValue, this.highlight});

  final List<BarGroup> groups;
  final List<Color> colors;
  final Color grid;
  final Color text;
  final String Function(double) formatValue;
  final int? highlight;

  @override
  void paint(Canvas canvas, Size size) {
    const double left = 44;
    const double bottom = 22;
    const double top = 8;
    final double w = size.width - left - 8;
    final double h = size.height - bottom - top;
    double maxV = 0;
    for (final BarGroup g in groups) {
      for (final double v in g.values) {
        maxV = math.max(maxV, v.abs());
      }
    }
    if (maxV <= 0) {
      maxV = 1;
    }
    final double step = _niceStep(maxV / 4);
    final double axisMax = (maxV / step).ceil() * step;
    final Paint gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (double v = 0; v <= axisMax + 1e-9; v += step) {
      final double y = top + h - v / axisMax * h;
      canvas.drawLine(Offset(left, y), Offset(size.width - 8, y), gp);
      _text(canvas, formatValue(v), Offset(0, y - 6), left - 4, TextAlign.right, 10);
    }
    if (groups.isEmpty) {
      return;
    }
    final double groupW = w / groups.length;
    final int n = groups.first.values.length;
    final double barW = math.min(groupW * 0.7 / n, 28);
    for (int i = 0; i < groups.length; i++) {
      final BarGroup g = groups[i];
      final double gx = left + i * groupW + (groupW - barW * n) / 2;
      for (int k = 0; k < g.values.length; k++) {
        final double v = g.values[k];
        final double bh = v.abs() / axisMax * h;
        final Paint bp = Paint()..color = colors[k % colors.length].withValues(alpha: highlight == null || highlight == i ? 1 : 0.35);
        final Rect r = Rect.fromLTWH(gx + k * barW, top + h - bh, barW - 2, bh);
        canvas.drawRRect(RRect.fromRectAndCorners(r, topLeft: const Radius.circular(4), topRight: const Radius.circular(4)), bp);
      }
      _text(canvas, g.label, Offset(left + i * groupW, top + h + 4), groupW, TextAlign.center, 10);
    }
  }

  void _text(Canvas canvas, String s, Offset at, double width, TextAlign align, double fontSize) {
    final ui.ParagraphBuilder pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: align, fontSize: fontSize, maxLines: 1, ellipsis: '…'))
      ..pushStyle(ui.TextStyle(color: text.withValues(alpha: 0.7)))
      ..addText(s);
    final ui.Paragraph p = pb.build()..layout(ui.ParagraphConstraints(width: width));
    canvas.drawParagraph(p, at);
  }

  static double _niceStep(double raw) {
    if (raw <= 0) {
      return 1;
    }
    final double mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final double norm = raw / mag;
    final double nice = norm <= 1 ? 1 : (norm <= 2 ? 2 : (norm <= 5 ? 5 : 10));
    return nice * mag;
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => old.groups != groups || old.highlight != highlight;
}

/// Línea simple (por ejemplo el neto por periodo o el saldo).
class LineChart extends StatelessWidget {
  const LineChart({super.key, required this.values, required this.labels, this.height = 140, this.color});

  final List<double> values;
  final List<String> labels;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _LinePainter(values: values, labels: labels, color: color ?? cs.primary, grid: cs.outlineVariant, text: cs.onSurface)));
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.values, required this.labels, required this.color, required this.grid, required this.text});

  final List<double> values;
  final List<String> labels;
  final Color color;
  final Color grid;
  final Color text;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) {
      return;
    }
    const double bottom = 20;
    const double top = 8;
    final double h = size.height - bottom - top;
    double minV = values.reduce(math.min);
    double maxV = values.reduce(math.max);
    if (minV > 0) {
      minV = 0;
    }
    if (maxV < 0) {
      maxV = 0;
    }
    if (maxV - minV < 1e-9) {
      maxV = minV + 1;
    }
    double y(double v) => top + h - (v - minV) / (maxV - minV) * h;
    final double zero = y(0);
    canvas.drawLine(Offset(0, zero), Offset(size.width, zero), Paint()..color = grid..strokeWidth = 1);
    final double dx = values.length == 1 ? size.width : size.width / (values.length - 1);
    final Path path = Path();
    for (int i = 0; i < values.length; i++) {
      final Offset p = Offset(values.length == 1 ? size.width / 2 : i * dx, y(values[i]));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeJoin = StrokeJoin.round);
    for (int i = 0; i < values.length; i++) {
      final Offset p = Offset(values.length == 1 ? size.width / 2 : i * dx, y(values[i]));
      canvas.drawCircle(p, 3.5, Paint()..color = values[i] >= 0 ? color : Colors.redAccent);
      if (i < labels.length) {
        final ui.ParagraphBuilder pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 10, maxLines: 1))
          ..pushStyle(ui.TextStyle(color: text.withValues(alpha: 0.7)))
          ..addText(labels[i]);
        final ui.Paragraph par = pb.build()..layout(ui.ParagraphConstraints(width: math.max(dx, 30)));
        canvas.drawParagraph(par, Offset(p.dx - math.max(dx, 30) / 2, top + h + 4));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.values != values;
}
