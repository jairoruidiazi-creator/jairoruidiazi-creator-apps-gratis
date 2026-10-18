import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/dates.dart';
import '../../logic/summary.dart';
import '../../model/habit.dart';
import '../habits/habit_texts.dart';
import '../widgets/common.dart';

/// Resúmenes de la semana, el mes y el año: cumplimiento por hábito, totales,
/// mejor día, minutos con temporizador y entrenamientos.
class SummaryPage extends StatefulWidget {
  const SummaryPage({super.key, required this.today});

  final DateTime today;

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  SummaryRange _range = SummaryRange.week;
  late DateTime _anchor = widget.today;

  @override
  void didUpdateWidget(SummaryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!sameDay(oldWidget.today, widget.today) && sameDay(_anchor, oldWidget.today)) {
      _anchor = widget.today;
    }
  }

  String _periodLabel(PeriodSummary p, bool es) {
    switch (p.range) {
      case SummaryRange.week:
        return formatDayRange(p.start, p.end, spanish: es);
      case SummaryRange.month:
        return formatMonthYear(p.start, spanish: es);
      case SummaryRange.year:
        return '${p.start.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'Resumen', 'Summary'))),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[s.habits, s.timers, s.settings]),
        builder: (BuildContext context, Widget? _) {
          final bool es = s.settings.spanish;
          final int weekStart = s.settings.weekStart;
          final PeriodSummary p = Summaries.build(
            range: _range,
            anchor: _anchor,
            today: widget.today,
            weekStart: weekStart,
            habits: s.habits.habits,
            entries: s.habits.entries,
            sessions: s.timers.sessions,
          );
          final DateTime nextStart = Summaries.bounds(_range, Summaries.shift(_range, _anchor, 1), weekStart)[0];
          final bool canNext = !nextStart.isAfter(widget.today);
          final ThemeData theme = Theme.of(context);
          return ReadableWidth(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: <Widget>[
                      for (final SummaryRange r in SummaryRange.values)
                        ChoiceChip(
                          label: Text(_rangeLabel(r, es)),
                          selected: _range == r,
                          onSelected: (_) => setState(() {
                            _range = r;
                            _anchor = widget.today;
                          }),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: <Widget>[
                      IconButton(tooltip: t(context, 'Periodo anterior', 'Previous period'), icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _anchor = Summaries.shift(_range, _anchor, -1))),
                      Expanded(child: Text(_periodLabel(p, es), textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                      IconButton(tooltip: t(context, 'Periodo siguiente', 'Next period'), icon: const Icon(Icons.chevron_right), onPressed: canNext ? () => setState(() => _anchor = Summaries.shift(_range, _anchor, 1)) : null),
                    ],
                  ),
                ),
                if (p.habits.isEmpty && p.workouts == 0 && p.workoutSeconds == 0)
                  EmptyState(
                    icon: Icons.insights_outlined,
                    title: t(context, 'Todavía no hay datos de este periodo', 'No data for this period yet'),
                    message: t(context, 'Cuando marques hábitos o hagas entrenamientos, aquí verás tu cumplimiento.', 'Once you check off habits or do workouts, your progress shows up here.'),
                  )
                else ...<Widget>[
                  _Overview(summary: p),
                  if (p.habits.isNotEmpty) _BarsCard(summary: p, weekStart: weekStart),
                  if (p.habits.isNotEmpty) ...<Widget>[
                    SectionHeader(t(context, 'Por hábito', 'By habit')),
                    for (final HabitPeriodStats h in p.habits) _HabitRow(stats: h),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  static String _rangeLabel(SummaryRange r, bool es) {
    switch (r) {
      case SummaryRange.week:
        return es ? 'Semana' : 'Week';
      case SummaryRange.month:
        return es ? 'Mes' : 'Month';
      case SummaryRange.year:
        return es ? 'Año' : 'Year';
    }
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.summary});

  final PeriodSummary summary;

  @override
  Widget build(BuildContext context) {
    final bool es = isSpanish(context);
    final ThemeData theme = Theme.of(context);
    final PeriodSummary p = summary;
    final double? rate = p.rate;
    final List<Widget> tiles = <Widget>[
      _Tile(icon: Icons.check_circle_outline, label: t(context, 'Hábitos hechos', 'Habits done'), value: '${p.completions}'),
      if (p.bestDay != null) _Tile(icon: Icons.star_outline, label: t(context, 'Mejor día', 'Best day'), value: formatShortDate(p.bestDay!, spanish: es), detail: es ? '${p.bestDayCount} ${p.bestDayCount == 1 ? 'hábito' : 'hábitos'}' : '${p.bestDayCount} ${p.bestDayCount == 1 ? 'habit' : 'habits'}'),
      if (p.bestWeekday != null) _Tile(icon: Icons.event_repeat, label: t(context, 'Día más constante', 'Most consistent day'), value: weekdayName(p.bestWeekday!, spanish: es), detail: es ? '${p.bestWeekdayAverage.toStringAsFixed(1).replaceAll('.', ',')} en promedio' : '${p.bestWeekdayAverage.toStringAsFixed(1)} on average'),
      _Tile(icon: Icons.timer_outlined, label: t(context, 'Minutos con temporizador', 'Timed minutes'), value: formatDurationShort(p.timedSeconds, spanish: es)),
      _Tile(icon: Icons.fitness_center, label: t(context, 'Entrenamientos hechos', 'Workouts done'), value: '${p.workouts}', detail: formatDurationShort(p.workoutSeconds, spanish: es)),
    ];
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              label: rate == null ? t(context, 'Cumplimiento: sin datos', 'Success rate: no data') : (es ? 'Cumplimiento: ${(rate * 100).round()} por ciento' : 'Success rate: ${(rate * 100).round()} percent'),
              excludeSemantics: true,
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        SizedBox(width: 72, height: 72, child: CircularProgressIndicator(value: rate ?? 0, strokeWidth: 8, backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15))),
                        FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: const EdgeInsets.all(10), child: Text(rate == null ? '—' : '${(rate * 100).round()} %', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(t(context, 'Cumplimiento', 'Success rate'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          rate == null ? t(context, 'Aún no termina ningún periodo de tus hábitos.', 'None of your habit periods has ended yet.') : (es ? '${p.met} cumplidos de ${p.met + p.missed} (sin contar los días saltados)' : '${p.met} met out of ${p.met + p.missed} (skipped days excluded)'),
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: tiles),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.value, this.detail});

  final IconData icon;
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 320),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(14)),
        child: Semantics(
          label: '$label: $value${detail == null ? '' : ', $detail'}',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Flexible(child: Text(label, style: theme.textTheme.labelMedium)),
                ],
              ),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              if (detail != null) Text(detail!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hábitos hechos por día (semana y mes) o por mes (año).
class _BarsCard extends StatelessWidget {
  const _BarsCard({required this.summary, required this.weekStart});

  final PeriodSummary summary;
  final int weekStart;

  @override
  Widget build(BuildContext context) {
    final bool es = isSpanish(context);
    final ThemeData theme = Theme.of(context);
    final PeriodSummary p = summary;
    final int maxV = math.max(1, p.bars.fold<int>(0, (int a, int b) => math.max(a, b)));
    final List<String> labels = <String>[];
    final List<String> spoken = <String>[];
    for (int i = 0; i < p.bars.length; i++) {
      if (p.range == SummaryRange.year) {
        labels.add(monthShort(i + 1, spanish: es).substring(0, 1).toUpperCase());
        spoken.add('${monthName(i + 1, spanish: es)}: ${p.bars[i]}');
      } else {
        final DateTime d = addDays(p.start, i);
        if (p.range == SummaryRange.week) {
          labels.add(weekdayLetter(d.weekday, spanish: es));
        } else {
          labels.add(d.day == 1 || d.day % 5 == 0 ? '${d.day}' : '');
        }
        spoken.add('${formatShortDate(d, spanish: es)}: ${p.bars[i]}');
      }
    }
    final String title = p.range == SummaryRange.year ? t(context, 'Hábitos hechos por mes', 'Habits done per month') : t(context, 'Hábitos hechos por día', 'Habits done per day');
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Semantics(
              label: '$title. ${spoken.join(', ')}',
              excludeSemantics: true,
              child: SizedBox(
                height: 140,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    for (int i = 0; i < p.bars.length; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: p.bars.length > 12 ? 1 : 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: <Widget>[
                              Expanded(
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor: p.bars[i] == 0 ? 0.02 : p.bars[i] / maxV,
                                    child: Container(decoration: BoxDecoration(color: p.bars[i] == 0 ? theme.colorScheme.outlineVariant : theme.colorScheme.primary, borderRadius: BorderRadius.circular(4))),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 18,
                                child: FittedBox(fit: BoxFit.scaleDown, child: Text(labels[i], style: theme.textTheme.labelSmall)),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitRow extends StatelessWidget {
  const _HabitRow({required this.stats});

  final HabitPeriodStats stats;

  @override
  Widget build(BuildContext context) {
    final bool es = isSpanish(context);
    final ThemeData theme = Theme.of(context);
    final Habit h = stats.habit;
    final double? rate = stats.rate;
    final List<String> lines = <String>[];
    if (h.isNegative) {
      lines.add(es ? '${stats.cleanDays} ${stats.cleanDays == 1 ? 'día' : 'días'} sin recaer · ${stats.relapseDays} con recaída' : '${stats.cleanDays} ${stats.cleanDays == 1 ? 'day' : 'days'} clean · ${stats.relapseDays} with a slip');
    } else {
      final int closed = stats.met + stats.missed;
      lines.add(closed == 0 ? (es ? 'Periodo en curso' : 'Period in progress') : (es ? '${stats.met} de $closed cumplidos' : '${stats.met} of $closed met'));
      if (h.kind == HabitKind.count && stats.totalValue > 0) {
        lines.add(es ? 'Total: ${stats.totalValue} ${HabitTexts.unit(h, stats.totalValue, true)}' : 'Total: ${stats.totalValue} ${HabitTexts.unit(h, stats.totalValue, false)}');
      } else if (h.kind == HabitKind.timed && stats.totalValue > 0) {
        lines.add(es ? 'Total: ${formatDurationShort(stats.totalValue, spanish: true)}' : 'Total: ${formatDurationShort(stats.totalValue, spanish: false)}');
      }
      if (stats.skippedDays > 0) {
        lines.add(es ? '${stats.skippedDays} ${stats.skippedDays == 1 ? 'día saltado' : 'días saltados'}' : '${stats.skippedDays} skipped ${stats.skippedDays == 1 ? 'day' : 'days'}');
      }
    }
    final String pct = rate == null ? '—' : '${(rate * 100).round()} %';
    return Semantics(
      label: '${h.name}: $pct. ${lines.join('. ')}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: <Widget>[
            HabitAvatar(icon: h.icon, color: h.color, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(child: Text(h.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                      Text(pct, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: rate ?? 0, minHeight: 8, color: Color(h.color), backgroundColor: Color(h.color).withValues(alpha: 0.15)),
                  ),
                  const SizedBox(height: 4),
                  for (final String l in lines) Text(l, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
