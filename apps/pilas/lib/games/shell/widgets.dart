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
    final Widget image = SvgPicture.asset(
      'assets/emoji/$code.svg',
      width: size,
      height: size,
      excludeFromSemantics: semanticsLabel == null,
      semanticsLabel: semanticsLabel,
      placeholderBuilder: (BuildContext context) => SizedBox(width: size, height: size),
    );
    return image;
  }
}

/// Pilo, la mascota: un rayo amarillo con cara. Dibujado con código.
class Mascot extends StatelessWidget {
  const Mascot({super.key, this.size = 96, this.happy = true});

  final double size;
  final bool happy;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(child: CustomPaint(size: Size(size, size), painter: _MascotPainter(happy: happy, ink: PilasPalette.of(context).tinta)));
  }
}

class _MascotPainter extends CustomPainter {
  const _MascotPainter({required this.happy, required this.ink});

  final bool happy;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Paint body = Paint()..color = PilasColors.amarillo;
    final Paint inkPaint = Paint()..color = ink;
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
    canvas.drawCircle(Offset(0.47 * s, 0.30 * s), r, inkPaint);
    canvas.drawCircle(Offset(0.58 * s, 0.30 * s), r, inkPaint);
    final Paint stroke = Paint()
      ..color = ink
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
  bool shouldRepaint(covariant _MascotPainter oldDelegate) => oldDelegate.happy != happy || oldDelegate.ink != ink;
}

/// Estado visual de una opción.
enum TileStatus { normal, correct, wrong, dim, selected }

/// Tarjeta grande para elegir. Se sacude al fallar y se ilumina al acertar.
/// El contenido se centra y nunca se sale de la tarjeta.
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
    this.minWidth = Dim.tapMin,
  });

  final Widget child;
  final VoidCallback? onTap;
  final TileStatus status;
  final String? semanticsLabel;
  final EdgeInsets padding;
  final Color? color;
  final double minHeight;
  final double minWidth;

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

  Color _border(PilasPalette pal) {
    switch (widget.status) {
      case TileStatus.correct:
        return pal.correcto;
      case TileStatus.wrong:
        return pal.error;
      case TileStatus.selected:
        return pal.acento;
      case TileStatus.dim:
      case TileStatus.normal:
        return pal.altoContraste ? pal.bordeFuerte : pal.borde;
    }
  }

  Color _fill(PilasPalette pal) {
    switch (widget.status) {
      case TileStatus.correct:
        return pal.correctoClaro;
      case TileStatus.wrong:
        return pal.errorClaro;
      case TileStatus.selected:
        return pal.acentoClaro;
      case TileStatus.dim:
        return pal.altoContraste ? pal.tarjeta : const Color(0xFFF3F0E8);
      case TileStatus.normal:
        return widget.color ?? pal.tarjeta;
    }
  }

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    final double opacity = widget.status == TileStatus.dim ? (pal.altoContraste ? 0.6 : 0.45) : 1.0;
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
        excludeSemantics: widget.semanticsLabel != null,
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
                constraints: BoxConstraints(minHeight: widget.minHeight, minWidth: widget.minWidth),
                padding: widget.padding,
                decoration: BoxDecoration(
                  color: _fill(pal),
                  borderRadius: BorderRadius.circular(Dim.radio),
                  border: Border.all(color: _border(pal), width: widget.status == TileStatus.normal ? (pal.altoContraste ? 3 : 2) : 4),
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
    final PilasPalette pal = PilasPalette.of(context);
    final bool enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: color ?? pal.tarjeta,
          shape: CircleBorder(side: BorderSide(color: pal.altoContraste ? pal.bordeFuerte : pal.borde, width: 2)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: size * 0.5, color: pal.tinta),
            ),
          ),
        ),
      ),
    );
  }
}

/// Puntos de progreso de la regla de dominio (uno por ronda de la ventana).
class ProgressDots extends StatelessWidget {
  const ProgressDots({super.key, required this.recent, this.total = 6});

  final List<bool> recent;
  final int total;

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    final List<Widget> dots = <Widget>[];
    for (int i = 0; i < total; i++) {
      Widget dot;
      if (i < recent.length && recent[i]) {
        // Acierto al primer intento: círculo lleno.
        dot = Container(width: 14, height: 14, decoration: BoxDecoration(color: pal.correcto, shape: BoxShape.circle));
      } else if (i < recent.length) {
        // Ronda con error: cuadrito (no se distingue solo por el color).
        dot = Container(width: 13, height: 13, decoration: BoxDecoration(color: pal.pista, borderRadius: BorderRadius.circular(3)));
      } else {
        // Ronda que falta: anillo.
        dot = Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: pal.cuadricula, width: 2)));
      }
      dots.add(Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: dot));
    }
    final int aciertos = recent.where((bool b) => b).length;
    return Semantics(
      label: 'Progreso del nivel: $aciertos ${aciertos == 1 ? 'acierto' : 'aciertos'} al primer intento en ${recent.length} de $total rondas',
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: dots),
    );
  }
}

/// Texto grande centrado para títulos y mensajes.
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
      style: TextStyle(fontSize: size, fontWeight: weight, color: color ?? PilasPalette.of(context).tinta, height: 1.25),
    );
  }
}

/// Figura geométrica de color, dibujada con código.
enum ShapeKind { circle, square, triangle, star, heart, hexagon, rectangle, oval, pentagon, octagon }

/// Colores con nombre para los juegos de los más pequeños. Cada uno tiene una
/// marca propia que se dibuja dentro de la figura en alto contraste, para que
/// no haga falta distinguir los colores (daltonismo).
class NamedColor {
  const NamedColor(this.id, this.nombre, this.color, this.mark);

  final String id;
  final String nombre;
  final Color color;
  final ColorMark mark;

  static const List<NamedColor> basicos = <NamedColor>[
    NamedColor('rojo', 'rojo', Color(0xFFE53935), ColorMark.punto),
    NamedColor('azul', 'azul', Color(0xFF1E88E5), ColorMark.rayasHorizontales),
    NamedColor('amarillo', 'amarillo', Color(0xFFFDD835), ColorMark.anillo),
    NamedColor('verde', 'verde', Color(0xFF43A047), ColorMark.rayasDiagonales),
    NamedColor('naranja', 'naranja', Color(0xFFFB8C00), ColorMark.cruz),
    NamedColor('morado', 'morado', Color(0xFF8E24AA), ColorMark.rayasVerticales),
    NamedColor('rosado', 'rosado', Color(0xFFEC407A), ColorMark.dosPuntos),
    NamedColor('cafe', 'café', Color(0xFF6D4C41), ColorMark.raya),
  ];
}

/// Marca interior de cada color (ver [NamedColor]).
enum ColorMark { ninguna, punto, rayasHorizontales, anillo, rayasDiagonales, cruz, rayasVerticales, dosPuntos, raya }

class ShapeIcon extends StatelessWidget {
  const ShapeIcon({super.key, required this.kind, required this.color, this.size = 64, this.mark = ColorMark.ninguna});

  final ShapeKind kind;
  final Color color;
  final double size;

  /// Marca de color: se dibuja solo con el alto contraste activo.
  final ColorMark mark;

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    return CustomPaint(size: Size(size, size), painter: ShapePainter(kind, color, edge: pal.altoContraste ? pal.tinta : Colors.black.withValues(alpha: 0.25), mark: pal.altoContraste ? mark : ColorMark.ninguna));
  }
}

class ShapePainter extends CustomPainter {
  const ShapePainter(this.kind, this.color, {required this.edge, this.mark = ColorMark.ninguna, this.fill = true});

  final ShapeKind kind;
  final Color color;
  final Color edge;
  final ColorMark mark;
  final bool fill;

  static Path pathFor(ShapeKind kind, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Offset c = Offset(w / 2, h / 2);
    final Path p = Path();
    void polygon(int n, double r, double start) {
      for (int i = 0; i < n; i++) {
        final double a = start + 2 * math.pi / n * i;
        final Offset o = Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r);
        if (i == 0) {
          p.moveTo(o.dx, o.dy);
        } else {
          p.lineTo(o.dx, o.dy);
        }
      }
      p.close();
    }

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
      case ShapeKind.pentagon:
        polygon(5, w * 0.45, -math.pi / 2);
        break;
      case ShapeKind.hexagon:
        polygon(6, w * 0.44, -math.pi / 6);
        break;
      case ShapeKind.octagon:
        polygon(8, w * 0.45, -math.pi / 8);
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
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Path p = pathFor(kind, size);
    if (fill) {
      canvas.drawPath(p, Paint()..color = color);
    }
    canvas.drawPath(
      p,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = fill ? 2 : 3,
    );
    if (mark != ColorMark.ninguna) {
      canvas.save();
      canvas.clipPath(p);
      _paintMark(canvas, size);
      canvas.restore();
    }
  }

  void _paintMark(Canvas canvas, Size size) {
    final double w = size.width;
    final Offset c = Offset(w / 2, size.height / 2);
    final Color ink = color.computeLuminance() > 0.35 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    final Paint line = Paint()
      ..color = ink
      ..strokeWidth = math.max(2, w * 0.05)
      ..style = PaintingStyle.stroke;
    final Paint dot = Paint()..color = ink;
    switch (mark) {
      case ColorMark.ninguna:
        break;
      case ColorMark.punto:
        canvas.drawCircle(c, w * 0.09, dot);
        break;
      case ColorMark.dosPuntos:
        canvas.drawCircle(c.translate(-w * 0.12, 0), w * 0.07, dot);
        canvas.drawCircle(c.translate(w * 0.12, 0), w * 0.07, dot);
        break;
      case ColorMark.anillo:
        canvas.drawCircle(c, w * 0.13, line);
        break;
      case ColorMark.cruz:
        canvas.drawLine(c.translate(-w * 0.12, -w * 0.12), c.translate(w * 0.12, w * 0.12), line);
        canvas.drawLine(c.translate(w * 0.12, -w * 0.12), c.translate(-w * 0.12, w * 0.12), line);
        break;
      case ColorMark.raya:
        canvas.drawLine(c.translate(-w * 0.16, 0), c.translate(w * 0.16, 0), line);
        break;
      case ColorMark.rayasHorizontales:
        for (double y = 0; y < size.height; y += w * 0.16) {
          canvas.drawLine(Offset(0, y), Offset(w, y), line);
        }
        break;
      case ColorMark.rayasVerticales:
        for (double x = 0; x < w; x += w * 0.16) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
        }
        break;
      case ColorMark.rayasDiagonales:
        for (double x = -w; x < w * 2; x += w * 0.18) {
          canvas.drawLine(Offset(x, 0), Offset(x + w, size.height), line);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant ShapePainter oldDelegate) => oldDelegate.kind != kind || oldDelegate.color != color || oldDelegate.edge != edge || oldDelegate.mark != mark || oldDelegate.fill != fill;
}

/// Nombre de la figura, sin artículo.
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
    case ShapeKind.pentagon:
      return 'pentágono';
    case ShapeKind.octagon:
      return 'octágono';
  }
}

/// Género gramatical de la figura ('f' solo para estrella).
String generoForma(ShapeKind k) => k == ShapeKind.star ? 'f' : 'm';

/// Plural del nombre de la figura.
String pluralForma(ShapeKind k) {
  switch (k) {
    case ShapeKind.circle:
      return 'círculos';
    case ShapeKind.square:
      return 'cuadrados';
    case ShapeKind.triangle:
      return 'triángulos';
    case ShapeKind.star:
      return 'estrellas';
    case ShapeKind.heart:
      return 'corazones';
    case ShapeKind.hexagon:
      return 'hexágonos';
    case ShapeKind.rectangle:
      return 'rectángulos';
    case ShapeKind.oval:
      return 'óvalos';
    case ShapeKind.pentagon:
      return 'pentágonos';
    case ShapeKind.octagon:
      return 'octágonos';
  }
}

/// Figura con su color, con la concordancia del adjetivo: "estrella roja",
/// "círculo rojo", "estrella amarilla", "triángulo verde".
String formaConColor(ShapeKind k, NamedColor c) => '${nombreForma(k)} ${colorConcordado(c, generoForma(k))}';

/// Adjetivo de color en el género pedido (rojo/roja, amarillo/amarilla…;
/// verde, azul, naranja, café y rosado no cambian o cambian según la norma).
String colorConcordado(NamedColor c, String genero) {
  if (genero != 'f') {
    return c.nombre;
  }
  switch (c.id) {
    case 'rojo':
      return 'roja';
    case 'amarillo':
      return 'amarilla';
    case 'morado':
      return 'morada';
    case 'rosado':
      return 'rosada';
    default:
      return c.nombre;
  }
}
