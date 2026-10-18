import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../model/models.dart';
import 'stamp_data.dart';

/// Tipografía del sello, incluida en la app (ver pubspec.yaml).
const String kStampFont = 'SelloSans';

/// Dónde va cada parte del sello sobre un lienzo de cierto tamaño.
class StampLayout {
  const StampLayout({required this.paragraphs, required this.block, required this.logo, required this.compassCenter, required this.compassRadius, required this.unit, required this.pad});

  final List<ui.Paragraph> paragraphs;

  /// Recuadro del texto (y de la rosa), o null si no hay nada que escribir.
  final Rect? block;

  /// Lugar del logo, o null si no hay.
  final Rect? logo;
  final Offset? compassCenter;
  final double compassRadius;

  /// Unidad del sello: el 1 % del lado corto del lienzo (menos si hubo que
  /// achicarlo para que no pase del alto máximo).
  final double unit;
  final double pad;

  /// Rectángulo que abarca todo lo que se dibuja (con un margen para el
  /// suavizado), o null si no se dibuja nada.
  Rect? get bounds {
    Rect? r = block;
    final Rect? l = logo;
    if (l != null) {
      r = r == null ? l : r.expandToInclude(l);
    }
    return r?.inflate(2);
  }
}

/// Dibuja el sello (texto, fondo, brújula y logo). Se usa igual para la
/// vista previa en pantalla, el editor de plantillas y la copia sellada: el
/// mismo código, distinta escala.
///
/// La unidad es el 1 % del lado corto de la foto, así que el sello mide lo
/// mismo en una foto vertical que en una horizontal (con el 1 % del ancho,
/// en horizontal tapaba casi la mitad de la foto). Y el bloque nunca pasa de
/// [maxBlockFraction] del alto: con muchas líneas o letra grande, se achica.
class StampPainter extends CustomPainter {
  StampPainter({required this.template, required this.data, this.logo}) : _templateKey = jsonEncode(template.toJson());

  final StampTemplate template;
  final StampData data;
  final ui.Image? logo;

  /// La plantilla se edita en el lugar (el mismo objeto): se compara su
  /// contenido, no su identidad.
  final String _templateKey;

  /// Parte del alto de la foto que el sello puede ocupar como máximo.
  static const double maxBlockFraction = 0.25;

  @override
  void paint(Canvas canvas, Size size) {
    paintStamp(canvas, size, template, data, logo: logo);
  }

  /// Solo se vuelve a dibujar si cambia algo que se ve: la plantilla, el
  /// logo o el texto (el maquetado del texto es lo caro).
  @override
  bool shouldRepaint(covariant StampPainter old) => old._templateKey != _templateKey || old.logo != logo || !data.sameLookAs(old.data, template);

  /// Dibujo del sello sobre un lienzo de [size] píxeles.
  static void paintStamp(Canvas canvas, Size size, StampTemplate t, StampData d, {ui.Image? logo}) {
    paintLayout(canvas, layout(size, t, d, logo: logo), t, d, logo: logo);
  }

  /// Calcula dónde va cada parte, sin dibujar.
  static StampLayout layout(Size size, StampTemplate t, StampData d, {ui.Image? logo}) {
    StampLayout l = _layoutWithUnit(size, t, d, logo, math.min(size.width, size.height) / 100);
    // Si el bloque pasa del máximo se achica en proporción, con un 2 % de
    // margen: el alto no es del todo proporcional a la letra (márgenes y
    // líneas que se reacomodan), así que puede hacer falta otra vuelta.
    final double maxHeight = size.height * maxBlockFraction;
    for (int i = 0; i < 6; i++) {
      final Rect? b = l.block;
      if (b == null || b.height <= maxHeight) {
        break;
      }
      l = _layoutWithUnit(size, t, d, logo, l.unit * maxHeight / b.height * 0.98);
    }
    return l;
  }

  static StampLayout _layoutWithUnit(Size size, StampTemplate t, StampData d, ui.Image? logo, double unit) {
    final double fontSize = unit * 2.1 * t.textScale;
    final double pad = unit * 1.6;
    final double margin = unit * 1.5;
    final List<StampLine> lines = d.lines(t);
    final bool bar = t.position == StampPosition.bottomBar;
    final double maxTextWidth = math.max(unit, bar ? size.width - pad * 2 - (t.items.contains(StampItem.compass) ? unit * 14 : 0) : size.width * 0.62);
    final Color textColor = Color(t.textColor);

    final List<ui.Paragraph> paragraphs = <ui.Paragraph>[];
    double textHeight = 0;
    double textWidth = 0;
    for (final StampLine l in lines) {
      final ui.ParagraphBuilder pb = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: fontSize, fontWeight: l.strong ? FontWeight.w700 : FontWeight.w500, maxLines: 4, ellipsis: '…'))
        ..pushStyle(ui.TextStyle(fontFamily: kStampFont, color: textColor, fontSize: fontSize * (l.strong ? 1.1 : 1), fontWeight: l.strong ? FontWeight.w700 : FontWeight.w500, shadows: <Shadow>[Shadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: unit * 0.3)]))
        ..addText(l.text);
      final ui.Paragraph p = pb.build()..layout(ui.ParagraphConstraints(width: maxTextWidth));
      paragraphs.add(p);
      textHeight += p.height + unit * 0.35;
      textWidth = math.max(textWidth, p.longestLine);
    }
    final bool compass = t.items.contains(StampItem.compass) && d.heading != null;
    final double compassSize = compass ? unit * 11 : 0;
    Rect? block;
    Offset? compassCenter;
    if (lines.isNotEmpty || compass) {
      final double blockW = bar ? size.width : math.min(size.width - margin * 2, textWidth + pad * 2 + (compass ? compassSize + pad : 0));
      final double blockH = math.max(textHeight + pad * 2, compass ? compassSize + pad * 2 : 0);
      final double left;
      final double top;
      switch (t.position) {
        case StampPosition.bottomLeft:
          left = margin;
          top = size.height - margin - blockH;
          break;
        case StampPosition.bottomRight:
          left = size.width - margin - blockW;
          top = size.height - margin - blockH;
          break;
        case StampPosition.topLeft:
          left = margin;
          top = margin;
          break;
        case StampPosition.topRight:
          left = size.width - margin - blockW;
          top = margin;
          break;
        case StampPosition.bottomBar:
          left = 0;
          top = size.height - blockH;
          break;
      }
      block = Rect.fromLTWH(left, top, blockW, blockH);
      if (compass) {
        compassCenter = Offset(left + blockW - pad - compassSize / 2, top + pad + compassSize / 2);
      }
    }
    Rect? logoRect;
    if (logo != null && logo.width > 0) {
      final double lw = unit * 14 * t.logoScale;
      final double lh = lw * logo.height / logo.width;
      double lx;
      double ly;
      switch (t.logoPosition) {
        case StampPosition.topLeft:
          lx = margin;
          ly = margin;
          break;
        case StampPosition.topRight:
          lx = size.width - margin - lw;
          ly = margin;
          break;
        case StampPosition.bottomLeft:
          lx = margin;
          ly = size.height - margin - lh;
          break;
        case StampPosition.bottomRight:
        case StampPosition.bottomBar:
          lx = size.width - margin - lw;
          ly = size.height - margin - lh - (bar && block != null ? block.height : 0);
          break;
      }
      // Si el logo cae sobre el texto se mueve al otro lado del recuadro:
      // encima si el texto va abajo, debajo si va arriba. Nunca fuera de la
      // foto.
      final Rect? b = block;
      if (b != null && !bar && Rect.fromLTWH(lx, ly, lw, lh).overlaps(b)) {
        ly = b.center.dy > size.height / 2 ? b.top - margin - lh : b.bottom + margin;
      }
      ly = ly.clamp(margin, math.max(margin, size.height - margin - lh)).toDouble();
      lx = lx.clamp(margin, math.max(margin, size.width - margin - lw)).toDouble();
      logoRect = Rect.fromLTWH(lx, ly, lw, lh);
    }
    return StampLayout(paragraphs: paragraphs, block: block, logo: logoRect, compassCenter: compassCenter, compassRadius: compassSize / 2, unit: unit, pad: pad);
  }

  /// Dibuja un diseño ya calculado.
  static void paintLayout(Canvas canvas, StampLayout l, StampTemplate t, StampData d, {ui.Image? logo}) {
    final Rect? block = l.block;
    final bool bar = t.position == StampPosition.bottomBar;
    final Color textColor = Color(t.textColor);
    if (block != null) {
      final Color bg = Color(t.backgroundColor).withValues(alpha: t.backgroundOpacity.clamp(0.0, 1.0));
      canvas.drawRRect(RRect.fromRectAndRadius(block, Radius.circular(bar ? 0 : l.unit * 1.2)), Paint()..color = bg);
      double y = block.top + l.pad;
      for (final ui.Paragraph p in l.paragraphs) {
        canvas.drawParagraph(p, Offset(block.left + l.pad, y));
        y += p.height + l.unit * 0.35;
      }
      final Offset? c = l.compassCenter;
      if (c != null && d.heading != null) {
        _drawCompass(canvas, c, l.compassRadius, d.heading!, textColor, l.unit);
      }
    }
    final Rect? lr = l.logo;
    if (logo != null && lr != null) {
      canvas.drawImageRect(
        logo,
        Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        lr,
        Paint()..color = Colors.white.withValues(alpha: t.logoOpacity.clamp(0.0, 1.0)),
      );
    }
  }

  static void _drawCompass(Canvas canvas, Offset c, double r, double heading, Color color, double unit) {
    final Paint ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.3;
    canvas.drawCircle(c, r, ring);
    for (int i = 0; i < 8; i++) {
      final double a = -math.pi / 2 + i * math.pi / 4 - heading * math.pi / 180;
      final Offset p1 = c + Offset(math.cos(a), math.sin(a)) * (r * 0.84);
      final Offset p2 = c + Offset(math.cos(a), math.sin(a)) * r;
      canvas.drawLine(p1, p2, ring);
      if (i == 0) {
        final ui.ParagraphBuilder pb = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: r * 0.42, fontWeight: FontWeight.w800, textAlign: TextAlign.center))
          ..pushStyle(ui.TextStyle(fontFamily: kStampFont, color: color, fontWeight: FontWeight.w800))
          ..addText('N');
        final ui.Paragraph p = pb.build()..layout(ui.ParagraphConstraints(width: r));
        final Offset pos = c + Offset(math.cos(a), math.sin(a)) * (r * 0.6);
        canvas.drawParagraph(p, pos - Offset(r / 2, p.height / 2));
      }
    }
    // Flecha fija hacia arriba: hacia dónde apunta la cámara.
    final Path arrow = Path()
      ..moveTo(c.dx, c.dy - r * 0.9)
      ..lineTo(c.dx - r * 0.18, c.dy - r * 0.45)
      ..lineTo(c.dx + r * 0.18, c.dy - r * 0.45)
      ..close();
    canvas.drawPath(arrow, Paint()..color = const Color(0xFFFF7043));
    final ui.ParagraphBuilder pb = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: r * 0.38, fontWeight: FontWeight.w700, textAlign: TextAlign.center))
      ..pushStyle(ui.TextStyle(fontFamily: kStampFont, color: color, fontWeight: FontWeight.w700))
      ..addText('${heading.toStringAsFixed(0)}°');
    final ui.Paragraph p = pb.build()..layout(ui.ParagraphConstraints(width: r * 2));
    canvas.drawParagraph(p, Offset(c.dx - r, c.dy - p.height / 2 + r * 0.15));
  }
}

/// Capa del sello lista para componer: un PNG con transparencia que cubre
/// solo la zona dibujada, y su posición dentro de la foto.
class StampOverlay {
  const StampOverlay({required this.png, required this.left, required this.top, required this.width, required this.height});

  final Uint8List png;
  final int left;
  final int top;
  final int width;
  final int height;
}

/// Dibuja el sello para una foto de [width] × [height] píxeles, a tamaño
/// real (el texto queda nítido en la foto completa), pero solo la parte que
/// tiene algo: la memoria y el tiempo no dependen del tamaño de la foto.
/// Devuelve null si la plantilla no dibuja nada.
Future<StampOverlay?> renderStampOverlay(StampTemplate t, StampData d, {required int width, required int height, ui.Image? logo}) async {
  final Size size = Size(width.toDouble(), height.toDouble());
  final StampLayout layout = StampPainter.layout(size, t, d, logo: logo);
  final Rect? bounds = layout.bounds;
  if (bounds == null) {
    return null;
  }
  final int left = bounds.left.floor().clamp(0, width);
  final int top = bounds.top.floor().clamp(0, height);
  final int right = bounds.right.ceil().clamp(0, width);
  final int bottom = bounds.bottom.ceil().clamp(0, height);
  final int w = right - left;
  final int h = bottom - top;
  if (w <= 0 || h <= 0) {
    return null;
  }
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final Canvas canvas = Canvas(rec, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  canvas.translate(-left.toDouble(), -top.toDouble());
  StampPainter.paintLayout(canvas, layout, t, d, logo: logo);
  final ui.Image img = await rec.endRecording().toImage(w, h);
  final ByteData? bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  if (bytes == null) {
    throw StateError('No se pudo dibujar el sello');
  }
  return StampOverlay(png: bytes.buffer.asUint8List(), left: left, top: top, width: w, height: h);
}

/// Carga un logo desde bytes para dibujarlo.
Future<ui.Image> decodeLogo(Uint8List bytes) async {
  final ui.Codec codec = await ui.instantiateImageCodec(bytes, targetWidth: 800);
  final ui.FrameInfo frame = await codec.getNextFrame();
  return frame.image;
}
