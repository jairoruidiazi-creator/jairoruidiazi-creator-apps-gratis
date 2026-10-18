import 'dart:async';

import 'package:flutter/foundation.dart';

import '../music/notes.dart';
import 'audio_engine.dart';

/// Tipos de acorde sostenido con sus intervalos en semitonos.
const Map<String, List<int>> kChordTypes = <String, List<int>>{
  'M': <int>[0, 4, 7],
  'm': <int>[0, 3, 7],
  '7': <int>[0, 4, 7, 10],
  'M7': <int>[0, 4, 7, 11],
  'm7': <int>[0, 3, 7, 10],
  'dim': <int>[0, 3, 6],
  'aug': <int>[0, 4, 8],
  'sus4': <int>[0, 5, 7],
  'sus2': <int>[0, 2, 7],
  '5': <int>[0, 7, 12],
};

enum _VoiceKind { drone, fifth, key, chord }

class _Voice {
  _Voice(this.kind, this.midi, this.tone);

  final _VoiceKind kind;

  /// Altura sonante de la voz (la quinta usa la del bordón).
  final int midi;
  final Tone tone;
}

/// Bordón, teclado y acordes: todas las voces sostenidas de la app.
///
/// - La ganancia se reparte entre las voces que suenan, así que un acorde o
///   varias teclas nunca saturan la salida.
/// - La quinta del bordón es pura (3:2 sobre la nota del bordón), sin
///   temperamento.
/// - Las demás notas siguen la referencia La4 y el temperamento: al cambiar
///   los ajustes, todo lo que suena se reafina ([setPitch]).
/// - La forma de onda la elige el motor sin aliasing ([bandLimitedShape]).
class DroneController extends ChangeNotifier {
  DroneController(this.engine);

  final AudioEngine engine;

  PitchSettings _pitch = const PitchSettings();
  double _volume = 0.5;
  WaveShape _shape = WaveShape.sine;

  /// Nota sonante del bordón (La3 por defecto).
  int droneMidi = 57;
  bool _fifth = false;
  bool sustain = false;

  _Voice? _drone;
  _Voice? _fifthVoice;
  final Map<int, _Voice> _keys = <int, _Voice>{};
  final List<_Voice> _chord = <_Voice>[];
  bool _starting = false;

  /// Peso de cada voz en el reparto de la ganancia.
  static const double _fifthWeight = 0.7;

  /// Ganancia total con el volumen al máximo (las formas de onda del motor
  /// llegan a ±0,5 y la cuadrada con su rizo a ±0,6).
  static const double _headroom = 1.5;

  bool get droneOn => _drone != null;

  bool get fifth => _fifth;

  WaveShape get shape => _shape;

  double get volume => _volume;

  /// true mientras suena algo (cuenta como práctica).
  bool get sounding => _drone != null || _keys.isNotEmpty || _chord.isNotEmpty;

  /// Teclas que suenan (alturas sonantes).
  Set<int> get pressedKeys => _keys.keys.toSet();

  bool get chordSounding => _chord.isNotEmpty;

  /// Frecuencias que suenan ahora (el afinador no las cuenta como práctica).
  List<double> get soundingFrequencies => <double>[
        if (_drone != null) frequencyOf(droneMidi),
        if (_fifthVoice != null) fifthFrequency,
        for (final _Voice v in _keys.values) frequencyOf(v.midi),
        for (final _Voice v in _chord) frequencyOf(v.midi),
      ];

  double frequencyOf(int midi) => _pitch.frequencyOf(midi);

  /// Quinta pura sobre el bordón.
  double get fifthFrequency => frequencyOf(droneMidi) * 1.5;

  void setPitch(PitchSettings p) {
    _pitch = p;
    _retune();
  }

  void setVolume(double v) {
    _volume = v.clamp(0.0, 1.0).toDouble();
    _rebalance();
  }

  Iterable<_Voice> get _all sync* {
    if (_drone != null) {
      yield _drone!;
    }
    if (_fifthVoice != null) {
      yield _fifthVoice!;
    }
    yield* _keys.values;
    yield* _chord;
  }

  double _weight(_Voice v) => v.kind == _VoiceKind.fifth ? _fifthWeight : 1.0;

  /// Volumen de cada voz: la ganancia total se reparte entre las que suenan.
  double _levelFor(_Voice v, double totalWeight) {
    final double share = _weight(v) / (totalWeight < 1 ? 1 : totalWeight);
    return _headroom * _volume * shapeGain(_shape) * share;
  }

  double get _totalWeight {
    double w = 0;
    for (final _Voice v in _all) {
      w += _weight(v);
    }
    return w;
  }

  void _rebalance() {
    final double total = _totalWeight;
    for (final _Voice v in _all) {
      engine.fadeToneVolume(v.tone, _levelFor(v, total), const Duration(milliseconds: 40));
    }
  }

  void _retune() {
    if (_drone != null) {
      engine.setToneFrequency(_drone!.tone, frequencyOf(droneMidi));
    }
    if (_fifthVoice != null) {
      engine.setToneFrequency(_fifthVoice!.tone, fifthFrequency);
    }
    for (final _Voice v in _keys.values) {
      engine.setToneFrequency(v.tone, frequencyOf(v.midi));
    }
    for (final _Voice v in _chord) {
      engine.setToneFrequency(v.tone, frequencyOf(v.midi));
    }
  }

  Future<_Voice?> _startVoice(_VoiceKind kind, int midi, double hz) async {
    final Tone? tone = await engine.startTone(hz, shape: _shape, volume: 0);
    if (tone == null) {
      return null;
    }
    return _Voice(kind, midi, tone);
  }

  Future<void> _stopVoices(List<_Voice> voices, {Duration fade = const Duration(milliseconds: 120)}) async {
    for (final _Voice v in voices) {
      unawaited(engine.stopTone(v.tone, fade: fade));
    }
  }

  // ------------------------------------------------------------ bordón

  Future<void> toggleDrone() => droneOn ? stopDrone() : startDrone();

  Future<void> startDrone() async {
    if (_drone != null || _starting) {
      return;
    }
    _starting = true;
    try {
      _drone = await _startVoice(_VoiceKind.drone, droneMidi, frequencyOf(droneMidi));
      if (_drone != null && _fifth) {
        _fifthVoice = await _startVoice(_VoiceKind.fifth, droneMidi, fifthFrequency);
      }
    } finally {
      _starting = false;
    }
    _rebalance();
    notifyListeners();
  }

  Future<void> stopDrone() async {
    final List<_Voice> old = <_Voice>[if (_drone != null) _drone!, if (_fifthVoice != null) _fifthVoice!];
    _drone = null;
    _fifthVoice = null;
    _rebalance();
    notifyListeners();
    await _stopVoices(old, fade: const Duration(milliseconds: 200));
  }

  void setDroneMidi(int midi) {
    droneMidi = midi.clamp(24, 96);
    _retune();
    notifyListeners();
  }

  Future<void> setFifth(bool v) async {
    _fifth = v;
    if (_drone != null) {
      if (v && _fifthVoice == null) {
        _fifthVoice = await _startVoice(_VoiceKind.fifth, droneMidi, fifthFrequency);
      } else if (!v && _fifthVoice != null) {
        final _Voice f = _fifthVoice!;
        _fifthVoice = null;
        unawaited(engine.stopTone(f.tone));
      }
      _rebalance();
    }
    notifyListeners();
  }

  /// Cambia la forma de onda de todo lo que suena.
  void setShape(WaveShape s) {
    _shape = s;
    for (final _Voice v in _all) {
      engine.setToneShape(v.tone, s);
    }
    _rebalance();
    notifyListeners();
  }

  // ------------------------------------------------------------ teclado

  Future<void> keyDown(int midi) async {
    if (_keys.containsKey(midi)) {
      return;
    }
    final _Voice? v = await _startVoice(_VoiceKind.key, midi, frequencyOf(midi));
    if (v == null) {
      return;
    }
    if (_keys.containsKey(midi)) {
      unawaited(engine.stopTone(v.tone));
      return;
    }
    _keys[midi] = v;
    _rebalance();
    notifyListeners();
  }

  Future<void> keyUp(int midi) async {
    if (sustain) {
      return;
    }
    final _Voice? v = _keys.remove(midi);
    if (v == null) {
      return;
    }
    _rebalance();
    notifyListeners();
    await _stopVoices(<_Voice>[v], fade: const Duration(milliseconds: 250));
  }

  /// Toca una tecla un momento (lectores de pantalla y teclado físico).
  Future<void> tapKey(int midi, {Duration hold = const Duration(milliseconds: 700)}) async {
    await keyDown(midi);
    if (sustain) {
      return;
    }
    await Future<void>.delayed(hold);
    await keyUp(midi);
  }

  void setSustain(bool v) {
    sustain = v;
    notifyListeners();
    if (!v) {
      unawaited(releaseKeys());
    }
  }

  Future<void> releaseKeys() async {
    final List<_Voice> old = _keys.values.toList();
    _keys.clear();
    _rebalance();
    notifyListeners();
    await _stopVoices(old, fade: const Duration(milliseconds: 250));
  }

  // ------------------------------------------------------------ acordes

  Future<void> playChord(int rootMidi, String type) async {
    final List<_Voice> old = List<_Voice>.from(_chord);
    _chord.clear();
    unawaited(_stopVoices(old));
    for (final int iv in kChordTypes[type] ?? kChordTypes['M']!) {
      final int midi = rootMidi + iv;
      final _Voice? v = await _startVoice(_VoiceKind.chord, midi, frequencyOf(midi));
      if (v != null) {
        _chord.add(v);
      }
    }
    _rebalance();
    notifyListeners();
  }

  /// Calla las teclas y el acorde (el bordón sigue).
  Future<void> silenceKeysAndChord() async {
    final List<_Voice> old = <_Voice>[..._keys.values, ..._chord];
    _keys.clear();
    _chord.clear();
    _rebalance();
    notifyListeners();
    await _stopVoices(old, fade: const Duration(milliseconds: 250));
  }

  /// Calla todo (al salir de la app en Android o al cerrarla).
  Future<void> stopAll() async {
    final List<_Voice> old = _all.toList();
    _drone = null;
    _fifthVoice = null;
    _keys.clear();
    _chord.clear();
    notifyListeners();
    await _stopVoices(old, fade: const Duration(milliseconds: 100));
  }

  @override
  void dispose() {
    unawaited(stopAll());
    super.dispose();
  }
}
