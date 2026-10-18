import 'dart:math' as math;

import '../core/storage.dart';
import '../logic/stopwatch.dart';
import '../logic/timer_engine.dart';
import '../model/workout.dart';
import 'persistent.dart';

/// Entrenamientos, cuentas atrás guardadas, cronómetro, historial y el
/// temporizador en marcha (`timers.json`).
class TimerStore extends PersistentStore {
  TimerStore(JsonStore store) : super(store, 'timers.json');

  final List<Workout> workouts = <Workout>[];
  final List<CountdownPreset> presets = <CountdownPreset>[];
  final List<WorkoutSession> sessions = <WorkoutSession>[];
  StopwatchState stopwatch = StopwatchState();

  /// Temporizador en marcha (se guarda para seguir si el sistema cierra la app).
  TimerRun? run;

  /// Última cuenta regresiva libre que se usó, en segundos.
  int lastCountdownSeconds = 300;

  List<Workout> get sortedWorkouts {
    final List<Workout> list = List<Workout>.of(workouts);
    list.sort((Workout a, Workout b) => a.order.compareTo(b.order));
    return list;
  }

  Workout? workoutById(String id) {
    for (final Workout w in workouts) {
      if (w.id == id) {
        return w;
      }
    }
    return null;
  }

  void addWorkout(Workout w) {
    w.order = workouts.isEmpty ? 0 : workouts.map((Workout x) => x.order).reduce(math.max) + 1;
    workouts.add(w);
    changed();
  }

  void updateWorkout(Workout w) {
    final int i = workouts.indexWhere((Workout x) => x.id == w.id);
    if (i < 0) {
      addWorkout(w);
      return;
    }
    workouts[i] = w;
    changed();
  }

  void removeWorkout(String id) {
    workouts.removeWhere((Workout w) => w.id == id);
    changed();
  }

  void addPreset(CountdownPreset p) {
    presets.add(p);
    presets.sort((CountdownPreset a, CountdownPreset b) => a.seconds.compareTo(b.seconds));
    changed();
  }

  void removePreset(String id) {
    presets.removeWhere((CountdownPreset p) => p.id == id);
    changed();
  }

  void addSession(WorkoutSession s) {
    sessions.add(s);
    // Se guardan los últimos dos años de entrenamientos (de sobra para los resúmenes).
    if (sessions.length > 3000) {
      sessions.removeRange(0, sessions.length - 3000);
    }
    changed();
  }

  @override
  void reset() {
    workouts.clear();
    presets.clear();
    sessions.clear();
    stopwatch = StopwatchState();
    run = null;
    lastCountdownSeconds = 300;
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'workouts': workouts.map((Workout w) => w.toJson()).toList(),
        'presets': presets.map((CountdownPreset p) => p.toJson()).toList(),
        'sessions': sessions.map((WorkoutSession s) => s.toJson()).toList(),
        'stopwatch': stopwatch.toJson(),
        'run': run?.toJson(),
        'lastCountdown': lastCountdownSeconds,
      };

  /// Reemplaza lo que viaja en las copias por lo de [other] (al restaurar una
  /// copia ya leída entera). El cronómetro y el temporizador en marcha se quedan.
  void replaceBackupWith(TimerStore other) {
    workouts
      ..clear()
      ..addAll(other.workouts);
    presets
      ..clear()
      ..addAll(other.presets);
    sessions
      ..clear()
      ..addAll(other.sessions);
    lastCountdownSeconds = other.lastCountdownSeconds;
    damagedCopy = null;
    changed();
    flush();
  }

  /// Lo que viaja en la copia de seguridad: sin el temporizador en marcha.
  Map<String, dynamic> toBackupJson() {
    final Map<String, dynamic> j = toJson();
    j.remove('run');
    j.remove('stopwatch');
    return j;
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    final Object? w = json['workouts'];
    if (w is List) {
      workouts.addAll(w.whereType<Map<String, dynamic>>().map(Workout.fromJson));
    }
    final Object? p = json['presets'];
    if (p is List) {
      presets.addAll(p.whereType<Map<String, dynamic>>().map(CountdownPreset.fromJson));
    }
    final Object? s = json['sessions'];
    if (s is List) {
      sessions.addAll(s.whereType<Map<String, dynamic>>().map(WorkoutSession.fromJson));
    }
    final Object? sw = json['stopwatch'];
    if (sw is Map<String, dynamic>) {
      stopwatch = StopwatchState.fromJson(sw);
    }
    final Object? r = json['run'];
    if (r is Map<String, dynamic>) {
      run = TimerRun.fromJson(r);
    }
    lastCountdownSeconds = ((json['lastCountdown'] as num?)?.toInt() ?? 300).clamp(1, 24 * 3600);
  }
}
