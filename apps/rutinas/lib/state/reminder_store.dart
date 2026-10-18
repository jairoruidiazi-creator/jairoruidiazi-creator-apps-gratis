import 'package:clock/clock.dart';

import '../core/ids.dart';
import '../core/storage.dart';
import '../logic/recurrence.dart';
import '../model/reminder.dart';
import 'persistent.dart';

/// Recordatorios y cuentas regresivas (`reminders.json`).
class ReminderStore extends PersistentStore {
  ReminderStore(JsonStore store) : super(store, 'reminders.json');

  final List<Reminder> reminders = <Reminder>[];

  /// Pendientes, del que suena primero al último.
  List<Reminder> get pending {
    final List<Reminder> list = reminders.where((Reminder r) => !r.done).toList();
    list.sort((Reminder a, Reminder b) => a.alertAt.compareTo(b.alertAt));
    return list;
  }

  /// Hechos, el más reciente primero.
  List<Reminder> get completed {
    final List<Reminder> list = reminders.where((Reminder r) => r.done).toList();
    list.sort((Reminder a, Reminder b) => b.doneAt!.compareTo(a.doneAt!));
    return list;
  }

  Reminder? byId(String id) {
    for (final Reminder r in reminders) {
      if (r.id == id) {
        return r;
      }
    }
    return null;
  }

  void add(Reminder r) {
    reminders.add(r);
    changed();
  }

  void update(Reminder r) {
    final int i = reminders.indexWhere((Reminder x) => x.id == r.id);
    if (i < 0) {
      reminders.add(r);
    } else {
      reminders[i] = r;
    }
    changed();
  }

  void remove(String id) {
    reminders.removeWhere((Reminder r) => r.id == id);
    changed();
  }

  /// Cuenta regresiva rápida: "avísame en [minutes] min" y que insista.
  Reminder addCountdown({required int seconds, required String title, required int nagMinutes}) {
    final DateTime now = clock.now();
    final Reminder r = Reminder(
      id: newId(),
      title: title,
      dueAt: now.add(Duration(seconds: seconds)),
      nagMinutes: nagMinutes,
      countdownSeconds: seconds,
      createdAt: now,
    );
    add(r);
    return r;
  }

  /// Marca hecho y devuelve cómo estaba, para poder deshacer.
  Map<String, dynamic>? complete(String id) {
    final Reminder? r = byId(id);
    if (r == null) {
      return null;
    }
    final Map<String, dynamic> before = r.toJson();
    ReminderLogic.complete(r, clock.now());
    changed();
    return before;
  }

  /// Vuelve a dejar un recordatorio como estaba antes de un cambio.
  void restore(Map<String, dynamic> json) {
    update(Reminder.fromJson(json));
  }

  /// Pospone [minutes] desde que suena (o desde ahora si ya sonó). Solo lo que
  /// ya sonó o está por sonar; nunca queda antes de su hora.
  void snooze(String id, int minutes) {
    final Reminder? r = byId(id);
    if (r == null || r.done) {
      return;
    }
    ReminderLogic.snooze(r, clock.now(), minutes);
    changed();
  }

  /// Pospone hasta una hora dada (por ejemplo, mañana a las 9:00).
  void snoozeUntil(String id, DateTime target) {
    final Reminder? r = byId(id);
    if (r == null || r.done) {
      return;
    }
    ReminderLogic.snoozeUntil(r, target);
    changed();
  }

  /// Reemplaza todo por lo de [other] (al restaurar una copia ya leída entera).
  void replaceWith(ReminderStore other) {
    reminders
      ..clear()
      ..addAll(other.reminders);
    damagedCopy = null;
    changed();
    flush();
  }

  /// Vuelve a dejar pendiente un recordatorio hecho.
  void reopen(String id) {
    final Reminder? r = byId(id);
    if (r == null || !r.done) {
      return;
    }
    ReminderLogic.reopen(r);
    changed();
  }

  /// Repite una cuenta regresiva ya hecha con la misma duración.
  void restartCountdown(String id) {
    final Reminder? r = byId(id);
    if (r == null || !r.isCountdown) {
      return;
    }
    final DateTime now = clock.now();
    r.doneAt = null;
    r.snoozedUntil = null;
    r.dueAt = now.add(Duration(seconds: r.countdownSeconds));
    changed();
  }

  int clearCompleted() {
    final int before = reminders.length;
    reminders.removeWhere((Reminder r) => r.done);
    final int removed = before - reminders.length;
    if (removed > 0) {
      changed();
    }
    return removed;
  }

  /// Pasa a la ocurrencia que toca los recordatorios que se repiten y no se
  /// marcaron a tiempo.
  bool rollOverAll() {
    final DateTime now = clock.now();
    bool any = false;
    for (final Reminder r in reminders) {
      if (ReminderLogic.rollOver(r, now)) {
        any = true;
      }
    }
    if (any) {
      changed();
    }
    return any;
  }

  @override
  void reset() => reminders.clear();

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'reminders': reminders.map((Reminder r) => r.toJson()).toList(),
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    final Object? list = json['reminders'];
    if (list is List) {
      for (final Map<String, dynamic> j in list.whereType<Map<String, dynamic>>()) {
        reminders.add(Reminder.fromJson(j));
      }
    }
  }
}
