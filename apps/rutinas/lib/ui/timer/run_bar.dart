import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/dates.dart';
import '../../logic/timer_engine.dart';
import '../catalog.dart';
import 'runner_screen.dart';
import 'timer_texts.dart';

/// Barra del temporizador en marcha (sobre la navegación), para volver a él
/// desde cualquier pestaña.
class RunBar extends StatelessWidget {
  const RunBar({super.key});

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s.timer,
      builder: (BuildContext context, Widget? _) {
        final TimerRun? r = s.timer.run;
        final RunSnapshot? snap = s.timer.snapshot;
        if (r == null || snap == null) {
          return const SizedBox.shrink();
        }
        final bool es = s.settings.spanish;
        final TimerSegment seg = r.segments[snap.index];
        final Color bg = Color(seg.color);
        final Color fg = onColor(bg);
        final String segName = seg.name.trim().isEmpty ? TimerTexts.kind(seg.kind, es) : seg.name.trim();
        final String line = r.kind == RunKind.workout ? '$segName · ${formatClock(snap.segmentRemainingSeconds)}' : formatClock(snap.segmentRemainingSeconds);
        return Material(
          color: bg,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Semantics(
                  button: true,
                  label: es ? 'Temporizador en marcha: ${r.name}, $line. Abrir.' : 'Timer running: ${r.name}, $line. Open.',
                  child: InkWell(
                    onTap: () => RunnerScreen.open(context),
                    child: ExcludeSemantics(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                        child: Row(
                          children: <Widget>[
                            Icon(snap.paused ? Icons.pause_circle : Icons.timer, color: fg),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
                                  Text(snap.paused ? '${t(context, 'En pausa', 'Paused')} · $line' : line, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: snap.paused ? t(context, 'Seguir', 'Resume') : t(context, 'Pausar', 'Pause'),
                color: fg,
                onPressed: s.timer.locked ? null : (snap.paused ? s.timer.resume : s.timer.pause),
                icon: Icon(snap.paused ? Icons.play_arrow : Icons.pause),
              ),
            ],
          ),
        );
      },
    );
  }
}
