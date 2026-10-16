import 'dart:async';

import 'package:flutter/material.dart';

import '../../audio/audio_engine.dart';
import '../../core/app_scope.dart';
import '../../core/theme.dart';
import '../../music/notes.dart';

/// Bordón (tono de referencia sostenido), teclado de 8 octavas y acordes.
class DroneScreen extends StatefulWidget {
  const DroneScreen({super.key});

  @override
  State<DroneScreen> createState() => _DroneScreenState();
}

class _DroneScreenState extends State<DroneScreen> with AutomaticKeepAliveClientMixin {
  Services? _services;
  bool _started = false;

  // Bordón
  int _droneMidi = 57; // La3
  bool _fifth = false;
  WaveShape _shape = WaveShape.sine;
  Tone? _droneTone;
  Tone? _fifthTone;

  // Teclado
  int _octave = 4;
  bool _sustain = false;
  final Map<int, Tone> _keys = <int, Tone>{};
  final List<Tone> _chordTones = <Tone>[];
  int _chordRoot = 60;
  String _chordType = 'M';

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _services = AppScope.of(context);
      _services!.settings.addListener(_onSettings);
    }
  }

  void _onSettings() {
    final Services? s = _services;
    if (s == null) {
      return;
    }
    if (_droneTone != null) {
      s.engine.setToneVolume(_droneTone!, s.settings.droneVolume);
      s.engine.setToneFrequency(_droneTone!, _freq(_droneMidi));
      if (_fifthTone != null) {
        s.engine.setToneVolume(_fifthTone!, s.settings.droneVolume * 0.7);
        s.engine.setToneFrequency(_fifthTone!, _freq(_droneMidi + 7));
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  double _freq(int midi) {
    final PitchSettings p = _services!.settings.pitch;
    return Notes.frequency(midi, a4: p.a4, temperament: p.temperament, root: p.temperamentRoot, custom: p.custom);
  }

  @override
  void dispose() {
    _services?.settings.removeListener(_onSettings);
    unawaited(_stopAll());
    super.dispose();
  }

  Future<void> _stopAll() async {
    final AudioEngine e = _services!.engine;
    final List<Tone> all = <Tone>[if (_droneTone != null) _droneTone!, if (_fifthTone != null) _fifthTone!, ..._keys.values, ..._chordTones];
    _droneTone = null;
    _fifthTone = null;
    _keys.clear();
    _chordTones.clear();
    for (final Tone tn in all) {
      await e.stopTone(tn);
    }
  }

  Future<void> _toggleDrone() async {
    final Services s = _services!;
    if (_droneTone != null) {
      final Tone d = _droneTone!;
      final Tone? f = _fifthTone;
      setState(() {
        _droneTone = null;
        _fifthTone = null;
      });
      await s.engine.stopTone(d, fade: const Duration(milliseconds: 200));
      if (f != null) {
        await s.engine.stopTone(f, fade: const Duration(milliseconds: 200));
      }
      return;
    }
    final Tone? d = await s.engine.startTone(_freq(_droneMidi), shape: _shape, volume: s.settings.droneVolume);
    Tone? f;
    if (_fifth) {
      f = await s.engine.startTone(_freq(_droneMidi + 7), shape: _shape, volume: s.settings.droneVolume * 0.7);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _droneTone = d;
      _fifthTone = f;
    });
    s.state.touchPractice('tono', s.settings.instrumentId);
  }

  Future<void> _setDroneMidi(int midi) async {
    _droneMidi = midi.clamp(24, 96);
    final Services s = _services!;
    if (_droneTone != null) {
      s.engine.setToneFrequency(_droneTone!, _freq(_droneMidi));
      if (_fifthTone != null) {
        s.engine.setToneFrequency(_fifthTone!, _freq(_droneMidi + 7));
      }
    }
    setState(() {});
  }

  Future<void> _toggleFifth(bool v) async {
    _fifth = v;
    final Services s = _services!;
    if (_droneTone != null) {
      if (v && _fifthTone == null) {
        _fifthTone = await s.engine.startTone(_freq(_droneMidi + 7), shape: _shape, volume: s.settings.droneVolume * 0.7);
      } else if (!v && _fifthTone != null) {
        final Tone f = _fifthTone!;
        _fifthTone = null;
        await s.engine.stopTone(f);
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _setShape(WaveShape sh) async {
    _shape = sh;
    if (_droneTone != null) {
      // Reinicia el bordón con la nueva forma de onda.
      await _toggleDrone();
      await _toggleDrone();
    } else {
      setState(() {});
    }
  }

  Future<void> _keyDown(int midi) async {
    final Services s = _services!;
    if (_keys.containsKey(midi)) {
      return;
    }
    final Tone? tn = await s.engine.startTone(_freq(midi), shape: _shape, volume: 0.45);
    if (tn == null) {
      return;
    }
    if (!mounted) {
      await s.engine.stopTone(tn);
      return;
    }
    setState(() => _keys[midi] = tn);
    s.state.touchPractice('tono', s.settings.instrumentId);
  }

  Future<void> _keyUp(int midi) async {
    if (_sustain) {
      return;
    }
    final Tone? tn = _keys.remove(midi);
    if (tn != null) {
      setState(() {});
      await _services!.engine.stopTone(tn, fade: const Duration(milliseconds: 250));
    }
  }

  Future<void> _releaseAllKeys() async {
    final List<Tone> all = <Tone>[..._keys.values, ..._chordTones];
    _keys.clear();
    _chordTones.clear();
    setState(() {});
    for (final Tone tn in all) {
      await _services!.engine.stopTone(tn, fade: const Duration(milliseconds: 250));
    }
  }

  static const Map<String, List<int>> chords = <String, List<int>>{
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

  Future<void> _playChord() async {
    final Services s = _services!;
    final List<Tone> old = List<Tone>.from(_chordTones);
    _chordTones.clear();
    for (final Tone tn in old) {
      unawaited(s.engine.stopTone(tn, fade: const Duration(milliseconds: 120)));
    }
    for (final int iv in chords[_chordType] ?? <int>[0, 4, 7]) {
      final Tone? tn = await s.engine.startTone(_freq(_chordRoot + iv), shape: _shape, volume: 0.32);
      if (tn != null) {
        _chordTones.add(tn);
      }
    }
    if (mounted) {
      setState(() {});
    }
    s.state.touchPractice('tono', s.settings.instrumentId);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final Services s = AppScope.of(context);
    final PitchSettings ps = s.settings.pitch;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool spanish = s.settings.spanish;
    final bool droneOn = _droneTone != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: <Widget>[
        // ---------------------------------------------------------------- bordón
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(child: Text(t(context, 'Bordón (tono de referencia)', 'Drone (reference tone)'), style: Theme.of(context).textTheme.titleMedium)),
                    FilledButton.icon(
                      onPressed: _toggleDrone,
                      icon: Icon(droneOn ? Icons.stop_rounded : Icons.play_arrow_rounded),
                      label: Text(droneOn ? t(context, 'Parar', 'Stop') : t(context, 'Sonar', 'Play')),
                      style: FilledButton.styleFrom(backgroundColor: droneOn ? cs.error : null),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    IconButton(onPressed: () => _setDroneMidi(_droneMidi - 1), icon: const Icon(Icons.remove_circle_outline)),
                    Expanded(
                      child: Column(
                        children: <Widget>[
                          Text('${ps.displayName(_droneMidi)}${ps.displayOctave(_droneMidi)}', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: droneOn ? ClaveColors.ambar : cs.onSurface)),
                          Text('${formatHz(_freq(_droneMidi), comma: spanish)} Hz${_fifth ? ' + ${ps.displayName(_droneMidi + 7)}' : ''}', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.65))),
                        ],
                      ),
                    ),
                    IconButton(onPressed: () => _setDroneMidi(_droneMidi + 1), icon: const Icon(Icons.add_circle_outline)),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (int pc = 0; pc < 12; pc++)
                      ChoiceChip(
                        label: Text(Notes.name(pc, ps.notation, flats: ps.flats)),
                        selected: Notes.pitchClassOf(_droneMidi) == pc,
                        onSelected: (_) => _setDroneMidi((_droneMidi ~/ 12) * 12 + pc),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(t(context, 'Octava', 'Octave')),
                    for (final int o in <int>[2, 3, 4, 5])
                      ChoiceChip(label: Text('$o'), selected: Notes.octaveOf(_droneMidi) == o, onSelected: (_) => _setDroneMidi((o + 1) * 12 + Notes.pitchClassOf(_droneMidi))),
                    const SizedBox(width: 12),
                    Text(t(context, 'Quinta', 'Fifth')),
                    Switch(value: _fifth, onChanged: _toggleFifth),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(t(context, 'Onda', 'Wave')),
                    for (final List<dynamic> o in <List<dynamic>>[
                      <dynamic>[WaveShape.sine, t(context, 'Seno', 'Sine')],
                      <dynamic>[WaveShape.triangle, t(context, 'Triángulo', 'Triangle')],
                      <dynamic>[WaveShape.saw, t(context, 'Sierra', 'Saw')],
                      <dynamic>[WaveShape.square, t(context, 'Cuadrada', 'Square')],
                    ])
                      ChoiceChip(label: Text(o[1] as String), selected: _shape == o[0], onSelected: (_) => _setShape(o[0] as WaveShape)),
                  ],
                ),
                Row(
                  children: <Widget>[
                    const Icon(Icons.volume_down_rounded),
                    Expanded(
                      child: Slider(
                        value: s.settings.droneVolume,
                        onChanged: (double v) {
                          s.settings.droneVolume = v;
                          s.settings.save();
                        },
                      ),
                    ),
                    const Icon(Icons.volume_up_rounded),
                  ],
                ),
              ],
            ),
          ),
        ),
        // ---------------------------------------------------------------- acordes
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(t(context, 'Acordes sostenidos', 'Sustained chords'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (int pc = 0; pc < 12; pc++)
                      ChoiceChip(
                        label: Text(Notes.name(pc, ps.notation, flats: ps.flats)),
                        selected: Notes.pitchClassOf(_chordRoot) == pc,
                        onSelected: (_) {
                          _chordRoot = 48 + pc;
                          _playChord();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final String ty in chords.keys)
                      ChoiceChip(
                        label: Text(ty),
                        selected: _chordType == ty,
                        onSelected: (_) {
                          _chordType = ty;
                          _playChord();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: <Widget>[
                    FilledButton.tonalIcon(onPressed: _playChord, icon: const Icon(Icons.play_arrow_rounded), label: Text(t(context, 'Tocar acorde', 'Play chord'))),
                    OutlinedButton.icon(onPressed: _chordTones.isEmpty && _keys.isEmpty ? null : _releaseAllKeys, icon: const Icon(Icons.stop_rounded), label: Text(t(context, 'Silenciar', 'Silence'))),
                  ],
                ),
              ],
            ),
          ),
        ),
        // ---------------------------------------------------------------- teclado
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(t(context, 'Teclado', 'Keyboard'), style: Theme.of(context).textTheme.titleMedium),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(onPressed: _octave > 0 ? () => setState(() => _octave -= 1) : null, icon: const Icon(Icons.chevron_left_rounded)),
                        Text('${t(context, 'Octava', 'Octave')} $_octave', style: const TextStyle(fontWeight: FontWeight.w600)),
                        IconButton(onPressed: _octave < 7 ? () => setState(() => _octave += 1) : null, icon: const Icon(Icons.chevron_right_rounded)),
                      ],
                    ),
                    FilterChip(
                      label: Text(t(context, 'Sostener', 'Sustain')),
                      selected: _sustain,
                      onSelected: (bool v) {
                        setState(() => _sustain = v);
                        if (!v) {
                          _releaseAllKeys();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 170,
                  child: _Keyboard(
                    baseMidi: (_octave + 1) * 12,
                    pressed: _keys.keys.toSet(),
                    labelOf: (int m) => ps.displayName(m),
                    onDown: _keyDown,
                    onUp: _keyUp,
                  ),
                ),
                const SizedBox(height: 4),
                Text(t(context, 'Las notas siguen la referencia y el temperamento del afinador.', 'Notes follow the tuner reference and temperament.'), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Una octava y media de teclas; se puede tocar más de una a la vez.
class _Keyboard extends StatelessWidget {
  const _Keyboard({required this.baseMidi, required this.pressed, required this.labelOf, required this.onDown, required this.onUp});

  final int baseMidi;
  final Set<int> pressed;
  final String Function(int midi) labelOf;
  final ValueChanged<int> onDown;
  final ValueChanged<int> onUp;

  static const List<int> whites = <int>[0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23, 24];
  static const Map<int, double> blacks = <int, double>{1: 0.5, 3: 1.5, 6: 3.5, 8: 4.5, 10: 5.5, 13: 7.5, 15: 8.5, 18: 10.5, 20: 11.5, 22: 12.5};

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final double w = c.maxWidth / whites.length;
      final double h = c.maxHeight;
      return Stack(
        children: <Widget>[
          for (int i = 0; i < whites.length; i++)
            Positioned(
              left: i * w,
              top: 0,
              width: w,
              height: h,
              child: _Key(
                midi: baseMidi + whites[i],
                black: false,
                pressed: pressed.contains(baseMidi + whites[i]),
                label: whites[i] % 12 == 0 ? '${labelOf(baseMidi + whites[i])}${(baseMidi + whites[i]) ~/ 12 - 1}' : null,
                onDown: onDown,
                onUp: onUp,
                color: cs,
              ),
            ),
          for (final MapEntry<int, double> b in blacks.entries)
            Positioned(
              left: (b.value + 0.5) * w - w * 0.32,
              top: 0,
              width: w * 0.64,
              height: h * 0.6,
              child: _Key(midi: baseMidi + b.key, black: true, pressed: pressed.contains(baseMidi + b.key), onDown: onDown, onUp: onUp, color: cs),
            ),
        ],
      );
    });
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.midi, required this.black, required this.pressed, required this.onDown, required this.onUp, required this.color, this.label});

  final int midi;
  final bool black;
  final bool pressed;
  final ValueChanged<int> onDown;
  final ValueChanged<int> onUp;
  final ColorScheme color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onDown(midi),
      onPointerUp: (_) => onUp(midi),
      onPointerCancel: (_) => onUp(midi),
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: pressed ? ClaveColors.ambar : (black ? const Color(0xFF1B1B1F) : Colors.white),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
          border: Border.all(color: Colors.black26),
        ),
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.only(bottom: 6),
        child: label == null ? null : Text(label!, style: const TextStyle(fontSize: 10, color: Colors.black54)),
      ),
    );
  }
}
