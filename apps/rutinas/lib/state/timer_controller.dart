import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/cues.dart';
import '../core/dates.dart';
import '../core/ids.dart';
import '../core/settings.dart';
import '../logic/timer_engine.dart';
import '../model/habit.dart';
import '../model/workout.dart';
import 'habit_store.dart';
import 'timer_store.dart';

/// Mantener la pantalla encendida (wakelock_plus en el teléfono).
abstract class ScreenWake {
  Future<void> keepOn(bool on);
}

class DeviceScreenWake implements ScreenWake {
  bool? _last;

  @override
  Future<void> keepOn(bool on) async {
    if (_last == on) {
      return;
    }
    _last = on;
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (e) {
      debugPrint('Pantalla encendida: $e');
    }
  }
}

class FakeScreenWake implements ScreenWake {
  bool on = false;

  @override
  Future<void> keepOn(bool value) async {
    on = value;
  }
}

/// Lo que se muestra al terminar un temporizador.
class FinishedRun {
  const FinishedRun({required this.kind, required this.refId, required this.name, required this.seconds, required this.endedAt});

  final RunKind kind;
  final String? refId;
  final String name;
  final int seconds;
  final DateTime endedAt;
}

/// Corre el temporizador de toda la app: calcula su estado con el reloj, da
/// los avisos de voz y sonido mientras la app está a la vista, registra lo
/// hecho al terminar y mantiene la pantalla encendida si se pidió.
class TimerController extends ChangeNotifier {
  TimerController({required this.store, required this.cues, required this.settings, required this.habits, required this.screen});

  final TimerStore store;
  final CuePlayer cues;
  final AppSettings settings;
  final HabitStore habits;
  final ScreenWake screen;

  final CueTracker _tracker = CueTracker();
  Timer? _ticker;
  bool _foreground = true;
  RunSnapshot? _snapshot;

  /// Bloqueo contra pausas accidentales: los botones no responden.
  bool locked = false;
  FinishedRun? finished;

  TimerRun? get run => store.run;

  RunSnapshot? get snapshot => _snapshot;

  bool get foreground => _foreground;

  /// Al abrir la app: si quedó un temporizador en marcha, sigue donde va (o
  /// se registra como terminado si acabó mientras la app estaba cerrada).
  void restore() {
    final TimerRun? r = run;
    if (r == null) {
      return;
    }
    final RunSnapshot s = r.snapshot(clock.now());
    _snapshot = s;
    _tracker.sync(s);
    if (s.finished) {
      _finish();
    } else {
      _ensureTicker();
      _applyScreen();
      notifyListeners();
    }
  }

  bool startWorkout(Workout w) {
    final List<TimerSegment> segments = TimerEngine.flatten(w.nodes);
    if (segments.isEmpty) {
      return false;
    }
    _begin(TimerRun(kind: RunKind.workout, refId: w.id, name: w.name, segments: segments, startedAt: clock.now(), finishSound: w.finishSound));
    return true;
  }

  void startCountdown({required String name, required int seconds, String? presetId}) {
    if (presetId == null) {
      store.lastCountdownSeconds = seconds;
    }
    _begin(TimerRun(
      kind: RunKind.countdown,
      refId: presetId,
      name: name,
      segments: <TimerSegment>[TimerSegment(name: name, seconds: seconds, kind: StepKind.work, color: 0xFF283593, sound: CueSound.none)],
      startedAt: clock.now(),
      finishSound: CueSound.gong,
    ));
  }

  /// Temporizador de un hábito con tiempo: corre [seconds] y los suma al día.
  void startHabit(Habit h, int seconds) {
    _begin(TimerRun(
      kind: RunKind.habit,
      refId: h.id,
      name: h.name,
      segments: <TimerSegment>[TimerSegment(name: h.name, seconds: seconds, kind: StepKind.work, color: 0xFF00695C, sound: CueSound.none)],
      startedAt: clock.now(),
      finishSound: CueSound.bell,
    ));
  }

  void _begin(TimerRun r) {
    if (store.run != null) {
      _record(store.run!, completed: false, endedAt: clock.now());
    }
    finished = null;
    locked = false;
    store.run = r;
    store.changed();
    _tracker.reset();
    _snapshot = null;
    _tick();
    _ensureTicker();
    _applyScreen();
  }

  void pause() {
    final TimerRun? r = run;
    if (r == null || r.paused) {
      return;
    }
    r.pause(clock.now());
    store.changed();
    unawaited(cues.stop());
    _tick();
    _applyScreen();
  }

  void resume() {
    final TimerRun? r = run;
    if (r == null || !r.paused) {
      return;
    }
    r.resume(clock.now());
    store.changed();
    _tick();
    _ensureTicker();
    _applyScreen();
  }

  void next() {
    final TimerRun? r = run;
    if (r == null) {
      return;
    }
    r.next(clock.now());
    store.changed();
    _tick();
  }

  void previous() {
    final TimerRun? r = run;
    if (r == null) {
      return;
    }
    r.previous(clock.now());
    store.changed();
    _tick();
  }

  /// Detiene el temporizador; lo hecho hasta ahora queda registrado.
  void stop() {
    final TimerRun? r = run;
    if (r == null) {
      return;
    }
    _record(r, completed: false, endedAt: clock.now());
    store.run = null;
    store.changed();
    _stopTicker();
    unawaited(cues.stop());
    locked = false;
    finished = null;
    _snapshot = null;
    _applyScreen();
    notifyListeners();
  }

  void dismissFinished() {
    finished = null;
    notifyListeners();
  }

  void setLocked(bool value) {
    locked = value;
    notifyListeners();
  }

  /// La app pasa a segundo plano (false) o vuelve (true). En segundo plano no
  /// suena nada desde la app: avisan las notificaciones programadas.
  void setForeground(bool value) {
    if (value == _foreground) {
      return;
    }
    _foreground = value;
    final TimerRun? r = run;
    if (value && r != null) {
      final RunSnapshot s = r.snapshot(clock.now());
      _snapshot = s;
      _tracker.sync(s);
      if (s.finished) {
        _finish();
        return;
      }
      _ensureTicker();
    } else if (!value) {
      _stopTicker();
      unawaited(cues.stop());
    }
    _applyScreen();
    notifyListeners();
  }

  void _ensureTicker() {
    final TimerRun? r = run;
    if (_ticker != null || !_foreground || r == null || r.paused) {
      return;
    }
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (Timer _) => _tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _tick() {
    final TimerRun? r = run;
    if (r == null) {
      _stopTicker();
      return;
    }
    final RunSnapshot s = r.snapshot(clock.now());
    final RunSnapshot? before = _snapshot;
    _snapshot = s;
    if (_foreground) {
      for (final CueEvent e in _tracker.update(s)) {
        _cue(r, e);
      }
    }
    if (s.finished) {
      _finish();
      return;
    }
    if (s.paused) {
      _stopTicker();
    }
    // Si el tiempo no avanzó (reloj detenido en las capturas de tienda), no
    // hay nada nuevo que dibujar.
    if (before != null && before.elapsedMs == s.elapsedMs && before.index == s.index && before.paused == s.paused) {
      return;
    }
    notifyListeners();
  }

  void _cue(TimerRun r, CueEvent e) {
    final bool es = settings.spanish;
    switch (e.type) {
      case CueType.segmentStart:
        if (r.kind != RunKind.workout) {
          return;
        }
        final TimerSegment seg = r.segments[e.index];
        unawaited(cues.sound(seg.sound));
        unawaited(cues.vibrate());
        final String name = seg.name.trim();
        final bool last = r.segments.length > 1 && e.index == r.segments.length - 1;
        if (name.isNotEmpty) {
          unawaited(cues.speak(last ? (es ? 'Último: $name' : 'Last one: $name') : name));
        }
        break;
      case CueType.countdown:
        if (r.kind != RunKind.workout) {
          return;
        }
        if (settings.voice && settings.voiceCountdown && cues.voiceAvailable != false) {
          unawaited(cues.speak('${e.number}'));
        } else {
          unawaited(cues.pip());
        }
        break;
      case CueType.finished:
        unawaited(cues.sound(r.finishSound));
        unawaited(cues.vibrate(strong: true));
        String text;
        switch (r.kind) {
          case RunKind.workout:
            text = es ? '¡Terminaste! Buen trabajo.' : 'Done! Great job.';
            break;
          case RunKind.countdown:
            text = es ? 'Se acabó el tiempo.' : 'Time is up.';
            break;
          case RunKind.habit:
            text = es ? 'Listo.' : 'All done.';
            break;
        }
        unawaited(cues.speak(text));
        break;
    }
  }

  void _finish() {
    final TimerRun? r = run;
    if (r == null) {
      return;
    }
    _stopTicker();
    final DateTime now = clock.now();
    final DateTime planned = r.wallTimeOf(r.totalMs);
    final DateTime end = planned.isBefore(now) ? planned : now;
    _record(r, completed: true, endedAt: end);
    finished = FinishedRun(kind: r.kind, refId: r.refId, name: r.name, seconds: r.totalMs ~/ 1000, endedAt: end);
    store.run = null;
    store.changed();
    locked = false;
    _snapshot = null;
    _applyScreen();
    notifyListeners();
  }

  /// Guarda lo hecho: el entrenamiento en el historial o los minutos del hábito.
  void _record(TimerRun r, {required bool completed, required DateTime endedAt}) {
    final int active = r.activeMs(endedAt) ~/ 1000;
    switch (r.kind) {
      case RunKind.workout:
        if (completed || active >= 30) {
          store.addSession(WorkoutSession(id: newId(), workoutId: r.refId, name: r.name, startedAt: r.startedAt, endedAt: endedAt, activeSeconds: active, completed: completed));
        }
        break;
      case RunKind.habit:
        final String? id = r.refId;
        final int seconds = completed ? r.totalMs ~/ 1000 : active;
        if (id != null && seconds >= 5 && habits.byId(id) != null) {
          habits.addValue(id, dateOnly(r.startedAt), seconds);
        }
        break;
      case RunKind.countdown:
        break;
    }
  }

  void _applyScreen() {
    final TimerRun? r = run;
    unawaited(screen.keepOn(settings.keepAwake && _foreground && r != null && !r.paused));
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }
}
