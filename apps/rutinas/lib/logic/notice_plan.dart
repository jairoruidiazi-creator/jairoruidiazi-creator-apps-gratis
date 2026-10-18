import 'dart:math' as math;

import '../core/dates.dart';
import '../model/habit.dart';
import '../model/reminder.dart';
import '../model/workout.dart';
import 'habit_logic.dart';
import 'recurrence.dart';
import 'timer_engine.dart';

/// Canal de una notificación: en Android define su sonido e importancia; en
/// iOS, el sonido.
enum NoticeChannel { reminders, countdowns, habits, timerBeep, timerBell, timerHorn, timerGong, timerSilent }

NoticeChannel timerChannelFor(CueSound sound) {
  switch (sound) {
    case CueSound.auto:
    case CueSound.beep:
      return NoticeChannel.timerBeep;
    case CueSound.bell:
      return NoticeChannel.timerBell;
    case CueSound.horn:
      return NoticeChannel.timerHorn;
    case CueSound.gong:
      return NoticeChannel.timerGong;
    case CueSound.none:
      return NoticeChannel.timerSilent;
  }
}

/// Botones de la notificación.
enum NoticeActions { none, reminder, habitCheck, habitCount }

/// Una notificación local que se va a programar.
class PlannedNotice {
  const PlannedNotice({required this.key, required this.when, required this.title, required this.body, required this.channel, required this.route, this.actions = NoticeActions.none, this.timeoutMs});

  /// Clave estable: la misma notificación tiene siempre la misma clave (y el
  /// mismo número), así se reemplaza en vez de duplicarse.
  final String key;
  final DateTime when;
  final String title;
  final String body;
  final NoticeChannel channel;

  /// A dónde lleva el toque: `reminder:<id>`, `habit:<id>:<día>` o `timer`.
  final String route;
  final NoticeActions actions;

  /// Android la quita sola pasado este tiempo (los cambios de intervalo, al
  /// llegar el siguiente).
  final int? timeoutMs;

  bool get isTimer => route == 'timer';

  /// Firma que se guarda como carga útil: si cambia la hora o el texto, se
  /// vuelve a programar; si no, se deja como está.
  String get payload => '$route|${when.millisecondsSinceEpoch}|${stableHash('$title\n$body\n${channel.name}\n${actions.name}')}';

  PlannedNotice withBody(String newBody) => PlannedNotice(key: key, when: when, title: title, body: newBody, channel: channel, route: route, actions: actions, timeoutMs: timeoutMs);
}

/// Hash FNV-1a de 31 bits, igual en todas las versiones de Dart.
int stableHash(String s) {
  int h = 0x811c9dc5;
  for (final int c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h & 0x7FFFFFFF;
}

/// Número de notificación (positivo de 31 bits) a partir de la clave.
int noticeIdFor(String key) {
  final int h = stableHash(key);
  return h == 0 ? 1 : h;
}

/// Ruta de una carga útil (`reminder:abc|123|456` → `reminder:abc`).
String routeOfPayload(String? payload) {
  if (payload == null) {
    return '';
  }
  final int bar = payload.indexOf('|');
  return bar < 0 ? payload : payload.substring(0, bar);
}

/// Cuántas notificaciones deja programar cada sistema: iOS guarda 64 en total
/// (se dejan 4 de margen); en Android cada una es una alarma y conviene no
/// pasar de unos cientos.
const int kIosNoticeBudget = 60;
const int kAndroidNoticeBudget = 240;

/// Repeticiones de un mismo aviso como máximo (60 = una hora si insiste cada minuto).
const int kMaxNags = 60;

class NoticePlanner {
  NoticePlanner._();

  static List<PlannedNotice> build({
    required DateTime now,
    required List<Reminder> reminders,
    required List<Habit> habits,
    required Map<String, Map<String, HabitEntry>> entries,
    required int weekStart,
    required bool spanish,
    TimerRun? backgroundRun,
    required int budget,
    Duration horizon = const Duration(days: 14),
  }) {
    String tr(String es, String en) => spanish ? es : en;
    final DateTime limit = now.add(horizon);
    // Margen para no programar algo que ya pasó mientras se calcula el plan.
    final DateTime soon = now.add(const Duration(seconds: 1));
    final List<PlannedNotice> all = <PlannedNotice>[];

    // ------------------------------------------------------------ recordatorios
    for (final Reminder r in reminders) {
      if (r.done) {
        continue;
      }
      final NoticeChannel channel = r.isCountdown ? NoticeChannel.countdowns : NoticeChannel.reminders;
      final String route = 'reminder:${r.id}';
      final String title = r.title.trim().isEmpty ? tr('Recordatorio', 'Reminder') : r.title.trim();
      // Ocurrencias: la actual (pospuesta o no) y, si se repite, las siguientes.
      final List<DateTime> alerts = <DateTime>[r.alertAt];
      final List<DateTime> dues = <DateTime>[r.dueAt];
      if (r.recurrence.repeats) {
        for (final DateTime d in Recurrences.upcoming(r.recurrence, r.dueAt, r.dueAt, 30)) {
          if (d.isAfter(limit)) {
            break;
          }
          alerts.add(d);
          dues.add(d);
        }
      }
      for (int k = 0; k < alerts.length; k++) {
        final DateTime alert = alerts[k];
        final DateTime? nextAlert = k + 1 < alerts.length ? alerts[k + 1] : null;
        final String when = formatTime(dues[k], spanish: spanish);
        String body;
        if (r.isCountdown) {
          body = tr('Se cumplió la cuenta regresiva de ${formatDurationShort(r.countdownSeconds, spanish: true)}.', 'Your ${formatDurationShort(r.countdownSeconds, spanish: false)} countdown is up.');
        } else if (r.notes.trim().isNotEmpty) {
          body = r.notes.trim();
        } else {
          body = tr('Para las $when', 'Due at $when');
        }
        // Repeticiones hasta la siguiente ocurrencia; en Android cada una quita
        // la anterior del panel (se borra sola al llegar la siguiente).
        final List<DateTime> nags = <DateTime>[];
        for (int j = 1; r.nagMinutes > 0 && j <= kMaxNags; j++) {
          final DateTime t = alert.add(Duration(minutes: r.nagMinutes * j));
          if (t.isAfter(limit) || (nextAlert != null && !t.isBefore(nextAlert))) {
            break;
          }
          nags.add(t);
        }
        final int nagMs = r.nagMinutes * 60 * 1000;
        if (alert.isAfter(soon) && !alert.isAfter(limit)) {
          all.add(PlannedNotice(key: 'r:${r.id}:${alert.millisecondsSinceEpoch}', when: alert, title: title, body: body, channel: channel, route: route, actions: NoticeActions.reminder, timeoutMs: nags.isEmpty ? null : nagMs));
        }
        final String nagBody = r.isCountdown ? tr('Sigue sonando hasta que toques Hecho.', 'It keeps ringing until you tap Done.') : tr('Sigue pendiente desde las ${formatTime(alert, spanish: true)}. Toca Hecho para que deje de sonar.', 'Still pending since ${formatTime(alert, spanish: false)}. Tap Done to stop the alerts.');
        for (int j = 0; j < nags.length; j++) {
          final DateTime t = nags[j];
          if (!t.isAfter(soon)) {
            continue;
          }
          all.add(PlannedNotice(key: 'n:${r.id}:${t.millisecondsSinceEpoch}', when: t, title: title, body: nagBody, channel: channel, route: route, actions: NoticeActions.reminder, timeoutMs: j + 1 < nags.length ? nagMs : null));
        }
      }
    }

    // ------------------------------------------------------------------ hábitos
    final DateTime today = dateOnly(now);
    for (final Habit h in habits) {
      if (h.archived || h.reminders.isEmpty) {
        continue;
      }
      final Map<String, HabitEntry> e = entries[h.id] ?? const <String, HabitEntry>{};
      final List<int> times = List<int>.of(h.reminders)..sort();
      for (int dayOffset = 0; dayOffset <= 7; dayOffset++) {
        final DateTime day = addDays(today, dayOffset);
        if (!HabitLogic.isDueOn(h, e, day, today, weekStart: weekStart)) {
          continue;
        }
        final HabitEntry? entry = e[dayKey(day)];
        if (!h.isNegative && (HabitLogic.isDone(h, entry) || (entry != null && entry.skipped))) {
          continue;
        }
        final String route = 'habit:${h.id}:${dayKey(day)}';
        final String body = _habitBody(h, e, entry, day, today, weekStart, spanish);
        NoticeActions actions = NoticeActions.none;
        if (h.kind == HabitKind.check) {
          actions = NoticeActions.habitCheck;
        } else if (h.kind == HabitKind.count) {
          actions = NoticeActions.habitCount;
        }
        for (int i = 0; i < times.length; i++) {
          final DateTime at = DateTime(day.year, day.month, day.day, times[i] ~/ 60, times[i] % 60);
          // Insiste hasta el siguiente aviso del día o hasta medianoche.
          final DateTime stop = i + 1 < times.length ? DateTime(day.year, day.month, day.day, times[i + 1] ~/ 60, times[i + 1] % 60) : addDays(day, 1);
          final List<DateTime> nags = <DateTime>[];
          for (int j = 1; h.nagMinutes > 0 && !h.isNegative && j <= kMaxNags; j++) {
            final DateTime t = at.add(Duration(minutes: h.nagMinutes * j));
            if (!t.isBefore(stop) || t.isAfter(limit)) {
              break;
            }
            nags.add(t);
          }
          final int nagMs = h.nagMinutes * 60 * 1000;
          if (at.isAfter(soon) && !at.isAfter(limit)) {
            all.add(PlannedNotice(key: 'h:${h.id}:${at.millisecondsSinceEpoch}', when: at, title: h.name, body: body, channel: NoticeChannel.habits, route: route, actions: actions, timeoutMs: nags.isEmpty ? null : nagMs));
          }
          final String nagBody = tr('Todavía no lo has marcado hoy.', 'You have not checked it off today.');
          for (int j = 0; j < nags.length; j++) {
            final DateTime t = nags[j];
            if (!t.isAfter(soon)) {
              continue;
            }
            all.add(PlannedNotice(key: 'g:${h.id}:${t.millisecondsSinceEpoch}', when: t, title: h.name, body: nagBody, channel: NoticeChannel.habits, route: route, actions: actions, timeoutMs: j + 1 < nags.length ? nagMs : null));
          }
        }
      }
    }

    // ------------------------------------------------- temporizador en segundo plano
    final List<PlannedNotice> timer = <PlannedNotice>[];
    final TimerRun? run = backgroundRun;
    if (run != null && !run.paused && run.segments.isNotEmpty) {
      final RunSnapshot snap = run.snapshot(now);
      if (!snap.finished) {
        if (run.kind == RunKind.workout) {
          for (int i = snap.index + 1; i < run.segments.length; i++) {
            final TimerSegment seg = run.segments[i];
            final DateTime at = run.wallTimeOf(run.startOf(i));
            if (!at.isAfter(soon)) {
              continue;
            }
            final List<String> parts = <String>[formatClock(seg.seconds)];
            if (seg.rounds.isNotEmpty) {
              final RoundInfo inner = seg.rounds.last;
              parts.add(tr('ronda ${inner.index} de ${inner.total}', 'round ${inner.index} of ${inner.total}'));
            }
            if (i + 1 < run.segments.length) {
              parts.add(tr('sigue: ${run.segments[i + 1].name}', 'next: ${run.segments[i + 1].name}'));
            }
            final String title = seg.name.trim().isEmpty ? tr('Intervalo ${i + 1}', 'Interval ${i + 1}') : seg.name;
            timer.add(PlannedNotice(key: 't:$i', when: at, title: title, body: parts.join(' · '), channel: timerChannelFor(seg.sound), route: 'timer', timeoutMs: seg.ms));
          }
        }
        final DateTime end = run.wallTimeOf(run.totalMs);
        if (end.isAfter(soon)) {
          String title;
          String body;
          switch (run.kind) {
            case RunKind.workout:
              title = tr('¡Terminaste!', 'Done!');
              body = tr('${run.name}: ${formatClock(run.totalMs ~/ 1000)} de entrenamiento.', '${run.name}: ${formatClock(run.totalMs ~/ 1000)} of training.');
              break;
            case RunKind.countdown:
              title = tr('Se acabó el tiempo', 'Time is up');
              body = run.name;
              break;
            case RunKind.habit:
              title = tr('¡Listo!', 'All done!');
              body = tr('${run.name}: ${formatDurationShort(run.totalMs ~/ 1000, spanish: true)}.', '${run.name}: ${formatDurationShort(run.totalMs ~/ 1000, spanish: false)}.');
              break;
          }
          timer.add(PlannedNotice(key: 'te', when: end, title: title, body: body, channel: timerChannelFor(run.finishSound), route: 'timer'));
        }
      }
    }
    all.addAll(timer);

    all.sort((PlannedNotice a, PlannedNotice b) {
      final int c = a.when.compareTo(b.when);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
    if (all.length <= budget) {
      return all;
    }
    final List<PlannedNotice> kept = all.sublist(0, math.max(0, budget));
    // Si no cupieron todos los cambios del temporizador, el último que cupo lo dice.
    final int lastTimer = kept.lastIndexWhere((PlannedNotice n) => n.isTimer);
    if (lastTimer >= 0 && kept.where((PlannedNotice n) => n.isTimer).length < timer.length) {
      kept[lastTimer] = kept[lastTimer].withBody('${kept[lastTimer].body}\n${tr('Abre Rutinas para seguir recibiendo los avisos del temporizador.', 'Open Rutinas to keep getting timer alerts.')}');
    }
    return kept;
  }

  static String _habitBody(Habit h, Map<String, HabitEntry> e, HabitEntry? entry, DateTime day, DateTime today, int weekStart, bool spanish) {
    String tr(String es, String en) => spanish ? es : en;
    final int value = entry?.value ?? 0;
    switch (h.kind) {
      case HabitKind.check:
        return tr('¿Ya lo hiciste hoy?', 'Have you done it today?');
      case HabitKind.count:
        final String unit = h.unit.trim().isEmpty ? tr('veces', 'times') : h.unit.trim();
        return value == 0 ? tr('Meta de hoy: ${h.goal} $unit.', 'Today\'s goal: ${h.goal} $unit.') : tr('Llevas $value de ${h.goal} $unit.', '$value of ${h.goal} $unit so far.');
      case HabitKind.timed:
        final int left = math.max(0, h.target - value);
        return tr('Te faltan ${formatDurationShort(left, spanish: true)}. Toca para abrir el temporizador.', '${formatDurationShort(left, spanish: false)} to go. Tap to open the timer.');
      case HabitKind.negative:
        final int days = HabitLogic.negativeStreak(h, e, day.isAfter(today) ? day : today).current;
        return tr('Llevas $days ${days == 1 ? 'día' : 'días'} sin recaer. ¡Sigue así!', '$days ${days == 1 ? 'day' : 'days'} without a slip. Keep going!');
    }
  }
}
