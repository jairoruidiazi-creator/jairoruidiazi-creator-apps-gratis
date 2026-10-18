import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../audio/click_synth.dart';
import '../../audio/count_in_voice.dart';
import '../../audio/metronome.dart';
import '../../audio/sequencer.dart';
import '../../core/app_scope.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../model/models.dart';
import '../../music/instruments.dart';
import '../widgets/adaptive.dart';
import 'presets_screen.dart';
import 'rhythm_sheets.dart';

class MetronomeScreen extends StatefulWidget {
  const MetronomeScreen({super.key, this.active = true});

  /// Si la pestaña está a la vista: solo entonces se anima (el sonido y la
  /// vibración siguen igual).
  final bool active;

  @override
  State<MetronomeScreen> createState() => _MetronomeScreenState();
}

class _MetronomeScreenState extends State<MetronomeScreen> {
  final CountInVoice _voice = CountInVoice();
  Services? _services;
  bool _countingIn = false;
  int _lastSpoken = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services ??= AppScope.of(context);
  }

  @override
  void dispose() {
    _services?.metronome.beat.removeListener(_onBeatForCountIn);
    unawaited(_voice.stop());
    super.dispose();
  }

  void _onBeatForCountIn() {
    final Services? s = _services;
    if (s == null || !_countingIn) {
      return;
    }
    final BeatState b = s.metronome.beat.value;
    if (!b.running || b.sub != 0 || b.beatCount == _lastSpoken) {
      return;
    }
    _lastSpoken = b.beatCount;
    if (b.bar == 0) {
      unawaited(_voice.speak(b.beat + 1));
    } else {
      _stopCountIn();
    }
  }

  void _stopCountIn() {
    _countingIn = false;
    _services?.metronome.beat.removeListener(_onBeatForCountIn);
  }

  Future<void> _toggle() async {
    final Services s = _services!;
    if (s.metronome.running) {
      _stopCountIn();
      await s.metronome.stop();
      return;
    }
    if (s.settings.countInVoice) {
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      final String noVoice = t(context, 'El teléfono no tiene una voz en español instalada: el conteo no se dirá.', 'The phone has no English voice installed: the count-in will not be spoken.');
      final bool ok = await _voice.prepare(spanish: s.settings.spanish);
      if (ok) {
        _countingIn = true;
        _lastSpoken = -1;
        s.metronome.beat.addListener(_onBeatForCountIn);
      } else {
        messenger.showSnackBar(SnackBar(content: Text(noVoice)));
      }
    }
    await s.metronome.start();
  }

  void _set(RhythmConfig c) => _services!.metronome.setConfig(c);

  /// Carga la canción [index] de la setlist activa.
  Future<void> _loadFromSetlist(Setlist sl, int index) async {
    final Services s = _services!;
    final List<Preset> list = s.state.presetsOf(sl);
    if (list.isEmpty) {
      return;
    }
    final int i = index.clamp(0, list.length - 1);
    s.metronome.setConfig(list[i].rhythm);
    s.settings.activeSetlistIndex = i;
    await s.settings.save();
  }

  Future<void> _leaveSetlist() async {
    final AppSettings st = _services!.settings;
    st.activeSetlistId = '';
    st.activeSetlistIndex = 0;
    await st.save();
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[s.metronome, s.settings, s.state]),
      builder: (BuildContext context, Widget? _) => _build(context, s),
    );
  }

  Widget _build(BuildContext context, Services s) {
    final Metronome m = s.metronome;
    final RhythmConfig c = m.config;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final ClavePalette pal = ClavePalette.of(context);
    final bool spanish = isSpanish(context);
    final bool numberView = s.settings.beatView == 'number';

    return LayoutBuilder(builder: (BuildContext context, BoxConstraints k) {
      final bool wide = k.maxWidth > k.maxHeight * 1.2;
      final bool tablet = !wide && isWideLayout(context);
      final Widget tempo = _TempoPanel(
        bpm: c.bpm,
        currentBpm: m.currentBpm,
        running: m.running,
        onBpm: (double v) => m.setBpm(v),
        onTap: () {
          final double? bpm = m.tap();
          if (bpm == null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Sigue tocando al ritmo…', 'Keep tapping…')), duration: const Duration(milliseconds: 900)));
          }
        },
        onToggle: _toggle,
        spanish: spanish,
        scale: tablet ? 1.45 : 1.0,
      );
      final Widget beats = _BeatBuilder(
        active: widget.active,
        beat: m.beat,
        builder: (BuildContext context, BeatState b) => _BeatRow(
          config: c,
          state: b,
          onCycle: (int i) {
            final List<BeatMode> list = List<BeatMode>.from(c.beats);
            final BeatMode cur = list[i];
            list[i] = cur == BeatMode.accent ? BeatMode.normal : (cur == BeatMode.normal ? BeatMode.silent : (cur == BeatMode.silent ? BeatMode.subOnly : BeatMode.accent));
            _set(c.copyWith(beats: list));
          },
        ),
      );
      final double visualHeight = wide ? 100 : (tablet ? 200 : 120);
      final Widget visual = SizedBox(
        height: visualHeight,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: ExcludeSemantics(
                child: _BeatBuilder(
                  active: widget.active,
                  beat: m.beat,
                  builder: (BuildContext context, BeatState b) => numberView
                      ? _BigNumber(state: b, beatsPerBar: c.beatsPerBar, height: visualHeight, accent: pal.accent, onSurface: cs.onSurface, muted: cs.onSurfaceVariant, spanish: spanish)
                      : CustomPaint(painter: _PendulumPainter(state: b, color: cs.primary, accent: pal.accent, onSurface: cs.onSurface), child: const SizedBox.expand()),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: IconButton(
                tooltip: numberView ? t(context, 'Ver el péndulo', 'Show the pendulum') : t(context, 'Ver el número grande', 'Show the big number'),
                icon: Icon(numberView ? Icons.swap_horiz_rounded : Icons.looks_one_outlined),
                onPressed: () {
                  s.settings.beatView = numberView ? 'pendulum' : 'number';
                  s.settings.save();
                },
              ),
            ),
          ],
        ),
      );
      final Widget controls = _Controls(config: c, onChange: _set, spanish: spanish, onOpenPresets: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PresetsScreen())));
      final Widget? setlistBar = _setlistBar(context, s);

      final List<Widget> column = <Widget>[if (setlistBar != null) setlistBar, tempo, visual, beats, const SizedBox(height: 8), controls];
      final Widget body = wide
          ? Row(
              children: <Widget>[
                Expanded(child: ListView(padding: const EdgeInsets.all(12), children: <Widget>[if (setlistBar != null) setlistBar, tempo, visual])),
                Expanded(child: ListView(padding: const EdgeInsets.all(12), children: <Widget>[beats, const SizedBox(height: 8), controls])),
              ],
            )
          : tablet
              // Tableta en vertical: todo en una columna centrada y más grande.
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: column),
                  ),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: column);
      return Stack(
        children: <Widget>[
          Positioned.fill(child: body),
          Positioned.fill(
            child: IgnorePointer(
              child: _BeatBuilder(
                active: widget.active,
                beat: m.beat,
                builder: (BuildContext context, BeatState b) {
                  final bool flashOn = b.running && m.flashEnabled && b.sub == 0 && b.phase < 0.12;
                  if (!flashOn) {
                    return const SizedBox.shrink();
                  }
                  final Color flash = b.kind == BeatKind.accent ? pal.accent : cs.primary;
                  return ColoredBox(color: flash.withValues(alpha: b.kind == BeatKind.accent ? 0.22 : 0.12));
                },
              ),
            ),
          ),
        ],
      );
    });
  }

  /// Barra de la setlist en uso: canción actual, anterior y siguiente.
  Widget? _setlistBar(BuildContext context, Services s) {
    final String id = s.settings.activeSetlistId;
    if (id.isEmpty) {
      return null;
    }
    final Setlist? sl = s.state.setlistById(id);
    if (sl == null) {
      return null;
    }
    final List<Preset> list = s.state.presetsOf(sl);
    if (list.isEmpty) {
      return null;
    }
    final int i = s.settings.activeSetlistIndex.clamp(0, list.length - 1);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String name = list[i].name.isEmpty ? t(context, 'Sin nombre', 'Untitled') : list[i].name;
    return Card(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      color: cs.secondaryContainer,
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: t(context, 'Canción anterior', 'Previous song'),
            onPressed: i > 0 ? () => _loadFromSetlist(sl, i - 1) : null,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('${sl.name} · ${i + 1}/${list.length}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer)),
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSecondaryContainer)),
              ],
            ),
          ),
          IconButton(
            tooltip: t(context, 'Canción siguiente', 'Next song'),
            onPressed: i < list.length - 1 ? () => _loadFromSetlist(sl, i + 1) : null,
            icon: const Icon(Icons.skip_next_rounded),
          ),
          IconButton(
            tooltip: t(context, 'Salir de la setlist', 'Leave the setlist'),
            onPressed: _leaveSetlist,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

/// Se dibuja con cada pulso solo si la pestaña está activa; si no, una vez.
class _BeatBuilder extends StatelessWidget {
  const _BeatBuilder({required this.active, required this.beat, required this.builder});

  final bool active;
  final ValueNotifier<BeatState> beat;
  final Widget Function(BuildContext context, BeatState state) builder;

  @override
  Widget build(BuildContext context) {
    if (!active) {
      return builder(context, beat.value);
    }
    return ValueListenableBuilder<BeatState>(valueListenable: beat, builder: (BuildContext context, BeatState b, Widget? _) => builder(context, b));
  }
}

class _TempoPanel extends StatelessWidget {
  const _TempoPanel({required this.bpm, required this.currentBpm, required this.running, required this.onBpm, required this.onTap, required this.onToggle, required this.spanish, this.scale = 1.0});

  final double bpm;
  final double currentBpm;
  final bool running;
  final ValueChanged<double> onBpm;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final bool spanish;

  /// Tamaño del número del tempo (mayor en tabletas).
  final double scale;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final ClavePalette pal = ClavePalette.of(context);
    final bool trainerActive = (currentBpm - bpm).abs() >= 0.5 && running;
    final String bpmText = trainerActive ? currentBpm.toStringAsFixed(0) : formatDecimal(bpm, spanish: spanish, decimals: bpm == bpm.roundToDouble() ? 0 : 1);
    return Column(
      children: <Widget>[
        const SizedBox(height: 6),
        Text(TempoMark.forBpm(bpm), style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant, letterSpacing: 1)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _RoundBtn(icon: Icons.remove_rounded, label: t(context, 'Bajar el tempo (mantén para bajar 10)', 'Slower (hold for −10)'), onTap: () => onBpm(bpm - 1), onLongPress: () => onBpm(bpm - 10)),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: '${t(context, 'Tempo', 'Tempo')}: $bpmText BPM. ${t(context, 'Toca para escribirlo', 'Tap to type it')}',
              onTap: () => _showBpmDialog(context),
              excludeSemantics: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _showBpmDialog(context),
                child: SizedBox(
                  width: 170 * scale,
                  child: Column(
                    children: <Widget>[
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          bpmText,
                          style: TextStyle(fontSize: 76 * scale, fontWeight: FontWeight.w800, height: 1, color: trainerActive ? pal.accent : cs.onSurface, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()]),
                        ),
                      ),
                      Text(trainerActive ? '${t(context, 'meta', 'target')} ${bpm.toStringAsFixed(0)} · BPM' : 'BPM', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _RoundBtn(icon: Icons.add_rounded, label: t(context, 'Subir el tempo (mantén para subir 10)', 'Faster (hold for +10)'), onTap: () => onBpm(bpm + 1), onLongPress: () => onBpm(bpm + 10)),
          ],
        ),
        Slider(
          min: RhythmConfig.minBpm,
          max: RhythmConfig.maxBpm,
          value: bpm.clamp(RhythmConfig.minBpm, RhythmConfig.maxBpm),
          label: '${bpm.round()} BPM',
          semanticFormatterCallback: (double v) => '${v.round()} BPM',
          onChanged: (double v) => onBpm(v.roundToDouble()),
        ),
        // Los dos botones reparten el ancho disponible: en pantallas angostas
        // el texto se recorta con puntos suspensivos en vez de desbordar.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 4,
                child: OutlinedButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.touch_app_outlined),
                  label: Text(t(context, 'Tap tempo', 'Tap tempo'), maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: FilledButton.icon(
                  onPressed: onToggle,
                  icon: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 30),
                  label: Text(running ? t(context, 'Parar', 'Stop') : t(context, 'Iniciar', 'Start'), style: const TextStyle(fontSize: 18), maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 56), backgroundColor: running ? cs.error : null, foregroundColor: running ? cs.onError : null),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showBpmDialog(BuildContext context) async {
    final TextEditingController ctrl = TextEditingController(text: bpm.toStringAsFixed(0));
    final String? v = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('BPM'),
        content: TextField(controller: ctrl, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(hintText: '20 – 400')),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t(context, 'Cancelar', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: Text(t(context, 'Aceptar', 'OK'))),
        ],
      ),
    );
    final double? parsed = double.tryParse((v ?? '').replaceAll(',', '.'));
    if (parsed != null && parsed.isFinite) {
      onBpm(parsed);
    }
    disposeLater(<ChangeNotifier>[ctrl]);
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.label, required this.onTap, this.onLongPress});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        onTap: onTap,
        onLongPress: onLongPress,
        excludeSemantics: true,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            onLongPress: onLongPress,
            child: SizedBox(width: 52, height: 52, child: Icon(icon, size: 30)),
          ),
        ),
      ),
    );
  }
}

/// Puntos del compás: cada uno muestra su modo y se ilumina con el pulso.
class _BeatRow extends StatelessWidget {
  const _BeatRow({required this.config, required this.state, required this.onCycle});

  final RhythmConfig config;
  final BeatState state;
  final ValueChanged<int> onCycle;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final ClavePalette pal = ClavePalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (int i = 0; i < config.beatsPerBar; i++)
            Semantics(
              button: true,
              label: '${t(context, 'Pulso', 'Beat')} ${i + 1}: ${_modeName(context, config.beats[i])}. ${t(context, 'Toca para cambiarlo', 'Tap to change it')}',
              onTap: () => onCycle(i),
              excludeSemantics: true,
              child: Material(
                color: _fill(i, cs, pal),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: state.running && state.beat == i ? cs.onSurface : cs.outline, width: state.running && state.beat == i ? 3 : 1),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onCycle(i),
                  child: SizedBox(width: 48, height: config.beatsPerBar > 8 ? 48 : 56, child: Center(child: _glyph(i, cs, pal))),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _lit(int i) => state.running && state.beat == i && state.sub == 0 && state.phase < 0.25;

  Color _fill(int i, ColorScheme cs, ClavePalette pal) {
    final bool active = _lit(i);
    switch (config.beats[i]) {
      case BeatMode.accent:
        return active ? pal.accent : pal.accent.withValues(alpha: 0.3);
      case BeatMode.normal:
        return active ? cs.primary : cs.primaryContainer;
      case BeatMode.silent:
        return cs.surfaceContainerHighest;
      case BeatMode.subOnly:
        return active ? cs.tertiary : cs.tertiaryContainer;
    }
  }

  Widget _glyph(int i, ColorScheme cs, ClavePalette pal) {
    final bool active = _lit(i);
    switch (config.beats[i]) {
      case BeatMode.accent:
        return Icon(Icons.keyboard_double_arrow_up_rounded, size: 20, color: active ? pal.onAccent : cs.onSurface);
      case BeatMode.normal:
        return Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w700, color: active ? cs.onPrimary : cs.onPrimaryContainer));
      case BeatMode.silent:
        return Icon(Icons.remove_rounded, size: 20, color: cs.onSurfaceVariant);
      case BeatMode.subOnly:
        return Icon(Icons.more_horiz_rounded, size: 20, color: active ? cs.onTertiary : cs.onTertiaryContainer);
    }
  }

  String _modeName(BuildContext context, BeatMode m) {
    switch (m) {
      case BeatMode.accent:
        return t(context, 'acento', 'accent');
      case BeatMode.normal:
        return t(context, 'normal', 'normal');
      case BeatMode.silent:
        return t(context, 'silencio', 'silent');
      case BeatMode.subOnly:
        return t(context, 'solo subdivisión', 'subdivision only');
    }
  }
}

/// Controles de compás, subdivisión, sonido, entrenador y compases mudos.
class _Controls extends StatelessWidget {
  const _Controls({required this.config, required this.onChange, required this.spanish, required this.onOpenPresets});

  final RhythmConfig config;
  final ValueChanged<RhythmConfig> onChange;
  final bool spanish;
  final VoidCallback onOpenPresets;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _Tile(
                title: t(context, 'Compás', 'Time signature'),
                value: config.timeSignature,
                onTap: () => showTimeSignatureSheet(context, config, onChange),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Tile(
                title: t(context, 'Subdivisión', 'Subdivision'),
                value: _subName(context, config.subdivision) + (config.subdivision == 2 && config.swing > 0 ? ' · swing ${formatPercent(config.swing, spanish: spanish)}' : ''),
                onTap: () => showSubdivisionSheet(context, config, onChange),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: _Tile(
                title: t(context, 'Sonido', 'Sound'),
                value: spanish ? config.sound.nameEs : config.sound.nameEn,
                onTap: () => showSoundSheet(context, config, onChange),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Tile(
                title: t(context, 'Entrenador', 'Trainer'),
                value: config.trainer == null ? t(context, 'Apagado', 'Off') : '→ ${config.trainer!.targetBpm.toStringAsFixed(0)} · ${config.trainer!.targetBpm >= config.bpm ? '+' : '−'}${config.trainer!.stepBpm.toStringAsFixed(0)} / ${config.trainer!.everyBars}',
                highlight: config.trainer != null,
                onTap: () => showTrainerSheet(context, config, onChange),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: _Tile(
                title: t(context, 'Compases mudos', 'Mute bars'),
                value: config.muteBars == null ? t(context, 'Apagado', 'Off') : '${config.muteBars!.soundBars} ${t(context, 'suenan', 'on')} · ${config.muteBars!.muteBarsCount} ${t(context, 'mudos', 'off')}',
                highlight: config.muteBars != null,
                onTap: () => showMuteSheet(context, config, onChange),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Tile(
                title: t(context, 'Preajustes', 'Presets'),
                value: t(context, 'Canciones y setlists', 'Songs & setlists'),
                icon: Icons.queue_music_rounded,
                onTap: onOpenPresets,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          t(context, 'Toca un pulso para cambiarlo: acento, normal, silencio o solo subdivisión.', 'Tap a beat to cycle it: accent, normal, silent or subdivision only.'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  String _subName(BuildContext context, int n) {
    switch (n) {
      case 1:
        return t(context, 'Ninguna', 'None');
      case 2:
        return t(context, 'Corcheas', 'Eighths');
      case 3:
        return t(context, 'Tresillos', 'Triplets');
      case 4:
        return t(context, 'Semicorcheas', 'Sixteenths');
      case 6:
        return t(context, 'Seisillos', 'Sextuplets');
      default:
        return '$n';
    }
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.title, required this.value, required this.onTap, this.highlight = false, this.icon});

  final String title;
  final String value;
  final VoidCallback onTap;
  final bool highlight;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color fg = highlight ? cs.onSecondaryContainer : cs.onSurface;
    final Color fgMuted = highlight ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    return Material(
      color: highlight ? cs.secondaryContainer : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: TextStyle(fontSize: 12, color: fgMuted)),
                      const SizedBox(height: 2),
                      Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Icon(icon ?? Icons.expand_more_rounded, size: 20, color: fgMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Número grande del pulso: el pulso en curso, el compás y la subdivisión.
class _BigNumber extends StatelessWidget {
  const _BigNumber({required this.state, required this.beatsPerBar, required this.height, required this.accent, required this.onSurface, required this.muted, required this.spanish});

  final BeatState state;
  final int beatsPerBar;
  final double height;
  final Color accent;
  final Color onSurface;
  final Color muted;
  final bool spanish;

  @override
  Widget build(BuildContext context) {
    final bool running = state.running;
    final String number = running ? '${state.beat + 1}' : '1';
    final Color color = !running ? muted : (state.kind == BeatKind.accent ? accent : onSurface);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(number, textScaler: TextScaler.noScaling, style: TextStyle(fontSize: height * 0.82, height: 1, fontWeight: FontWeight.w800, color: color, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
        const SizedBox(width: 12),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('/ $beatsPerBar', textScaler: TextScaler.noScaling, style: TextStyle(fontSize: height * 0.2, color: muted)),
            if (running) Text('${spanish ? 'compás' : 'bar'} ${state.bar + 1}', textScaler: TextScaler.noScaling, style: TextStyle(fontSize: height * 0.14, color: muted)),
          ],
        ),
      ],
    );
  }
}

/// Péndulo atado a la fase del pulso: va y viene alternando con cada pulso
/// contado desde el arranque, así que no salta en compases impares.
class _PendulumPainter extends CustomPainter {
  _PendulumPainter({required this.state, required this.color, required this.accent, required this.onSurface});

  final BeatState state;
  final Color color;
  final Color accent;
  final Color onSurface;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset pivot = Offset(size.width / 2, size.height * 0.92);
    final double len = size.height * 0.8;
    final double dir = state.beatCount.isEven ? 1 : -1;
    final double phase = state.running ? state.phase : 0.5;
    final double x = math.cos(math.pi * phase) * dir; // 1 → -1
    final double angle = -x * 0.55;
    final Offset tip = pivot + Offset(math.sin(angle), -math.cos(angle)) * len;
    canvas.drawLine(Offset(size.width * 0.15, pivot.dy), Offset(size.width * 0.85, pivot.dy), Paint()
      ..color = onSurface.withValues(alpha: 0.15)
      ..strokeWidth = 2);
    canvas.drawLine(pivot, tip, Paint()
      ..color = onSurface.withValues(alpha: 0.6)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round);
    canvas.drawCircle(tip, 11, Paint()..color = state.running && state.sub == 0 && state.phase < 0.15 ? accent : color);
    canvas.drawCircle(pivot, 5, Paint()..color = onSurface.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(covariant _PendulumPainter old) => true;
}
