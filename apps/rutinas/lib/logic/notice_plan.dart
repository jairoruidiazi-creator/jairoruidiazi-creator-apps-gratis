import 'dart:math' as math;

import '../core/dates.dart';
import '../model/habit.dart';
import '../model/reminder.dart';
import '../model/workout.dart';
import 'habit_logic.dart';
import 'recurrence.dart';
import 'timer_engine.dart';

/// Canal de una notificación: en Android define su sonido, su vibración y su
/// importancia; en iOS, el sonido.
enum NoticeChannel {
  reminders,
  countdowns,
  habits,
  timerBeep,
  timerBell,
  timerHorn,
  timerGong,
  timerBeepNoVibration,
  timerBellNoVibration,
  timerHornNoVibration,
  timerGongNoVibration,

  /// Sin sonido y con vibración: sonidos apagados en Ajustes o intervalo sin sonido.
  timerVibrate,

  /// Ni sonido ni vibración.
  timerSilent,
}

/// Canal de un aviso del temporizador según su sonido y los ajustes de
/// sonido y vibración del temporizador.
NoticeChannel timerChannelFor(CueSound sound, {bool sounds = true, bool vibration = true}) {
  if (!sounds) {
    return vibration ? NoticeChannel.timerVibrate : NoticeChannel.timerSilent;
  }
  switch (sound) {
    case CueSound.auto:
    case CueSound.beep:
      return vibration ? NoticeChannel.timerBeep : NoticeChannel.timerBeepNoVibration;
    case CueSound.bell:
      return vibration ? NoticeChannel.timerBell : NoticeChannel.timerBellNoVibration;
    case CueSound.horn:
      return vibration ? NoticeChannel.timerHorn : NoticeChannel.timerHornNoVibration;
    case CueSound.gong:
      return vibration ? NoticeChannel.timerGong : NoticeChannel.timerGongNoVibration;
    case CueSound.none:
      return vibration ? NoticeChannel.timerVibrate : NoticeChannel.timerSilent;
  }
}

/// Botones de la notificación.
enum NoticeActions { none, reminder, habitCheck, habitCount, habitTimed }

/// Qué es cada aviso del plan.
/// - first: el primer aviso de una ocurrencia (un recordatorio o la hora de un hábito).
/// - nag: una repetición (insistencia) de la ocurrencia más próxima.
/// - repeating: una sola solicitud que se repite, para la ocurrencia ya vencida.
/// - timer: un cambio de intervalo o el final del temporizador.
/// - coverage: el aviso honesto cuando el cupo no alcanza para todo el horizonte.
enum NoticeKind { first, nag, repeating, timer, coverage }

/// Una notificación local que se va a programar.
class PlannedNotice {
  const PlannedNotice({
    required this.key,
    required this.when,
    required this.title,
    required this.body,
    required this.channel,
    required this.route,
    this.actions = NoticeActions.none,
    this.timeoutMs,
    this.occurrence,
    this.repeatEvery,
    this.kind = NoticeKind.first,
    this.urgent = false,
    this.segment,
  });

  /// Clave estable: la misma notificación tiene siempre la misma clave (y el
  /// mismo número), así se reemplaza en vez de duplicarse.
  final String key;

  /// Primera vez que suena.
  final DateTime when;
  final String title;
  final String body;
  final NoticeChannel channel;

  /// A dónde lleva el toque: `reminder:<id>`, `habit:<id>:<día>` o `timer`.
  final String route;
  final NoticeActions actions;

  /// Android la quita sola pasado este tiempo: al llegar el siguiente aviso del
  /// mismo elemento. Se calcula después de recortar al cupo.
  final int? timeoutMs;

  /// Ocurrencia a la que pertenece (la hora del recordatorio o la del aviso del
  /// hábito): los botones de una notificación vieja solo afectan a la suya.
  final DateTime? occurrence;

  /// Se repite cada tanto hasta que se cancela (insistencia de una ocurrencia vencida).
  final Duration? repeatEvery;
  final NoticeKind kind;

  /// En iOS se marca «sensible al tiempo»: si el usuario lo permite, pasa por
  /// encima de los modos de concentración y del resumen programado.
  final bool urgent;

  /// Intervalo que empieza (avisos del temporizador).
  final int? segment;

  bool get isTimer => route == 'timer';

  /// Elemento al que pertenece (sin el día en los hábitos).
  String get element {
    if (route.startsWith('habit:')) {
      final int second = route.indexOf(':', 6);
      return second < 0 ? route : route.substring(0, second);
    }
    return route;
  }

  /// Carga útil: `ruta|ocurrencia|hora|firma`. La firma resume lo que se ve y
  /// cómo se programa (también si es una alarma exacta): si algo cambia, se
  /// vuelve a programar; si no, se deja como está. Una solicitud que se repite
  /// no lleva su hora, que depende de cuándo se programó.
  String payload({required bool exact}) {
    final String time = repeatEvery == null ? '${when.millisecondsSinceEpoch}' : 'cada${repeatEvery!.inSeconds}';
    final String sig = '$title\n$body\n${channel.name}\n${actions.name}\n${timeoutMs ?? ''}\n${urgent ? 1 : 0}\n${exact ? 'exacta' : 'inexacta'}';
    return '$route|${occurrence?.millisecondsSinceEpoch ?? ''}|$time|${stableHash(sig)}';
  }

  PlannedNotice copyWith({String? body, int? timeoutMs, bool clearTimeout = false}) => PlannedNotice(
        key: key,
        when: when,
        title: title,
        body: body ?? this.body,
        channel: channel,
        route: route,
        actions: actions,
        timeoutMs: clearTimeout ? null : (timeoutMs ?? this.timeoutMs),
        occurrence: occurrence,
        repeatEvery: repeatEvery,
        kind: kind,
        urgent: urgent,
        segment: segment,
      );
}

/// Lo que trae la carga útil de una notificación.
class NoticePayload {
  const NoticePayload({required this.route, this.occurrence});

  final String route;
  final DateTime? occurrence;

  factory NoticePayload.parse(String? payload) {
    if (payload == null || payload.isEmpty) {
      return const NoticePayload(route: '');
    }
    final List<String> parts = payload.split('|');
    final int? occ = parts.length > 1 ? int.tryParse(parts[1]) : null;
    return NoticePayload(route: parts.first, occurrence: occ == null ? null : DateTime.fromMillisecondsSinceEpoch(occ));
  }
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

/// Ruta de una carga útil (`reminder:abc|123|456|789` → `reminder:abc`).
String routeOfPayload(String? payload) => NoticePayload.parse(payload).route;

/// Cuánto deja programar cada sistema y cómo se reparte.
class NoticeLimits {
  const NoticeLimits({required this.budget, required this.nagCap, required this.guaranteed});

  /// Notificaciones programadas a la vez, como mucho (las que se repiten cuentan una).
  final int budget;

  /// Repeticiones de la ocurrencia más próxima de cada recordatorio o hábito
  /// cuando la app no está abierta para seguir insistiendo.
  final int nagCap;

  /// Ventana en que los primeros avisos van antes que cualquier repetición.
  final Duration guaranteed;

  /// Cambios de intervalo que caben con la pantalla bloqueada: todo el cupo
  /// menos un hueco para el aviso de cobertura.
  int get timerCapacity => budget - 1;
}

/// iOS guarda 64 notificaciones programadas por app (se usan 60). Con 6
/// repeticiones por elemento, la demo de la tienda (seis hábitos y ocho
/// recordatorios, cinco de ellos con insistencia) sigue cubriendo una semana.
const NoticeLimits kIosLimits = NoticeLimits(budget: 60, nagCap: 6, guaranteed: Duration(days: 3));

/// En Android cada aviso es una alarma: 240 cubren dos semanas con un uso
/// intenso y caben 30 repeticiones por elemento.
const NoticeLimits kAndroidLimits = NoticeLimits(budget: 240, nagCap: 30, guaranteed: Duration(days: 7));

/// El plan que se programa.
class NoticePlan {
  const NoticePlan({this.notices = const <PlannedNotice>[], this.coveredUntil, this.timerLastCovered});

  final List<PlannedNotice> notices;

  /// Hora del primer aviso que no cupo en el cupo del sistema: hasta ahí
  /// llegan los avisos si no se vuelve a abrir la app (a esa hora suena el
  /// aviso de cobertura). Null si cupo todo el horizonte.
  final DateTime? coveredUntil;

  /// Si no cupieron todos los cambios del temporizador, el último intervalo
  /// cuyo inicio sí avisa.
  final int? timerLastCovered;
}

int _kindOrder(NoticeKind k) {
  switch (k) {
    case NoticeKind.timer:
      return 0;
    case NoticeKind.first:
      return 1;
    case NoticeKind.repeating:
      return 2;
    case NoticeKind.nag:
      return 3;
    case NoticeKind.coverage:
      return 4;
  }
}

int _byTime(PlannedNotice a, PlannedNotice b) {
  final int c = a.when.compareTo(b.when);
  if (c != 0) {
    return c;
  }
  final int k = _kindOrder(a.kind).compareTo(_kindOrder(b.kind));
  return k != 0 ? k : a.key.compareTo(b.key);
}

class NoticePlanner {
  NoticePlanner._();

  /// Arma el plan. El cupo se reparte por prioridad:
  /// 1. Con un entrenamiento en segundo plano, sus cambios de intervalo (si no
  ///    caben todos, el último que cabe pide abrir la app).
  /// 2. Las solicitudes que se repiten de las ocurrencias ya vencidas y los
  ///    primeros avisos de los próximos [NoticeLimits.guaranteed].
  /// 3. Por orden de hora, las repeticiones de la ocurrencia más próxima de
  ///    cada elemento (hasta [NoticeLimits.nagCap]) y los primeros avisos
  ///    posteriores.
  /// Si se queda afuera algún primer aviso, el último hueco es un aviso honesto
  /// a la hora del primero que no cupo.
  static NoticePlan build({
    required DateTime now,
    required List<Reminder> reminders,
    required List<Habit> habits,
    required Map<String, Map<String, HabitEntry>> entries,
    required int weekStart,
    required bool spanish,
    required NoticeLimits limits,
    TimerRun? backgroundRun,
    bool sounds = true,
    bool vibration = true,
    Duration horizon = const Duration(days: 14),
  }) {
    String tr(String es, String en) => spanish ? es : en;
    final DateTime limit = now.add(horizon);
    // Margen para no programar algo que ya pasó mientras se calcula el plan.
    final DateTime soon = now.add(const Duration(seconds: 1));
    final List<PlannedNotice> cands = <PlannedNotice>[];

    // ------------------------------------------------------------ recordatorios
    for (final Reminder r in reminders) {
      if (r.done) {
        continue;
      }
      final NoticeChannel channel = r.isCountdown ? NoticeChannel.countdowns : NoticeChannel.reminders;
      final String route = 'reminder:${r.id}';
      final String title = r.title.trim().isEmpty ? tr('Recordatorio', 'Reminder') : r.title.trim();
      // Ocurrencias: la actual (con su aviso, pospuesto o no) y las siguientes.
      final List<DateTime> dues = <DateTime>[r.dueAt];
      final List<DateTime> alerts = <DateTime>[r.alertAt];
      if (r.recurrence.repeats) {
        final DateTime from = r.alertAt.isAfter(r.dueAt) ? r.alertAt : r.dueAt;
        for (final DateTime d in Recurrences.upcoming(r.recurrence, r.dueAt, from, 40)) {
          if (d.isAfter(limit)) {
            break;
          }
          dues.add(d);
          alerts.add(d);
        }
      }
      for (int k = 0; k < alerts.length; k++) {
        final DateTime alert = alerts[k];
        if (alert.isAfter(soon) && !alert.isAfter(limit)) {
          cands.add(PlannedNotice(
            key: 'r:${r.id}:${alert.millisecondsSinceEpoch}',
            when: alert,
            title: title,
            body: _reminderBody(r, dues[k], spanish),
            channel: channel,
            route: route,
            actions: NoticeActions.reminder,
            occurrence: dues[k],
            urgent: true,
          ));
        }
      }
      if (r.nagMinutes <= 0) {
        continue;
      }
      // Insistencia de la ocurrencia más próxima (la actual).
      final Duration every = Duration(minutes: r.nagMinutes);
      final DateTime alert = alerts.first;
      if (!alert.isAfter(now)) {
        // Ya sonó: una sola solicitud que se repite hasta que se marque hecho.
        cands.add(PlannedNotice(
          key: 'p:${r.id}:${r.dueAt.millisecondsSinceEpoch}',
          when: now.add(every),
          title: title,
          body: _nagBody(r, alert, spanish, repeating: true),
          channel: channel,
          route: route,
          actions: NoticeActions.reminder,
          occurrence: r.dueAt,
          repeatEvery: every,
          kind: NoticeKind.repeating,
          urgent: true,
        ));
      } else {
        // Todavía no suena: repeticiones sueltas, nunca más allá de la siguiente ocurrencia.
        final DateTime? next = alerts.length > 1 ? alerts[1] : null;
        for (int j = 1; j <= limits.nagCap; j++) {
          final DateTime t = alert.add(every * j);
          if (t.isAfter(limit) || (next != null && !t.isBefore(next))) {
            break;
          }
          cands.add(PlannedNotice(
            key: 'n:${r.id}:${t.millisecondsSinceEpoch}',
            when: t,
            title: title,
            body: _nagBody(r, alert, spanish, repeating: false),
            channel: channel,
            route: route,
            actions: NoticeActions.reminder,
            occurrence: r.dueAt,
            kind: NoticeKind.nag,
            urgent: true,
          ));
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
      final NoticeActions actions = _habitActions(h);
      // Solo insiste la ocurrencia más próxima que todavía puede insistir. Los
      // hábitos no usan la solicitud que se repite: su insistencia termina sola
      // en el siguiente aviso del día o a medianoche.
      bool nagged = h.nagMinutes <= 0 || h.isNegative;
      for (int dayOffset = 0; dayOffset <= 7; dayOffset++) {
        final DateTime day = addDays(today, dayOffset);
        if (!HabitLogic.isDueOn(h, e, day, today, weekStart: weekStart)) {
          continue;
        }
        final HabitEntry? entry = e[dayKey(day)];
        if (!h.isNegative && (HabitLogic.isDone(h, entry, day) || (entry != null && entry.skipped))) {
          continue;
        }
        final String route = 'habit:${h.id}:${dayKey(day)}';
        final String body = _habitBody(h, e, entry, day, today, weekStart, spanish);
        for (int i = 0; i < times.length; i++) {
          final DateTime at = DateTime(day.year, day.month, day.day, times[i] ~/ 60, times[i] % 60);
          // Insiste hasta el siguiente aviso del día o hasta medianoche.
          final DateTime stop = i + 1 < times.length ? DateTime(day.year, day.month, day.day, times[i + 1] ~/ 60, times[i + 1] % 60) : addDays(day, 1);
          if (at.isAfter(soon) && !at.isAfter(limit)) {
            cands.add(PlannedNotice(key: 'h:${h.id}:${at.millisecondsSinceEpoch}', when: at, title: h.name, body: body, channel: NoticeChannel.habits, route: route, actions: actions, occurrence: at));
          }
          if (nagged || !stop.isAfter(soon)) {
            continue;
          }
          final Duration every = Duration(minutes: h.nagMinutes);
          int j = 1;
          if (soon.isAfter(at)) {
            j = math.max(1, soon.difference(at).inMicroseconds ~/ every.inMicroseconds + 1);
          }
          int count = 0;
          for (; count < limits.nagCap; j++) {
            final DateTime t = at.add(every * j);
            if (!t.isBefore(stop) || t.isAfter(limit)) {
              break;
            }
            if (!t.isAfter(soon)) {
              continue;
            }
            cands.add(PlannedNotice(
              key: 'g:${h.id}:${t.millisecondsSinceEpoch}',
              when: t,
              title: h.name,
              body: tr('Todavía no lo has marcado hoy.', 'You have not checked it off today.'),
              channel: NoticeChannel.habits,
              route: route,
              actions: actions,
              occurrence: at,
              kind: NoticeKind.nag,
            ));
            count++;
          }
          if (count > 0) {
            nagged = true;
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
            timer.add(PlannedNotice(key: 't:$i', when: at, title: title, body: parts.join(' · '), channel: timerChannelFor(seg.sound, sounds: sounds, vibration: vibration), route: 'timer', kind: NoticeKind.timer, urgent: true, segment: i));
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
          timer.add(PlannedNotice(key: 'te', when: end, title: title, body: body, channel: timerChannelFor(run.finishSound, sounds: sounds, vibration: vibration), route: 'timer', kind: NoticeKind.timer, urgent: true));
        }
      }
    }

    // ------------------------------------------------------------------- cupo
    timer.sort(_byTime);
    final List<PlannedNotice> timerKept = timer.length > limits.timerCapacity ? timer.sublist(0, limits.timerCapacity) : List<PlannedNotice>.of(timer);
    int? timerLastCovered;
    if (timerKept.length < timer.length && timerKept.isNotEmpty) {
      // El último cambio que cabe lo dice (y no se borra solo: se calcula abajo).
      final PlannedNotice last = timerKept.last;
      timerKept[timerKept.length - 1] = last.copyWith(body: '${last.body}\n${tr('Abre Rutinas para seguir recibiendo los avisos del temporizador.', 'Open Rutinas to keep getting timer alerts.')}');
      timerLastCovered = last.segment;
    }
    final int room = limits.budget - timerKept.length;
    cands.sort(_byTime);
    List<PlannedNotice> chosen;
    PlannedNotice? lost;
    if (cands.length <= room) {
      chosen = cands;
    } else {
      final DateTime edge = now.add(limits.guaranteed);
      bool guaranteed(PlannedNotice n) => n.kind == NoticeKind.repeating || (n.kind == NoticeKind.first && !n.when.isAfter(edge));
      final List<PlannedNotice> tierA = cands.where(guaranteed).toList();
      final List<PlannedNotice> tierB = cands.where((PlannedNotice n) => !guaranteed(n)).toList();
      // El último hueco es para el aviso honesto.
      final int space = math.max(0, room - 1);
      final List<PlannedNotice> dropped = <PlannedNotice>[];
      if (tierA.length > space) {
        chosen = tierA.sublist(0, space);
        dropped
          ..addAll(tierA.sublist(space))
          ..addAll(tierB);
      } else {
        final int rest = space - tierA.length;
        chosen = <PlannedNotice>[...tierA, ...tierB.take(rest)];
        dropped.addAll(tierB.skip(rest));
      }
      for (final PlannedNotice n in dropped) {
        if (n.kind == NoticeKind.first && (lost == null || n.when.isBefore(lost.when))) {
          lost = n;
        }
      }
      final PlannedNotice? firstLost = lost;
      if (firstLost == null) {
        // Solo quedaron afuera repeticiones: el hueco reservado sirve para una más.
        if (dropped.isNotEmpty && chosen.length < room) {
          chosen.add(dropped.first);
        }
      } else {
        // Lo que iba a sonar después del primer aviso perdido no sirve: antes
        // llega el aviso honesto, y al abrir la app se vuelve a planear.
        chosen = chosen.where((PlannedNotice n) => n.when.isBefore(firstLost.when)).toList();
        if (chosen.length < room) {
          chosen.add(PlannedNotice(
            key: 'cov',
            when: firstLost.when,
            title: firstLost.title,
            body: tr('Abre Rutinas para que este y tus próximos avisos sigan llegando.', 'Open Rutinas so this alert and your next ones keep arriving.'),
            channel: firstLost.channel,
            route: firstLost.route,
            occurrence: firstLost.occurrence,
            kind: NoticeKind.coverage,
            urgent: firstLost.urgent,
          ));
        }
      }
    }
    final List<PlannedNotice> all = <PlannedNotice>[...timerKept, ...chosen]..sort(_byTime);
    return NoticePlan(notices: _withTimeouts(all), coveredUntil: lost?.when, timerLastCovered: timerLastCovered);
  }

  /// Android quita cada aviso al llegar el siguiente del mismo elemento (su
  /// repetición, la ocurrencia que sigue o el siguiente intervalo). Se calcula
  /// sobre lo que de verdad se programa: el último de cada cadena se queda.
  static List<PlannedNotice> _withTimeouts(List<PlannedNotice> list) {
    final Map<String, int> lastOf = <String, int>{};
    final List<PlannedNotice> out = List<PlannedNotice>.of(list);
    for (int i = 0; i < out.length; i++) {
      final PlannedNotice n = out[i];
      String? chain;
      if (n.kind == NoticeKind.timer) {
        chain = 'timer';
      } else if (n.kind == NoticeKind.first || n.kind == NoticeKind.nag) {
        chain = n.element;
      }
      out[i] = n.copyWith(clearTimeout: true);
      if (chain == null) {
        continue;
      }
      final int? prev = lastOf[chain];
      if (prev != null) {
        final int ms = n.when.difference(out[prev].when).inMilliseconds;
        out[prev] = out[prev].copyWith(timeoutMs: ms > 0 ? ms : null, clearTimeout: ms <= 0);
      }
      lastOf[chain] = i;
    }
    return out;
  }

  static NoticeActions _habitActions(Habit h) {
    switch (h.kind) {
      case HabitKind.check:
        return NoticeActions.habitCheck;
      case HabitKind.count:
        return NoticeActions.habitCount;
      case HabitKind.timed:
        return NoticeActions.habitTimed;
      case HabitKind.negative:
        return NoticeActions.none;
    }
  }

  static String _reminderBody(Reminder r, DateTime due, bool spanish) {
    if (r.isCountdown) {
      return spanish ? 'Se cumplió la cuenta regresiva de ${formatDurationShort(r.countdownSeconds, spanish: true)}.' : 'Your ${formatDurationShort(r.countdownSeconds, spanish: false)} countdown is up.';
    }
    if (r.notes.trim().isNotEmpty) {
      return r.notes.trim();
    }
    final String when = formatTime(due, spanish: spanish);
    return spanish ? 'Para las $when' : 'Due at $when';
  }

  /// Texto de las repeticiones. La solicitud que se repite lleva la fecha:
  /// puede seguir sonando al día siguiente.
  static String _nagBody(Reminder r, DateTime alert, bool spanish, {required bool repeating}) {
    final String time = formatTime(alert, spanish: spanish);
    String since;
    if (repeating) {
      since = spanish ? 'el ${formatShortDate(alert, spanish: true)} a las $time' : '${formatShortDate(alert, spanish: false)} at $time';
    } else {
      since = spanish ? 'las $time' : time;
    }
    if (r.isCountdown) {
      return spanish ? 'Sonando desde $since. Toca Hecho para apagarla.' : 'Ringing since $since. Tap Done to turn it off.';
    }
    return spanish ? 'Sigue pendiente desde $since. Toca Hecho si ya lo hiciste.' : 'Still pending since $since. Tap Done if you already did it.';
  }

  static String _habitBody(Habit h, Map<String, HabitEntry> e, HabitEntry? entry, DateTime day, DateTime today, int weekStart, bool spanish) {
    String tr(String es, String en) => spanish ? es : en;
    final int value = entry?.value ?? 0;
    final int target = h.targetOn(day);
    switch (h.kind) {
      case HabitKind.check:
        return tr('¿Ya lo hiciste hoy?', 'Have you done it today?');
      case HabitKind.count:
        final String unit = h.unit.trim().isEmpty ? tr('veces', 'times') : h.unit.trim();
        return value == 0 ? tr('Meta de hoy: $target $unit.', 'Today\'s goal: $target $unit.') : tr('Llevas $value de $target $unit.', '$value of $target $unit so far.');
      case HabitKind.timed:
        final int left = math.max(0, target - value);
        return tr('Te faltan ${formatDurationShort(left, spanish: true)}. Toca Empezar para abrir el temporizador.', '${formatDurationShort(left, spanish: false)} to go. Tap Start to open the timer.');
      case HabitKind.negative:
        final int days = HabitLogic.negativeStreak(h, e, day.isAfter(today) ? day : today).current;
        return tr('Llevas $days ${days == 1 ? 'día' : 'días'} sin recaer. ¡Sigue así!', '$days ${days == 1 ? 'day' : 'days'} without a slip. Keep going!');
    }
  }
}
