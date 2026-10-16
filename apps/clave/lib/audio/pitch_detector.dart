import 'dart:math' as math;
import 'dart:typed_data';

/// Resultado de una detección de tono.
class PitchResult {
  const PitchResult({required this.frequency, required this.clarity, required this.rms});

  /// Frecuencia fundamental en Hz, o 0 si no hay tono claro.
  final double frequency;

  /// Claridad de 0 a 1 (1 = periodicidad perfecta).
  final double clarity;

  /// Nivel RMS de la señal (0 a 1).
  final double rms;

  bool get hasPitch => frequency > 0;

  static const PitchResult none = PitchResult(frequency: 0, clarity: 0, rms: 0);
}

/// Detector de tono por el método YIN (de Cheveigné y Kawahara, 2002) con
/// interpolación parabólica. Para los graves se analiza primero la señal
/// diezmada (así cabe un periodo de 16 Hz en un búfer corto) y después se
/// afina el resultado sobre la señal completa alrededor del candidato.
class PitchDetector {
  PitchDetector({this.sampleRate = 44100, this.minFrequency = 16, this.maxFrequency = 4500, this.threshold = 0.12, this.minRms = 0.004});

  final int sampleRate;
  final double minFrequency;
  final double maxFrequency;

  /// Umbral YIN: valores menores exigen periodicidad más clara.
  final double threshold;

  /// Nivel mínimo para intentar detectar (evita ruido de fondo).
  final double minRms;

  PitchResult detect(Float32List samples) {
    final double rms = _rms(samples);
    if (rms < minRms) {
      return PitchResult(frequency: 0, clarity: 0, rms: rms);
    }
    // Paso 1: señal diezmada por 4 para cubrir los graves con poco cálculo.
    const int dec = 4;
    final Float32List low = _decimate(samples, dec);
    final int lowRate = sampleRate ~/ dec;
    final _YinHit? coarse = _yin(low, lowRate, minFrequency, math.min(maxFrequency, lowRate / 4), threshold);
    if (coarse == null) {
      return PitchResult(frequency: 0, clarity: 0, rms: rms);
    }
    double f = coarse.frequency;
    double clarity = coarse.clarity;
    // Paso 2: afinar sobre la señal completa en una banda estrecha.
    if (f > 60) {
      final _YinHit? fine = _yin(samples, sampleRate, f / 1.08, f * 1.08, math.max(threshold, 0.2));
      if (fine != null) {
        f = fine.frequency;
        clarity = fine.clarity;
      }
    }
    if (f < minFrequency || f > maxFrequency) {
      return PitchResult(frequency: 0, clarity: 0, rms: rms);
    }
    return PitchResult(frequency: f, clarity: clarity, rms: rms);
  }

  static double _rms(Float32List s) {
    double acc = 0;
    for (int i = 0; i < s.length; i++) {
      acc += s[i] * s[i];
    }
    return s.isEmpty ? 0 : math.sqrt(acc / s.length);
  }

  /// Diezmado con promedio (filtro de caja), suficiente como antialias
  /// para buscar la fundamental.
  static Float32List _decimate(Float32List s, int factor) {
    final int n = s.length ~/ factor;
    final Float32List out = Float32List(n);
    for (int i = 0; i < n; i++) {
      double acc = 0;
      final int base = i * factor;
      for (int k = 0; k < factor; k++) {
        acc += s[base + k];
      }
      out[i] = acc / factor;
    }
    return out;
  }

  /// YIN sobre [s] buscando periodos entre rate/maxF y rate/minF.
  static _YinHit? _yin(Float32List s, int rate, double minF, double maxF, double thr) {
    final int n = s.length;
    final int tauMin = math.max(2, (rate / maxF).floor());
    int tauMax = (rate / minF).ceil();
    // Hace falta al menos un periodo de ventana además del retardo.
    final int window = n ~/ 2;
    if (tauMax > n - window) {
      tauMax = n - window;
    }
    if (tauMax <= tauMin + 2) {
      return null;
    }
    final Float64List d = Float64List(tauMax + 1);
    for (int tau = tauMin; tau <= tauMax; tau++) {
      double acc = 0;
      for (int j = 0; j < window; j++) {
        final double diff = s[j] - s[j + tau];
        acc += diff * diff;
      }
      d[tau] = acc;
    }
    // Diferencia media normalizada acumulada.
    final Float64List cmnd = Float64List(tauMax + 1);
    double running = 0;
    for (int tau = tauMin; tau <= tauMax; tau++) {
      running += d[tau];
      cmnd[tau] = running == 0 ? 1 : d[tau] * (tau - tauMin + 1) / running;
    }
    // Primer mínimo por debajo del umbral; si no hay, el mínimo global.
    int best = -1;
    for (int tau = tauMin + 1; tau < tauMax; tau++) {
      if (cmnd[tau] < thr) {
        while (tau + 1 < tauMax && cmnd[tau + 1] < cmnd[tau]) {
          tau++;
        }
        best = tau;
        break;
      }
    }
    if (best < 0) {
      double minVal = double.infinity;
      for (int tau = tauMin + 1; tau < tauMax; tau++) {
        if (cmnd[tau] < minVal) {
          minVal = cmnd[tau];
          best = tau;
        }
      }
      if (best < 0 || minVal > 0.5) {
        return null;
      }
    }
    // Interpolación parabólica alrededor del mínimo.
    double tauEst = best.toDouble();
    if (best > tauMin && best < tauMax) {
      final double a = cmnd[best - 1];
      final double b = cmnd[best];
      final double c = cmnd[best + 1];
      final double denom = a - 2 * b + c;
      if (denom.abs() > 1e-12) {
        tauEst = best + (a - c) / (2 * denom);
      }
    }
    final double clarity = (1 - cmnd[best]).clamp(0.0, 1.0).toDouble();
    return _YinHit(rate / tauEst, clarity);
  }
}

class _YinHit {
  const _YinHit(this.frequency, this.clarity);

  final double frequency;
  final double clarity;
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
