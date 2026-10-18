import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/practice_log.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../music/instruments.dart';
import '../widgets/adaptive.dart';

/// Registro de práctica: metas, racha, minutos por día, desglose y últimas
/// sesiones. Con la pestaña a la vista se actualiza cada segundo mientras
/// alguna herramienta cuenta; oculta, no se redibuja.
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key, this.active = true});

  /// Si la pestaña está a la vista.
  final bool active;

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

/// Nombre de cada herramienta en el registro.
String practiceToolName(BuildContext context, String tool) {
  switch (tool) {
    case 'afinador':
      return t(context, 'Afinador', 'Tuner');
    case 'metronomo':
      return t(context, 'Metrónomo', 'Metronome');
    case 'tono':
      return t(context, 'Tono y teclado', 'Drone & keyboard');
    case 'grabadora':
      return t(context, 'Grabadora', 'Recorder');
    default:
      return tool;
  }
}

class _PracticeScreenState extends State<PracticeScreen> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    if (!widget.active) {
      return _content(context, s);
    }
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[s.practice, s.settings]),
      builder: (BuildContext context, Widget? _) => _content(context, s),
    );
  }

  Widget _content(BuildContext context, Services s) {
    final PracticeLog log = s.practice;
    final AppSettings st = s.settings;
    final bool spanish = isSpanish(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final ClavePalette pal = ClavePalette.of(context);
    final MaterialLocalizations ml = MaterialLocalizations.of(context);
    final DateTime now = clock.now();
    final DateTime today = PracticeLog.dayOf(now);
    // La semana empieza el lunes en español y el domingo en inglés.
    final int sinceWeekStart = (today.weekday % 7 - ml.firstDayOfWeekIndex + 7) % 7;
    final DateTime weekStart = DateTime(today.year, today.month, today.day - sinceWeekStart);
    final DateTime weekEnd = DateTime(weekStart.year, weekStart.month, weekStart.day + 7);
    final Map<DateTime, int> daily = log.dailySeconds();
    final int todaySec = daily[today] ?? 0;
    final int weekSec = log.secondsBetween(weekStart, weekEnd);
    final int dailyGoal = st.dailyGoalMinutes * 60;
    final int weeklyGoal = st.weeklyGoalMinutes * 60;
    final List<DateTime> barDays = <DateTime>[for (int i = _days - 1; i >= 0; i--) DateTime(today.year, today.month, today.day - i)];
    final List<int> bars = <int>[for (final DateTime d in barDays) daily[d] ?? 0];
    final DateTime from = barDays.first;
    final Map<String, int> byInstrument = log.secondsByInstrument(from: from);
    final Map<String, int> byTool = log.secondsByTool(from: from);
    final int streak = log.streak();
    final List<SessionGroup> recent = log.recentGroups();
    final int periodTotal = bars.fold<int>(0, (int a, int b) => a + b);
    final int goalDays = dailyGoal <= 0 ? 0 : bars.where((int v) => v >= dailyGoal).length;
    final String chartSummary = t(
      context,
      'Últimos $_days días: ${formatPracticeTime(periodTotal)} en total. Meta diaria cumplida ${goalDays == 1 ? '1 día' : '$goalDays días'}. Hoy: ${formatPracticeTime(todaySec)}.',
      'Last $_days days: ${formatPracticeTime(periodTotal)} in total. Daily goal met on ${goalDays == 1 ? '1 day' : '$goalDays days'}. Today: ${formatPracticeTime(todaySec)}.',
    );
    final List<MapEntry<String, int>> instruments = byInstrument.entries.toList()..sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));
    final List<MapEntry<String, int>> tools = byTool.entries.toList()..sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));
    final int maxInstrument = instruments.isEmpty ? 0 : instruments.first.value;
    final int maxTool = tools.isEmpty ? 0 : tools.first.value;
    final TextStyle? section = Theme.of(context).textTheme.titleMedium;
    final TextStyle muted = TextStyle(color: cs.onSurfaceVariant);

    return ReadableWidth(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: <Widget>[
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final Widget day = _Goal(title: t(context, 'Hoy', 'Today'), done: todaySec, goal: dailyGoal, spanish: spanish);
              final Widget week = _Goal(title: t(context, 'Esta semana', 'This week'), done: weekSec, goal: weeklyGoal, spanish: spanish);
              // Con letra grande en un teléfono estrecho, una meta debajo de la otra.
              if (c.maxWidth < 340 || (MediaQuery.textScalerOf(context).scale(14) > 17 && c.maxWidth < 420)) {
                return Column(children: <Widget>[day, const SizedBox(height: 10), week]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: day),
                  const SizedBox(width: 10),
                  Expanded(child: week),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: <Widget>[
                  ExcludeSemantics(child: Icon(Icons.local_fire_department_rounded, color: pal.accent)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          streak == 1 ? t(context, '1 día seguido', '1 day in a row') : '$streak ${t(context, 'días seguidos', 'days in a row')}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t(context, 'Cuenta los días con al menos 5 minutos. Puedes descansar un día de cada siete sin perder la racha.', 'Counts days with at least 5 minutes. You can rest one day in seven without losing the streak.'),
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                  TextButton(onPressed: () => _goalsDialog(context), child: Text(t(context, 'Metas', 'Goals'))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              Text(t(context, 'Minutos por día', 'Minutes per day'), style: section),
              SegmentedButton<int>(
                segments: <ButtonSegment<int>>[
                  for (final int d in <int>[7, 14, 30]) ButtonSegment<int>(value: d, label: Text('$d'), tooltip: t(context, '$d días', '$d days')),
                ],
                selected: <int>{_days},
                showSelectedIcon: false,
                onSelectionChanged: (Set<int> v) => setState(() => _days = v.first),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            container: true,
            label: chartSummary,
            child: SizedBox(
              height: 168,
              child: CustomPaint(
                painter: _BarsPainter(
                  values: bars,
                  days: barDays,
                  goal: dailyGoal,
                  color: cs.primary,
                  reached: pal.inTune,
                  goalLine: pal.accent,
                  // Con la tipografía del tema (Roboto o la del sistema en
                  // iOS), no con la fuente por defecto del lienzo.
                  labelStyle: Theme.of(context).textTheme.labelSmall!.copyWith(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant),
                  narrowWeekdays: ml.narrowWeekdays,
                  textScaler: MediaQuery.textScalerOf(context),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: <Widget>[
              _Legend(color: cs.primary, label: t(context, 'Práctica del día', 'Practice that day')),
              _Legend(color: pal.inTune, label: t(context, 'Meta cumplida', 'Goal met')),
              _Legend(color: pal.accent, label: t(context, 'Meta diaria', 'Daily goal'), line: true),
            ],
          ),
          const SizedBox(height: 16),
          Text(t(context, 'Por instrumento', 'By instrument'), style: section),
          const SizedBox(height: 6),
          if (instruments.isEmpty) Text(t(context, 'Aún no hay práctica en este periodo.', 'No practice in this period yet.'), style: muted),
          for (final MapEntry<String, int> e in instruments)
            _Breakdown(
              label: Instruments.maybeById(e.key)?.name(spanish) ?? t(context, 'Sin instrumento', 'No instrument'),
              seconds: e.value,
              max: maxInstrument,
              color: cs.primary,
            ),
          const SizedBox(height: 12),
          Text(t(context, 'Por herramienta', 'By tool'), style: section),
          const SizedBox(height: 6),
          if (tools.isEmpty) Text(t(context, 'Aún no hay práctica en este periodo.', 'No practice in this period yet.'), style: muted),
          for (final MapEntry<String, int> e in tools) _Breakdown(label: practiceToolName(context, e.key), seconds: e.value, max: maxTool, color: pal.accent),
          const SizedBox(height: 12),
          Text(t(context, 'Últimas sesiones', 'Recent sessions'), style: section),
          for (final SessionGroup g in recent) _sessionTile(context, log, g, now, spanish),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                t(
                  context,
                  'Las sesiones se registran solas: el metrónomo mientras suena, el tono y el teclado mientras suenan, la grabadora mientras graba y el afinador mientras oye tu instrumento.',
                  'Sessions are logged automatically: the metronome while it plays, the drone and keyboard while they sound, the recorder while it records and the tuner while it hears your instrument.',
                ),
                style: muted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sessionTile(BuildContext context, PracticeLog log, SessionGroup g, DateTime now, bool spanish) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String? instrument = Instruments.maybeById(g.instrumentId)?.name(spanish);
    final bool live = log.isActive(g.tool) && now.difference(g.end) < const Duration(seconds: 3);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: ExcludeSemantics(child: Icon(_toolIcon(g.tool), color: cs.onSurfaceVariant)),
      title: Text('${practiceToolName(context, g.tool)}${instrument == null ? '' : ' · $instrument'}'),
      subtitle: Text('${formatDateTime(context, g.start)} · ${formatPracticeTime(g.activeSeconds)}${live ? ' · ${t(context, 'en curso', 'in progress')}' : ''}'),
    );
  }

  Future<void> _goalsDialog(BuildContext context) async {
    final Services s = AppScope.of(context);
    int daily = s.settings.dailyGoalMinutes;
    int weekly = s.settings.weeklyGoalMinutes;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, void Function(void Function()) setDialog) => AlertDialog(
          title: Text(t(context, 'Metas de práctica', 'Practice goals')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('${t(context, 'Diaria', 'Daily')}: ${formatMinutes(daily * 60)}'),
                Slider(
                  min: 5,
                  max: 180,
                  divisions: 35,
                  value: daily.toDouble().clamp(5.0, 180.0),
                  semanticFormatterCallback: (double v) => '${t(context, 'Meta diaria', 'Daily goal')}: ${formatMinutes(v.round() * 60)}',
                  onChanged: (double v) => setDialog(() => daily = v.round()),
                ),
                Text('${t(context, 'Semanal', 'Weekly')}: ${formatMinutes(weekly * 60)}'),
                Slider(
                  min: 30,
                  max: 1200,
                  divisions: 39,
                  value: weekly.toDouble().clamp(30.0, 1200.0),
                  semanticFormatterCallback: (double v) => '${t(context, 'Meta semanal', 'Weekly goal')}: ${formatMinutes(v.round() * 60)}',
                  onChanged: (double v) => setDialog(() => weekly = v.round()),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t(context, 'Cancelar', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t(context, 'Guardar', 'Save'))),
          ],
        ),
      ),
    );
    if (ok == true) {
      s.settings.dailyGoalMinutes = daily;
      s.settings.weeklyGoalMinutes = weekly;
      await s.settings.save();
    }
  }

  IconData _toolIcon(String tool) {
    switch (tool) {
      case 'afinador':
        return Icons.graphic_eq_rounded;
      case 'metronomo':
        return Icons.timer_outlined;
      case 'tono':
        return Icons.piano_rounded;
      default:
        return Icons.mic_none_rounded;
    }
  }
}

class _Goal extends StatelessWidget {
  const _Goal({required this.title, required this.done, required this.goal, required this.spanish});

  final String title;
  final int done;
  final int goal;
  final bool spanish;

  @override
  Widget build(BuildContext context) {
    final double frac = goal <= 0 ? 0 : (done / goal).clamp(0.0, 1.0);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final ClavePalette pal = ClavePalette.of(context);
    final String percent = formatPercent(frac, spanish: spanish);
    return Semantics(
      container: true,
      label: '$title: ${formatPracticeTime(done)} ${spanish ? 'de' : 'of'} ${formatMinutes(goal)} ($percent)',
      excludeSemantics: true,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  fit: StackFit.expand,
                  children: <Widget>[
                    CircularProgressIndicator(value: frac, strokeWidth: 6, backgroundColor: cs.surfaceContainerHighest, color: frac >= 1 ? pal.inTune : cs.primary),
                    Padding(
                      padding: const EdgeInsets.all(9),
                      child: FittedBox(fit: BoxFit.scaleDown, child: Text(percent, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    Text(formatPracticeTime(done), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    Text('${spanish ? 'meta' : 'goal'} ${formatMinutes(goal)}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.line = false});

  final Color color;
  final String label;
  final bool line;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(
          child: Container(
            width: 14,
            height: line ? 3 : 14,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(line ? 1 : 3)),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.label, required this.seconds, required this.max, required this.color});

  final String label;
  final int seconds;

  /// El valor más alto de la lista (su barra va llena).
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final double frac = max <= 0 ? 0 : (seconds / max).clamp(0.0, 1.0);
    final String time = formatPracticeTime(seconds);
    return Semantics(
      container: true,
      label: '$label: $time',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Text(time, style: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: frac, minHeight: 8, color: color, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.days,
    required this.goal,
    required this.color,
    required this.reached,
    required this.goalLine,
    required this.labelStyle,
    required this.narrowWeekdays,
    required this.textScaler,
  });

  final List<int> values;
  final List<DateTime> days;
  final int goal;
  final Color color;
  final Color reached;
  final Color goalLine;
  final TextStyle labelStyle;

  /// Iniciales de los días desde el domingo (MaterialLocalizations).
  final List<String> narrowWeekdays;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    final int n = values.length;
    if (n == 0) {
      return;
    }
    final double bottom = 8 + textScaler.scale(12);
    final double h = size.height - bottom;
    final int maxV = math.max(goal, values.fold<int>(0, math.max));
    final double gap = n > 14 ? 2 : 6;
    final double w = (size.width - gap * (n - 1)) / n;
    for (int i = 0; i < n; i++) {
      final double bh = maxV == 0 ? 0 : h * values[i] / maxV;
      final Rect r = Rect.fromLTWH(i * (w + gap), h - bh, w, bh);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), Paint()..color = values[i] >= goal && goal > 0 ? reached : color);
      if (n <= 14 || i % 5 == 0 || i == n - 1) {
        final DateTime d = days[i];
        final String text = n <= 7 ? narrowWeekdays[d.weekday % 7] : '${d.day}';
        final TextPainter tp = TextPainter(
          text: TextSpan(text: text, style: labelStyle),
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
        )..layout();
        tp.paint(canvas, Offset(i * (w + gap) + w / 2 - tp.width / 2, h + 4));
      }
    }
    // Línea de la meta, encima de las barras.
    if (goal > 0 && maxV > 0) {
      final double gy = h - h * goal / maxV;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), Paint()
        ..color = goalLine
        ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => true;
}
