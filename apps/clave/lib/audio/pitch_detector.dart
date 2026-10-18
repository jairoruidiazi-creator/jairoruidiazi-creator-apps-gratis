import 'dart:math' as math;
import 'dart:typed_data';

/// Resultado de una detección de tono.
class PitchResult {
  const PitchResult({required this.frequency, required this.clarity, required this.rms});

  /// Frecuencia fundamental en Hz, o 0 si no hay tono claro.
  final double frequency;

  /// Claridad de 0 a 1 (correlación normalizada en el periodo elegido;
  /// 1 = periodicidad perfecta).
  final double clarity;

  /// Nivel RMS de la señal (0 a 1).
  final double rms;

  bool get hasPitch => frequency > 0;

  static const PitchResult none = PitchResult(frequency: 0, clarity: 0, rms: 0);
}

/// Detector de tono para el afinador, verificado de Do0 (16,35 Hz) a Do8
/// (4186 Hz) con senos, timbres con muchos armónicos, fundamental débil,
/// fases aleatorias, voz y ruido (test/pitch_detector_test.dart).
///
/// Pasos:
///  1. Nivel mínimo y resta de la media.
///  2. Graves: filtro antialias FIR (sinc con ventana de Blackman, corte en
///     2 kHz) y diezmado por 4; YIN sobre la señal diezmada de 15,5 a 1100 Hz.
///  3. Agudos: YIN a tasa completa sobre la señal con paso bajo (Butterworth
///     de orden 6 en 5 kHz) de 600 a 4500 Hz.
///  4. Cada candidato se verifica a tasa completa con la NSDF (correlación
///     normalizada) y se comprueban los subarmónicos: si T/k tiene NSDF ≥ 0,9
///     y no peor que T, la nota es k veces más aguda (gana la k mayor). Al
///     revés, si 2T, 3T o 4T tienen NSDF ≥ 0,9 y claramente mayor (+0,06),
///     la nota es más grave.
///  5. Entre candidatos gana la NSDF mayor; en empate, el periodo más corto.
///  6. Afinado fino con la diferencia de YIN (parábola): sobre la señal
///     original hasta 1 kHz y sobre la filtrada por encima.
///  7. Refinamiento espectral (ventana de Hann) solo si en la fundamental hay
///     un pico con energía, a menos de 1,5 bins de la estimación.
///
/// El prototipo en Python que validó el diseño está descrito en
/// docs/DECISIONES.md.
class PitchDetector {
  PitchDetector({this.sampleRate = 44100, this.minFrequency = 15.5, this.maxFrequency = 4500, this.minRms = 0.004})
      : _fir = _blackmanLowpass(_firTaps, 2000.0 / sampleRate),
        _sections = _butterworthLowpass(5000.0 / sampleRate);

  final int sampleRate;
  final double minFrequency;
  final double maxFrequency;

  /// Nivel mínimo para intentar detectar (evita ruido de fondo).
  final double minRms;

  /// Muestras mínimas por análisis (la pasada aguda usa las últimas 4096).
  static const int minSamples = 4096;

  static const int _decimation = 4;
  static const int _firTaps = 63;
  static const double _lowMaxFrequency = 1100;
  static const double _highMinFrequency = 600;
  static const int _highSpan = 4096;
  static const int _highWindow = 2048;
  static const double _yinThreshold = 0.15;
  static const double _subharmonicMin = 0.9;
  static const double _tieTolerance = 0.02;
  static const double _superGain = 0.06;
  static const double _spectralMinFrequency = 120;
  static const double _rawRefineMaxFrequency = 1000;
  static const int _goldenSteps = 14;

  final Float64List _fir;
  final List<_Biquad> _sections;
  final Map<int, Float64List> _scratch = <int, Float64List>{};
  final Map<int, Float64List> _hann = <int, Float64List>{};

  PitchResult detect(Float32List samples) {
    final int n = samples.length;
    if (n < minSamples) {
      return PitchResult.none;
    }
    double acc = 0;
    double sum = 0;
    for (int i = 0; i < n; i++) {
      final double v = samples[i];
      acc += v * v;
      sum += v;
    }
    final double rms = math.sqrt(acc / n);
    if (rms < minRms) {
      return PitchResult(frequency: 0, clarity: 0, rms: rms);
    }
    final double mean = sum / n;
    final Float64List x = _buffer(0, n);
    for (int i = 0; i < n; i++) {
      x[i] = samples[i] - mean;
    }
    final Float64List y = _buffer(1, n);
    _lowpass(x, y);
    final Float64List py = _buffer(2, n + 1);
    _prefixSquares(y, py);
    final int w = n ~/ 2;

    // Candidatos graves (señal diezmada) y agudos (tasa completa filtrada).
    final List<double> taus = <double>[];
    final int lowN = n ~/ _decimation;
    final Float64List low = _buffer(3, lowN);
    _decimate(x, low);
    final Float64List plow = _buffer(4, lowN + 1);
    _prefixSquares(low, plow);
    final double? lo = _yin(low, plow, 0, lowN, sampleRate / _decimation, minFrequency, _lowMaxFrequency, lowN ~/ 2);
    if (lo != null) {
      taus.add(lo * _decimation);
    }
    final double? hi = _yin(y, py, n - _highSpan, n, sampleRate.toDouble(), _highMinFrequency, maxFrequency, _highWindow);
    if (hi != null) {
      taus.add(hi);
    }
    if (taus.isEmpty) {
      return PitchResult(frequency: 0, clarity: 0, rms: rms);
    }

    double bestTau = -1;
    double bestValue = -2;
    for (final double tau in taus) {
      final _Peak? r = _verify(y, py, w, tau);
      if (r == null) {
        continue;
      }
      if (bestTau < 0 || r.value > bestValue + _tieTolerance || ((r.value - bestValue).abs() <= _tieTolerance && r.tau < bestTau * 0.97)) {
        bestTau = r.tau;
        bestValue = r.value;
      }
    }
    if (bestTau < 0 || bestValue < 0.3) {
      return PitchResult(frequency: 0, clarity: 0, rms: rms);
    }

    double tau;
    if (sampleRate / bestTau < _rawRefineMaxFrequency) {
      final Float64List px = _buffer(5, n + 1);
      _prefixSquares(x, px);
      tau = _yinRefine(x, px, w, bestTau);
    } else {
      tau = _yinRefine(y, py, w, bestTau);
    }
    double f = sampleRate / tau;
    if (!f.isFinite || f < minFrequency || f > maxFrequency) {
      return PitchResult(frequency: 0, clarity: 0, rms: rms);
    }
    if (f > _spectralMinFrequency) {
      f = _refineSpectral(x, f);
    }
    return PitchResult(frequency: f, clarity: bestValue.clamp(0.0, 1.0).toDouble(), rms: rms);
  }

  // ------------------------------------------------------------ utilidades

  Float64List _buffer(int slot, int length) {
    final int key = slot * 1000003 + length;
    return _scratch.putIfAbsent(key, () => Float64List(length));
  }

  static void _prefixSquares(Float64List x, Float64List p) {
    double acc = 0;
    p[0] = 0;
    for (int i = 0; i < x.length; i++) {
      acc += x[i] * x[i];
      p[i + 1] = acc;
    }
  }

  /// Producto punto de x[a..a+w) y x[b..b+w), desenrollado de a cuatro.
  static double _corr(Float64List x, int a, int b, int w) {
    double s0 = 0;
    double s1 = 0;
    double s2 = 0;
    double s3 = 0;
    int j = 0;
    final int limit = w - 3;
    for (; j < limit; j += 4) {
      s0 += x[a + j] * x[b + j];
      s1 += x[a + j + 1] * x[b + j + 1];
      s2 += x[a + j + 2] * x[b + j + 2];
      s3 += x[a + j + 3] * x[b + j + 3];
    }
    for (; j < w; j++) {
      s0 += x[a + j] * x[b + j];
    }
    return (s0 + s1) + (s2 + s3);
  }

  /// Paso bajo sinc con ventana de Blackman, normalizado a ganancia 1.
  static Float64List _blackmanLowpass(int taps, double cutoff) {
    final Float64List h = Float64List(taps);
    final int m = taps - 1;
    double total = 0;
    for (int i = 0; i < taps; i++) {
      final double t = i - m / 2;
      final double s = t == 0 ? 2 * cutoff : math.sin(2 * math.pi * cutoff * t) / (math.pi * t);
      final double win = 0.42 - 0.5 * math.cos(2 * math.pi * i / m) + 0.08 * math.cos(4 * math.pi * i / m);
      h[i] = s * win;
      total += h[i];
    }
    for (int i = 0; i < taps; i++) {
      h[i] /= total;
    }
    return h;
  }

  /// Butterworth paso bajo de orden 6 (tres secciones de segundo orden).
  static List<_Biquad> _butterworthLowpass(double cutoff) {
    const int order = 6;
    final double k = math.tan(math.pi * cutoff);
    final List<_Biquad> out = <_Biquad>[];
    for (int i = 0; i < order ~/ 2; i++) {
      final double q = 1 / (2 * math.cos(math.pi * (2 * i + 1) / (2 * order)));
      final double norm = 1 / (1 + k / q + k * k);
      final double b0 = k * k * norm;
      out.add(_Biquad(b0, 2 * b0, b0, 2 * (k * k - 1) * norm, (1 - k / q + k * k) * norm));
    }
    return out;
  }

  void _lowpass(Float64List x, Float64List y) {
    for (int i = 0; i < x.length; i++) {
      y[i] = x[i];
    }
    for (final _Biquad s in _sections) {
      double x1 = 0;
      double x2 = 0;
      double y1 = 0;
      double y2 = 0;
      for (int i = 0; i < y.length; i++) {
        final double xi = y[i];
        final double yi = s.b0 * xi + s.b1 * x1 + s.b2 * x2 - s.a1 * y1 - s.a2 * y2;
        x2 = x1;
        x1 = xi;
        y2 = y1;
        y1 = yi;
        y[i] = yi;
      }
    }
  }

  /// Filtra con el FIR y se queda con una de cada [_decimation] muestras.
  void _decimate(Float64List x, Float64List out) {
    final int n = x.length;
    const int half = _firTaps ~/ 2;
    for (int i = 0; i < out.length; i++) {
      final int c = i * _decimation + _decimation ~/ 2;
      final int lo = c - half;
      final int hi = c + half + 1;
      final int a = lo < 0 ? 0 : lo;
      final int b = hi > n ? n : hi;
      double acc = 0;
      for (int j = a; j < b; j++) {
        acc += x[j] * _fir[j - lo];
      }
      out[i] = acc;
    }
  }

  /// YIN sobre x[start..end): periodo (en muestras de esa tasa) o null.
  static double? _yin(Float64List x, Float64List p, int start, int end, double rate, double minF, double maxF, int window) {
    final int n = end - start;
    final int tauMin = math.max(2, (rate / maxF).floor());
    int tauMax = (rate / minF).ceil();
    final int w = window;
    if (tauMax > n - w - 1) {
      tauMax = n - w - 1;
    }
    if (tauMax <= tauMin + 2) {
      return null;
    }
    final double ea = p[start + w] - p[start];
    final Float64List cm = Float64List(tauMax + 2);
    double running = 0;
    for (int tau = tauMin; tau <= tauMax + 1; tau++) {
      final double eb = p[start + tau + w] - p[start + tau];
      final double d = ea + eb - 2 * _corr(x, start, start + tau, w);
      running += d;
      cm[tau] = running <= 0 ? 1 : d * (tau - tauMin + 1) / running;
    }
    int best = -1;
    for (int tau = tauMin + 1; tau < tauMax; tau++) {
      if (cm[tau] < _yinThreshold) {
        while (tau + 1 < tauMax && cm[tau + 1] < cm[tau]) {
          tau++;
        }
        best = tau;
        break;
      }
    }
    if (best < 0) {
      double minValue = double.infinity;
      for (int tau = tauMin + 1; tau < tauMax; tau++) {
        if (cm[tau] < minValue) {
          minValue = cm[tau];
          best = tau;
        }
      }
      if (best < 0 || minValue > 0.5) {
        return null;
      }
    }
    double estimate = best.toDouble();
    final double a = cm[best - 1];
    final double b = cm[best];
    final double c = cm[best + 1];
    final double den = a - 2 * b + c;
    if (den.abs() > 1e-12) {
      final double off = (a - c) / (2 * den);
      if (off.abs() < 1) {
        estimate = best + off;
      }
    }
    return estimate;
  }

  /// Pico de la NSDF de x (ventana [w] desde el inicio) cerca de [tauC].
  static _Peak? _nsdfPeak(Float64List x, Float64List p, int w, double tauC, double span) {
    final int n = x.length;
    final int lo = math.max(2, (tauC - span).floor());
    int hi = (tauC + span).ceil();
    if (hi + 1 + w > n) {
      hi = n - w - 1;
    }
    if (hi <= lo) {
      return null;
    }
    final double ea = p[w];
    final int first = lo - 1;
    final int count = hi - lo + 3;
    final Float64List values = Float64List(count);
    int bestTau = -1;
    double bestValue = -2;
    for (int k = 0; k < count; k++) {
      final int tau = first + k;
      final double eb = p[tau + w] - p[tau];
      final double den = ea + eb;
      final double v = den > 0 ? 2 * _corr(x, 0, tau, w) / den : 0;
      values[k] = v;
      if (tau >= lo && tau <= hi && v > bestValue) {
        bestValue = v;
        bestTau = tau;
      }
    }
    if (bestTau < 0) {
      return null;
    }
    double tau = bestTau.toDouble();
    double value = bestValue;
    final int k = bestTau - first;
    final double a = values[k - 1];
    final double b = values[k];
    final double c = values[k + 1];
    final double den = a - 2 * b + c;
    if (den < -1e-12) {
      final double off = 0.5 * (a - c) / den;
      if (off.abs() <= 1) {
        tau = bestTau + off;
        value = b - 0.25 * (a - c) * off;
      }
    }
    return _Peak(tau, math.min(value, 1.0));
  }

  /// NSDF cerca de [tau] y comprobación de subarmónicos.
  _Peak? _verify(Float64List y, Float64List p, int w, double tau) {
    final _Peak? first = _nsdfPeak(y, p, w, tau, math.max(3.0, tau * 0.006));
    if (first == null) {
      return null;
    }
    _Peak best = first;
    final double minTau = sampleRate / maxFrequency - 0.5;
    for (int k = 2; k <= 8 && first.tau / k >= minTau; k++) {
      final double tk = first.tau / k;
      final _Peak? r = _nsdfPeak(y, p, w, tk, math.max(1.5, tk * 0.02));
      if (r != null && r.value >= _subharmonicMin && r.value >= first.value - _tieTolerance) {
        best = r;
      }
    }
    // Periodos más largos: si m·T es claramente más periódico que T, la nota
    // real es más grave (fundamental débil con armónicos impares débiles,
    // como en algunas vocales cantadas).
    final double maxTau = math.min(sampleRate / minFrequency, (y.length - w - 2).toDouble());
    bool changed = true;
    for (int round = 0; changed && round < 3; round++) {
      changed = false;
      for (int m = 2; m <= 4; m++) {
        final double tm = best.tau * m;
        if (tm + 3 > maxTau) {
          break;
        }
        final _Peak? r = _nsdfPeak(y, p, w, tm, math.max(3.0, tm * 0.006));
        if (r != null && r.value >= _subharmonicMin && r.value >= best.value + _superGain) {
          best = r;
          changed = true;
          break;
        }
      }
    }
    return best;
  }

  /// Parábola sobre la diferencia de YIN (sin normalizar) cerca de [tau].
  static double _yinRefine(Float64List x, Float64List p, int w, double tau) {
    final int n = x.length;
    int b = tau.round();
    if (b < 3 || b + 2 + w > n) {
      return tau;
    }
    final double ea = p[w];
    double d(int t) => ea + (p[t + w] - p[t]) - 2 * _corr(x, 0, t, w);
    double va = d(b - 1);
    double vb = d(b);
    double vc = d(b + 1);
    // Se mueve al mínimo local más cercano (como mucho tres pasos).
    for (int step = 0; step < 3 && (va < vb || vc < vb); step++) {
      if (va < vb && va <= vc) {
        if (b - 2 < 2) {
          break;
        }
        b -= 1;
        vc = vb;
        vb = va;
        va = d(b - 1);
      } else {
        if (b + 2 + w > n) {
          break;
        }
        b += 1;
        va = vb;
        vb = vc;
        vc = d(b + 1);
      }
    }
    final double den = va - 2 * vb + vc;
    if (den > 1e-15) {
      final double off = 0.5 * (va - vc) / den;
      if (off.abs() <= 1) {
        return b + off;
      }
    }
    return b.toDouble();
  }

  // ------------------------------------------------------------ espectral

  Float64List _hannWindow(int n) {
    return _hann.putIfAbsent(n, () {
      final Float64List h = Float64List(n);
      for (int i = 0; i < n; i++) {
        h[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
      }
      return h;
    });
  }

  /// Potencia de la DFT de [s] en [hz] (rotación incremental del fasor).
  double _power(Float64List s, double hz) {
    final int n = s.length;
    final double wv = 2 * math.pi * hz / sampleRate;
    final double cw = math.cos(wv);
    final double sw = math.sin(wv);
    double cr = 1;
    double ci = 0;
    double re = 0;
    double im = 0;
    for (int i = 0; i < n; i++) {
      final double v = s[i];
      re += v * cr;
      im += v * ci;
      final double ncr = cr * cw - ci * sw;
      ci = cr * sw + ci * cw;
      cr = ncr;
    }
    return re * re + im * im;
  }

  /// Pico espectral cerca de [f0], solo si la fundamental tiene energía
  /// (al menos un 5 % del total) y el pico está a menos de 1,5 bins.
  double _refineSpectral(Float64List x, double f0) {
    final int n = math.min(f0 < 400 ? 8192 : 4096, x.length);
    final Float64List win = _hannWindow(n);
    final Float64List s = _buffer(6, n);
    final int offset = x.length - n;
    double energy = 0;
    for (int i = 0; i < n; i++) {
      final double v = x[offset + i] * win[i];
      s[i] = v;
      energy += v * v;
    }
    if (energy <= 0) {
      return f0;
    }
    final double binHz = sampleRate / n;
    final double step = 0.375 * binHz;
    double bestF = f0;
    double bestP = _power(s, f0);
    for (int i = -4; i <= 4; i++) {
      if (i == 0) {
        continue;
      }
      final double fi = f0 + i * step;
      final double pi = _power(s, fi);
      if (pi > bestP) {
        bestP = pi;
        bestF = fi;
      }
    }
    // Para un seno puro con ventana de Hann esta fracción vale 1.
    final double fraction = bestP / (n * energy) * 3.0;
    if (fraction < 0.05 || (bestF - f0).abs() > 1.4 * binHz) {
      return f0;
    }
    double a = bestF - step;
    double b = bestF + step;
    const double phi = 0.6180339887498949;
    double x1 = b - phi * (b - a);
    double x2 = a + phi * (b - a);
    double p1 = _power(s, x1);
    double p2 = _power(s, x2);
    for (int i = 0; i < _goldenSteps; i++) {
      if (p1 > p2) {
        b = x2;
        x2 = x1;
        p2 = p1;
        x1 = b - phi * (b - a);
        p1 = _power(s, x1);
      } else {
        a = x1;
        x1 = x2;
        p1 = p2;
        x2 = a + phi * (b - a);
        p2 = _power(s, x2);
      }
    }
    final double best = (a + b) / 2;
    return (best - f0).abs() <= 1.5 * binHz ? best : f0;
  }
}

class _Biquad {
  const _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;
}

class _Peak {
  const _Peak(this.tau, this.value);

  final double tau;
  final double value;
}

/// Convierte PCM de 16 bits little-endian en flotantes de -1 a 1.
Float32List pcm16ToFloat(Uint8List bytes) {
  final int n = bytes.lengthInBytes ~/ 2;
  final ByteData view = ByteData.sublistView(bytes);
  final Float32List out = Float32List(n);
  for (int i = 0; i < n; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}
