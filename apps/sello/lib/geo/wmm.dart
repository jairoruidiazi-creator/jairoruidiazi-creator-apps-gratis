import 'dart:math' as math;

import 'package:clock/clock.dart';

/// Modelo Magnético Mundial (WMM-2025, NOAA/NCEI y BGS, publicado 11/13/2024):
/// calcula la declinación magnética (diferencia entre el norte magnético que
/// marca la brújula y el norte geográfico) en cualquier punto del planeta,
/// sin internet. Válido de 2025.0 a 2030.0; fuera de ese rango se
/// extrapola y [MagneticField.extrapolated] queda en verdadero.
///
/// Los coeficientes son de dominio público (modelo oficial del gobierno de
/// EE. UU.). La implementación sigue el informe técnico del WMM: funciones
/// de Legendre seminormalizadas de Schmidt, conversión geodésica → esférica
/// con WGS84 y rotación de vuelta al sistema geodésico.
class MagneticField {
  const MagneticField({required this.declination, required this.inclination, required this.intensity, required this.horizontal, required this.extrapolated});

  /// Declinación en grados (este positivo). Se suma al rumbo magnético para
  /// obtener el rumbo verdadero.
  final double declination;

  /// Inclinación en grados (abajo positivo).
  final double inclination;

  /// Intensidad total en nT.
  final double intensity;

  /// Intensidad horizontal en nT (si es < 6000 la brújula es poco fiable).
  final double horizontal;

  /// Verdadero si la fecha está fuera de la vigencia del modelo.
  final bool extrapolated;

  /// La brújula es poco fiable (zona de precaución del WMM).
  bool get weakField => horizontal < 6000;
}

class Wmm {
  Wmm._();

  static const double epoch = 2025.0;
  static const String model = 'WMM-2025';
  static const int maxDegree = 12;

  // n, m, g, h, dg/dt, dh/dt (nT y nT/año) para cada armónico.
  static const List<double> _coef = <double>[
  1, 0, -29351.8, 0.0, 12.0, 0.0,
  1, 1, -1410.8, 4545.4, 9.7, -21.5,
  2, 0, -2556.6, 0.0, -11.6, 0.0,
  2, 1, 2951.1, -3133.6, -5.2, -27.7,
  2, 2, 1649.3, -815.1, -8.0, -12.1,
  3, 0, 1361.0, 0.0, -1.3, 0.0,
  3, 1, -2404.1, -56.6, -4.2, 4.0,
  3, 2, 1243.8, 237.5, 0.4, -0.3,
  3, 3, 453.6, -549.5, -15.6, -4.1,
  4, 0, 895.0, 0.0, -1.6, 0.0,
  4, 1, 799.5, 278.6, -2.4, -1.1,
  4, 2, 55.7, -133.9, -6.0, 4.1,
  4, 3, -281.1, 212.0, 5.6, 1.6,
  4, 4, 12.1, -375.6, -7.0, -4.4,
  5, 0, -233.2, 0.0, 0.6, 0.0,
  5, 1, 368.9, 45.4, 1.4, -0.5,
  5, 2, 187.2, 220.2, 0.0, 2.2,
  5, 3, -138.7, -122.9, 0.6, 0.4,
  5, 4, -142.0, 43.0, 2.2, 1.7,
  5, 5, 20.9, 106.1, 0.9, 1.9,
  6, 0, 64.4, 0.0, -0.2, 0.0,
  6, 1, 63.8, -18.4, -0.4, 0.3,
  6, 2, 76.9, 16.8, 0.9, -1.6,
  6, 3, -115.7, 48.8, 1.2, -0.4,
  6, 4, -40.9, -59.8, -0.9, 0.9,
  6, 5, 14.9, 10.9, 0.3, 0.7,
  6, 6, -60.7, 72.7, 0.9, 0.9,
  7, 0, 79.5, 0.0, -0.0, 0.0,
  7, 1, -77.0, -48.9, -0.1, 0.6,
  7, 2, -8.8, -14.4, -0.1, 0.5,
  7, 3, 59.3, -1.0, 0.5, -0.8,
  7, 4, 15.8, 23.4, -0.1, 0.0,
  7, 5, 2.5, -7.4, -0.8, -1.0,
  7, 6, -11.1, -25.1, -0.8, 0.6,
  7, 7, 14.2, -2.3, 0.8, -0.2,
  8, 0, 23.2, 0.0, -0.1, 0.0,
  8, 1, 10.8, 7.1, 0.2, -0.2,
  8, 2, -17.5, -12.6, 0.0, 0.5,
  8, 3, 2.0, 11.4, 0.5, -0.4,
  8, 4, -21.7, -9.7, -0.1, 0.4,
  8, 5, 16.9, 12.7, 0.3, -0.5,
  8, 6, 15.0, 0.7, 0.2, -0.6,
  8, 7, -16.8, -5.2, -0.0, 0.3,
  8, 8, 0.9, 3.9, 0.2, 0.2,
  9, 0, 4.6, 0.0, -0.0, 0.0,
  9, 1, 7.8, -24.8, -0.1, -0.3,
  9, 2, 3.0, 12.2, 0.1, 0.3,
  9, 3, -0.2, 8.3, 0.3, -0.3,
  9, 4, -2.5, -3.3, -0.3, 0.3,
  9, 5, -13.1, -5.2, 0.0, 0.2,
  9, 6, 2.4, 7.2, 0.3, -0.1,
  9, 7, 8.6, -0.6, -0.1, -0.2,
  9, 8, -8.7, 0.8, 0.1, 0.4,
  9, 9, -12.9, 10.0, -0.1, 0.1,
  10, 0, -1.3, 0.0, 0.1, 0.0,
  10, 1, -6.4, 3.3, 0.0, 0.0,
  10, 2, 0.2, 0.0, 0.1, -0.0,
  10, 3, 2.0, 2.4, 0.1, -0.2,
  10, 4, -1.0, 5.3, -0.0, 0.1,
  10, 5, -0.6, -9.1, -0.3, -0.1,
  10, 6, -0.9, 0.4, 0.0, 0.1,
  10, 7, 1.5, -4.2, -0.1, 0.0,
  10, 8, 0.9, -3.8, -0.1, -0.1,
  10, 9, -2.7, 0.9, -0.0, 0.2,
  10, 10, -3.9, -9.1, -0.0, -0.0,
  11, 0, 2.9, 0.0, 0.0, 0.0,
  11, 1, -1.5, 0.0, -0.0, -0.0,
  11, 2, -2.5, 2.9, 0.0, 0.1,
  11, 3, 2.4, -0.6, 0.0, -0.0,
  11, 4, -0.6, 0.2, 0.0, 0.1,
  11, 5, -0.1, 0.5, -0.1, -0.0,
  11, 6, -0.6, -0.3, 0.0, -0.0,
  11, 7, -0.1, -1.2, -0.0, 0.1,
  11, 8, 1.1, -1.7, -0.1, -0.0,
  11, 9, -1.0, -2.9, -0.1, 0.0,
  11, 10, -0.2, -1.8, -0.1, 0.0,
  11, 11, 2.6, -2.3, -0.1, 0.0,
  12, 0, -2.0, 0.0, 0.0, 0.0,
  12, 1, -0.2, -1.3, 0.0, -0.0,
  12, 2, 0.3, 0.7, -0.0, 0.0,
  12, 3, 1.2, 1.0, -0.0, -0.1,
  12, 4, -1.3, -1.4, -0.0, 0.1,
  12, 5, 0.6, -0.0, -0.0, -0.0,
  12, 6, 0.6, 0.6, 0.1, -0.0,
  12, 7, 0.5, -0.1, -0.0, -0.0,
  12, 8, -0.1, 0.8, 0.0, 0.0,
  12, 9, -0.4, 0.1, 0.0, -0.0,
  12, 10, -0.2, -1.0, -0.1, -0.0,
  12, 11, -1.3, 0.1, -0.0, 0.0,
  12, 12, -0.7, 0.2, -0.1, -0.1,
  ];

  /// Año decimal de una fecha.
  static double decimalYear(DateTime d) {
    final DateTime start = DateTime.utc(d.year);
    final DateTime end = DateTime.utc(d.year + 1);
    return d.year + d.toUtc().difference(start).inSeconds / end.difference(start).inSeconds;
  }

  /// Declinación magnética en grados en ([lat], [lon]) a [altitudeMeters]
  /// sobre el elipsoide para la fecha [at] (por defecto ahora).
  static double declination(double lat, double lon, {double altitudeMeters = 0, DateTime? at}) => compute(lat, lon, altitudeMeters: altitudeMeters, at: at).declination;

  static MagneticField compute(double lat, double lon, {double altitudeMeters = 0, DateTime? at}) {
    final double t = decimalYear(at ?? clock.now());
    final double dt = t - epoch;
    const double a = 6378.137;
    const double f = 1 / 298.257223563;
    const double e2 = f * (2 - f);
    const double re = 6371.2;
    final double altKm = altitudeMeters / 1000;
    final double phi = lat * math.pi / 180;
    final double lam = lon * math.pi / 180;
    final double sinPhi = math.sin(phi);
    final double cosPhi = math.cos(phi);
    // Geodésico → esférico geocéntrico.
    final double rc = a / math.sqrt(1 - e2 * sinPhi * sinPhi);
    final double p = (rc + altKm) * cosPhi;
    final double z = (rc * (1 - e2) + altKm) * sinPhi;
    final double r = math.sqrt(p * p + z * z);
    final double phiP = math.asin(z / r);
    final double theta = math.pi / 2 - phiP;
    final double ct = math.cos(theta);
    final double st = math.sin(theta);
    const int size = maxDegree + 1;
    // Funciones de Legendre P[n][m] y dP/dθ.
    final List<double> pl = List<double>.filled(size * size, 0);
    final List<double> dpl = List<double>.filled(size * size, 0);
    pl[0] = 1;
    for (int n = 1; n <= maxDegree; n++) {
      for (int m = 0; m <= n; m++) {
        final int i = n * size + m;
        if (n == m) {
          final double k = n == 1 ? 1.0 : math.sqrt(1 - 1 / (2.0 * n));
          final int j = (n - 1) * size + (m - 1);
          pl[i] = k * st * pl[j];
          dpl[i] = k * (st * dpl[j] + ct * pl[j]);
        } else {
          final double a1 = n - 1 >= m ? math.sqrt(((n - 1) * (n - 1) - m * m).toDouble()) : 0.0;
          final double den = math.sqrt((n * n - m * m).toDouble());
          final int j1 = (n - 1) * size + m;
          final double p2 = n - 2 >= m ? pl[(n - 2) * size + m] : 0.0;
          final double dp2 = n - 2 >= m ? dpl[(n - 2) * size + m] : 0.0;
          pl[i] = ((2 * n - 1) * ct * pl[j1] - a1 * p2) / den;
          dpl[i] = ((2 * n - 1) * (ct * dpl[j1] - st * pl[j1]) - a1 * dp2) / den;
        }
      }
    }
    double x = 0;
    double y = 0;
    double zz = 0;
    int row = 0;
    for (int n = 1; n <= maxDegree; n++) {
      final double ar = math.pow(re / r, n + 2).toDouble();
      for (int m = 0; m <= n; m++) {
        final double g = _coef[row * 6 + 2] + dt * _coef[row * 6 + 4];
        final double h = _coef[row * 6 + 3] + dt * _coef[row * 6 + 5];
        row++;
        final double cm = math.cos(m * lam);
        final double sm = math.sin(m * lam);
        final double c = g * cm + h * sm;
        final double s = g * sm - h * cm;
        final int i = n * size + m;
        x += ar * c * dpl[i];
        y += ar * m * s * pl[i];
        zz -= (n + 1) * ar * c * pl[i];
      }
    }
    final double cosPhiP = math.cos(phiP);
    y = cosPhiP.abs() < 1e-12 ? 0 : y / cosPhiP;
    // Rotación al sistema geodésico.
    final double psi = phiP - phi;
    final double xg = x * math.cos(psi) - zz * math.sin(psi);
    final double zg = x * math.sin(psi) + zz * math.cos(psi);
    final double hh = math.sqrt(xg * xg + y * y);
    return MagneticField(
      declination: math.atan2(y, xg) * 180 / math.pi,
      inclination: math.atan2(zg, hh) * 180 / math.pi,
      intensity: math.sqrt(hh * hh + zg * zg),
      horizontal: hh,
      extrapolated: dt < 0 || dt > 5,
    );
  }
}
