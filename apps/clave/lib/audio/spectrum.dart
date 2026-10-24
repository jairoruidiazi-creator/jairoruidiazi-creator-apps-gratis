import 'dart:math' as math;
import 'dart:typed_data';

/// Espectro de magnitud de un búfer (ventana de Hann, FFT de base 2), para
/// medir si hay energía propia en una frecuencia.
///
/// Se calcula una vez por análisis y solo cuando hace falta (la regla de los
/// tonos de la app): una FFT de 8192 puntos son unas 53 000 mariposas, y
/// después cada medida mira unas decenas de bins.
class Spectrum {
  Spectrum(Float32List samples, {required this.sampleRate})
      : n = samples.length,
        mag = _magnitudes(samples);

  final int n;
  final int sampleRate;

  /// |X(k)| para k de 0 a n/2.
  final Float64List mag;

  /// Bins mínimos del entorno para decidir; con menos, las medidas devuelven
  /// `double.nan` (no se puede decidir).
  static const int minRingBins = 4;

  static final Map<int, Float64List> _windows = <int, Float64List>{};
  static final Map<int, Float64List> _cos = <int, Float64List>{};
  static final Map<int, Float64List> _sin = <int, Float64List>{};

  static Float64List _magnitudes(Float32List x) {
    final int n = x.length;
    if (n < 16 || (n & (n - 1)) != 0) {
      throw ArgumentError.value(n, 'samples.length', 'debe ser potencia de 2');
    }
    final Float64List w = _windows.putIfAbsent(n, () => Float64List.fromList(<double>[for (int i = 0; i < n; i++) 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1))]));
    final Float64List cosT = _cos.putIfAbsent(n, () => Float64List.fromList(<double>[for (int t = 0; t < n ~/ 2; t++) math.cos(2 * math.pi * t / n)]));
    final Float64List sinT = _sin.putIfAbsent(n, () => Float64List.fromList(<double>[for (int t = 0; t < n ~/ 2; t++) -math.sin(2 * math.pi * t / n)]));
    final Float64List re = Float64List(n);
    final Float64List im = Float64List(n);
    for (int i = 0; i < n; i++) {
      re[i] = x[i] * w[i];
    }
    // Orden de bits invertido.
    int j = 0;
    for (int i = 1; i < n; i++) {
      int bit = n >> 1;
      while ((j & bit) != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j ^= bit;
      if (i < j) {
        final double t = re[i];
        re[i] = re[j];
        re[j] = t;
      }
    }
    for (int len = 2; len <= n; len <<= 1) {
      final int half = len >> 1;
      final int step = n ~/ len;
      for (int i = 0; i < n; i += len) {
        for (int k = 0; k < half; k++) {
          final double wr = cosT[k * step];
          final double wi = sinT[k * step];
          final int a = i + k;
          final int b = a + half;
          final double xr = re[b] * wr - im[b] * wi;
          final double xi = re[b] * wi + im[b] * wr;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] += xr;
          im[a] += xi;
        }
      }
    }
    final int half = n ~/ 2;
    return Float64List.fromList(<double>[for (int k = 0; k <= half; k++) math.sqrt(re[k] * re[k] + im[k] * im[k])]);
  }

  /// Prominencia, en dB, de la energía en [hz]: el pico (±1,5 bins) sobre la
  /// mediana de su entorno, de 0,55·[hz] a 1,45·[hz] sin los ±2,5 bins del
  /// centro. El entorno no llega a [hz]/2 ni a 2·[hz]: no incluye armónicos
  /// ni subarmónicos de un tono en [hz]. Sirve para ver si un tono de la app
  /// suena en el búfer. Devuelve `double.nan` si el entorno tiene menos de
  /// [minRingBins] bins o si [hz] queda en el borde del espectro.
  double prominenceDb(double hz) {
    if (!(hz > 0)) {
      return double.nan;
    }
    final int half = n ~/ 2;
    final double b = hz * n / sampleRate;
    if (b + 1.5 >= half) {
      return double.nan;
    }
    final List<double> ring = <double>[
      for (int k = math.max(1, (b * 0.55).ceil()); k <= math.min(half, (b * 1.45).floor()); k++)
        if ((k - b).abs() > 2.5) mag[k],
    ];
    return _ratioDb(_peak(b), ring);
  }

  /// Prominencia, en dB, del armónico [h] de [f0] sobre el piso entre
  /// armónicos: el pico (±1,5 bins) en h·[f0] sobre la mediana de los bins
  /// de los huecos entre armónicos vecinos, de máx(0,5·f0, (h − 1,5)·f0) a
  /// (h + 1,5)·f0, sin los ±2,5 bins de cada múltiplo de [f0]: el piso no
  /// incluye armónicos de la nota. Agrupa tres huecos para que en las notas
  /// graves (pocos bins por hueco) la mediana no dependa de dos o tres bins
  /// de ruido. Devuelve `double.nan` si quedan menos de [minRingBins] bins o
  /// si h·[f0] queda en el borde del espectro.
  ///
  /// Una nota de verdad tiene picos en sus armónicos aunque el micrófono le
  /// quite la fundamental; un residuo (la "fundamental ausente" de la mezcla
  /// con un tono de la app) solo los tiene donde caen lo tocado y la app.
  double harmonicProminenceDb(double f0, int h) {
    if (!(f0 > 0) || h < 1) {
      return double.nan;
    }
    final int half = n ~/ 2;
    final double s = f0 * n / sampleRate;
    final double b = h * s;
    if (b + 1.5 >= half) {
      return double.nan;
    }
    final double lo = math.max(0.5 * s, b - 1.5 * s);
    final List<double> ring = <double>[
      for (int k = math.max(1, lo.ceil()); k <= math.min(half, (b + 1.5 * s).floor()); k++)
        if ((k - (k / s).round() * s).abs() > 2.5) mag[k],
    ];
    return _ratioDb(_peak(b), ring);
  }

  double _peak(double b) {
    final int half = n ~/ 2;
    double peak = 0;
    for (int k = math.max(1, (b - 1.5).floor()); k <= math.min(half, (b + 1.5).ceil()); k++) {
      peak = math.max(peak, mag[k]);
    }
    return peak;
  }

  static double _ratioDb(double peak, List<double> ring) {
    if (ring.length < minRingBins) {
      return double.nan;
    }
    ring.sort();
    final int l = ring.length;
    final double median = l.isOdd ? ring[l ~/ 2] : (ring[l ~/ 2 - 1] + ring[l ~/ 2]) / 2;
    return 20 * math.log(peak / (median + 1e-12)) / math.ln10;
  }
}
