import 'dart:math' as math;
import 'dart:typed_data';

/// Familias de sonido del metrónomo. Cada una se sintetiza con código: no
/// hay muestras de terceros. Todas tienen variante de acento, pulso y
/// subdivisión (más corta y suave).
enum ClickSound {
  madera,
  clave,
  beep,
  campana,
  cencerro,
  caja,
  bombo,
  hihat,
  palmada,
  triangulo,
  gota,
  tecla,
}

extension ClickSoundX on ClickSound {
  String get nameEs {
    switch (this) {
      case ClickSound.madera:
        return 'Madera';
      case ClickSound.clave:
        return 'Clave';
      case ClickSound.beep:
        return 'Pitido';
      case ClickSound.campana:
        return 'Campana';
      case ClickSound.cencerro:
        return 'Cencerro';
      case ClickSound.caja:
        return 'Caja';
      case ClickSound.bombo:
        return 'Bombo';
      case ClickSound.hihat:
        return 'Hi-hat';
      case ClickSound.palmada:
        return 'Palmada';
      case ClickSound.triangulo:
        return 'Triángulo';
      case ClickSound.gota:
        return 'Gota';
      case ClickSound.tecla:
        return 'Tecla';
    }
  }

  String get nameEn {
    switch (this) {
      case ClickSound.madera:
        return 'Wood block';
      case ClickSound.clave:
        return 'Clave';
      case ClickSound.beep:
        return 'Beep';
      case ClickSound.campana:
        return 'Bell';
      case ClickSound.cencerro:
        return 'Cowbell';
      case ClickSound.caja:
        return 'Snare';
      case ClickSound.bombo:
        return 'Kick';
      case ClickSound.hihat:
        return 'Hi-hat';
      case ClickSound.palmada:
        return 'Clap';
      case ClickSound.triangulo:
        return 'Triangle';
      case ClickSound.gota:
        return 'Drop';
      case ClickSound.tecla:
        return 'Key';
    }
  }
}

/// Tipo de golpe dentro del compás.
enum BeatKind { accent, normal, sub }

/// Sintetiza los golpes del metrónomo como muestras de punto flotante.
class ClickSynth {
  ClickSynth({this.sampleRate = 44100});

  final int sampleRate;
  final Map<String, Float32List> _cache = <String, Float32List>{};
  final math.Random _random = math.Random(7);

  /// Muestras de un golpe (cacheadas por sonido y tipo).
  Float32List sample(ClickSound sound, BeatKind kind) {
    final String key = '${sound.name}/${kind.name}';
    return _cache.putIfAbsent(key, () => _render(sound, kind));
  }

  Float32List _render(ClickSound sound, BeatKind kind) {
    final double gain = kind == BeatKind.accent ? 1.0 : (kind == BeatKind.normal ? 0.72 : 0.42);
    final double pitchMul = kind == BeatKind.accent ? 1.35 : (kind == BeatKind.normal ? 1.0 : 0.85);
    switch (sound) {
      case ClickSound.madera:
        return _tone(freq: 880 * pitchMul, decay: 0.045, gain: gain, noise: 0.25, noiseDecay: 0.01, harmonics: <double>[1, 0.4]);
      case ClickSound.clave:
        return _tone(freq: 2500 * pitchMul, decay: 0.04, gain: gain * 0.9, noise: 0.08, noiseDecay: 0.004);
      case ClickSound.beep:
        return _tone(freq: 1000 * pitchMul, decay: 0.06, gain: gain, attack: 0.002, sustain: 0.03);
      case ClickSound.campana:
        return _tone(freq: 1760 * pitchMul, decay: 0.35, gain: gain * 0.7, harmonics: <double>[1, 0.5, 0.25, 0.15], inharmonic: true);
      case ClickSound.cencerro:
        return _tone(freq: 587 * pitchMul, decay: 0.12, gain: gain * 0.9, harmonics: <double>[1, 0.9, 0.3], inharmonic: true, noise: 0.15, noiseDecay: 0.02);
      case ClickSound.caja:
        return _tone(freq: 180 * pitchMul, decay: 0.08, gain: gain * 0.6, noise: 1.0, noiseDecay: 0.09);
      case ClickSound.bombo:
        return _kick(gain: gain, pitchMul: pitchMul);
      case ClickSound.hihat:
        return _tone(freq: 6000, decay: 0.01, gain: gain * 0.5, noise: 1.0, noiseDecay: kind == BeatKind.accent ? 0.12 : 0.04, highpass: true);
      case ClickSound.palmada:
        return _clap(gain: gain);
      case ClickSound.triangulo:
        return _tone(freq: 4200 * pitchMul, decay: 0.5, gain: gain * 0.45, harmonics: <double>[1, 0.6, 0.4, 0.3], inharmonic: true);
      case ClickSound.gota:
        return _tone(freq: 1400 * pitchMul, decay: 0.09, gain: gain * 0.8, sweep: 0.45);
      case ClickSound.tecla:
        return _tone(freq: 2200 * pitchMul, decay: 0.03, gain: gain * 0.7, noise: 0.5, noiseDecay: 0.008);
    }
  }

  /// Tono amortiguado con armónicos, ruido inicial y barrido opcional.
  Float32List _tone({
    required double freq,
    required double decay,
    required double gain,
    double attack = 0.0005,
    double sustain = 0,
    List<double> harmonics = const <double>[1],
    bool inharmonic = false,
    double noise = 0,
    double noiseDecay = 0.01,
    double sweep = 0,
    bool highpass = false,
  }) {
    final double tail = decay > noiseDecay ? decay : noiseDecay;
    final int n = (((attack + sustain + tail * 4).clamp(0.02, 1.0)) * sampleRate).ceil();
    final Float32List out = Float32List(n);
    double lastNoise = 0;
    for (int i = 0; i < n; i++) {
      final double t = i / sampleRate;
      double env;
      if (t < attack) {
        env = t / attack;
      } else if (t < attack + sustain) {
        env = 1;
      } else {
        env = math.exp(-(t - attack - sustain) / decay);
      }
      final double f = sweep > 0 ? freq * (1 - sweep * math.min(1, t / (decay * 2))) : freq;
      double v = 0;
      for (int h = 0; h < harmonics.length; h++) {
        final double mul = inharmonic ? <double>[1, 2.76, 5.4, 8.9, 13.3][h % 5] : (h + 1).toDouble();
        v += harmonics[h] * math.sin(2 * math.pi * f * mul * t);
      }
      v /= harmonics.fold<double>(0, (double a, double b) => a + b);
      if (noise > 0) {
        double white = _random.nextDouble() * 2 - 1;
        if (highpass) {
          final double hp = white - lastNoise;
          lastNoise = white;
          white = hp;
        }
        v += noise * white * math.exp(-t / noiseDecay);
      }
      out[i] = (v * env * gain).clamp(-1.0, 1.0).toDouble();
    }
    return out;
  }

  Float32List _kick({required double gain, required double pitchMul}) {
    final int n = (0.25 * sampleRate).ceil();
    final Float32List out = Float32List(n);
    double phase = 0;
    for (int i = 0; i < n; i++) {
      final double t = i / sampleRate;
      final double f = (55 + 120 * math.exp(-t / 0.03)) * pitchMul;
      phase += 2 * math.pi * f / sampleRate;
      final double env = math.exp(-t / 0.09);
      final double click = i < 60 ? (1 - i / 60) * 0.5 : 0;
      out[i] = ((math.sin(phase) + click) * env * gain).clamp(-1.0, 1.0).toDouble();
    }
    return out;
  }

  Float32List _clap({required double gain}) {
    final int n = (0.16 * sampleRate).ceil();
    final Float32List out = Float32List(n);
    // Tres ráfagas de ruido muy seguidas y una cola.
    const List<double> bursts = <double>[0, 0.011, 0.022];
    for (int i = 0; i < n; i++) {
      final double t = i / sampleRate;
      double env = 0;
      for (final double b in bursts) {
        if (t >= b) {
          env = math.max(env, math.exp(-(t - b) / 0.008));
        }
      }
      if (t > 0.03) {
        env = math.max(env, 0.6 * math.exp(-(t - 0.03) / 0.04));
      }
      out[i] = ((_random.nextDouble() * 2 - 1) * env * gain * 0.8).clamp(-1.0, 1.0).toDouble();
    }
    return out;
  }
}

/// Convierte flotantes (-1 a 1) a PCM de 16 bits little-endian.
Uint8List floatToPcm16(Float32List samples) {
  final ByteData data = ByteData(samples.length * 2);
  for (int i = 0; i < samples.length; i++) {
    final double v = samples[i].clamp(-1.0, 1.0).toDouble();
    data.setInt16(i * 2, (v * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}
