import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme.dart';

/// Pictograma de Twemoji por código, por ejemplo '1f431'.
class EmojiImage extends StatelessWidget {
  const EmojiImage(this.code, {super.key, this.size = 64, this.semanticsLabel});

  final String code;
  final double size;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    if (size <= 0) {
      return const SizedBox.shrink();
    }
    return SvgPicture.asset(
      'assets/emoji/$code.svg',
      width: size,
      height: size,
      semanticsLabel: semanticsLabel,
      placeholderBuilder: (BuildContext context) => SizedBox(width: size, height: size),
    );
  }
}

/// Pilo, la mascota: un rayo amarillo con cara. Dibujado con código.
class Mascot extends StatelessWidget {
  const Mascot({super.key, this.size = 96, this.happy = true});

  final double size;
  final bool happy;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(size, size), painter: _MascotPainter(happy: happy));
  }
}

class _MascotPainter extends CustomPainter {
  const _MascotPainter({required this.happy});

  final bool happy;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Paint body = Paint()..color = PilasColors.amarillo;
    final Paint ink = Paint()..color = PilasColors.tinta;
    final Path bolt = Path()
      ..moveTo(0.56 * s, 0.04 * s)
      ..lineTo(0.26 * s, 0.54 * s)
      ..lineTo(0.46 * s, 0.54 * s)
      ..lineTo(0.38 * s, 0.98 * s)
      ..lineTo(0.76 * s, 0.42 * s)
      ..lineTo(0.55 * s, 0.42 * s)
      ..lineTo(0.64 * s, 0.04 * s)
      ..close();
    canvas.drawShadow(bolt, Colors.black.withValues(alpha: 0.25), 3, true);
    canvas.drawPath(bolt, body);
    final double r = 0.035 * s;
    canvas.drawCircle(Offset(0.47 * s, 0.30 * s), r, ink);
    canvas.drawCircle(Offset(0.58 * s, 0.30 * s), r, ink);
    final Paint stroke = Paint()
      ..color = PilasColors.tinta
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, 0.02 * s)
      ..strokeCap = StrokeCap.round;
    final Rect mouth = Rect.fromLTWH(0.455 * s, 0.33 * s, 0.14 * s, 0.09 * s);
    if (happy) {
      canvas.drawArc(mouth, 0.2, math.pi - 0.4, false, stroke);
    } else {
      canvas.drawLine(Offset(0.47 * s, 0.40 * s), Offset(0.58 * s, 0.40 * s), stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _MascotPainter oldDelegate) => oldDelegate.happy != happy;
}

/// Estado visual de una opción.
enum TileStatus { normal, correct, wrong, dim, selected }

/// Tarjeta grande para elegir. Se sacude al fallar y se ilumina al acertar.
class OptionTile extends StatefulWidget {
  const OptionTile({
    super.key,
    required this.child,
    required this.onTap,
    this.status = TileStatus.normal,
    this.semanticsLabel,
    this.padding = const EdgeInsets.all(12),
    this.color,
    this.minHeight = Dim.tapMin,
  });

  final Widget child;
  final VoidCallback? onTap;
  final TileStatus status;
  final String? semanticsLabel;
  final EdgeInsets padding;
  final Color? color;
  final double minHeight;

  @override
  State<OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<OptionTile> with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didUpdateWidget(covariant OptionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status == TileStatus.wrong && oldWidget.status != TileStatus.wrong) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Color _border() {
    switch (widget.status) {
      case TileStatus.correct:
        return PilasColors.verde;
      case TileStatus.wrong:
        return PilasColors.naranja;
      case TileStatus.selected:
        return PilasColors.azul;
      case TileStatus.dim:
      case TileStatus.normal:
        return PilasColors.borde;
    }
  }

  Color _fill() {
    switch (widget.status) {
      case TileStatus.correct:
        return PilasColors.verdeClaro;
      case TileStatus.wrong:
        return PilasColors.rojoSuave;
      case TileStatus.selected:
        return PilasColors.azulClaro;
      case TileStatus.dim:
        return const Color(0xFFF3F0E8);
      case TileStatus.normal:
        return widget.color ?? Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double opacity = widget.status == TileStatus.dim ? 0.45 : 1.0;
    return AnimatedBuilder(
      animation: _shake,
      builder: (BuildContext context, Widget? child) {
        final double t = _shake.value;
        final double dx = math.sin(t * math.pi * 6) * (1 - t) * 10;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Semantics(
        button: true,
        label: widget.semanticsLabel,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: opacity,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(Dim.radio),
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                constraints: BoxConstraints(minHeight: widget.minHeight, minWidth: Dim.tapMin),
                padding: widget.padding,
                decoration: BoxDecoration(
                  color: _fill(),
                  borderRadius: BorderRadius.circular(Dim.radio),
                  border: Border.all(color: _border(), width: widget.status == TileStatus.normal ? 2 : 4),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 3)),
                  ],
                ),
                child: Center(child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón redondo con ícono, grande para dedos pequeños.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.size = 56,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: color ?? Colors.white,
        shape: const CircleBorder(side: BorderSide(color: PilasColors.borde, width: 2)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size * 0.5, color: PilasColors.tinta),
          ),
        ),
      ),
    );
  }
}

/// Puntos de progreso de la regla 3 de 4.
class ProgressDots extends StatelessWidget {
  const ProgressDots({super.key, required this.recent, this.total = 4});

  final List<bool> recent;
  final int total;

  @override
  Widget build(BuildContext context) {
    final List<Widget> dots = <Widget>[];
    for (int i = 0; i < total; i++) {
      Color c = const Color(0xFFE3DCCB);
      if (i < recent.length) {
        c = recent[i] ? PilasColors.verde : PilasColors.naranja;
      }
      dots.add(Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      ));
    }
    return Semantics(
      label: 'Progreso del nivel: ${recent.where((bool b) => b).length} de $total',
      child: Row(mainAxisSize: MainAxisSize.min, children: dots),
    );
  }
}

/// Texto grande para los niños que leen; se oculta para los más pequeños si se pide.
class BigText extends StatelessWidget {
  const BigText(this.text, {super.key, this.size = 24, this.weight = FontWeight.w600, this.align = TextAlign.center, this.color});

  final String text;
  final double size;
  final FontWeight weight;
  final TextAlign align;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: align,
      style: TextStyle(fontSize: size, fontWeight: weight, color: color ?? PilasColors.tinta, height: 1.25),
    );
  }
}

/// Figura geométrica de color, dibujada con código.
enum ShapeKind { circle, square, triangle, star, heart, hexagon, rectangle, oval }

class ShapeIcon extends StatelessWidget {
  const ShapeIcon({super.key, required this.kind, required this.color, this.size = 64});

  final ShapeKind kind;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(size, size), painter: _ShapePainter(kind, color));
  }
}

class _ShapePainter extends CustomPainter {
  const _ShapePainter(this.kind, this.color);

  final ShapeKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()..color = color;
    final Paint edge = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final double w = size.width;
    final double h = size.height;
    final Offset c = Offset(w / 2, h / 2);
    final Path p = Path();
    switch (kind) {
      case ShapeKind.circle:
        p.addOval(Rect.fromCircle(center: c, radius: w * 0.42));
        break;
      case ShapeKind.oval:
        p.addOval(Rect.fromCenter(center: c, width: w * 0.9, height: h * 0.58));
        break;
      case ShapeKind.square:
        p.addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: w * 0.78, height: h * 0.78), const Radius.circular(6)));
        break;
      case ShapeKind.rectangle:
        p.addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: w * 0.9, height: h * 0.5), const Radius.circular(6)));
        break;
      case ShapeKind.triangle:
        p.moveTo(w / 2, h * 0.08);
        p.lineTo(w * 0.94, h * 0.9);
        p.lineTo(w * 0.06, h * 0.9);
        p.close();
        break;
      case ShapeKind.hexagon:
        for (int i = 0; i < 6; i++) {
          final double a = math.pi / 3 * i - math.pi / 6;
          final Offset o = Offset(c.dx + math.cos(a) * w * 0.44, c.dy + math.sin(a) * w * 0.44);
          if (i == 0) {
            p.moveTo(o.dx, o.dy);
          } else {
            p.lineTo(o.dx, o.dy);
          }
        }
        p.close();
        break;
      case ShapeKind.star:
        for (int i = 0; i < 10; i++) {
          final double r = i.isEven ? w * 0.46 : w * 0.2;
          final double a = -math.pi / 2 + math.pi / 5 * i;
          final Offset o = Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r);
          if (i == 0) {
            p.moveTo(o.dx, o.dy);
          } else {
            p.lineTo(o.dx, o.dy);
          }
        }
        p.close();
        break;
      case ShapeKind.heart:
        p.moveTo(w * 0.5, h * 0.88);
        p.cubicTo(w * 0.1, h * 0.6, w * 0.02, h * 0.22, w * 0.3, h * 0.14);
        p.cubicTo(w * 0.42, h * 0.1, w * 0.5, h * 0.22, w * 0.5, h * 0.3);
        p.cubicTo(w * 0.5, h * 0.22, w * 0.58, h * 0.1, w * 0.7, h * 0.14);
        p.cubicTo(w * 0.98, h * 0.22, w * 0.9, h * 0.6, w * 0.5, h * 0.88);
        p.close();
        break;
    }
    canvas.drawPath(p, fill);
    canvas.drawPath(p, edge);
  }

  @override
  bool shouldRepaint(covariant _ShapePainter oldDelegate) => oldDelegate.kind != kind || oldDelegate.color != color;
}

/// Colores con nombre para los juegos de los más pequeños.
class NamedColor {
  const NamedColor(this.id, this.nombre, this.color);

  final String id;
  final String nombre;
  final Color color;

  static const List<NamedColor> basicos = <NamedColor>[
    NamedColor('rojo', 'rojo', Color(0xFFE53935)),
    NamedColor('azul', 'azul', Color(0xFF1E88E5)),
    NamedColor('amarillo', 'amarillo', Color(0xFFFDD835)),
    NamedColor('verde', 'verde', Color(0xFF43A047)),
    NamedColor('naranja', 'naranja', Color(0xFFFB8C00)),
    NamedColor('morado', 'morado', Color(0xFF8E24AA)),
    NamedColor('rosado', 'rosado', Color(0xFFEC407A)),
    NamedColor('cafe', 'café', Color(0xFF6D4C41)),
  ];
}

String nombreForma(ShapeKind k) {
  switch (k) {
    case ShapeKind.circle:
      return 'círculo';
    case ShapeKind.square:
      return 'cuadrado';
    case ShapeKind.triangle:
      return 'triángulo';
    case ShapeKind.star:
      return 'estrella';
    case ShapeKind.heart:
      return 'corazón';
    case ShapeKind.hexagon:
      return 'hexágono';
    case ShapeKind.rectangle:
      return 'rectángulo';
    case ShapeKind.oval:
      return 'óvalo';
  }
}
