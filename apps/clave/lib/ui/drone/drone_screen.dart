import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../audio/audio_engine.dart';
import '../../audio/drone.dart';
import '../../core/app_scope.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../music/notes.dart';
import '../tuner/tuner_screen.dart' show spokenNoteName;
import '../widgets/adaptive.dart';

/// Bordón (tono de referencia sostenido), teclado de 8 octavas y acordes.
///
/// Todo se muestra en altura escrita (con la transposición del instrumento,
/// igual que el afinador) y suena en altura real. El sonido vive en
/// [DroneController]: cambiar de pestaña no lo corta.
class DroneScreen extends StatefulWidget {
  const DroneScreen({super.key, this.active = true});

  /// Si la pestaña está a la vista.
  final bool active;

  @override
  State<DroneScreen> createState() => _DroneScreenState();
}

class _DroneScreenState extends State<DroneScreen> {
  /// Raíz del acorde en altura escrita (octava de Do4: se oye bien también en
  /// el altavoz del teléfono).
  int _chordRoot = 60;
  String _chordType = 'M';

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[s.drone, s.settings]),
      builder: (BuildContext context, Widget? _) => _build(context, s),
    );
  }

  Widget _build(BuildContext context, Services s) {
    final DroneController d = s.drone;
    final AppSettings st = s.settings;
    final PitchSettings ps = st.pitch;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final ClavePalette pal = ClavePalette.of(context);
    final bool spanish = isSpanish(context);
    final bool droneOn = d.droneOn;
    final int written = ps.writtenMidi(d.droneMidi);
    final String hz = formatHz(d.frequencyOf(d.droneMidi), comma: spanish);

    // Las tarjetas ya dejan 12 dp a cada lado: el teclado aprovecha el ancho
    // (en un teléfono de 360 dp caben 7 teclas blancas de 48 dp, una octava).
    return ReadableWidth(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
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
                        onPressed: d.toggleDrone,
                        icon: Icon(droneOn ? Icons.stop_rounded : Icons.play_arrow_rounded),
                        label: Text(droneOn ? t(context, 'Parar', 'Stop') : t(context, 'Sonar', 'Play')),
                        style: FilledButton.styleFrom(backgroundColor: droneOn ? cs.error : null, foregroundColor: droneOn ? cs.onError : null),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      IconButton(tooltip: t(context, 'Medio tono abajo', 'Half step down'), onPressed: () => d.setDroneMidi(d.droneMidi - 1), icon: const Icon(Icons.remove_circle_outline)),
                      Expanded(
                        child: Semantics(
                          container: true,
                          label: '${t(context, 'Bordón', 'Drone')}: ${spokenNoteName(ps.displayName(d.droneMidi), spanish: spanish)} ${ps.displayOctave(d.droneMidi)}, $hz Hz',
                          excludeSemantics: true,
                          child: Column(
                            children: <Widget>[
                              Text(ps.displayFull(d.droneMidi), style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: droneOn ? pal.accent : cs.onSurface)),
                              Text(
                                '$hz Hz${d.fifth ? ' + ${ps.displayName(d.droneMidi + 7)} (${t(context, 'quinta pura', 'pure fifth')})' : ''}',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(tooltip: t(context, 'Medio tono arriba', 'Half step up'), onPressed: () => d.setDroneMidi(d.droneMidi + 1), icon: const Icon(Icons.add_circle_outline)),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (int pc = 0; pc < 12; pc++)
                        ChoiceChip(
                          label: Text(ps.nameOfWritten(pc)),
                          selected: Notes.pitchClassOf(written) == pc,
                          onSelected: (_) => d.setDroneMidi(ps.soundingMidi((Notes.octaveOf(written) + 1) * 12 + pc)),
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
                        ChoiceChip(
                          label: Text('$o'),
                          tooltip: '${t(context, 'Octava', 'Octave')} $o',
                          selected: Notes.octaveOf(written) == o,
                          onSelected: (_) => d.setDroneMidi(ps.soundingMidi((o + 1) * 12 + Notes.pitchClassOf(written))),
                        ),
                      const SizedBox(width: 12),
                      MergeSemantics(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(t(context, 'Quinta pura', 'Pure fifth')),
                            Switch(value: d.fifth, onChanged: d.setFifth),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(t(context, 'Onda', 'Wave')),
                      for (final MapEntry<WaveShape, String> o in <WaveShape, String>{
                        WaveShape.sine: t(context, 'Seno', 'Sine'),
                        WaveShape.triangle: t(context, 'Triángulo', 'Triangle'),
                        WaveShape.saw: t(context, 'Sierra', 'Saw'),
                        WaveShape.square: t(context, 'Cuadrada', 'Square'),
                      }.entries)
                        ChoiceChip(label: Text(o.value), selected: d.shape == o.key, onSelected: (_) => d.setShape(o.key)),
                    ],
                  ),
                  MergeSemantics(
                    child: Row(
                      children: <Widget>[
                        Semantics(label: t(context, 'Volumen', 'Volume'), child: const ExcludeSemantics(child: Icon(Icons.volume_down_rounded))),
                        Expanded(
                          child: Slider(
                            value: st.droneVolume.clamp(0.0, 1.0),
                            semanticFormatterCallback: (double v) => formatPercent(v, spanish: spanish),
                            onChanged: (double v) {
                              st.droneVolume = v;
                              st.save();
                            },
                          ),
                        ),
                        const ExcludeSemantics(child: Icon(Icons.volume_up_rounded)),
                      ],
                    ),
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
                          label: Text(ps.nameOfWritten(pc)),
                          selected: Notes.pitchClassOf(_chordRoot) == pc,
                          onSelected: (_) {
                            setState(() => _chordRoot = 60 + pc);
                            unawaited(d.playChord(ps.soundingMidi(_chordRoot), _chordType));
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final String ty in kChordTypes.keys)
                        ChoiceChip(
                          label: Text(ty),
                          tooltip: _chordName(context, ty),
                          selected: _chordType == ty,
                          onSelected: (_) {
                            setState(() => _chordType = ty);
                            unawaited(d.playChord(ps.soundingMidi(_chordRoot), _chordType));
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: <Widget>[
                      FilledButton.tonalIcon(onPressed: () => d.playChord(ps.soundingMidi(_chordRoot), _chordType), icon: const Icon(Icons.play_arrow_rounded), label: Text(t(context, 'Tocar acorde', 'Play chord'))),
                      OutlinedButton.icon(onPressed: d.chordSounding || d.pressedKeys.isNotEmpty ? d.silenceKeysAndChord : null, icon: const Icon(Icons.stop_rounded), label: Text(t(context, 'Silenciar', 'Silence'))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // ---------------------------------------------------------------- teclado
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                  child: Row(
                    children: <Widget>[
                      Expanded(child: Text(t(context, 'Teclado', 'Keyboard'), style: Theme.of(context).textTheme.titleMedium)),
                      FilterChip(
                        label: Text(t(context, 'Sostener', 'Sustain')),
                        selected: d.sustain,
                        onSelected: d.setSustain,
                      ),
                    ],
                  ),
                ),
                DroneKeyboard(controller: d, settings: ps, spanish: spanish),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                  child: Text(t(context, 'Las notas siguen la referencia y el temperamento del afinador.', 'Notes follow the tuner reference and temperament.'), style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _chordName(BuildContext context, String ty) {
    switch (ty) {
      case 'M':
        return t(context, 'Mayor', 'Major');
      case 'm':
        return t(context, 'Menor', 'Minor');
      case '7':
        return t(context, 'Séptima de dominante', 'Dominant seventh');
      case 'M7':
        return t(context, 'Séptima mayor', 'Major seventh');
      case 'm7':
        return t(context, 'Menor con séptima', 'Minor seventh');
      case 'dim':
        return t(context, 'Disminuido', 'Diminished');
      case 'aug':
        return t(context, 'Aumentado', 'Augmented');
      case 'sus4':
        return t(context, 'Cuarta suspendida', 'Suspended fourth');
      case 'sus2':
        return t(context, 'Segunda suspendida', 'Suspended second');
      default:
        return t(context, 'Quinta (power chord)', 'Fifth (power chord)');
    }
  }
}

/// Teclado de Do0 a Do8 (altura escrita) que muestra una ventana de teclas
/// blancas de al menos [minWhite] dp, todas enteras.
///
/// Los botones mueven la ventana una octava (si cabe una entera) o la ventana
/// menos una tecla: así la tecla negra que queda partida en un borde aparece
/// entera en la ventana siguiente. Cada tecla entera tiene su nombre para el
/// lector de pantalla y un área de al menos 48 × 48 dp, también las negras;
/// con el lector, tocar una tecla la hace sonar un momento.
class DroneKeyboard extends StatefulWidget {
  const DroneKeyboard({super.key, required this.controller, required this.settings, required this.spanish});

  final DroneController controller;
  final PitchSettings settings;
  final bool spanish;

  static const int lowest = 12; // Do0 escrito
  static const int highest = 108; // Do8 escrito
  static const double minWhite = 48;
  static const double height = 168;

  static const List<int> _whitePcs = <int>[0, 2, 4, 5, 7, 9, 11];

  static bool isWhite(int midi) => _whitePcs.contains(Notes.pitchClassOf(midi));

  /// Teclas blancas del teclado (alturas escritas), de grave a agudo.
  static final List<int> whites = <int>[
    for (int m = lowest; m <= highest; m++)
      if (isWhite(m)) m,
  ];

  /// Cuántas teclas blancas enteras caben en [width] dp.
  static int visibleFor(double width) => math.max(1, (width / minWhite).floor());

  @override
  State<DroneKeyboard> createState() => _DroneKeyboardState();
}

class _DroneKeyboardState extends State<DroneKeyboard> {
  /// Índice en [DroneKeyboard.whites] de la primera tecla a la vista (Do4).
  int _start = DroneKeyboard.whites.indexOf(60);

  int _maxStart(int n) => math.max(0, DroneKeyboard.whites.length - n);

  int _next(int start, int n) {
    final int target = n >= 7 ? (start ~/ 7 + 1) * 7 : start + math.max(1, n - 1);
    return math.min(target, _maxStart(n));
  }

  int _previous(int start, int n) {
    final int target = n >= 7 ? ((start + 6) ~/ 7 - 1) * 7 : start - math.max(1, n - 1);
    return math.max(target, 0);
  }

  String _name(int written) => '${widget.settings.nameOfWritten(written)}${Notes.octaveOf(written)}';

  String _spoken(int written) => '${spokenNoteName(widget.settings.nameOfWritten(written), spanish: widget.spanish)} ${Notes.octaveOf(written)}';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double width = c.maxWidth.isFinite ? c.maxWidth : 360;
        final int n = math.min(DroneKeyboard.visibleFor(width), DroneKeyboard.whites.length);
        final int start = _start.clamp(0, _maxStart(n));
        final List<int> shown = DroneKeyboard.whites.sublist(start, start + n);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  tooltip: t(context, 'Notas más graves', 'Lower notes'),
                  onPressed: start > 0 ? () => setState(() => _start = _previous(start, n)) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      '${_name(shown.first)} – ${_name(shown.last)}',
                      semanticsLabel: '${_spoken(shown.first)} ${t(context, 'a', 'to')} ${_spoken(shown.last)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: t(context, 'Notas más agudas', 'Higher notes'),
                  onPressed: start < _maxStart(n) ? () => setState(() => _start = _next(start, n)) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            SizedBox(
              height: DroneKeyboard.height,
              width: width,
              child: _keys(context, shown, width / n),
            ),
          ],
        );
      },
    );
  }

  Widget _keys(BuildContext context, List<int> shown, double kw) {
    final ClavePalette pal = ClavePalette.of(context);
    final PitchSettings ps = widget.settings;
    final DroneController d = widget.controller;
    final Set<int> pressed = d.pressedKeys;
    const double h = DroneKeyboard.height;
    const double blackHeight = h * 0.6;
    final double blackWidth = kw * 0.62;
    final List<Widget> whites = <Widget>[];
    final List<Widget> blacks = <Widget>[];
    final List<Widget> nodes = <Widget>[];

    Widget node(int written, Rect r) {
      final int sounding = ps.soundingMidi(written);
      return Positioned.fromRect(
        rect: r,
        child: Semantics(
          sortKey: OrdinalSortKey(written.toDouble()),
          button: true,
          selected: pressed.contains(sounding),
          label: _spoken(written),
          onTap: () => d.tapKey(sounding),
          child: const SizedBox.expand(),
        ),
      );
    }

    Widget black(int written, double boundary) {
      final int sounding = ps.soundingMidi(written);
      return Positioned(
        left: boundary - blackWidth / 2,
        top: 0,
        width: blackWidth,
        height: blackHeight,
        child: _Key(black: true, pressed: pressed.contains(sounding), onDown: () => d.keyDown(sounding), onUp: () => d.keyUp(sounding), pressedColor: pal.accent, pressedTextColor: pal.onAccent),
      );
    }

    for (int i = 0; i < shown.length; i++) {
      final int written = shown[i];
      final int sounding = ps.soundingMidi(written);
      whites.add(Positioned(
        left: i * kw,
        top: 0,
        width: kw,
        height: h,
        child: _Key(
          black: false,
          pressed: pressed.contains(sounding),
          label: Notes.pitchClassOf(written) == 0 ? _name(written) : null,
          onDown: () => d.keyDown(sounding),
          onUp: () => d.keyUp(sounding),
          pressedColor: pal.accent,
          pressedTextColor: pal.onAccent,
        ),
      ));
      nodes.add(node(written, Rect.fromLTWH(i * kw, 0, kw, h)));
    }
    // Negras entre dos blancas de la ventana: se tocan y se nombran (su área
    // para el lector mide al menos 48 dp de ancho y queda dentro).
    for (int i = 0; i + 1 < shown.length; i++) {
      final int written = shown[i] + 1;
      if (DroneKeyboard.isWhite(written)) {
        continue;
      }
      final double boundary = (i + 1) * kw;
      blacks.add(black(written, boundary));
      final double nodeWidth = math.max(48.0, blackWidth);
      nodes.add(node(written, Rect.fromLTWH(boundary - nodeWidth / 2, 0, nodeWidth, blackHeight)));
    }
    // Negras partidas en los bordes: se ven y se tocan; para el lector están
    // enteras en la ventana vecina.
    final int before = shown.first - 1;
    if (before >= DroneKeyboard.lowest && !DroneKeyboard.isWhite(before)) {
      blacks.add(black(before, 0));
    }
    final int after = shown.last + 1;
    if (after <= DroneKeyboard.highest && !DroneKeyboard.isWhite(after)) {
      blacks.add(black(after, shown.length * kw));
    }

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: <Widget>[
        Positioned.fill(child: ExcludeSemantics(child: Stack(clipBehavior: Clip.hardEdge, children: <Widget>[...whites, ...blacks]))),
        Positioned.fill(child: Semantics(container: true, explicitChildNodes: true, child: Stack(children: nodes))),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.black, required this.pressed, required this.onDown, required this.onUp, required this.pressedColor, required this.pressedTextColor, this.label});

  final bool black;
  final bool pressed;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final Color pressedColor;
  final Color pressedTextColor;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onDown(),
      onPointerUp: (_) => onUp(),
      onPointerCancel: (_) => onUp(),
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: pressed ? pressedColor : (black ? const Color(0xFF1B1B1F) : Colors.white),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
          border: Border.all(color: Colors.black38),
        ),
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.only(bottom: 6),
        child: label == null ? null : Text(label!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pressed ? pressedTextColor : Colors.black87)),
      ),
    );
  }
}
