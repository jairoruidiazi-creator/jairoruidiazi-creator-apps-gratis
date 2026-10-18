import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/core/rng.dart';
import 'package:pilas/games/rompecabezas/rompecabezas_screen.dart';
import 'package:pilas/model/age_band.dart';

const int _lado = 240; // divisible entre 3, 4 y 5

Future<Uint8List> _rasterizar(String code) async {
  final PictureInfo info = await vg.loadPicture(SvgAssetLoader('assets/emoji/$code.svg'), null);
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final Canvas c = Canvas(rec);
  c.drawRect(const Rect.fromLTWH(0, 0, _lado * 1.0, _lado * 1.0), Paint()..color = Colors.white);
  c.scale(_lado / info.size.width, _lado / info.size.height);
  c.drawPicture(info.picture);
  final ui.Image img = await rec.endRecording().toImage(_lado, _lado);
  info.picture.dispose();
  final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  img.dispose();
  return data!.buffer.asUint8List();
}

/// Diferencia media (0 a 1) entre dos fichas de una imagen partida en n×n.
double _diferencia(Uint8List px, int n, int a, int b) {
  final int t = _lado ~/ n;
  final int ax = (a % n) * t;
  final int ay = (a ~/ n) * t;
  final int bx = (b % n) * t;
  final int by = (b ~/ n) * t;
  int suma = 0;
  for (int y = 0; y < t; y++) {
    for (int x = 0; x < t; x++) {
      final int ia = ((ay + y) * _lado + ax + x) * 4;
      final int ib = ((by + y) * _lado + bx + x) * 4;
      for (int k = 0; k < 3; k++) {
        final int d = px[ia + k] - px[ib + k];
        suma += d < 0 ? -d : d;
      }
    }
  }
  return suma / (t * t * 3 * 255);
}

/// Si la ficha es casi toda blanca (no tiene nada que la distinga).
bool _vacia(Uint8List px, int n, int a) {
  final int t = _lado ~/ n;
  final int ax = (a % n) * t;
  final int ay = (a ~/ n) * t;
  int suma = 0;
  for (int y = 0; y < t; y++) {
    for (int x = 0; x < t; x++) {
      final int i = ((ay + y) * _lado + ax + x) * 4;
      suma += (255 - px[i]) + (255 - px[i + 1]) + (255 - px[i + 2]);
    }
  }
  return suma / (t * t * 3 * 255) < 0.01;
}

/// G19: en cada tamaño en que se usa una imagen, todas sus fichas se ven
/// distintas. Si dos fichas fueran iguales (dos pedazos de cielo blanco), el
/// tablero podría verse armado sin estarlo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Cada imagen del rompecabezas tiene fichas distintas en los tamaños en que se usa', () async {
    for (final ImagenPuzzle img in SwapPuzzle.imagenes) {
      final Uint8List px = await _rasterizar(img.emoji);
      for (final int n in img.tamanos) {
        int vacias = 0;
        double minima = 1;
        for (int a = 0; a < n * n; a++) {
          if (_vacia(px, n, a)) {
            vacias += 1;
          }
          for (int b = a + 1; b < n * n; b++) {
            final double d = _diferencia(px, n, a, b);
            if (d < minima) {
              minima = d;
            }
          }
        }
        expect(vacias, lessThanOrEqualTo(1), reason: '${img.nombre} en $n×$n tiene $vacias fichas en blanco');
        expect(minima, greaterThan(0.02), reason: '${img.nombre} en $n×$n tiene dos fichas casi iguales (${minima.toStringAsFixed(3)})');
      }
    }
  });

  test('Cada tamaño de rompecabezas tiene varias imágenes y el tamaño sale del nivel', () {
    for (final int n in <int>[3, 4, 5]) {
      expect(SwapPuzzle.imagenes.where((ImagenPuzzle i) => i.tamanos.contains(n)).length, greaterThanOrEqualTo(5), reason: '$n×$n');
    }
    for (final AgeBand band in <AgeBand>[AgeBand.b7a8, AgeBand.b9a11]) {
      for (int level = 1; level <= 4; level++) {
        for (int seed = 0; seed < 20; seed++) {
          final SwapPuzzle p = SwapPuzzle.generate(Rng(seed), band, level);
          expect(p.imagen.tamanos, contains(p.n));
          // Resolverlo intercambiando hacia el orden correcto lo termina.
          for (int i = 0; i < p.order.length; i++) {
            while (p.order[i] != i) {
              final int j = p.order[i];
              final int t = p.order[j];
              p.order[j] = p.order[i];
              p.order[i] = t;
              p.swaps += 1;
            }
          }
          expect(p.solved, isTrue);
          expect(p.swaps, p.minInicial);
          expect(p.eficiente, isTrue);
        }
      }
    }
  });
}
