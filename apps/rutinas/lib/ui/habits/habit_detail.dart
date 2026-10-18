import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/dates.dart';
import '../../logic/habit_logic.dart';
import '../../model/habit.dart';
import '../catalog.dart';
import '../timer/runner_screen.dart';
import '../widgets/common.dart';
import 'day_sheet.dart';
import 'habit_editor.dart';
import 'habit_texts.dart';

/// Detalle de un hábito: rachas, cumplimiento, el día de hoy, el calendario
/// del mes y las notas.
class HabitDetailScreen extends StatefulWidget {
  const HabitDetailScreen({super.key, required this.habitId});

  final String habitId;

  static Future<void> open(BuildContext context, String habitId) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HabitDetailScreen(habitId: habitId)));

  @override
  State<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends State<HabitDetailScreen> {
  DateTime _month = startOfMonth(clock.now());

  Future<void> _delete(Services s, Habit h) async {
    final bool ok = await confirm(
      context,
      title: t(context, '¿Borrar "${h.name}"?', 'Delete "${h.name}"?'),
      message: t(context, 'Se borran el hábito y toda su historia. Si solo quieres dejar de verlo, archívalo.', 'The habit and its whole history are deleted. If you just want to hide it, archive it.'),
      yes: t(context, 'Borrar', 'Delete'),
      destructive: true,
    );
    if (!ok || !mounted) {
      return;
    }
    Navigator.of(context).pop();
    s.habits.remove(h.id);
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[s.habits, s.settings]),
      builder: (BuildContext context, Widget? _) {
        final Habit? h = s.habits.byId(widget.habitId);
        if (h == null) {
          return Scaffold(appBar: AppBar(), body: Center(child: Text(t(context, 'Este hábito ya no existe.', 'This habit no longer exists.'))));
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(h.name),
            actions: <Widget>[
              IconButton(tooltip: t(context, 'Editar', 'Edit'), icon: const Icon(Icons.edit_outlined), onPressed: () => HabitEditorScreen.open(context, habit: h)),
              PopupMenuButton<String>(
                tooltip: t(context, 'Más opciones', 'More options'),
                onSelected: (String v) {
                  if (v == 'archive') {
                    s.habits.setArchived(h.id, !h.archived);
                    if (!h.archived) {
                      return;
                    }
                    Navigator.of(context).pop();
                  } else if (v == 'delete') {
                    unawaited(_delete(s, h));
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(value: 'archive', child: Text(h.archived ? t(context, 'Recuperar', 'Restore') : t(context, 'Archivar', 'Archive'))),
                  PopupMenuItem<String>(value: 'delete', child: Text(t(context, 'Borrar', 'Delete'))),
                ],
              ),
            ],
          ),
          body: ReadableWidth(child: _content(context, s, h)),
        );
      },
    );
  }

  Widget _content(BuildContext context, Services s, Habit h) {
    final bool es = s.settings.spanish;
    final int weekStart = s.settings.weekStart;
    final ThemeData theme = Theme.of(context);
    final DateTime today = dateOnly(clock.now());
    final Map<String, HabitEntry> entries = s.habits.entriesOf(h.id);
    final StreakInfo streak = HabitLogic.streak(h, entries, today, weekStart: weekStart);
    final double? rate = streak.rate;
    final List<MapEntry<String, HabitEntry>> notes = entries.entries.where((MapEntry<String, HabitEntry> e) => e.value.note.trim().isNotEmpty).toList()..sort((MapEntry<String, HabitEntry> a, MapEntry<String, HabitEntry> b) => b.key.compareTo(a.key));
    final String unit = HabitTexts.streakUnit(streak.unit, 2, es);
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: <Widget>[
              HabitAvatar(icon: h.icon, color: h.color, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(h.isNegative ? HabitTexts.kind(h.kind, es) : HabitTexts.frequency(h.frequency, es, weekStart), style: theme.textTheme.titleMedium),
                    if (h.kind == HabitKind.count) Text(es ? 'Meta: ${h.goal} ${HabitTexts.unit(h, h.goal, es)} al día' : 'Goal: ${h.goal} ${HabitTexts.unit(h, h.goal, es)} a day', style: theme.textTheme.bodyMedium),
                    if (h.kind == HabitKind.timed) Text(es ? 'Meta: ${HabitTexts.minutesOf(h.target, true)} min al día' : 'Goal: ${HabitTexts.minutesOf(h.target, false)} min a day', style: theme.textTheme.bodyMedium),
                    Text(es ? 'Desde el ${formatLongDate(HabitLogic.effectiveStart(h, entries), spanish: true)}' : 'Since ${formatLongDate(HabitLogic.effectiveStart(h, entries), spanish: false)}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    if (h.notes.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(h.notes.trim(), style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic))),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TileGrid(
            children: <Widget>[
              _Stat(label: h.isNegative ? t(context, 'Sin recaer', 'Without a slip') : t(context, 'Racha actual', 'Current streak'), value: '${streak.current}', unit: HabitTexts.streakUnit(streak.unit, streak.current, es), icon: Icons.local_fire_department),
              _Stat(label: t(context, 'Mejor racha', 'Best streak'), value: '${streak.best}', unit: HabitTexts.streakUnit(streak.unit, streak.best, es), icon: Icons.emoji_events_outlined),
              _Stat(label: t(context, 'Cumplimiento', 'Success rate'), value: rate == null ? '—' : '${(rate * 100).round()} %', unit: h.isNegative ? t(context, 'de los días', 'of days') : (es ? 'de los $unit' : 'of $unit'), icon: Icons.percent),
              _Stat(label: h.isNegative ? t(context, 'Recaídas', 'Slips') : t(context, 'Días hechos', 'Days done'), value: h.isNegative ? '${streak.missed + ((entries[dayKey(today)]?.value ?? 0) > 0 ? 1 : 0)}' : '${streak.completions}', unit: t(context, 'en total', 'in total'), icon: h.isNegative ? Icons.restart_alt : Icons.check),
            ],
          ),
        ),
        if (!today.isBefore(HabitLogic.effectiveStart(h, entries))) _TodayCard(habit: h, today: today),
        SectionHeader(t(context, 'Calendario', 'Calendar')),
        _MonthCalendar(
          habit: h,
          month: _month,
          today: today,
          weekStart: weekStart,
          onMonth: (DateTime m) => setState(() => _month = m),
        ),
        if (notes.isNotEmpty) ...<Widget>[
          SectionHeader(t(context, 'Notas', 'Notes')),
          for (final MapEntry<String, HabitEntry> n in notes.take(40))
            ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: Text(n.value.note),
              subtitle: Text(formatWeekdayDate(parseDayKey(n.key)!, spanish: es)),
              onTap: () => DaySheet.show(context, h, parseDayKey(n.key)!),
            ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.unit, required this.icon});

  final String label;
  final String value;
  final String unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Semantics(
        label: '$label: $value $unit',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Flexible(child: Text(label, style: theme.textTheme.labelLarge)),
                ],
              ),
              const SizedBox(height: 4),
              Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text(unit, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lo de hoy, con los mismos controles de la lista y un poco más.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.habit, required this.today});

  final Habit habit;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final bool es = s.settings.spanish;
    final ThemeData theme = Theme.of(context);
    final Habit h = habit;
    final HabitEntry? e = s.habits.entry(h.id, today);
    final int value = e?.value ?? 0;
    final List<Widget> controls = <Widget>[];
    switch (h.kind) {
      case HabitKind.check:
        controls.add(FilledButton.tonalIcon(
          onPressed: () {
            final bool wasDone = value >= 1;
            s.habits.toggleDone(h.id, today);
            if (!wasDone) {
              unawaited(s.notices.dismissHabit(h, today));
            }
          },
          icon: Icon(value >= 1 ? Icons.undo : Icons.check),
          label: Text(value >= 1 ? t(context, 'Desmarcar', 'Uncheck') : t(context, 'Marcar hecho', 'Mark done')),
        ));
        break;
      case HabitKind.count:
        controls.add(NumberStepper(
          value: value,
          min: 0,
          max: 9999,
          label: HabitTexts.unit(h, 2, es),
          onChanged: (int v) {
            s.habits.setValue(h.id, today, v);
            if (v >= h.target && value < h.target) {
              unawaited(s.notices.dismissHabit(h, today));
            }
          },
        ));
        break;
      case HabitKind.timed:
        final int left = value >= h.target ? h.target : h.target - value;
        controls.add(FilledButton.icon(
          onPressed: () async {
            final bool ok = await RunnerScreen.confirmReplace(context);
            if (!ok || !context.mounted) {
              return;
            }
            s.timer.startHabit(h, left);
            unawaited(s.notices.askNotifications());
            if (context.mounted) {
              unawaited(RunnerScreen.open(context));
            }
          },
          icon: const Icon(Icons.play_arrow),
          label: Text(es ? 'Iniciar ${HabitTexts.minutesOf(left, true)} min' : 'Start ${HabitTexts.minutesOf(left, false)} min'),
        ));
        break;
      case HabitKind.negative:
        controls.add(OutlinedButton.icon(
          onPressed: () async {
            final bool ok = await confirm(context, title: t(context, '¿Anotar una recaída hoy?', 'Log a slip today?'), message: t(context, 'La cuenta de días sin recaer vuelve a empezar desde mañana.', 'The count of days without a slip starts again tomorrow.'), yes: t(context, 'Anotar', 'Log it'));
            if (ok) {
              s.habits.addValue(h.id, today, 1);
            }
          },
          icon: const Icon(Icons.restart_alt),
          label: Text(t(context, 'Anotar recaída', 'Log a slip')),
        ));
        break;
    }
    if (!h.isNegative && value < h.target) {
      final bool skipped = e?.skipped ?? false;
      controls.add(TextButton.icon(
        onPressed: () => s.habits.setSkipped(h.id, today, !skipped),
        icon: Icon(skipped ? Icons.redo : Icons.skip_next),
        label: Text(skipped ? t(context, 'No saltar hoy', 'Do not skip today') : t(context, 'Saltar hoy', 'Skip today')),
      ));
    }
    controls.add(TextButton.icon(
      onPressed: () => DaySheet.show(context, h, today),
      icon: const Icon(Icons.edit_note),
      label: Text(t(context, 'Nota', 'Note')),
    ));
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(t(context, 'Hoy', 'Today'), style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(HabitTexts.progress(h, e, es), style: theme.textTheme.titleMedium),
            if ((e?.note ?? '').isNotEmpty) Text(e!.note, style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: controls),
          ],
        ),
      ),
    );
  }
}

/// Calendario de un mes con el estado de cada día.
class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({required this.habit, required this.month, required this.today, required this.weekStart, required this.onMonth});

  final Habit habit;
  final DateTime month;
  final DateTime today;
  final int weekStart;
  final ValueChanged<DateTime> onMonth;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final bool es = s.settings.spanish;
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final Map<String, HabitEntry> entries = s.habits.entriesOf(habit.id);
    final Color hc = Color(habit.color);
    final DateTime first = startOfMonth(month);
    final DateTime gridStart = startOfWeek(first, weekStart);
    final int days = daysInMonth(first.year, first.month);
    final int cells = ((daysBetween(gridStart, first) + days + 6) ~/ 7) * 7;
    final bool canNext = !DateTime(first.year, first.month + 1).isAfter(today);
    final List<Widget> rows = <Widget>[];
    for (int r = 0; r < cells ~/ 7; r++) {
      final List<Widget> row = <Widget>[];
      for (int c = 0; c < 7; c++) {
        final DateTime d = addDays(gridStart, r * 7 + c);
        if (d.month != first.month) {
          row.add(const Expanded(child: SizedBox(height: 48)));
          continue;
        }
        final DayStatus st = HabitLogic.dayStatus(habit, entries, d, today, weekStart: weekStart);
        Color bg = Colors.transparent;
        Color fg = cs.onSurface;
        BoxBorder? border;
        switch (st) {
          case DayStatus.done:
          case DayStatus.clean:
            bg = hc;
            fg = onColor(hc);
            break;
          case DayStatus.partial:
            border = Border.all(color: hc, width: 2.5);
            break;
          case DayStatus.skipped:
            bg = cs.surfaceContainerHighest;
            fg = cs.onSurfaceVariant;
            break;
          case DayStatus.missed:
          case DayStatus.relapse:
            bg = cs.errorContainer;
            fg = cs.onErrorContainer;
            break;
          case DayStatus.pending:
            border = Border.all(color: cs.outline, width: 1.5);
            break;
          case DayStatus.notDue:
            fg = cs.onSurfaceVariant;
            break;
          case DayStatus.beforeStart:
          case DayStatus.future:
            fg = cs.onSurface.withValues(alpha: 0.38);
            break;
        }
        final bool tappable = st != DayStatus.future && st != DayStatus.beforeStart;
        row.add(Expanded(
          child: Semantics(
            button: tappable,
            label: '${formatWeekdayDate(d, spanish: es)}: ${dayStatusLabel(st, es)}',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: tappable ? () => DaySheet.show(context, habit, d) : null,
              child: ExcludeSemantics(
                child: SizedBox(
                  height: 48,
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: border ?? (sameDay(d, today) ? Border.all(color: cs.primary, width: 2) : null)),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text('${d.day}', style: theme.textTheme.bodyMedium?.copyWith(color: fg, fontWeight: st == DayStatus.skipped ? FontWeight.w400 : FontWeight.w600, decoration: st == DayStatus.skipped ? TextDecoration.lineThrough : null)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
      }
      rows.add(Row(children: row));
    }
    // Casi a todo el ancho: siete casillas de 48 dp caben en un teléfono de 360 dp.
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(tooltip: t(context, 'Mes anterior', 'Previous month'), icon: const Icon(Icons.chevron_left), onPressed: () => onMonth(DateTime(first.year, first.month - 1))),
                Expanded(child: Text(formatMonthYear(first, spanish: es), textAlign: TextAlign.center, style: theme.textTheme.titleMedium)),
                IconButton(tooltip: t(context, 'Mes siguiente', 'Next month'), icon: const Icon(Icons.chevron_right), onPressed: canNext ? () => onMonth(DateTime(first.year, first.month + 1)) : null),
              ],
            ),
            ExcludeSemantics(
              child: Row(
                children: <Widget>[
                  for (final int wd in orderedWeekdays(weekStart))
                    Expanded(child: Center(child: Text(weekdayLetter(wd, spanish: es), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)))),
                ],
              ),
            ),
            const SizedBox(height: 4),
            ...rows,
            const SizedBox(height: 8),
            ExcludeSemantics(
              child: Wrap(
                spacing: 14,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  _Legend(color: hc, label: habit.isNegative ? t(context, 'Sin recaer', 'No slip') : t(context, 'Hecho', 'Done')),
                  if (!habit.isNegative) _Legend(color: Colors.transparent, border: hc, label: t(context, 'A medias', 'Partly')),
                  if (!habit.isNegative) _Legend(color: cs.surfaceContainerHighest, label: t(context, 'Saltado', 'Skipped')),
                  _Legend(color: cs.errorContainer, label: habit.isNegative ? t(context, 'Recaída', 'Slip') : t(context, 'No se hizo', 'Missed')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.border});

  final Color color;
  final Color? border;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: border == null ? null : Border.all(color: border!, width: 2))),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
