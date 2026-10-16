import 'dart:math' as math;

/// Punto proyectado (metros).
class ProjectedPoint {
  const ProjectedPoint(this.easting, this.northing);

  final double easting;
  final double northing;
}

/// Proyección transversa de Mercator con la serie de Krüger–Karney (orden 6
/// en la tercera aplanamiento, "Transverse Mercator with an accuracy of a few
/// nanometers", 2011). Sirve para UTM y para los orígenes colombianos
/// (Origen Nacional CTM12 y las zonas MAGNA-SIRGAS), validada contra PROJ.
class TransverseMercator {
  const TransverseMercator({
    required this.a,
    required this.f,
    required this.centralMeridian,
    this.latitudeOfOrigin = 0,
    this.scale = 1,
    this.falseEasting = 0,
    this.falseNorthing = 0,
  });

  /// Semieje mayor (m).
  final double a;

  /// Aplanamiento.
  final double f;

  /// Meridiano central (grados, este positivo).
  final double centralMeridian;

  /// Latitud de origen (grados).
  final double latitudeOfOrigin;

  /// Factor de escala en el meridiano central.
  final double scale;
  final double falseEasting;
  final double falseNorthing;

  static const double _wgs84A = 6378137.0;
  static const double _wgs84F = 1 / 298.257223563;
  static const double _grs80A = 6378137.0;
  static const double _grs80F = 1 / 298.257222101;

  /// Zona UTM (WGS84) con meridiano central [lon0].
  static TransverseMercator utm(double lon0, {required bool southern}) => TransverseMercator(a: _wgs84A, f: _wgs84F, centralMeridian: lon0, scale: 0.9996, falseEasting: 500000, falseNorthing: southern ? 10000000 : 0);

  /// MAGNA-SIRGAS / Origen-Nacional (CTM12, EPSG:9377), oficial en Colombia
  /// desde la Resolución IGAC 471 de 2020.
  static const TransverseMercator origenNacional = TransverseMercator(a: _grs80A, f: _grs80F, centralMeridian: -73, latitudeOfOrigin: 4, scale: 0.9992, falseEasting: 5000000, falseNorthing: 2000000);

  /// Zonas MAGNA-SIRGAS clásicas (EPSG:3114 a 3118), de oeste a este.
  static const List<String> magnaZoneNames = <String>['Oeste Oeste', 'Oeste', 'Bogotá', 'Este Central', 'Este'];
  static const double _magnaLat0 = 4.596200416666666; // 4°35'46,3215" N
  static const double _magnaLon0Bogota = -74.07750791666666; // 74°04'39,0285" O

  static TransverseMercator magnaZone(int index) => TransverseMercator(a: _grs80A, f: _grs80F, centralMeridian: _magnaLon0Bogota + (index - 2) * 3, latitudeOfOrigin: _magnaLat0, scale: 1, falseEasting: 1000000, falseNorthing: 1000000);

  /// Índice de la zona MAGNA-SIRGAS que corresponde a [lon] (0 a 4).
  static int magnaZoneIndex(double lon) {
    final double d = (lon - _magnaLon0Bogota) / 3; // 0 = Bogotá
    return (d.round() + 2).clamp(0, 4);
  }

  ProjectedPoint forward(double lat, double lon) {
    final double n = f / (2 - f);
    final double n2 = n * n;
    final double n3 = n2 * n;
    final double n4 = n3 * n;
    final double n5 = n4 * n;
    final double n6 = n5 * n;
    final double aA = a / (1 + n) * (1 + n2 / 4 + n4 / 64 + n6 / 256);
    final List<double> alpha = <double>[
      0,
      n / 2 - 2 * n2 / 3 + 5 * n3 / 16 + 41 * n4 / 180 - 127 * n5 / 288 + 7891 * n6 / 37800,
      13 * n2 / 48 - 3 * n3 / 5 + 557 * n4 / 1440 + 281 * n5 / 630 - 1983433 * n6 / 1935360,
      61 * n3 / 240 - 103 * n4 / 140 + 15061 * n5 / 26880 + 167603 * n6 / 181440,
      49561 * n4 / 161280 - 179 * n5 / 168 + 6601661 * n6 / 7257600,
      34729 * n5 / 80640 - 3418889 * n6 / 1995840,
      212378941 * n6 / 319334400,
    ];
    final double e = math.sqrt(f * (2 - f));
    final List<double> xe = _xiEta(e, alpha, lat * math.pi / 180, (lon - centralMeridian) * math.pi / 180);
    double xi0 = 0;
    if (latitudeOfOrigin != 0) {
      xi0 = _xiEta(e, alpha, latitudeOfOrigin * math.pi / 180, 0)[0];
    }
    return ProjectedPoint(scale * aA * xe[1] + falseEasting, scale * aA * (xe[0] - xi0) + falseNorthing);
  }

  static List<double> _xiEta(double e, List<double> alpha, double phi, double lam) {
    final double t = math.tan(phi);
    final double s = _sinh(e * _atanh(e * t / math.sqrt(1 + t * t)));
    final double tp = t * math.sqrt(1 + s * s) - s * math.sqrt(1 + t * t);
    final double cosLam = math.cos(lam);
    final double xip = math.atan2(tp, cosLam);
    final double etap = _asinh(math.sin(lam) / math.sqrt(tp * tp + cosLam * cosLam));
    double xi = xip;
    double eta = etap;
    for (int j = 1; j <= 6; j++) {
      xi += alpha[j] * math.sin(2 * j * xip) * _cosh(2 * j * etap);
      eta += alpha[j] * math.cos(2 * j * xip) * _sinh(2 * j * etap);
    }
    return <double>[xi, eta];
  }

  static double _sinh(double x) => x.abs() < 1e-4 ? x + x * x * x / 6 : (math.exp(x) - math.exp(-x)) / 2;

  static double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;

  static double _asinh(double x) => x.abs() < 1e-4 ? x - x * x * x / 6 : (x < 0 ? -math.log(-x + math.sqrt(x * x + 1)) : math.log(x + math.sqrt(x * x + 1)));

  static double _atanh(double x) => 0.5 * math.log((1 + x) / (1 - x));
}
