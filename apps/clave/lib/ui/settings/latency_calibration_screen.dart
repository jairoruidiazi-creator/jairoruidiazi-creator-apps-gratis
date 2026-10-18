import 'dart:async';

import 'package:flutter/material.dart';

import '../../audio/latency_calibration.dart';
import '../../core/app_scope.dart';
import '../../core/theme.dart';
import '../widgets/adaptive.dart';

/// Calibrar el retraso del audio con toques: suena un clic a 90 BPM y se toca
/// el botón al ritmo de lo que se oye, con los audífonos que se van a usar.
class LatencyCalibrationScreen extends StatefulWidget {
  const LatencyCalibrationScreen({super.key, this.calibration});

  /// Para las pruebas; si no, usa el motor de la app.
  final LatencyCalibration? calibration;

  @override
  State<LatencyCalibrationScreen> createState() => _LatencyCalibrationScreenState();
}

class _LatencyCalibrationScreenState extends State<LatencyCalibrationScreen> {
  LatencyCalibration? _cal;
  bool _failed = false;
  bool _pressed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cal == null) {
      final Services s = AppScope.of(context);
      _cal = widget.calibration ?? LatencyCalibration(s.engine);
    }
  }

  @override
  void dispose() {
    unawaited(_cal?.stop());
    super.dispose();
  }

  Future<void> _start() async {
    final Services s = AppScope.of(context);
    // Solo debe sonar el clic de la calibración.
    if (s.metronome.running) {
      await s.metronome.stop();
    }
    if (s.drone.sounding) {
      await s.drone.stopAll();
    }
    final bool ok = await _cal!.start();
    if (mounted) {
      setState(() => _failed = !ok);
    }
  }

  Future<void> _restart() async {
    await _cal!.stop();
    await _start();
  }

  void _tap() {
    final LatencyCalibration cal = _cal!;
    if (!cal.running) {
      return;
    }
    cal.tap();
    setState(() {});
  }

  Future<void> _save(int ms) async {
    final Services s = AppScope.of(context);
    s.settings.audioDelayMs = ms;
    await s.settings.save();
    await _cal!.stop();
    if (mounted) {
      Navigator.of(context).pop(ms);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LatencyCalibration cal = _cal!;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final ClavePalette pal = ClavePalette.of(context);
    final int? result = cal.resultMs;
    final int taps = cal.taps;
    final String status;
    if (!cal.running) {
      status = t(context, 'Toca «Empezar» y luego el círculo al ritmo del clic que oyes.', 'Tap “Start”, then tap the circle in time with the click you hear.');
    } else if (result != null) {
      status = t(context, 'Retraso medido: $result ms ($taps toques).', 'Measured delay: $result ms ($taps taps).');
    } else if (taps < LatencyCalibration.minTaps) {
      status = t(context, 'Toques: $taps de ${LatencyCalibration.minTaps}.', 'Taps: $taps of ${LatencyCalibration.minTaps}.');
    } else {
      status = t(context, 'Los toques no son parejos todavía: sigue tocando al ritmo.', 'The taps are not steady yet: keep tapping in time.');
    }
    return ReadableScaffold(
      appBar: AppBar(title: Text(t(context, 'Calibrar el retraso', 'Calibrate the delay'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          Text(
            t(
              context,
              'Conecta los audífonos o el altavoz que vas a usar. Suena un clic a 90 BPM: toca el círculo justo cuando lo oigas, al menos ${LatencyCalibration.minTaps} veces. Clave mide cuánto tarda el sonido en llegarte y retrasa lo mismo la animación y la vibración.',
              'Connect the headphones or speaker you will use. A click plays at 90 BPM: tap the circle exactly when you hear it, at least ${LatencyCalibration.minTaps} times. Clave measures how long the sound takes to reach you and delays the animation and vibration by the same amount.',
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Semantics(
              button: true,
              enabled: cal.running,
              label: t(context, 'Tocar al ritmo del clic', 'Tap in time with the click'),
              onTap: cal.running ? _tap : null,
              excludeSemantics: true,
              child: Listener(
                // Al bajar el dedo, no al levantarlo: así no se suma el tiempo del toque.
                onPointerDown: (_) {
                  setState(() => _pressed = true);
                  _tap();
                },
                onPointerUp: (_) => setState(() => _pressed = false),
                onPointerCancel: (_) => setState(() => _pressed = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 60),
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: !cal.running ? cs.surfaceContainerHighest : (_pressed ? pal.accent : cs.primaryContainer),
                    border: Border.all(color: cal.running ? pal.accent : cs.outline, width: 3),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.touch_app_rounded, size: 64, color: !cal.running ? cs.onSurfaceVariant : (_pressed ? pal.onAccent : cs.onPrimaryContainer)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: Text(status, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
          if (_failed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(t(context, 'No se pudo abrir el audio. Inténtalo de nuevo.', 'Could not open the audio. Please try again.'), textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
            ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (!cal.running)
                FilledButton.icon(onPressed: _start, icon: const Icon(Icons.play_arrow_rounded), label: Text(t(context, 'Empezar', 'Start')))
              else
                OutlinedButton.icon(onPressed: _restart, icon: const Icon(Icons.restart_alt_rounded), label: Text(t(context, 'Reiniciar', 'Restart'))),
              if (result != null)
                FilledButton.icon(onPressed: () => _save(result), icon: const Icon(Icons.check_rounded), label: Text(t(context, 'Guardar $result ms', 'Save $result ms'))),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            t(
              context,
              'Sin audífonos el retraso suele ser bajo (0 a 50 ms); con audífonos Bluetooth, de 150 a 300 ms. El tempo del clic no cambia: solo se corre lo que ves y sientes.',
              'Without headphones the delay is usually low (0 to 50 ms); with Bluetooth headphones, 150 to 300 ms. The click tempo does not change: only what you see and feel is shifted.',
            ),
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
