import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/dates.dart';
import '../../logic/stopwatch.dart';
import '../widgets/common.dart';

/// Cronómetro con vueltas; la más rápida y la más lenta se resaltan.
class StopwatchView extends StatefulWidget {
  const StopwatchView({super.key});

  @override
  State<StopwatchView> createState() => _StopwatchViewState();
}

class _StopwatchViewState extends State<StopwatchView> {
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _sync(bool running, bool visible) {
    if (running && visible) {
      _ticker ??= Timer.periodic(const Duration(milliseconds: 50), (Timer _) {
        if (mounted) {
          setState(() {});
        }
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final bool visible = Visibility.of(context);
    return ListenableBuilder(
      listenable: s.timers,
      builder: (BuildContext context, Widget? _) {
        final StopwatchState sw = s.timers.stopwatch;
        _sync(sw.running, visible);
        return _content(context, s, sw);
      },
    );
  }

  Widget _content(BuildContext context, Services s, StopwatchState sw) {
    final bool es = s.settings.spanish;
    final ThemeData theme = Theme.of(context);
    final DateTime now = clock.now();
    final int elapsed = sw.elapsedMs(now);
    final List<int> laps = sw.lapDurations();
    final int? best = sw.bestLap;
    final int? worst = sw.worstLap;
    final bool dark = theme.brightness == Brightness.dark;
    final Color good = dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
    final Color bad = dark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828);
    final List<Widget> lapTiles = <Widget>[];
    if (sw.running || laps.isNotEmpty) {
      lapTiles.add(ListTile(
        dense: false,
        title: Text(es ? 'Vuelta ${laps.length + 1}' : 'Lap ${laps.length + 1}'),
        trailing: Text(formatStopwatch(sw.currentLapMs(now)), style: theme.textTheme.titleMedium?.copyWith(fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
      ));
    }
    for (int i = laps.length - 1; i >= 0; i--) {
      final bool isBest = i == best;
      final bool isWorst = i == worst;
      final Color? color = isBest ? good : (isWorst ? bad : null);
      final String tag = isBest ? (es ? 'Mejor' : 'Best') : (isWorst ? (es ? 'Peor' : 'Worst') : '');
      lapTiles.add(Semantics(
        label: '${es ? 'Vuelta' : 'Lap'} ${i + 1}: ${formatStopwatch(laps[i])}${tag.isEmpty ? '' : ', $tag'}',
        excludeSemantics: true,
        child: ListTile(
          leading: isBest || isWorst ? Icon(isBest ? Icons.arrow_downward : Icons.arrow_upward, color: color) : const SizedBox(width: 24),
          title: Text(es ? 'Vuelta ${i + 1}' : 'Lap ${i + 1}', style: TextStyle(color: color, fontWeight: color == null ? null : FontWeight.w700)),
          subtitle: Text('${tag.isEmpty ? '' : '$tag · '}total ${formatStopwatch(sw.laps[i])}'),
          trailing: Text(formatStopwatch(laps[i]), style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
        ),
      ));
    }
    return ReadableWidth(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          const SizedBox(height: 24),
          Semantics(
            label: es ? 'Tiempo: ${formatStopwatch(elapsed)}' : 'Time: ${formatStopwatch(elapsed)}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(formatStopwatch(elapsed), style: theme.textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: <Widget>[
              if (sw.running)
                OutlinedButton.icon(
                  onPressed: () {
                    sw.lap(clock.now());
                    s.timers.changed();
                  },
                  icon: const Icon(Icons.flag_outlined),
                  label: Text(t(context, 'Vuelta', 'Lap')),
                )
              else
                OutlinedButton.icon(
                  onPressed: sw.isZero
                      ? null
                      : () {
                          sw.reset();
                          s.timers.changed();
                        },
                  icon: const Icon(Icons.restart_alt),
                  label: Text(t(context, 'Reiniciar', 'Reset')),
                ),
              FilledButton.icon(
                onPressed: () {
                  if (sw.running) {
                    sw.pause(clock.now());
                  } else {
                    sw.start(clock.now());
                  }
                  s.timers.changed();
                },
                icon: Icon(sw.running ? Icons.pause : Icons.play_arrow),
                label: Text(sw.running ? t(context, 'Pausar', 'Pause') : (sw.isZero ? t(context, 'Iniciar', 'Start') : t(context, 'Seguir', 'Resume'))),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (lapTiles.isNotEmpty) ...<Widget>[
            SectionHeader(t(context, 'Vueltas', 'Laps')),
            ...lapTiles,
          ] else
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(t(context, 'Marca vueltas mientras corre: la más rápida y la más lenta se resaltan.', 'Mark laps while it runs: the fastest and the slowest are highlighted.'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}
