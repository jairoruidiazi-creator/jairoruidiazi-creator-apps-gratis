import 'dart:math' as math;

/// Formatos de coordenadas disponibles para el sello.
enum CoordFormat { dd, dms, ddm, utm, mgrs, plusCode }

/// Conversión de coordenadas WGS84: grados decimales, sexagesimales, UTM,
/// MGRS y Plus Codes. Todo se calcula en el teléfono.
class Coords {
  Coords._();

  static String degreesSymbol(double v, String pos, String neg, {int decimals = 6}) {
    final String s = v.abs().toStringAsFixed(decimals);
    return '$s° ${v >= 0 ? pos : neg}';
  }

  /// Grados decimales: "4.711000, -74.072100".
  static String dd(double lat, double lon, {int decimals = 6}) => '${lat.toStringAsFixed(decimals)}, ${lon.toStringAsFixed(decimals)}';

  /// Grados, minutos y segundos: 4°42'39.6"N 74°04'19.6"W.
  static String dms(double lat, double lon, {int secondDecimals = 1}) {
    String one(double v, String pos, String neg) {
      final double a = v.abs();
      final int d = a.floor();
      final double mFull = (a - d) * 60;
      final int m = mFull.floor();
      double s = (mFull - m) * 60;
      // Evita 60.0" por redondeo.
      final double factor = math.pow(10, secondDecimals).toDouble();
      s = (s * factor).round() / factor;
      int mm = m;
      int dd = d;
      if (s >= 60) {
        s = 0;
        mm += 1;
      }
      if (mm >= 60) {
        mm = 0;
        dd += 1;
      }
      return '$dd°${mm.toString().padLeft(2, '0')}\'${s.toStringAsFixed(secondDecimals).padLeft(secondDecimals + 3, '0')}"${v >= 0 ? pos : neg}';
    }

    return '${one(lat, 'N', 'S')} ${one(lon, 'E', 'W')}';
  }

  /// Grados y minutos decimales: 4°42.660'N 74°04.326'W.
  static String ddm(double lat, double lon, {int minuteDecimals = 3}) {
    String one(double v, String pos, String neg) {
      final double a = v.abs();
      int d = a.floor();
      double m = (a - d) * 60;
      final double factor = math.pow(10, minuteDecimals).toDouble();
      m = (m * factor).round() / factor;
      if (m >= 60) {
        m = 0;
        d += 1;
      }
      return '$d°${m.toStringAsFixed(minuteDecimals).padLeft(minuteDecimals + 3, '0')}\'${v >= 0 ? pos : neg}';
    }

    return '${one(lat, 'N', 'S')} ${one(lon, 'E', 'W')}';
  }

  // ------------------------------------------------------------ UTM (WGS84)

  static const double _a = 6378137.0;
  static const double _f = 1 / 298.257223563;
  static const double _k0 = 0.9996;

  static int utmZone(double lat, double lon) {
    int zone = ((lon + 180) / 6).floor() + 1;
    if (zone > 60) {
      zone = 60;
    }
    // Excepciones de Noruega y Svalbard.
    if (lat >= 56 && lat < 64 && lon >= 3 && lon < 12) {
      zone = 32;
    }
    if (lat >= 72 && lat < 84) {
      if (lon >= 0 && lon < 9) {
        zone = 31;
      } else if (lon >= 9 && lon < 21) {
        zone = 33;
      } else if (lon >= 21 && lon < 33) {
        zone = 35;
      } else if (lon >= 33 && lon < 42) {
        zone = 37;
      }
    }
    return zone;
  }

  static String utmBand(double lat) {
    const String letters = 'CDEFGHJKLMNPQRSTUVWX';
    if (lat < -80 || lat > 84) {
      return 'Z';
    }
    final int i = ((lat + 80) / 8).floor().clamp(0, 19);
    return letters[i];
  }

  /// Proyección transversa de Mercator (fórmulas de Krüger, serie estándar).
  static UtmPoint toUtm(double lat, double lon, {int? forceZone}) {
    final int zone = forceZone ?? utmZone(lat, lon);
    final double lon0 = ((zone - 1) * 6 - 180 + 3) * math.pi / 180;
    final double phi = lat * math.pi / 180;
    final double lam = lon * math.pi / 180 - lon0;
    final double e2 = _f * (2 - _f);
    final double ep2 = e2 / (1 - e2);
    final double n = _a / math.sqrt(1 - e2 * math.pow(math.sin(phi), 2));
    final double t = math.tan(phi);
    final double t2 = t * t;
    final double c = ep2 * math.pow(math.cos(phi), 2);
    final double aA = math.cos(phi) * lam;
    final double e4 = e2 * e2;
    final double e6 = e4 * e2;
    final double m = _a *
        ((1 - e2 / 4 - 3 * e4 / 64 - 5 * e6 / 256) * phi -
            (3 * e2 / 8 + 3 * e4 / 32 + 45 * e6 / 1024) * math.sin(2 * phi) +
            (15 * e4 / 256 + 45 * e6 / 1024) * math.sin(4 * phi) -
            (35 * e6 / 3072) * math.sin(6 * phi));
    final double easting = _k0 * n * (aA + (1 - t2 + c) * math.pow(aA, 3) / 6 + (5 - 18 * t2 + t2 * t2 + 72 * c - 58 * ep2) * math.pow(aA, 5) / 120) + 500000;
    double northing = _k0 * (m + n * t * (aA * aA / 2 + (5 - t2 + 9 * c + 4 * c * c) * math.pow(aA, 4) / 24 + (61 - 58 * t2 + t2 * t2 + 600 * c - 330 * ep2) * math.pow(aA, 6) / 720));
    if (lat < 0) {
      northing += 10000000;
    }
    return UtmPoint(zone: zone, band: utmBand(lat), easting: easting, northing: northing, southern: lat < 0);
  }

  static String utm(double lat, double lon, {int decimals = 0}) {
    final UtmPoint p = toUtm(lat, lon);
    return '${p.zone}${p.band} ${p.easting.toStringAsFixed(decimals)} E ${p.northing.toStringAsFixed(decimals)} N';
  }

  // ------------------------------------------------------------ MGRS

  static const String _e100k = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const String _n100k = 'ABCDEFGHJKLMNPQRSTUV';

  /// MGRS con [precision] dígitos por coordenada (5 = 1 m).
  static String mgrs(double lat, double lon, {int precision = 5}) {
    final UtmPoint p = toUtm(lat, lon);
    final int set = (p.zone - 1) % 6; // 0..5
    final int col = (p.easting / 100000).floor(); // 1..8
    final int eIndex = (set % 3) * 8 + col - 1;
    final String eLetter = _e100k[eIndex % 24];
    final int row = (p.northing / 100000).floor() % 20;
    // En las zonas pares la fila de letras empieza en F (desplazada 5).
    final int nIndex = (row + (p.zone.isEven ? 5 : 0)) % 20;
    final String nLetter = _n100k[nIndex];
    final int div = math.pow(10, 5 - precision).toInt();
    final int e = ((p.easting % 100000) / div).floor();
    final int n = ((p.northing % 100000) / div).floor();
    if (p.band == 'Z') {
      return '—';
    }
    return '${p.zone.toString().padLeft(2, '0')}${p.band}$eLetter$nLetter${e.toString().padLeft(precision, '0')}${n.toString().padLeft(precision, '0')}';
  }

  // ------------------------------------------------------------ Plus Codes

  static const String _olcAlphabet = '23456789CFGHJMPQRVWX';

  /// Open Location Code de [length] dígitos (10 ≈ 14 m, 11 ≈ 3 m), según
  /// la implementación de referencia de Google (enteros, sin acumulación de
  /// error de coma flotante).
  static String plusCode(double lat, double lon, {int length = 10}) {
    double la = lat.clamp(-90.0, 90.0);
    double lo = lon;
    while (lo < -180) {
      lo += 360;
    }
    while (lo >= 180) {
      lo -= 360;
    }
    if (la == 90) {
      la -= length <= 10 ? math.pow(20, (length ~/ -2) + 2).toDouble() : math.pow(20, -3).toDouble() / math.pow(5, length - 10);
    }
    int latVal = ((la + 90) * 25000000).round();
    int lonVal = ((lo + 180) * 8192000).round();
    String code = '';
    if (length > 10) {
      for (int i = 0; i < 5; i++) {
        final int latDigit = latVal % 5;
        final int lonDigit = lonVal % 4;
        code = _olcAlphabet[latDigit * 4 + lonDigit] + code;
        latVal ~/= 5;
        lonVal ~/= 4;
      }
    } else {
      latVal ~/= 3125;
      lonVal ~/= 1024;
    }
    for (int i = 0; i < 5; i++) {
      code = _olcAlphabet[lonVal % 20] + code;
      code = _olcAlphabet[latVal % 20] + code;
      latVal ~/= 20;
      lonVal ~/= 20;
    }
    code = '${code.substring(0, 8)}+${code.substring(8)}';
    if (length >= 8) {
      return code.substring(0, math.min(code.length, length + 1));
    }
    return '${code.substring(0, length)}${'0' * (8 - length)}+';
  }

  /// Texto según el formato elegido.
  static String format(CoordFormat f, double lat, double lon) {
    switch (f) {
      case CoordFormat.dd:
        return dd(lat, lon);
      case CoordFormat.dms:
        return dms(lat, lon);
      case CoordFormat.ddm:
        return ddm(lat, lon);
      case CoordFormat.utm:
        return utm(lat, lon);
      case CoordFormat.mgrs:
        return mgrs(lat, lon);
      case CoordFormat.plusCode:
        return plusCode(lat, lon);
    }
  }

  static String formatName(CoordFormat f) {
    switch (f) {
      case CoordFormat.dd:
        return 'Grados decimales';
      case CoordFormat.dms:
        return 'Grados, minutos y segundos';
      case CoordFormat.ddm:
        return 'Grados y minutos decimales';
      case CoordFormat.utm:
        return 'UTM';
      case CoordFormat.mgrs:
        return 'MGRS';
      case CoordFormat.plusCode:
        return 'Plus Code';
    }
  }

  /// Distancia en metros (fórmula de haversine).
  static double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371008.8;
    final double p1 = lat1 * math.pi / 180;
    final double p2 = lat2 * math.pi / 180;
    final double dp = (lat2 - lat1) * math.pi / 180;
    final double dl = (lon2 - lon1) * math.pi / 180;
    final double a = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Punto cardinal de 16 vientos.
  static String cardinal(double heading, {bool spanish = true}) {
    const List<String> es = <String>['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSO', 'SO', 'OSO', 'O', 'ONO', 'NO', 'NNO'];
    const List<String> en = <String>['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
    final int i = (((heading % 360) + 360) % 360 / 22.5).round() % 16;
    return (spanish ? es : en)[i];
  }

  /// Fachada fotografiada: la que mira hacia la cámara (rumbo + 180°).
  static String facade(double heading, {bool spanish = true}) {
    const List<String> es = <String>['norte', 'noreste', 'este', 'sureste', 'sur', 'suroeste', 'oeste', 'noroeste'];
    const List<String> en = <String>['north', 'northeast', 'east', 'southeast', 'south', 'southwest', 'west', 'northwest'];
    final double facing = (heading + 180) % 360;
    final int i = (facing / 45).round() % 8;
    return (spanish ? es : en)[i];
  }
}

class UtmPoint {
  const UtmPoint({required this.zone, required this.band, required this.easting, required this.northing, required this.southern});

  final int zone;
  final String band;
  final double easting;
  final double northing;
  final bool southern;
}
