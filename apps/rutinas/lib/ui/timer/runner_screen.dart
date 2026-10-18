import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/dates.dart';
import '../../logic/timer_engine.dart';
import '../../model/habit.dart';
import '../../model/workout.dart';
import '../../state/timer_controller.dart';
import '../catalog.dart';
import '../widgets/common.dart';
import 'timer_texts.dart';

/// Pantalla del temporizador en marcha: color del intervalo, tiempo grande,
/// intervalo actual y siguiente, ronda y total restante, y bloqueo contra
/// toques accidentales.
class RunnerScreen extends StatefulWidget {
  const RunnerScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RunnerScreen()));

  /// Si ya hay un temporizador en marcha, pregunta antes de reemplazarlo.
  static Future<bool> confirmReplace(BuildContext context) async {
    final Services s = AppScope.read(context);
    final TimerRun? r = s.timer.run;
    if (r == null) {
      return true;
    }
    return confirm(
      context,
      title: t(context, '¿Detener el temporizador en marcha?', 'Stop the running timer?'),
      message: s.settings.spanish ? '"${r.name}" sigue en marcha. Si empiezas otro, se detiene y lo hecho queda guardado.' : '"${r.name}" is still running. If you start another, it stops and what you did is saved.',
      yes: t(context, 'Empezar otro', 'Start another'),
    );
  }

  @override
  State<RunnerScreen> createState() => _RunnerScreenState();
}

class _RunnerScreenState extends State<RunnerScreen> {
  bool _closing = false;

  void _closeIfIdle(TimerController c) {
    if (_closing || c.run != null || c.finished != null) {
      return;
    }
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _stop(Services s) async {
    final bool ok = await confirm(
      context,
      title: t(context, '¿Terminar ahora?', 'Stop now?'),
      message: t(context, 'Lo hecho hasta ahora queda guardado.', 'What you have done so far is saved.'),
      yes: t(context, 'Terminar', 'Stop'),
    );
    if (ok) {
      s.timer.stop();
    }
  }

  void _repeat(Services s, FinishedRun f) {
    switch (f.kind) {
      case RunKind.workout:
        final Workout? w = f.refId == null ? null : s.timers.workoutById(f.refId!);
        if (w != null) {
          s.timer.startWorkout(w);
        }
        break;
      case RunKind.countdown:
        int seconds = s.timers.lastCountdownSeconds;
        for (final CountdownPreset p in s.timers.presets) {
          if (p.id == f.refId) {
            seconds = p.seconds;
          }
        }
        s.timer.startCountdown(name: f.name, seconds: seconds, presetId: f.refId);
        break;
      case RunKind.habit:
        final Habit? h = f.refId == null ? null : s.habits.byId(f.refId!);
        if (h != null) {
          s.timer.startHabit(h, h.target);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s.timer,
      builder: (BuildContext context, Widget? _) {
        final TimerController c = s.timer;
        final TimerRun? run = c.run;
        final FinishedRun? fin = c.finished;
        if (run == null && fin != null) {
          return _Finished(finished: fin, onClose: () => c.dismissFinished(), onRepeat: () => _repeat(s, fin));
        }
        final RunSnapshot? snap = c.snapshot;
        if (run == null || snap == null) {
          _closeIfIdle(c);
          return const Scaffold(body: SizedBox.expand());
        }
        return _Running(run: run, snap: snap, locked: c.locked, onStop: () => _stop(s));
      },
    );
  }
}

class _Running extends StatelessWidget {
  const _Running({required this.run, required this.snap, required this.locked, required this.onStop});

  final TimerRun run;
  final RunSnapshot snap;
  final bool locked;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final bool es = s.settings.spanish;
    final TimerController c = s.timer;
    final TimerSegment seg = run.segments[snap.index];
    final Color bg = Color(seg.color);
    final Color fg = onColor(bg);
    final TimerSegment? next = snap.index + 1 < run.segments.length ? run.segments[snap.index + 1] : null;
    final bool workout = run.kind == RunKind.workout;
    final String name = seg.name.trim().isEmpty ? TimerTexts.kind(seg.kind, es) : seg.name.trim();
    final String remaining = formatClock(snap.segmentRemainingSeconds);
    final TextTheme tt = Theme.of(context).textTheme;
    final ThemeData dark = Theme.of(context).copyWith(
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: fg, disabledForegroundColor: fg.withValues(alpha: 0.4))),
    );

    final List<Widget> info = <Widget>[
      if (seg.rounds.isNotEmpty) Text(TimerTexts.rounds(seg.rounds, es), textAlign: TextAlign.center, style: tt.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w600)),
      if (workout && next != null)
        Text(
          '${t(context, 'Sigue', 'Next')}: ${next.name.trim().isEmpty ? TimerTexts.kind(next.kind, es) : next.name.trim()} · ${formatClock(next.seconds)}',
          textAlign: TextAlign.center,
          style: tt.titleMedium?.copyWith(color: fg),
        ),
      if (workout && next == null) Text(t(context, 'Último intervalo', 'Last interval'), textAlign: TextAlign.center, style: tt.titleMedium?.copyWith(color: fg)),
      if (workout)
        Text(
          '${t(context, 'Total restante', 'Total left')}: ${formatClock(snap.totalRemainingSeconds)} · ${es ? 'intervalo ${snap.index + 1} de ${run.segments.length}' : 'interval ${snap.index + 1} of ${run.segments.length}'}',
          textAlign: TextAlign.center,
          style: tt.bodyLarge?.copyWith(color: fg),
        ),
      if (snap.paused) Text(t(context, 'En pausa', 'Paused'), textAlign: TextAlign.center, style: tt.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w800)),
    ];

    final Widget clock = Semantics(
      label: es ? 'Quedan $remaining de $name' : '$remaining left of $name',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.headlineMedium?.copyWith(color: fg, fontWeight: FontWeight.w800)),
          Flexible(
            child: FittedBox(
              fit: BoxFit.contain,
              child: Text(remaining, style: TextStyle(fontSize: 120, fontWeight: FontWeight.w800, color: fg, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()], height: 1.05)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: snap.segmentProgress, minHeight: 10, color: fg, backgroundColor: fg.withValues(alpha: 0.25)),
            ),
          ),
        ],
      ),
    );

    final Widget controls = Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: <Widget>[
        if (workout) IconButton(tooltip: t(context, 'Intervalo anterior', 'Previous interval'), iconSize: 36, onPressed: locked ? null : c.previous, icon: const Icon(Icons.skip_previous)),
        IconButton.filled(
          tooltip: snap.paused ? t(context, 'Seguir', 'Resume') : t(context, 'Pausar', 'Pause'),
          iconSize: 48,
          style: IconButton.styleFrom(backgroundColor: fg, foregroundColor: bg, disabledBackgroundColor: fg.withValues(alpha: 0.35), disabledForegroundColor: bg, minimumSize: const Size(80, 80)),
          onPressed: locked ? null : (snap.paused ? c.resume : c.pause),
          icon: Icon(snap.paused ? Icons.play_arrow : Icons.pause),
        ),
        if (workout) IconButton(tooltip: t(context, 'Intervalo siguiente', 'Next interval'), iconSize: 36, onPressed: locked ? null : c.next, icon: const Icon(Icons.skip_next)),
        IconButton(tooltip: t(context, 'Terminar', 'Stop'), iconSize: 32, onPressed: locked ? null : onStop, icon: const Icon(Icons.stop)),
      ],
    );

    final Widget lockButton = Semantics(
      button: true,
      label: locked ? t(context, 'Controles bloqueados', 'Controls locked') : t(context, 'Bloquear controles', 'Lock controls'),
      hint: locked ? t(context, 'Mantén presionado para desbloquear', 'Press and hold to unlock') : null,
      onTap: locked ? null : () => c.setLocked(true),
      onLongPress: locked ? () => c.setLocked(false) : null,
      excludeSemantics: true,
      child: InkResponse(
        key: const ValueKey<String>('runner-lock'),
        radius: 28,
        onTap: locked ? () => showSnack(context, t(context, 'Mantén presionado el candado para desbloquear.', 'Press and hold the lock to unlock.')) : () => c.setLocked(true),
        onLongPress: locked ? () => c.setLocked(false) : null,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(locked ? Icons.lock : Icons.lock_open, color: fg, size: 30),
        ),
      ),
    );

    final Widget top = Row(
      children: <Widget>[
        IconButton(tooltip: t(context, 'Minimizar', 'Minimize'), icon: const Icon(Icons.keyboard_arrow_down), iconSize: 32, onPressed: () => Navigator.of(context).maybePop()),
        Expanded(child: Text(run.name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w600))),
        lockButton,
      ],
    );

    final Widget lockedHint = locked
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(t(context, 'Bloqueado: mantén presionado el candado para desbloquear.', 'Locked: press and hold the lock to unlock.'), textAlign: TextAlign.center, style: tt.bodyMedium?.copyWith(color: fg)),
          )
        : const SizedBox.shrink();

    return Theme(
      data: dark,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final bool landscape = box.maxWidth > box.maxHeight * 1.2;
              // Los controles van siempre a la vista, abajo; si el texto es
              // muy grande, lo que se desplaza es la información de en medio.
              final Widget details = SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ...info.map((Widget w) => Padding(padding: const EdgeInsets.only(bottom: 4), child: w)),
                  ],
                ),
              );
              if (landscape) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Column(
                    children: <Widget>[
                      top,
                      Expanded(
                        child: Row(
                          children: <Widget>[
                            Expanded(flex: 5, child: clock),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 4,
                              child: Column(
                                children: <Widget>[
                                  Expanded(child: Center(child: details)),
                                  const SizedBox(height: 8),
                                  controls,
                                  lockedHint,
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                child: Column(
                  children: <Widget>[
                    top,
                    Expanded(flex: 6, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: clock)),
                    const SizedBox(height: 12),
                    Flexible(flex: 3, child: details),
                    const SizedBox(height: 12),
                    controls,
                    lockedHint,
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Finished extends StatelessWidget {
  const _Finished({required this.finished, required this.onClose, required this.onRepeat});

  final FinishedRun finished;
  final VoidCallback onClose;
  final VoidCallback onRepeat;

  @override
  Widget build(BuildContext context) {
    final bool es = isSpanish(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme tt = Theme.of(context).textTheme;
    String title;
    switch (finished.kind) {
      case RunKind.workout:
        title = t(context, '¡Terminaste!', 'Done!');
        break;
      case RunKind.countdown:
        title = t(context, 'Se acabó el tiempo', 'Time is up');
        break;
      case RunKind.habit:
        title = t(context, '¡Listo!', 'All done!');
        break;
    }
    return Scaffold(
      backgroundColor: cs.primaryContainer,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ExcludeSemantics(child: Icon(Icons.check_circle, size: 96, color: cs.primary)),
                const SizedBox(height: 12),
                Semantics(liveRegion: true, child: Text(title, textAlign: TextAlign.center, style: tt.headlineMedium?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.w800))),
                const SizedBox(height: 8),
                Text(finished.name, textAlign: TextAlign.center, style: tt.titleLarge?.copyWith(color: cs.onPrimaryContainer)),
                Text(formatDurationShort(finished.seconds, spanish: es), textAlign: TextAlign.center, style: tt.titleMedium?.copyWith(color: cs.onPrimaryContainer)),
                if (finished.kind == RunKind.habit)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(t(context, 'Los minutos quedaron anotados en el hábito.', 'The minutes were logged to the habit.'), textAlign: TextAlign.center, style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer)),
                  ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: <Widget>[
                    OutlinedButton.icon(onPressed: onRepeat, icon: const Icon(Icons.replay), label: Text(t(context, 'Repetir', 'Repeat'))),
                    FilledButton.icon(onPressed: onClose, icon: const Icon(Icons.close), label: Text(t(context, 'Cerrar', 'Close'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
