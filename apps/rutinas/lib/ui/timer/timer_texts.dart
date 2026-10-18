import '../../core/dates.dart';
import '../../logic/timer_engine.dart';
import '../../model/workout.dart';

/// Textos del temporizador en español e inglés.
class TimerTexts {
  TimerTexts._();

  static String kind(StepKind k, bool es) {
    switch (k) {
      case StepKind.prepare:
        return es ? 'Preparación' : 'Get ready';
      case StepKind.warmup:
        return es ? 'Calentamiento' : 'Warm-up';
      case StepKind.work:
        return es ? 'Trabajo' : 'Work';
      case StepKind.rest:
        return es ? 'Descanso' : 'Rest';
      case StepKind.cooldown:
        return es ? 'Enfriamiento' : 'Cool-down';
    }
  }

  static String sound(CueSound s, bool es) {
    switch (s) {
      case CueSound.auto:
        return es ? 'Según el tipo' : 'By type';
      case CueSound.beep:
        return es ? 'Pitido' : 'Beep';
      case CueSound.bell:
        return es ? 'Campana' : 'Bell';
      case CueSound.horn:
        return es ? 'Bocina' : 'Horn';
      case CueSound.gong:
        return 'Gong';
      case CueSound.none:
        return es ? 'Sin sonido' : 'No sound';
    }
  }

  static String template(WorkoutTemplate t, bool es) {
    switch (t) {
      case WorkoutTemplate.hiit:
        return 'HIIT';
      case WorkoutTemplate.tabata:
        return 'Tabata';
      case WorkoutTemplate.circuit:
        return es ? 'Circuito' : 'Circuit';
      case WorkoutTemplate.custom:
        return es ? 'Personalizado' : 'Custom';
    }
  }

  static String templateHelp(WorkoutTemplate t, bool es) {
    switch (t) {
      case WorkoutTemplate.hiit:
        return es ? 'Calentamiento, 10 rondas de 30 s de trabajo y 30 s de descanso, y enfriamiento.' : 'Warm-up, 10 rounds of 30 s work and 30 s rest, and a cool-down.';
      case WorkoutTemplate.tabata:
        return es ? '4 series de 8 rondas de 20 s de trabajo y 10 s de descanso, con 1 min entre series.' : '4 sets of 8 rounds of 20 s work and 10 s rest, with 1 min between sets.';
      case WorkoutTemplate.circuit:
        return es ? '3 rondas de 4 ejercicios de 45 s, con 15 s de descanso entre ejercicios y 1 min entre rondas.' : '3 rounds of 4 exercises of 45 s, with 15 s rests between exercises and 1 min between rounds.';
      case WorkoutTemplate.custom:
        return es ? 'Empieza con un intervalo y arma tus bloques.' : 'Start with one interval and build your own blocks.';
    }
  }

  /// Nombre de una vuelta: el del bloque, o Ronda / Serie / Bloque según el
  /// nivel contado desde adentro.
  static String roundLabel(RoundInfo r, int levelFromInside, bool es) {
    if (r.label.trim().isNotEmpty) {
      return r.label.trim();
    }
    switch (levelFromInside) {
      case 0:
        return es ? 'Ronda' : 'Round';
      case 1:
        return es ? 'Serie' : 'Set';
      default:
        return es ? 'Bloque' : 'Block';
    }
  }

  /// "Ronda 3 de 8 · Serie 2 de 4" (de adentro hacia afuera).
  static String rounds(List<RoundInfo> rounds, bool es) {
    final List<String> parts = <String>[];
    for (int i = rounds.length - 1; i >= 0; i--) {
      final RoundInfo r = rounds[i];
      parts.add(es ? '${roundLabel(r, rounds.length - 1 - i, true)} ${r.index} de ${r.total}' : '${roundLabel(r, rounds.length - 1 - i, false)} ${r.index} of ${r.total}');
    }
    return parts.join(' · ');
  }

  /// "18:30 · 37 intervalos".
  static String summary(List<TimerSegment> segments, bool es) {
    final int total = TimerEngine.totalSeconds(segments);
    final int n = segments.length;
    return es ? '${formatClock(total)} · $n ${n == 1 ? 'intervalo' : 'intervalos'}' : '${formatClock(total)} · $n ${n == 1 ? 'interval' : 'intervals'}';
  }
}
