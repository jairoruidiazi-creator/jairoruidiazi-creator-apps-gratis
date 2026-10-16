import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../model/models.dart';
import 'stamp_data.dart';

/// Dibuja el sello (texto, fondo, brújula y logo) como una capa transparente
/// del tamaño de la foto. Se usa igual para la vista previa en pantalla y
/// para la copia sellada: la misma función, distinta escala.
class StampPainter extends CustomPainter {
  StampPainter({required this.template, required this.data, this.logo, this.previewScale = 1.0});

  final StampTemplate template;
  final StampData data;
  final ui.Image? logo;

  /// Escala respecto a una foto de referencia de 2000 px de ancho.
  final double previewScale;

  @override
  void paint(Canvas canvas, Size size) {
    paintStamp(canvas, size, template, data, logo: logo);
  }

  @override
  bool shouldRepaint(covariant StampPainter old) => true;

  /// Dibujo del sello sobre un lienzo de [size] píxeles.
  static void paintStamp(Canvas canvas, Size size, StampTemplate t, StampData d, {ui.Image? logo}) {
    final double unit = size.width / 100; // 1 % del ancho
    final double fontSize = unit * 2.1 * t.textScale;
    final double pad = unit * 1.6;
    final double margin = unit * 1.5;
    final List<StampLine> lines = d.lines(t);
    final bool bar = t.position == StampPosition.bottomBar;
    final double maxTextWidth = bar ? size.width - pad * 2 - (t.items.contains(StampItem.compass) ? unit * 14 : 0) : size.width * 0.62;
    final Color textColor = Color(t.textColor);
    final Color bg = Color(t.backgroundColor).withValues(alpha: t.backgroundOpacity.clamp(0.0, 1.0));

    // Párrafos
    final List<ui.Paragraph> paragraphs = <ui.Paragraph>[];
    double textHeight = 0;
    double textWidth = 0;
    for (final StampLine l in lines) {
      final ui.ParagraphBuilder pb = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: fontSize, fontWeight: l.strong ? FontWeight.w700 : FontWeight.w500, maxLines: 4, ellipsis: '…'))
        ..pushStyle(ui.TextStyle(color: textColor, fontSize: fontSize * (l.strong ? 1.1 : 1), fontWeight: l.strong ? FontWeight.w700 : FontWeight.w500, shadows: <Shadow>[Shadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: unit * 0.3)]))
        ..addText(l.text);
      final ui.Paragraph p = pb.build()..layout(ui.ParagraphConstraints(width: maxTextWidth));
      paragraphs.add(p);
      textHeight += p.height + unit * 0.35;
      textWidth = math.max(textWidth, p.longestLine);
    }
    final bool compass = t.items.contains(StampItem.compass) && d.heading != null;
    final double compassSize = compass ? unit * 11 : 0;
    final double blockW = bar ? size.width : math.min(size.width - margin * 2, textWidth + pad * 2 + (compass ? compassSize + pad : 0));
    final double blockH = math.max(textHeight + pad * 2, compass ? compassSize + pad * 2 : 0);

    double left;
    double top;
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
    if (lines.isNotEmpty || compass) {
      final RRect box = RRect.fromRectAndRadius(Rect.fromLTWH(left, top, blockW, blockH), Radius.circular(bar ? 0 : unit * 1.2));
      canvas.drawRRect(box, Paint()..color = bg);
      double y = top + pad;
      for (final ui.Paragraph p in paragraphs) {
        canvas.drawParagraph(p, Offset(left + pad, y));
        y += p.height + unit * 0.35;
      }
      if (compass) {
        final Offset c = Offset(left + blockW - pad - compassSize / 2, top + pad + compassSize / 2);
        _drawCompass(canvas, c, compassSize / 2, d.heading!, textColor, unit);
      }
    }
    if (logo != null) {
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
          ly = size.height - margin - lh - (bar ? blockH : 0);
          break;
      }
      // Si el logo cae sobre el bloque de texto, se sube encima de él.
      final Rect logoRect = Rect.fromLTWH(lx, ly, lw, lh);
      final Rect block = Rect.fromLTWH(left, top, blockW, blockH);
      if (logoRect.overlaps(block) && !bar) {
        ly = top - margin - lh;
      }
      canvas.drawImageRect(
        logo,
        Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        Rect.fromLTWH(lx, ly, lw, lh),
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
          ..pushStyle(ui.TextStyle(color: color, fontWeight: FontWeight.w800))
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
      ..pushStyle(ui.TextStyle(color: color, fontWeight: FontWeight.w700))
      ..addText('${heading.toStringAsFixed(0)}°');
    final ui.Paragraph p = pb.build()..layout(ui.ParagraphConstraints(width: r * 2));
    canvas.drawParagraph(p, Offset(c.dx - r, c.dy - p.height / 2 + r * 0.15));
  }
}

/// Dibuja el sello en una imagen transparente de [width] × [height] píxeles
/// y la devuelve como PNG (para componerla sobre la foto en un isolate).
Future<Uint8List> renderStampPng(StampTemplate t, StampData d, {required int width, required int height, ui.Image? logo}) async {
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final Canvas canvas = Canvas(rec, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
  StampPainter.paintStamp(canvas, Size(width.toDouble(), height.toDouble()), t, d, logo: logo);
  final ui.Image img = await rec.endRecording().toImage(width, height);
  final ByteData? bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  if (bytes == null) {
    throw StateError('No se pudo dibujar el sello');
  }
  return bytes.buffer.asUint8List();
}

/// Carga un logo desde bytes para dibujarlo.
Future<ui.Image> decodeLogo(Uint8List bytes) async {
  final ui.Codec codec = await ui.instantiateImageCodec(bytes, targetWidth: 800);
  final ui.FrameInfo frame = await codec.getNextFrame();
  return frame.image;
}
