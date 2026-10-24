import 'dart:math' as math;
import 'dart:typed_data';

/// Espectro de magnitud de un búfer (ventana de Hann, FFT de base 2), para
/// medir si hay energía propia en una frecuencia.
///
/// Se calcula una vez por análisis y solo cuando hace falta (la regla de los
/// tonos de la app): una FFT de 8192 puntos son unas 53 000 mariposas, y
/// después cada medida mira unas decenas de bins. Los búferes de trabajo
/// (partes real e imaginaria, entornos) se reservan una vez por tamaño y se
/// reutilizan: cada análisis solo reserva [mag].
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
  static final Map<int, Float64List> _re = <int, Float64List>{};
  static final Map<int, Float64List> _im = <int, Float64List>{};

  /// Entorno de la medida en curso (se reutiliza; se ordena una vista).
  static Float64List _ring = Float64List(256);

  static Float64List _magnitudes(Float32List x) {
    final int n = x.length;
    if (n < 16 || (n & (n - 1)) != 0) {
      throw ArgumentError.value(n, 'samples.length', 'debe ser potencia de 2');
    }
    final Float64List w = _windows.putIfAbsent(n, () => Float64List.fromList(<double>[for (int i = 0; i < n; i++) 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1))]));
    final Float64List cosT = _cos.putIfAbsent(n, () => Float64List.fromList(<double>[for (int t = 0; t < n ~/ 2; t++) math.cos(2 * math.pi * t / n)]));
    final Float64List sinT = _sin.putIfAbsent(n, () => Float64List.fromList(<double>[for (int t = 0; t < n ~/ 2; t++) -math.sin(2 * math.pi * t / n)]));
    final Float64List re = _re.putIfAbsent(n, () => Float64List(n));
    final Float64List im = _im.putIfAbsent(n, () => Float64List(n));
    for (int i = 0; i < n; i++) {
      re[i] = x[i] * w[i];
      im[i] = 0;
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
    final Float64List mag = Float64List(half + 1);
    for (int k = 0; k <= half; k++) {
      mag[k] = math.sqrt(re[k] * re[k] + im[k] * im[k]);
    }
    return mag;
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
    int count = 0;
    for (int k = math.max(1, (b * 0.55).ceil()); k <= math.min(half, (b * 1.45).floor()); k++) {
      if ((k - b).abs() > 2.5) {
        count = _push(count, mag[k]);
      }
    }
    return _ratioDb(_peak(b), count);
  }

  /// Como [prominenceDb], pero el piso es la mayor de las medianas de cada
  /// lado (de 0,55·[hz] a [hz] y de [hz] a 1,45·[hz], sin los ±2,5 bins del
  /// centro). Con el paso alto de un teléfono el piso sube con la frecuencia:
  /// contra la mediana de los dos lados juntos, un poco de ruido en [hz]
  /// asomaría sobre el lado grave, más atenuado. Devuelve `double.nan` si
  /// algún lado tiene menos de 2 bins.
  double prominenceBothSidesDb(double hz) {
    if (!(hz > 0)) {
      return double.nan;
    }
    final int half = n ~/ 2;
    final double b = hz * n / sampleRate;
    if (b + 1.5 >= half) {
      return double.nan;
    }
    final int from = math.max(1, (b * 0.55).ceil());
    final int to = math.min(half, (b * 1.45).floor());
    int count = 0;
    for (int k = from; k <= to; k++) {
      if (b - k > 2.5) {
        count = _push(count, mag[k]);
      }
    }
    final double left = _median(count);
    count = 0;
    for (int k = from; k <= to; k++) {
      if (k - b > 2.5) {
        count = _push(count, mag[k]);
      }
    }
    final double right = _median(count);
    if (left.isNaN || right.isNaN) {
      return double.nan;
    }
    return 20 * math.log(_peak(b) / (math.max(left, right) + 1e-12)) / math.ln10;
  }

  /// Prominencia, en dB, del armónico [h] de [f0] sobre el piso entre
  /// armónicos: el pico (±1,5 bins) en h·[f0] sobre la mediana de los bins
  /// de los huecos entre armónicos vecinos, de máx(0,5·f0, (h − 1,5)·f0) a
  /// (h + 1,5)·f0, a más de [guard] bins de cada múltiplo de [f0]: el piso no
  /// incluye armónicos de la nota (el lóbulo de Hann mide ±2 bins). Agrupa
  /// tres huecos para que en las notas graves (pocos bins por hueco) la
  /// mediana no dependa de dos o tres bins de ruido. Devuelve `double.nan`
  /// si quedan menos de [minRingBins] bins o si h·[f0] queda en el borde del
  /// espectro.
  ///
  /// Una nota de verdad tiene picos en sus armónicos aunque el micrófono le
  /// quite la fundamental; un residuo (la "fundamental ausente" de la mezcla
  /// con un tono de la app) solo los tiene donde caen lo tocado y la app.
  ///
  /// Con [localMax], el pico tiene que ser un máximo local (más alto que los
  /// bins a ±2 del suyo); si no, es la falda de Hann de un parcial vecino
  /// fuerte y devuelve −∞ (medido, sin pico). Hace falta con [guard] bajo:
  /// el piso queda cerca de los lóbulos y la falda asomaría sobre él.
  double harmonicProminenceDb(double f0, int h, {double guard = 2.5, bool localMax = false}) {
    if (!(f0 > 0) || h < 1) {
      return double.nan;
    }
    final int half = n ~/ 2;
    final double s = f0 * n / sampleRate;
    final double b = h * s;
    if (b + 1.5 >= half) {
      return double.nan;
    }
    if (localMax) {
      int kp = math.max(1, (b - 1.5).floor());
      for (int k = kp + 1; k <= math.min(half, (b + 1.5).ceil()); k++) {
        if (mag[k] > mag[kp]) {
          kp = k;
        }
      }
      if (kp - 2 >= 0 && kp + 2 <= half && !(mag[kp] > mag[kp - 2] && mag[kp] > mag[kp + 2])) {
        return double.negativeInfinity;
      }
    }
    final double lo = math.max(0.5 * s, b - 1.5 * s);
    int count = 0;
    for (int k = math.max(1, lo.ceil()); k <= math.min(half, (b + 1.5 * s).floor()); k++) {
      if ((k - (k / s).round() * s).abs() > guard) {
        count = _push(count, mag[k]);
      }
    }
    return _ratioDb(_peak(b), count);
  }

  double _peak(double b) {
    final int half = n ~/ 2;
    double peak = 0;
    for (int k = math.max(1, (b - 1.5).floor()); k <= math.min(half, (b + 1.5).ceil()); k++) {
      peak = math.max(peak, mag[k]);
    }
    return peak;
  }

  static int _push(int count, double v) {
    if (count == _ring.length) {
      final Float64List bigger = Float64List(_ring.length * 2)..setRange(0, count, _ring);
      _ring = bigger;
    }
    _ring[count] = v;
    return count + 1;
  }

  static double _ratioDb(double peak, int count) {
    if (count < minRingBins) {
      return double.nan;
    }
    return 20 * math.log(peak / (_median(count) + 1e-12)) / math.ln10;
  }

  /// Mediana de los primeros [count] valores del entorno (`nan` si son
  /// menos de 2).
  static double _median(int count) {
    if (count < 2) {
      return double.nan;
    }
    final Float64List ring = Float64List.sublistView(_ring, 0, count)..sort();
    return count.isOdd ? ring[count ~/ 2] : (ring[count ~/ 2 - 1] + ring[count ~/ 2]) / 2;
  }
}
