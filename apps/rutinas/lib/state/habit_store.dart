import 'dart:math' as math;

import 'package:clock/clock.dart';

import '../core/dates.dart';
import '../core/storage.dart';
import '../model/habit.dart';
import 'persistent.dart';

/// Hábitos y sus registros por día (`habits.json`).
class HabitStore extends PersistentStore {
  HabitStore(JsonStore store) : super(store, 'habits.json');

  final List<Habit> habits = <Habit>[];

  /// Registros: id del hábito → día (`aaaa-mm-dd`) → registro.
  final Map<String, Map<String, HabitEntry>> entries = <String, Map<String, HabitEntry>>{};

  /// Hábitos activos, en el orden del usuario.
  List<Habit> get active {
    final List<Habit> list = habits.where((Habit h) => !h.archived).toList();
    list.sort((Habit a, Habit b) => a.order.compareTo(b.order));
    return list;
  }

  List<Habit> get archived {
    final List<Habit> list = habits.where((Habit h) => h.archived).toList();
    list.sort((Habit a, Habit b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Habit? byId(String id) {
    for (final Habit h in habits) {
      if (h.id == id) {
        return h;
      }
    }
    return null;
  }

  Map<String, HabitEntry> entriesOf(String habitId) => entries[habitId] ?? const <String, HabitEntry>{};

  HabitEntry? entry(String habitId, DateTime day) => entries[habitId]?[dayKey(day)];

  void add(Habit h) {
    h.order = habits.isEmpty ? 0 : habits.map((Habit x) => x.order).reduce(math.max) + 1;
    habits.add(h);
    changed();
  }

  /// Guarda los cambios de un hábito editado (copia hecha con [Habit.copy]).
  void update(Habit h) {
    final int i = habits.indexWhere((Habit x) => x.id == h.id);
    if (i < 0) {
      add(h);
      return;
    }
    habits[i] = h;
    changed();
  }

  void remove(String id) {
    habits.removeWhere((Habit h) => h.id == id);
    entries.remove(id);
    changed();
  }

  /// Archiva o recupera un hábito. Archivado, deja de contar desde hoy; al
  /// recuperarlo, el tiempo que estuvo archivado queda como pausa.
  void setArchived(String id, bool value) {
    final Habit? h = byId(id);
    if (h == null || h.archived == value) {
      return;
    }
    final DateTime today = dateOnly(clock.now());
    if (value) {
      h.archive(today);
    } else {
      h.unarchive(today);
      h.order = habits.map((Habit x) => x.order).reduce(math.max) + 1;
    }
    changed();
  }

  /// ¿El hábito tiene algo anotado (veces, minutos o recaídas)? Entonces su
  /// tipo ya no se puede cambiar.
  bool hasValues(String habitId) {
    final Map<String, HabitEntry>? map = entries[habitId];
    if (map == null) {
      return false;
    }
    for (final HabitEntry e in map.values) {
      if (e.value > 0) {
        return true;
      }
    }
    return false;
  }

  /// Reemplaza todo por lo de [other] (al restaurar una copia ya leída entera).
  void replaceWith(HabitStore other) {
    habits
      ..clear()
      ..addAll(other.habits);
    entries
      ..clear()
      ..addAll(other.entries);
    damagedCopy = null;
    changed();
    flush();
  }

  /// Sube (−1) o baja (+1) un hábito en la lista.
  void move(String id, int delta) {
    final List<Habit> list = active;
    final int i = list.indexWhere((Habit h) => h.id == id);
    final int j = i + delta;
    if (i < 0 || j < 0 || j >= list.length) {
      return;
    }
    final Habit a = list[i];
    final Habit b = list[j];
    list[i] = b;
    list[j] = a;
    for (int k = 0; k < list.length; k++) {
      list[k].order = k;
    }
    changed();
  }

  HabitEntry _edit(String habitId, DateTime day) {
    final Map<String, HabitEntry> map = entries.putIfAbsent(habitId, () => <String, HabitEntry>{});
    return map.putIfAbsent(dayKey(day), () => HabitEntry());
  }

  void _tidy(String habitId, DateTime day) {
    final Map<String, HabitEntry>? map = entries[habitId];
    final HabitEntry? e = map?[dayKey(day)];
    if (map != null && e != null && e.isEmpty) {
      map.remove(dayKey(day));
    }
  }

  /// Fija el valor del día (veces, segundos o recaídas).
  void setValue(String habitId, DateTime day, int value) {
    final HabitEntry e = _edit(habitId, day);
    e.value = math.max(0, value);
    if (e.value > 0) {
      e.skipped = false;
    }
    e.updatedAt = clock.now();
    _tidy(habitId, day);
    changed();
  }

  void addValue(String habitId, DateTime day, int delta) {
    setValue(habitId, day, (entry(habitId, day)?.value ?? 0) + delta);
  }

  /// Hecho / no hecho (hábitos de sí o no).
  void toggleDone(String habitId, DateTime day) {
    final Habit? h = byId(habitId);
    if (h == null) {
      return;
    }
    final int now = entry(habitId, day)?.value ?? 0;
    final int target = h.targetOn(dateOnly(day));
    setValue(habitId, day, now >= target ? 0 : target);
  }

  void setSkipped(String habitId, DateTime day, bool skipped) {
    final HabitEntry e = _edit(habitId, day);
    e.skipped = skipped;
    e.updatedAt = clock.now();
    _tidy(habitId, day);
    changed();
  }

  void setNote(String habitId, DateTime day, String note) {
    final HabitEntry e = _edit(habitId, day);
    e.note = note.trim();
    e.updatedAt = clock.now();
    _tidy(habitId, day);
    changed();
  }

  /// Todo el registro de un día de una vez (hoja de edición del día).
  void setDay(String habitId, DateTime day, {required int value, required bool skipped, required String note}) {
    final HabitEntry e = _edit(habitId, day);
    e.value = math.max(0, value);
    e.skipped = skipped;
    e.note = note.trim();
    e.updatedAt = clock.now();
    _tidy(habitId, day);
    changed();
  }

  @override
  void reset() {
    habits.clear();
    entries.clear();
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'habits': habits.map((Habit h) => h.toJson()).toList(),
        'entries': entries.map((String id, Map<String, HabitEntry> days) => MapEntry<String, dynamic>(id, days.map((String k, HabitEntry e) => MapEntry<String, dynamic>(k, e.toJson())))),
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    final Object? list = json['habits'];
    if (list is List) {
      for (final Map<String, dynamic> j in list.whereType<Map<String, dynamic>>()) {
        habits.add(Habit.fromJson(j));
      }
    }
    final Object? map = json['entries'];
    if (map is Map<String, dynamic>) {
      for (final MapEntry<String, dynamic> h in map.entries) {
        final Object? days = h.value;
        if (days is! Map<String, dynamic>) {
          continue;
        }
        final Map<String, HabitEntry> out = <String, HabitEntry>{};
        for (final MapEntry<String, dynamic> d in days.entries) {
          final Object? v = d.value;
          if (v is Map<String, dynamic> && parseDayKey(d.key) != null) {
            final HabitEntry e = HabitEntry.fromJson(v);
            if (!e.isEmpty) {
              out[d.key] = e;
            }
          }
        }
        if (out.isNotEmpty) {
          entries[h.key] = out;
        }
      }
    }
    // Hábitos archivados con una versión sin fecha de archivo: se toma el día
    // siguiente al último registro (o el inicio), para que no cuenten como
    // fallados los días en que ya no se seguían.
    for (final Habit h in habits) {
      if (h.archived && h.archivedAt == null) {
        DateTime? last;
        for (final String key in (entries[h.id] ?? const <String, HabitEntry>{}).keys) {
          final DateTime? d = parseDayKey(key);
          if (d != null && (last == null || d.isAfter(last))) {
            last = d;
          }
        }
        final DateTime start = dateOnly(h.startDate);
        h.archivedAt = last == null || last.isBefore(start) ? start : addDays(last, 1);
      }
    }
  }
}
