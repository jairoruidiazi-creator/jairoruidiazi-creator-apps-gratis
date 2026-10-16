import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Ondulación del geoide EGM96 (altura del nivel medio del mar sobre el
/// elipsoide WGS84) para pasar de la altura elipsoidal que entrega el GPS en
/// Android a la altura sobre el nivel del mar.
///
/// Usa dos rejillas incluidas en la app (`assets/geoid/`, generadas por
/// `tools/gen_sello_geoid.py` a partir del modelo público de la NGA): el mundo
/// a 30' y Colombia a 5'. La interpolación es bilineal.
class Geoid {
  Geoid._();

  static Int16List? _world;
  static Int16List? _colombia;

  static const int _worldRows = 361; // −90° a 90° cada 0,5°
  static const int _worldCols = 721; // −180° a 180° cada 0,5°
  static const double _coLat0 = -5;
  static const double _coLon0 = -83;
  static const int _coRows = 265; // −5° a 17° cada 5'
  static const int _coCols = 205; // −83° a −66° cada 5'

  static bool get loaded => _world != null;

  /// Carga las rejillas desde los recursos (una sola vez; segura de repetir).
  static Future<void> load({AssetBundle? bundle}) async {
    if (_world != null) {
      return;
    }
    final AssetBundle b = bundle ?? rootBundle;
    final ByteData w = await b.load('assets/geoid/egm96_30m.bin');
    final ByteData c = await b.load('assets/geoid/egm96_co_5m.bin');
    _world = _toInt16(w);
    _colombia = _toInt16(c);
  }

  /// Para pruebas o plataformas sin recursos.
  static void setGrids(Int16List world, Int16List colombia) {
    _world = world;
    _colombia = colombia;
  }

  static Int16List _toInt16(ByteData d) {
    final Int16List out = Int16List(d.lengthInBytes ~/ 2);
    for (int i = 0; i < out.length; i++) {
      out[i] = d.getInt16(i * 2, Endian.little);
    }
    return out;
  }

  /// Ondulación N en metros (geoide − elipsoide), o null si no está cargado.
  static double? undulation(double lat, double lon) {
    final Int16List? w = _world;
    if (w == null) {
      return null;
    }
    double lo = lon;
    while (lo < -180) {
      lo += 360;
    }
    while (lo > 180) {
      lo -= 360;
    }
    final double la = lat.clamp(-90.0, 90.0);
    final Int16List? c = _colombia;
    if (c != null && la >= _coLat0 && la <= _coLat0 + (_coRows - 1) / 12 && lo >= _coLon0 && lo <= _coLon0 + (_coCols - 1) / 12) {
      return _bilinear(c, _coRows, _coCols, (la - _coLat0) * 12, (lo - _coLon0) * 12);
    }
    return _bilinear(w, _worldRows, _worldCols, (la + 90) * 2, (lo + 180) * 2);
  }

  static double _bilinear(Int16List g, int rows, int cols, double fi, double fj) {
    int i0 = fi.floor().clamp(0, rows - 1);
    int j0 = fj.floor().clamp(0, cols - 1);
    final int i1 = (i0 + 1).clamp(0, rows - 1);
    final int j1 = (j0 + 1).clamp(0, cols - 1);
    final double di = (fi - i0).clamp(0.0, 1.0);
    final double dj = (fj - j0).clamp(0.0, 1.0);
    i0 = i0.clamp(0, rows - 1);
    j0 = j0.clamp(0, cols - 1);
    final double v = g[i0 * cols + j0] * (1 - di) * (1 - dj) + g[i0 * cols + j1] * (1 - di) * dj + g[i1 * cols + j0] * di * (1 - dj) + g[i1 * cols + j1] * di * dj;
    return v / 100;
  }

  /// Altura sobre el nivel del mar a partir de la elipsoidal.
  static double? toMsl(double ellipsoidal, double lat, double lon) {
    final double? n = undulation(lat, lon);
    return n == null ? null : ellipsoidal - n;
  }

  /// Altura elipsoidal a partir de la del nivel del mar.
  static double? toEllipsoid(double msl, double lat, double lon) {
    final double? n = undulation(lat, lon);
    return n == null ? null : msl + n;
  }
}
