import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Forma de onda de los tonos sostenidos.
enum WaveShape { sine, triangle, saw, square }

/// Forma que suena de verdad a [hz] para que no haya aliasing a 44,1 kHz.
/// La sierra y la cuadrada del motor son series de Fourier de 14 y 11
/// armónicos (hasta el 21.º en la cuadrada): por encima de 1500 Hz y 1000 Hz
/// sus armónicos pasarían la frecuencia de Nyquist y se usa el seno. El
/// triángulo (armónicos que caen 12 dB por octava) pasa a seno desde 3000 Hz.
WaveShape bandLimitedShape(WaveShape shape, double hz) {
  switch (shape) {
    case WaveShape.sine:
      return WaveShape.sine;
    case WaveShape.triangle:
      return hz < 3000 ? WaveShape.triangle : WaveShape.sine;
    case WaveShape.saw:
      return hz <= 1500 ? WaveShape.saw : WaveShape.sine;
    case WaveShape.square:
      return hz <= 1000 ? WaveShape.square : WaveShape.sine;
  }
}

/// Ganancia relativa por forma de onda: la cuadrada y la sierra suenan más
/// fuerte que el seno con la misma amplitud.
double shapeGain(WaveShape shape) {
  switch (shape) {
    case WaveShape.sine:
      return 1.0;
    case WaveShape.triangle:
      return 1.0;
    case WaveShape.saw:
      return 0.8;
    case WaveShape.square:
      return 0.65;
  }
}

/// Identificador opaco de un flujo PCM abierto.
class PcmStream {
  PcmStream({this.source, this.handle});

  final AudioSource? source;
  final SoundHandle? handle;
}

/// Un tono sostenido en reproducción.
class Tone {
  Tone({this.source, this.handle, this.shape = WaveShape.sine, this.actual = WaveShape.sine});

  final AudioSource? source;
  final SoundHandle? handle;

  /// Forma pedida y forma que suena (ver [bandLimitedShape]).
  WaveShape shape;
  WaveShape actual;
}

/// Capa fina sobre el motor de audio para que el resto de la app (y las
/// pruebas) no dependan de SoLoud directamente.
abstract class AudioEngine {
  bool get ready;

  Future<void> init();

  /// Abre un flujo PCM mono s16le al que se le irán empujando bloques.
  Future<PcmStream?> openPcmStream({int sampleRate = 44100, double bufferingSeconds = 0.05});

  void pushPcm(PcmStream stream, Uint8List bytes);

  /// Segundos de audio ya consumidos por el mezclador (lo que se oye llega
  /// un poco después: ese es el retraso del audio que se ajusta en Ajustes).
  double consumedSeconds(PcmStream stream);

  Future<void> closePcmStream(PcmStream stream);

  Future<Tone?> startTone(double hz, {WaveShape shape = WaveShape.sine, double volume = 0.5});

  void setToneFrequency(Tone tone, double hz);

  void setToneShape(Tone tone, WaveShape shape);

  void setToneVolume(Tone tone, double volume);

  void fadeToneVolume(Tone tone, double volume, Duration time);

  Future<void> stopTone(Tone tone, {Duration fade = const Duration(milliseconds: 60)});

  Future<void> dispose();
}

/// Motor real sobre flutter_soloud.
class SoLoudEngine implements AudioEngine {
  bool _ready = false;
  Future<void>? _initializing;

  @override
  bool get ready => _ready;

  @override
  Future<void> init() {
    if (_ready) {
      return Future<void>.value();
    }
    return _initializing ??= _init().whenComplete(() => _initializing = null);
  }

  Future<void> _init() async {
    try {
      await SoLoud.instance.init(sampleRate: 44100, bufferSize: 1024);
      _ready = SoLoud.instance.isInitialized;
    } catch (e) {
      debugPrint('No se pudo iniciar el audio: $e');
      _ready = false;
    }
  }

  @override
  Future<PcmStream?> openPcmStream({int sampleRate = 44100, double bufferingSeconds = 0.05}) async {
    if (!_ready) {
      await init();
      if (!_ready) {
        return null;
      }
    }
    try {
      final AudioSource source = SoLoud.instance.setBufferStream(
        maxBufferSizeBytes: 1024 * 1024 * 512,
        bufferingType: BufferingType.released,
        bufferingTimeNeeds: bufferingSeconds,
        sampleRate: sampleRate,
        channels: Channels.mono,
        format: BufferType.s16le,
      );
      final SoundHandle handle = SoLoud.instance.play(source);
      return PcmStream(source: source, handle: handle);
    } catch (e) {
      debugPrint('No se pudo abrir el flujo de audio: $e');
      return null;
    }
  }

  @override
  void pushPcm(PcmStream stream, Uint8List bytes) {
    final AudioSource? source = stream.source;
    if (source == null) {
      return;
    }
    try {
      SoLoud.instance.addAudioDataStream(source, bytes);
    } catch (e) {
      debugPrint('Error al enviar audio: $e');
    }
  }

  @override
  double consumedSeconds(PcmStream stream) {
    final AudioSource? source = stream.source;
    if (source == null) {
      return 0;
    }
    try {
      return SoLoud.instance.getStreamTimeConsumed(source).inMicroseconds / 1e6;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<void> closePcmStream(PcmStream stream) async {
    final AudioSource? source = stream.source;
    final SoundHandle? handle = stream.handle;
    if (source == null || handle == null) {
      return;
    }
    try {
      SoLoud.instance.setDataIsEnded(source);
      await SoLoud.instance.stop(handle);
      await SoLoud.instance.disposeSource(source);
    } catch (e) {
      debugPrint('Error al cerrar el flujo: $e');
    }
  }

  WaveForm _wave(WaveShape s) {
    switch (s) {
      case WaveShape.sine:
        return WaveForm.sin;
      case WaveShape.triangle:
        return WaveForm.triangle;
      case WaveShape.saw:
        return WaveForm.fSaw;
      case WaveShape.square:
        return WaveForm.fSquare;
    }
  }

  @override
  Future<Tone?> startTone(double hz, {WaveShape shape = WaveShape.sine, double volume = 0.5}) async {
    if (!_ready) {
      await init();
      if (!_ready) {
        return null;
      }
    }
    try {
      final WaveShape actual = bandLimitedShape(shape, hz);
      final AudioSource source = await SoLoud.instance.loadWaveform(_wave(actual), false, 1, 0);
      SoLoud.instance.setWaveformFreq(source, hz);
      final SoundHandle handle = SoLoud.instance.play(source, volume: 0);
      // Entrada suave para evitar el chasquido.
      SoLoud.instance.fadeVolume(handle, volume, const Duration(milliseconds: 40));
      final Tone tone = Tone(source: source, handle: handle, shape: shape, actual: actual);
      _lastHz[tone] = hz;
      return tone;
    } catch (e) {
      debugPrint('No se pudo iniciar el tono: $e');
      return null;
    }
  }

  @override
  void setToneFrequency(Tone tone, double hz) {
    final AudioSource? source = tone.source;
    if (source == null) {
      return;
    }
    try {
      final WaveShape actual = bandLimitedShape(tone.shape, hz);
      if (actual != tone.actual) {
        SoLoud.instance.setWaveform(source, _wave(actual));
        tone.actual = actual;
      }
      SoLoud.instance.setWaveformFreq(source, hz);
      _lastHz[tone] = hz;
    } catch (_) {}
  }

  @override
  void setToneShape(Tone tone, WaveShape shape) {
    final AudioSource? source = tone.source;
    tone.shape = shape;
    if (source == null) {
      return;
    }
    try {
      // La frecuencia no cambia: se recalcula la forma que puede sonar.
      final WaveShape actual = bandLimitedShape(shape, _lastHz[tone] ?? 0);
      SoLoud.instance.setWaveform(source, _wave(actual));
      tone.actual = actual;
    } catch (_) {}
  }

  final Expando<double> _lastHz = Expando<double>();

  @override
  void setToneVolume(Tone tone, double volume) {
    final SoundHandle? handle = tone.handle;
    if (handle == null) {
      return;
    }
    try {
      SoLoud.instance.setVolume(handle, volume);
    } catch (_) {}
  }

  @override
  void fadeToneVolume(Tone tone, double volume, Duration time) {
    final SoundHandle? handle = tone.handle;
    if (handle == null) {
      return;
    }
    try {
      SoLoud.instance.fadeVolume(handle, volume, time);
    } catch (_) {}
  }

  @override
  Future<void> stopTone(Tone tone, {Duration fade = const Duration(milliseconds: 60)}) async {
    final AudioSource? source = tone.source;
    final SoundHandle? handle = tone.handle;
    if (source == null || handle == null) {
      return;
    }
    try {
      SoLoud.instance.fadeVolume(handle, 0, fade);
      await Future<void>.delayed(fade + const Duration(milliseconds: 10));
      await SoLoud.instance.stop(handle);
      await SoLoud.instance.disposeSource(source);
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    if (!_ready) {
      return;
    }
    try {
      await SoLoud.instance.disposeAllSources();
      SoLoud.instance.deinit();
    } catch (_) {}
    _ready = false;
  }
}

/// Motor mudo para pruebas y para cuando el audio no está disponible. Lleva
/// la cuenta de los tonos para que las pruebas vean lo que sonaría.
class SilentEngine implements AudioEngine {
  // Usa el reloj de `package:clock`, que las pruebas de widgets pueden
  // adelantar con el tiempo simulado.
  DateTime? _started;
  int _pushedBytes = 0;
  int _sampleRate = 44100;

  /// Tonos que suenan, con su frecuencia, forma real y volumen.
  final Map<Tone, double> frequencies = <Tone, double>{};
  final Map<Tone, double> volumes = <Tone, double>{};

  @override
  bool get ready => true;

  @override
  Future<void> init() async {}

  @override
  Future<PcmStream?> openPcmStream({int sampleRate = 44100, double bufferingSeconds = 0.05}) async {
    _sampleRate = sampleRate;
    _pushedBytes = 0;
    _started = clock.now();
    return PcmStream();
  }

  @override
  void pushPcm(PcmStream stream, Uint8List bytes) {
    _pushedBytes += bytes.length;
  }

  @override
  double consumedSeconds(PcmStream stream) {
    final double pushed = _pushedBytes / 2 / _sampleRate;
    final DateTime? started = _started;
    final double elapsed = started == null ? 0 : clock.now().difference(started).inMicroseconds / 1e6;
    return elapsed < pushed ? elapsed : pushed;
  }

  @override
  Future<void> closePcmStream(PcmStream stream) async {
    _started = null;
  }

  @override
  Future<Tone?> startTone(double hz, {WaveShape shape = WaveShape.sine, double volume = 0.5}) async {
    final Tone t = Tone(shape: shape, actual: bandLimitedShape(shape, hz));
    frequencies[t] = hz;
    volumes[t] = volume;
    return t;
  }

  @override
  void setToneFrequency(Tone tone, double hz) {
    if (frequencies.containsKey(tone)) {
      frequencies[tone] = hz;
      tone.actual = bandLimitedShape(tone.shape, hz);
    }
  }

  @override
  void setToneShape(Tone tone, WaveShape shape) {
    tone.shape = shape;
    tone.actual = bandLimitedShape(shape, frequencies[tone] ?? 0);
  }

  @override
  void setToneVolume(Tone tone, double volume) {
    if (volumes.containsKey(tone)) {
      volumes[tone] = volume;
    }
  }

  @override
  void fadeToneVolume(Tone tone, double volume, Duration time) => setToneVolume(tone, volume);

  @override
  Future<void> stopTone(Tone tone, {Duration fade = const Duration(milliseconds: 60)}) async {
    frequencies.remove(tone);
    volumes.remove(tone);
  }

  @override
  Future<void> dispose() async {}
}
