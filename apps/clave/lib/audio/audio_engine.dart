import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Forma de onda de los tonos sostenidos.
enum WaveShape { sine, triangle, saw, square }

/// Identificador opaco de un flujo PCM abierto.
class PcmStream {
  PcmStream({this.source, this.handle});

  final AudioSource? source;
  final SoundHandle? handle;
}

/// Un tono sostenido en reproducción.
class Tone {
  Tone({this.source, this.handle});

  final AudioSource? source;
  final SoundHandle? handle;
}

/// Capa fina sobre el motor de audio para que el resto de la app (y las
/// pruebas) no dependan de SoLoud directamente.
abstract class AudioEngine {
  bool get ready;

  Future<void> init();

  /// Abre un flujo PCM mono s16le al que se le irán empujando bloques.
  Future<PcmStream?> openPcmStream({int sampleRate = 44100, double bufferingSeconds = 0.05});

  void pushPcm(PcmStream stream, Uint8List bytes);

  /// Segundos de audio ya consumidos (reproducidos) del flujo.
  double consumedSeconds(PcmStream stream);

  Future<void> closePcmStream(PcmStream stream);

  Future<Tone?> startTone(double hz, {WaveShape shape = WaveShape.sine, double volume = 0.5});

  void setToneFrequency(Tone tone, double hz);

  void setToneVolume(Tone tone, double volume);

  Future<void> stopTone(Tone tone, {Duration fade = const Duration(milliseconds: 60)});

  Future<void> dispose();
}

/// Motor real sobre flutter_soloud.
class SoLoudEngine implements AudioEngine {
  bool _ready = false;

  @override
  bool get ready => _ready;

  @override
  Future<void> init() async {
    if (_ready) {
      return;
    }
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
        return WaveForm.saw;
      case WaveShape.square:
        return WaveForm.square;
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
      final AudioSource source = await SoLoud.instance.loadWaveform(_wave(shape), false, 1, 0);
      SoLoud.instance.setWaveformFreq(source, hz);
      final SoundHandle handle = SoLoud.instance.play(source, volume: 0);
      // Entrada suave para evitar el chasquido.
      SoLoud.instance.fadeVolume(handle, volume, const Duration(milliseconds: 40));
      return Tone(source: source, handle: handle);
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
      SoLoud.instance.setWaveformFreq(source, hz);
    } catch (_) {}
  }

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

/// Motor mudo para pruebas y para cuando el audio no está disponible.
class SilentEngine implements AudioEngine {
  final Stopwatch _clock = Stopwatch();
  int _pushedBytes = 0;
  int _sampleRate = 44100;

  @override
  bool get ready => true;

  @override
  Future<void> init() async {}

  @override
  Future<PcmStream?> openPcmStream({int sampleRate = 44100, double bufferingSeconds = 0.05}) async {
    _sampleRate = sampleRate;
    _pushedBytes = 0;
    _clock
      ..reset()
      ..start();
    return PcmStream();
  }

  @override
  void pushPcm(PcmStream stream, Uint8List bytes) {
    _pushedBytes += bytes.length;
  }

  @override
  double consumedSeconds(PcmStream stream) {
    final double pushed = _pushedBytes / 2 / _sampleRate;
    final double elapsed = _clock.elapsedMicroseconds / 1e6;
    return elapsed < pushed ? elapsed : pushed;
  }

  @override
  Future<void> closePcmStream(PcmStream stream) async {
    _clock.stop();
  }

  @override
  Future<Tone?> startTone(double hz, {WaveShape shape = WaveShape.sine, double volume = 0.5}) async => Tone();

  @override
  void setToneFrequency(Tone tone, double hz) {}

  @override
  void setToneVolume(Tone tone, double volume) {}

  @override
  Future<void> stopTone(Tone tone, {Duration fade = const Duration(milliseconds: 60)}) async {}

  @override
  Future<void> dispose() async {}
}
