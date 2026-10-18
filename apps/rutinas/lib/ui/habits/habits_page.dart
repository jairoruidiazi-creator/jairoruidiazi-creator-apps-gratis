import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/dates.dart';
import '../../logic/habit_logic.dart';
import '../../model/habit.dart';
import '../timer/runner_screen.dart';
import '../widgets/common.dart';
import 'day_sheet.dart';
import 'habit_detail.dart';
import 'habit_editor.dart';
import 'habit_texts.dart';

/// Pestaña de hábitos: lo que toca hoy (o el día elegido), lo hecho y lo que
/// no toca, con la racha de cada uno.
class HabitsPage extends StatefulWidget {
  const HabitsPage({super.key, required this.today});

  final DateTime today;

  @override
  State<HabitsPage> createState() => _HabitsPageState();
}

class _HabitsPageState extends State<HabitsPage> {
  late DateTime _day = widget.today;

  @override
  void didUpdateWidget(HabitsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!sameDay(oldWidget.today, widget.today) && sameDay(_day, oldWidget.today)) {
      _day = widget.today;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, 'Hábitos', 'Habits')),
        actions: <Widget>[
          // Arriba y no como botón flotante: abajo taparía el botón de hecho del
          // último hábito a la vista, que es lo que más se toca en esta lista.
          IconButton(
            tooltip: t(context, 'Nuevo hábito', 'New habit'),
            icon: const Icon(Icons.add),
            onPressed: () => HabitEditorScreen.open(context),
          ),
          ListenableBuilder(
            listenable: s.habits,
            builder: (BuildContext context, Widget? _) => s.habits.archived.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: t(context, 'Archivados', 'Archived'),
                    icon: const Icon(Icons.inventory_2_outlined),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ArchivedHabitsScreen())),
                  ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[s.habits, s.settings]),
        builder: (BuildContext context, Widget? _) => _body(context, s),
      ),
    );
  }

  Widget _body(BuildContext context, Services s) {
    final bool es = s.settings.spanish;
    final int weekStart = s.settings.weekStart;
    final DateTime today = widget.today;
    final List<Habit> habits = s.habits.active;
    if (habits.isEmpty) {
      return ListView(
        children: <Widget>[
          EmptyState(
            icon: Icons.check_circle_outline,
            title: t(context, 'Crea tu primer hábito', 'Create your first habit'),
            message: t(context, 'Beber agua, leer, meditar o dejar de fumar: marca cada día y mira crecer tu racha.', 'Drink water, read, meditate or quit smoking: check in each day and watch your streak grow.'),
            action: FilledButton.icon(onPressed: () => HabitEditorScreen.open(context), icon: const Icon(Icons.add), label: Text(t(context, 'Nuevo hábito', 'New habit'))),
          ),
        ],
      );
    }
    final List<Habit> pending = <Habit>[];
    final List<Habit> done = <Habit>[];
    final List<Habit> skipped = <Habit>[];
    final List<Habit> quitting = <Habit>[];
    final List<Habit> other = <Habit>[];
    for (final Habit h in habits) {
      final Map<String, HabitEntry> e = s.habits.entriesOf(h.id);
      final HabitEntry? entry = e[dayKey(_day)];
      if (_day.isBefore(HabitLogic.effectiveStart(h, e))) {
        other.add(h);
      } else if (h.isNegative) {
        quitting.add(h);
      } else if (HabitLogic.isDone(h, entry, _day)) {
        done.add(h);
      } else if (entry != null && entry.skipped) {
        // Saltado a propósito: ya no está por hacer.
        skipped.add(h);
      } else if (HabitLogic.isDueOn(h, e, _day, today, weekStart: weekStart)) {
        pending.add(h);
      } else {
        other.add(h);
      }
    }
    final bool isToday = sameDay(_day, today);
    final String dayTitle = isToday ? '${t(context, 'Hoy', 'Today')} · ${formatWeekdayDate(_day, spanish: es)}' : formatWeekdayDate(_day, spanish: es);
    return ReadableWidth(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          _DayStrip(
            day: _day,
            today: today,
            weekStart: weekStart,
            spanish: es,
            stats: (DateTime d) => _dayStats(s, habits, d, today, weekStart),
            onSelect: (DateTime d) => setState(() => _day = d),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
            child: Row(
              children: <Widget>[
                IconButton(
                  tooltip: t(context, 'Semana anterior', 'Previous week'),
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() => _day = addDays(_day, -7)),
                ),
                Expanded(child: Text(dayTitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
                IconButton(
                  tooltip: t(context, 'Semana siguiente', 'Next week'),
                  icon: const Icon(Icons.chevron_right),
                  onPressed: startOfWeek(addDays(_day, 7), weekStart).isAfter(today)
                      ? null
                      : () => setState(() {
                            final DateTime next = addDays(_day, 7);
                            _day = next.isAfter(today) ? today : next;
                          }),
                ),
              ],
            ),
          ),
          if (!isToday)
            Center(child: TextButton(onPressed: () => setState(() => _day = today), child: Text(t(context, 'Volver a hoy', 'Back to today')))),
          if (pending.isNotEmpty) ...<Widget>[
            SectionHeader('${t(context, 'Por hacer', 'To do')} (${pending.length})'),
            for (final Habit h in pending) HabitTile(habit: h, day: _day, today: today),
          ],
          if (done.isNotEmpty) ...<Widget>[
            SectionHeader('${t(context, 'Hechos', 'Done')} (${done.length})'),
            for (final Habit h in done) HabitTile(habit: h, day: _day, today: today),
          ],
          if (skipped.isNotEmpty) ...<Widget>[
            SectionHeader('${t(context, 'Saltados', 'Skipped')} (${skipped.length})'),
            for (final Habit h in skipped) HabitTile(habit: h, day: _day, today: today),
          ],
          if (quitting.isNotEmpty) ...<Widget>[
            SectionHeader(t(context, 'Sin recaer', 'Quitting')),
            for (final Habit h in quitting) HabitTile(habit: h, day: _day, today: today),
          ],
          if (other.isNotEmpty) ...<Widget>[
            SectionHeader(isToday ? t(context, 'No tocan hoy', 'Not due today') : t(context, 'No tocan este día', 'Not due this day')),
            for (final Habit h in other) HabitTile(habit: h, day: _day, today: today),
          ],
        ],
      ),
    );
  }

  /// Hábitos hechos y que tocaban en un día (sin contar los de dejar de…).
  List<int> _dayStats(Services s, List<Habit> habits, DateTime d, DateTime today, int weekStart) {
    int due = 0;
    int doneCount = 0;
    for (final Habit h in habits) {
      if (h.isNegative) {
        continue;
      }
      final Map<String, HabitEntry> e = s.habits.entriesOf(h.id);
      final bool isDone = HabitLogic.isDone(h, e[dayKey(d)], d);
      if (isDone) {
        doneCount++;
        due++;
      } else if (!d.isAfter(today) && HabitLogic.isDueOn(h, e, d, today, weekStart: weekStart) && !(e[dayKey(d)]?.skipped ?? false)) {
        due++;
      }
    }
    return <int>[doneCount, due];
  }
}

/// Franja con los siete días de la semana, cada uno con su avance.
class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.day, required this.today, required this.weekStart, required this.spanish, required this.stats, required this.onSelect});

  final DateTime day;
  final DateTime today;
  final int weekStart;
  final bool spanish;
  final List<int> Function(DateTime d) stats;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime start = startOfWeek(day, weekStart);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < 7; i++)
            Expanded(
              child: Builder(builder: (BuildContext context) {
                final DateTime d = addDays(start, i);
                final bool future = d.isAfter(today);
                final bool selected = sameDay(d, day);
                final List<int> st = future ? const <int>[0, 0] : stats(d);
                final double frac = st[1] == 0 ? 0 : st[0] / st[1];
                final Color ring = theme.colorScheme.primary;
                final String label = '${formatWeekdayDate(d, spanish: spanish)}${future ? '' : ', ${spanish ? '${st[0]} de ${st[1]} hábitos' : '${st[0]} of ${st[1]} habits'}'}';
                return Semantics(
                  button: true,
                  enabled: !future,
                  selected: selected,
                  label: label,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: future ? null : () => onSelect(d),
                    child: ExcludeSemantics(
                     child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(weekdayLetter(d.weekday, spanish: spanish), style: theme.textTheme.labelSmall?.copyWith(color: future ? theme.disabledColor : theme.colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: 34,
                                height: 34,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: <Widget>[
                                    if (!future)
                                      SizedBox(
                                        width: 34,
                                        height: 34,
                                        child: CircularProgressIndicator(value: frac, strokeWidth: 3, color: ring, backgroundColor: ring.withValues(alpha: 0.15)),
                                      ),
                                    Container(
                                      width: 26,
                                      height: 26,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? theme.colorScheme.primary : Colors.transparent),
                                      child: Text(
                                        '${d.day}',
                                        style: theme.textTheme.labelLarge?.copyWith(
                                          fontWeight: sameDay(d, today) || selected ? FontWeight.w800 : FontWeight.w500,
                                          color: selected ? theme.colorScheme.onPrimary : (future ? theme.disabledColor : theme.colorScheme.onSurface),
                                        ),
                                      ),
                                    ),
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
                );
              }),
            ),
        ],
      ),
    );
  }
}

/// Fila de un hábito con su avance, su racha y el botón rápido.
class HabitTile extends StatelessWidget {
  const HabitTile({super.key, required this.habit, required this.day, required this.today});

  final Habit habit;
  final DateTime day;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final bool es = s.settings.spanish;
    final ThemeData theme = Theme.of(context);
    final Habit h = habit;
    final Map<String, HabitEntry> entries = s.habits.entriesOf(h.id);
    final HabitEntry? entry = entries[dayKey(day)];
    final StreakInfo streak = HabitLogic.streak(h, entries, today, weekStart: s.settings.weekStart);
    final bool beforeStart = day.isBefore(HabitLogic.effectiveStart(h, entries));
    final List<String> lines = <String>[];
    if (h.isNegative) {
      lines.add(es ? '${streak.current} ${HabitTexts.streakUnit(streak.unit, streak.current, es)} sin recaer' : '${streak.current} ${HabitTexts.streakUnit(streak.unit, streak.current, es)} without a slip');
      if ((entry?.value ?? 0) > 0) {
        lines.add(HabitTexts.progress(h, entry, es, day: day));
      }
    } else {
      lines.add(beforeStart ? (es ? 'Empieza el ${formatShortDate(h.startDate, spanish: true)}' : 'Starts ${formatShortDate(h.startDate, spanish: false)}') : HabitTexts.progress(h, entry, es, day: day));
      final HabitSlot? slot = HabitLogic.slotFor(h, entries, day, today, weekStart: s.settings.weekStart);
      final String? period = HabitTexts.period(h, slot, es, current: slot == null || slot.contains(today));
      if (period != null) {
        lines.add(period);
      }
    }
    final bool showRing = h.kind == HabitKind.count || h.kind == HabitKind.timed;
    final String streakText = h.isNegative ? (es ? 'Mejor: ${streak.best}' : 'Best: ${streak.best}') : '${t(context, 'Racha', 'Streak')}: ${HabitTexts.streak(streak, es)}';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => HabitDetailScreen.open(context, h.id),
        onLongPress: () => DaySheet.show(context, h, day),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: <Widget>[
              HabitAvatar(icon: h.icon, color: h.color, progress: showRing ? HabitTexts.fraction(h, entry, day: day) : null),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  label: '${h.name}. ${lines.join('. ')}. $streakText',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(h.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      for (final String l in lines) Text(l, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Row(
                        children: <Widget>[
                          Icon(h.isNegative ? Icons.emoji_events_outlined : Icons.local_fire_department, size: 18, color: streak.current > 0 ? const Color(0xFFE65100) : theme.colorScheme.outline),
                          const SizedBox(width: 4),
                          Flexible(child: Text(streakText, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (!beforeStart) _QuickAction(habit: h, day: day, today: today, entry: entry),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.habit, required this.day, required this.today, required this.entry});

  final Habit habit;
  final DateTime day;
  final DateTime today;
  final HabitEntry? entry;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final bool es = s.settings.spanish;
    final Habit h = habit;
    final Color color = Color(h.color);
    final int value = entry?.value ?? 0;
    final int target = h.targetOn(day);
    switch (h.kind) {
      case HabitKind.check:
        final bool done = value >= 1;
        return IconButton(
          tooltip: done ? t(context, 'Desmarcar', 'Uncheck') : t(context, 'Marcar como hecho', 'Mark as done'),
          isSelected: done,
          iconSize: 32,
          icon: Icon(Icons.radio_button_unchecked, color: color),
          selectedIcon: Icon(Icons.check_circle, color: color),
          onPressed: () {
            s.habits.toggleDone(h.id, day);
            if (!done) {
              unawaited(s.notices.dismissHabit(h, day));
            }
          },
        );
      case HabitKind.count:
        final String unit = HabitTexts.unit(h, 1, es);
        return IconButton.filledTonal(
          tooltip: es ? 'Sumar 1 ($unit)' : 'Add 1 ($unit)',
          icon: const Icon(Icons.add),
          onPressed: () {
            final bool wasDone = value >= target;
            s.habits.addValue(h.id, day, 1);
            if (!wasDone && value + 1 >= target) {
              unawaited(s.notices.dismissHabit(h, day));
            }
          },
        );
      case HabitKind.timed:
        final bool isToday = sameDay(day, today);
        final int left = value >= target ? target : target - value;
        return IconButton.filledTonal(
          tooltip: isToday ? (es ? 'Iniciar temporizador de ${HabitTexts.minutesOf(left, true)} min' : 'Start ${HabitTexts.minutesOf(left, false)} min timer') : t(context, 'Anotar minutos', 'Log minutes'),
          icon: Icon(isToday ? Icons.play_arrow : Icons.edit),
          onPressed: () async {
            if (!isToday) {
              await DaySheet.show(context, h, day);
              return;
            }
            final bool ok = await RunnerScreen.beforeStart(context);
            if (!ok || !context.mounted) {
              return;
            }
            s.timer.startHabit(h, left);
            unawaited(s.notices.askNotifications());
            if (context.mounted) {
              unawaited(RunnerScreen.open(context));
            }
          },
        );
      case HabitKind.negative:
        return IconButton.outlined(
          tooltip: t(context, 'Anotar una recaída', 'Log a slip'),
          icon: const Icon(Icons.restart_alt),
          onPressed: () async {
            final bool ok = await confirm(
              context,
              title: t(context, '¿Anotar una recaída?', 'Log a slip?'),
              message: sameDay(day, today)
                  ? t(context, 'La cuenta de días sin recaer vuelve a empezar desde mañana. No pasa nada: lo importante es retomar.', 'The count of days without a slip starts again tomorrow. That is fine: what matters is getting back on track.')
                  : t(context, 'Se anota en el día elegido y la racha se recalcula.', 'It is logged on the chosen day and the streak is recalculated.'),
              yes: t(context, 'Anotar', 'Log it'),
            );
            if (ok) {
              s.habits.addValue(h.id, day, 1);
            }
          },
        );
    }
  }
}

/// Hábitos archivados: se pueden recuperar o borrar.
class ArchivedHabitsScreen extends StatelessWidget {
  const ArchivedHabitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'Hábitos archivados', 'Archived habits'))),
      body: ListenableBuilder(
        listenable: s.habits,
        builder: (BuildContext context, Widget? _) {
          final List<Habit> list = s.habits.archived;
          if (list.isEmpty) {
            return ListView(children: <Widget>[EmptyState(icon: Icons.inventory_2_outlined, title: t(context, 'No hay hábitos archivados', 'No archived habits'), message: t(context, 'Lo que archives se guarda aquí con toda su historia.', 'Habits you archive are kept here with their full history.'))]);
          }
          return ReadableWidth(
            child: ListView(
              children: <Widget>[
                for (final Habit h in list)
                  ListTile(
                    leading: HabitAvatar(icon: h.icon, color: h.color, size: 40),
                    title: Text(h.name),
                    subtitle: Text(HabitTexts.frequency(h.frequency, s.settings.spanish, s.settings.weekStart)),
                    onTap: () => HabitDetailScreen.open(context, h.id),
                    trailing: IconButton(
                      tooltip: t(context, 'Recuperar', 'Restore'),
                      icon: const Icon(Icons.unarchive_outlined),
                      onPressed: () => s.habits.setArchived(h.id, false),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
