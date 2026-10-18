import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../audio/click_synth.dart';
import '../../audio/metronome.dart';
import '../../audio/sequencer.dart';
import '../../core/app_scope.dart';
import '../../core/theme.dart';
import '../../music/instruments.dart';
import '../widgets/adaptive.dart';
import 'presets_screen.dart';
import 'rhythm_sheets.dart';

class MetronomeScreen extends StatefulWidget {
  const MetronomeScreen({super.key});

  @override
  State<MetronomeScreen> createState() => _MetronomeScreenState();
}

class _MetronomeScreenState extends State<MetronomeScreen> with AutomaticKeepAliveClientMixin {
  Services? _services;
  bool _started = false;
  final FlutterTts _tts = FlutterTts();
  int _lastSpokenBar = -1;
  int _lastSpokenBeat = -1;
  bool _countingIn = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _services = AppScope.of(context);
      _services!.metronome.addListener(_onBeat);
      _services!.settings.addListener(_onSettings);
      _onSettings();
    }
  }

  void _onSettings() {
    final Services? s = _services;
    if (s == null) {
      return;
    }
    s.metronome
      ..hapticsEnabled = s.settings.haptics
      ..flashEnabled = s.settings.flash
      ..visualOffsetMs = s.settings.visualOffsetMs
      ..volume = s.settings.metronomeVolume;
    if (mounted) {
      setState(() {});
    }
  }

  void _onBeat() {
    final Services? s = _services;
    if (s == null || !mounted) {
      return;
    }
    final BeatState b = s.metronome.state;
    if (b.running) {
      s.state.touchPractice('metronomo', s.settings.instrumentId);
      // Conteo hablado durante el primer compás.
      if (_countingIn && b.sub == 0 && (b.bar != _lastSpokenBar || b.beat != _lastSpokenBeat)) {
        _lastSpokenBar = b.bar;
        _lastSpokenBeat = b.beat;
        if (b.bar == 0) {
          unawaited(_speakCount(b.beat + 1));
        } else {
          _countingIn = false;
        }
      }
    }
    setState(() {});
  }

  Future<void> _speakCount(int n) async {
    final bool spanish = _services?.settings.spanish ?? true;
    const List<String> es = <String>['uno', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete', 'ocho', 'nueve', 'diez', 'once', 'doce'];
    const List<String> en = <String>['one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve'];
    if (n < 1 || n > 12) {
      return;
    }
    try {
      await _tts.setLanguage(spanish ? 'es-CO' : 'en-US');
      await _tts.setSpeechRate(0.6);
      await _tts.speak(spanish ? es[n - 1] : en[n - 1]);
    } catch (_) {}
  }

  @override
  void dispose() {
    _services?.metronome.removeListener(_onBeat);
    _services?.settings.removeListener(_onSettings);
    unawaited(_tts.stop().catchError((Object e) => 0));
    super.dispose();
  }

  Future<void> _toggle() async {
    final Services s = _services!;
    if (s.metronome.running) {
      await s.metronome.stop();
      _countingIn = false;
    } else {
      _countingIn = s.settings.countInVoice;
      _lastSpokenBar = -1;
      _lastSpokenBeat = -1;
      await s.metronome.start();
    }
  }

  void _set(RhythmConfig c) => _services!.metronome.setConfig(c);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final Services s = AppScope.of(context);
    final Metronome m = s.metronome;
    final RhythmConfig c = m.config;
    final BeatState b = m.state;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool spanish = s.settings.spanish;
    final bool flashOn = b.running && m.flashEnabled && b.sub == 0 && b.phase < 0.12;
    final Color flashColor = b.kind == BeatKind.accent ? ClaveColors.ambar : cs.primary;

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
      final Widget beats = _BeatRow(
        config: c,
        state: b,
        onCycle: (int i) {
          final List<BeatMode> beats = List<BeatMode>.from(c.beats);
          final BeatMode cur = beats[i];
          final BeatMode next = cur == BeatMode.accent ? BeatMode.normal : (cur == BeatMode.normal ? BeatMode.silent : (cur == BeatMode.silent ? BeatMode.subOnly : BeatMode.accent));
          beats[i] = next;
          _set(c.copyWith(beats: beats));
        },
      );
      final Widget pendulum = SizedBox(
        height: wide ? 90 : (tablet ? 200 : 110),
        child: CustomPaint(painter: _PendulumPainter(state: b, color: cs.primary, onSurface: cs.onSurface), child: const SizedBox.expand()),
      );
      final Widget controls = _Controls(config: c, onChange: _set, spanish: spanish, onOpenPresets: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PresetsScreen())));

      final Widget body = wide
          ? Row(
              children: <Widget>[
                Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[tempo, pendulum])),
                Expanded(child: ListView(padding: const EdgeInsets.all(12), children: <Widget>[beats, const SizedBox(height: 8), controls])),
              ],
            )
          : tablet
              // Tableta en vertical: todo en una columna centrada y más grande.
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: Column(children: <Widget>[tempo, const SizedBox(height: 16), pendulum, const SizedBox(height: 16), beats, const SizedBox(height: 16), controls]),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  children: <Widget>[tempo, pendulum, beats, const SizedBox(height: 8), controls],
                );
      return Stack(
        children: <Widget>[
          Positioned.fill(child: body),
          if (flashOn) Positioned.fill(child: IgnorePointer(child: Container(color: flashColor.withValues(alpha: b.kind == BeatKind.accent ? 0.22 : 0.12)))),
        ],
      );
    });
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
    final bool trainerActive = (currentBpm - bpm).abs() >= 0.5 && running;
    return Column(
      children: <Widget>[
        const SizedBox(height: 6),
        Text(TempoMark.forBpm(bpm), style: TextStyle(fontSize: 16, color: cs.onSurface.withValues(alpha: 0.7), letterSpacing: 1)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _RoundBtn(icon: Icons.remove_rounded, onTap: () => onBpm(bpm - 1), onLongPress: () => onBpm(bpm - 10)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showBpmDialog(context),
              child: SizedBox(
                width: 170 * scale,
                child: Column(
                  children: <Widget>[
                    Text(
                      trainerActive ? currentBpm.toStringAsFixed(0) : bpm.toStringAsFixed(bpm == bpm.roundToDouble() ? 0 : 1).replaceAll('.', spanish ? ',' : '.'),
                      style: TextStyle(fontSize: 76 * scale, fontWeight: FontWeight.w800, height: 1, color: trainerActive ? ClaveColors.ambar : cs.onSurface, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()]),
                    ),
                    Text(trainerActive ? '${t(context, 'meta', 'target')} ${bpm.toStringAsFixed(0)} · BPM' : 'BPM', style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.6))),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            _RoundBtn(icon: Icons.add_rounded, onTap: () => onBpm(bpm + 1), onLongPress: () => onBpm(bpm + 10)),
          ],
        ),
        Slider(
          min: 20,
          max: 400,
          value: bpm.clamp(20.0, 400.0),
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
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 56), backgroundColor: running ? cs.error : null),
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
    if (parsed != null) {
      onBpm(parsed);
    }
    disposeLater(<ChangeNotifier>[ctrl]);
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap, this.onLongPress});

  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(width: 52, height: 52, child: Icon(icon, size: 30)),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (int i = 0; i < config.beatsPerBar; i++)
            GestureDetector(
              onTap: () => onCycle(i),
              child: Semantics(
                button: true,
                label: '${t(context, 'Pulso', 'Beat')} ${i + 1}: ${_modeName(context, config.beats[i])}',
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 60),
                  width: config.beatsPerBar > 8 ? 30 : 42,
                  height: config.beatsPerBar > 8 ? 42 : 56,
                  decoration: BoxDecoration(
                    color: _fill(i, cs),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: state.running && state.beat == i ? cs.onSurface : cs.outlineVariant, width: state.running && state.beat == i ? 3 : 1),
                  ),
                  child: Center(child: _glyph(i, cs)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _fill(int i, ColorScheme cs) {
    final bool active = state.running && state.beat == i && state.sub == 0 && state.phase < 0.25;
    switch (config.beats[i]) {
      case BeatMode.accent:
        return active ? ClaveColors.ambar : ClaveColors.ambar.withValues(alpha: 0.45);
      case BeatMode.normal:
        return active ? cs.primary : cs.primary.withValues(alpha: 0.35);
      case BeatMode.silent:
        return cs.surfaceContainerHighest;
      case BeatMode.subOnly:
        return active ? cs.tertiary : cs.tertiary.withValues(alpha: 0.3);
    }
  }

  Widget _glyph(int i, ColorScheme cs) {
    switch (config.beats[i]) {
      case BeatMode.accent:
        return const Icon(Icons.keyboard_double_arrow_up_rounded, size: 18);
      case BeatMode.normal:
        return Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700));
      case BeatMode.silent:
        return Icon(Icons.remove_rounded, size: 18, color: cs.onSurface.withValues(alpha: 0.4));
      case BeatMode.subOnly:
        return const Icon(Icons.more_horiz_rounded, size: 18);
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
                value: _subName(context, config.subdivision) + (config.subdivision == 2 && config.swing > 0 ? ' · swing ${(config.swing * 100).round()} %' : ''),
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
                value: config.trainer == null ? t(context, 'Apagado', 'Off') : '→ ${config.trainer!.targetBpm.toStringAsFixed(0)} · +${config.trainer!.stepBpm.toStringAsFixed(0)} / ${config.trainer!.everyBars}',
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
          style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
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
    return Material(
      color: highlight ? cs.secondaryContainer : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.65))),
                    const SizedBox(height: 2),
                    Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Icon(icon ?? Icons.expand_more_rounded, size: 20, color: cs.onSurface.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Péndulo atado a la fase del pulso.
class _PendulumPainter extends CustomPainter {
  _PendulumPainter({required this.state, required this.color, required this.onSurface});

  final BeatState state;
  final Color color;
  final Color onSurface;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset pivot = Offset(size.width / 2, size.height * 0.92);
    final double len = size.height * 0.8;
    // Va de izquierda a derecha en los pulsos pares y vuelve en los impares.
    final double dir = state.beat.isEven ? 1 : -1;
    final double phase = state.running ? state.phase : 0.5;
    final double x = math.cos(math.pi * phase) * dir; // 1 → -1
    final double angle = -x * 0.55;
    final Offset tip = pivot + Offset(math.sin(angle), -math.cos(angle)) * len;
    canvas.drawLine(Offset(size.width * 0.15, pivot.dy), Offset(size.width * 0.85, pivot.dy), Paint()..color = onSurface.withValues(alpha: 0.15)..strokeWidth = 2);
    canvas.drawLine(pivot, tip, Paint()..color = onSurface.withValues(alpha: 0.6)..strokeWidth = 3..strokeCap = StrokeCap.round);
    canvas.drawCircle(tip, 11, Paint()..color = state.running && state.sub == 0 && state.phase < 0.15 ? ClaveColors.ambar : color);
    canvas.drawCircle(pivot, 5, Paint()..color = onSurface.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(covariant _PendulumPainter old) => true;
}
