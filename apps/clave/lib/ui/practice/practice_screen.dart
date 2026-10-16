import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../model/models.dart';
import '../../music/instruments.dart';

/// Registro de práctica: metas, racha, barras por día y desglose.
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> with AutomaticKeepAliveClientMixin {
  int _days = 7;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final Services s = AppScope.of(context);
    final AppState st = s.state;
    final bool spanish = s.settings.spanish;
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: st,
      builder: (BuildContext context, Widget? _) {
        final DateTime now = DateTime.now();
        final DateTime today = DateTime(now.year, now.month, now.day);
        final int todaySec = st.secondsOn(today);
        final DateTime weekStart = today.subtract(Duration(days: today.weekday - 1));
        final int weekSec = st.secondsBetween(weekStart, weekStart.add(const Duration(days: 7)));
        final int dailyGoal = s.settings.dailyGoalMinutes * 60;
        final int weeklyGoal = s.settings.weeklyGoalMinutes * 60;
        final List<int> bars = <int>[for (int i = _days - 1; i >= 0; i--) st.secondsOn(today.subtract(Duration(days: i)))];
        final List<DateTime> barDays = <DateTime>[for (int i = _days - 1; i >= 0; i--) today.subtract(Duration(days: i))];
        final Map<String, int> byInstrument = st.secondsByInstrument(days: _days);
        final Map<String, int> byTool = st.secondsByTool(days: _days);
        final int streak = st.streak();
        final List<PracticeSession> recent = st.sessions.reversed.take(30).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: _Goal(title: t(context, 'Hoy', 'Today'), done: todaySec, goal: dailyGoal, spanish: spanish)),
                const SizedBox(width: 10),
                Expanded(child: _Goal(title: t(context, 'Esta semana', 'This week'), done: weekSec, goal: weeklyGoal, spanish: spanish)),
              ],
            ),
            const SizedBox(height: 10),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.local_fire_department_rounded, color: ClaveColors.ambar),
                title: Text(streak == 1 ? t(context, '1 día seguido', '1 day in a row') : '$streak ${t(context, 'días seguidos', 'days in a row')}'),
                subtitle: Text(t(context, 'Cuenta los días con al menos 5 minutos. Descansar también es practicar: la racha no castiga.', 'Counts days with at least 5 minutes. Rest days are practice too: no penalty.')),
                trailing: TextButton(onPressed: () => _goalsDialog(context), child: Text(t(context, 'Metas', 'Goals'))),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(child: Text(t(context, 'Minutos por día', 'Minutes per day'), style: Theme.of(context).textTheme.titleMedium)),
                SegmentedButton<int>(
                  segments: const <ButtonSegment<int>>[
                    ButtonSegment<int>(value: 7, label: Text('7')),
                    ButtonSegment<int>(value: 14, label: Text('14')),
                    ButtonSegment<int>(value: 30, label: Text('30')),
                  ],
                  selected: <int>{_days},
                  showSelectedIcon: false,
                  onSelectionChanged: (Set<int> v) => setState(() => _days = v.first),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: CustomPaint(painter: _BarsPainter(values: bars, days: barDays, goal: dailyGoal, color: cs.primary, onSurface: cs.onSurface, spanish: spanish), child: const SizedBox.expand()),
            ),
            const SizedBox(height: 16),
            Text(t(context, 'Por instrumento', 'By instrument'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            if (byInstrument.isEmpty) Text(t(context, 'Aún no hay sesiones en este periodo.', 'No sessions in this period yet.'), style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
            for (final MapEntry<String, int> e in (byInstrument.entries.toList()..sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value))))
              _Breakdown(label: Instruments.byId(e.key).name(spanish), seconds: e.value, total: byInstrument.values.fold<int>(0, (int a, int b) => a + b), color: cs.primary),
            const SizedBox(height: 12),
            Text(t(context, 'Por herramienta', 'By tool'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            for (final MapEntry<String, int> e in (byTool.entries.toList()..sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value))))
              _Breakdown(label: _toolName(context, e.key), seconds: e.value, total: byTool.values.fold<int>(0, (int a, int b) => a + b), color: ClaveColors.ambar),
            const SizedBox(height: 12),
            Text(t(context, 'Últimas sesiones', 'Recent sessions'), style: Theme.of(context).textTheme.titleMedium),
            for (final PracticeSession ps in recent)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(_toolIcon(ps.tool), color: cs.onSurface.withValues(alpha: 0.7)),
                title: Text('${_toolName(context, ps.tool)} · ${Instruments.byId(ps.instrumentId).name(spanish)}'),
                subtitle: Text('${_dateTime(ps.start)} · ${formatMinutes(ps.seconds, spanish: spanish)}'),
              ),
            if (recent.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(t(context, 'Las sesiones se registran solas cuando usas el afinador, el metrónomo, el tono o la grabadora.', 'Sessions are logged automatically when you use the tuner, metronome, drone or recorder.'), style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
              ),
          ],
        );
      },
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('${t(context, 'Diaria', 'Daily')}: $daily min'),
              Slider(min: 5, max: 180, divisions: 35, value: daily.toDouble(), onChanged: (double v) => setDialog(() => daily = v.round())),
              Text('${t(context, 'Semanal', 'Weekly')}: $weekly min'),
              Slider(min: 30, max: 1200, divisions: 39, value: weekly.toDouble(), onChanged: (double v) => setDialog(() => weekly = v.round())),
            ],
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

  String _toolName(BuildContext context, String tool) {
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

  String _dateTime(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
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
    return Card(
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
                children: <Widget>[
                  CircularProgressIndicator(value: frac, strokeWidth: 6, backgroundColor: cs.surfaceContainerHighest, color: frac >= 1 ? ClaveColors.afinado : cs.primary),
                  Text('${(frac * 100).round()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.65))),
                  Text(formatMinutes(done, spanish: spanish), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text('${spanish ? 'meta' : 'goal'} ${formatMinutes(goal, spanish: spanish)}', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.65))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.label, required this.seconds, required this.total, required this.color});

  final String label;
  final int seconds;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final double frac = total <= 0 ? 0 : seconds / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          SizedBox(width: 130, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: frac, minHeight: 10, color: color, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 70, child: Text(formatMinutes(seconds), textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.values, required this.days, required this.goal, required this.color, required this.onSurface, required this.spanish});

  final List<int> values;
  final List<DateTime> days;
  final int goal;
  final Color color;
  final Color onSurface;
  final bool spanish;

  @override
  void paint(Canvas canvas, Size size) {
    final int n = values.length;
    if (n == 0) {
      return;
    }
    const double bottom = 22;
    final double h = size.height - bottom;
    final int maxV = math.max(goal, values.fold<int>(0, math.max));
    final double gap = n > 14 ? 2 : 6;
    final double w = (size.width - gap * (n - 1)) / n;
    // Línea de la meta.
    if (goal > 0 && maxV > 0) {
      final double gy = h - h * goal / maxV;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), Paint()..color = ClaveColors.ambar.withValues(alpha: 0.7)..strokeWidth = 1.5);
    }
    for (int i = 0; i < n; i++) {
      final double bh = maxV == 0 ? 0 : h * values[i] / maxV;
      final Rect r = Rect.fromLTWH(i * (w + gap), h - bh, w, bh);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), Paint()..color = values[i] >= goal && goal > 0 ? ClaveColors.afinado : color.withValues(alpha: 0.8));
      if (n <= 14 || i % 5 == 0 || i == n - 1) {
        final DateTime d = days[i];
        final String label = n <= 7 ? (spanish ? <String>['L', 'M', 'X', 'J', 'V', 'S', 'D'] : <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'])[d.weekday - 1] : '${d.day}';
        final TextPainter tp = TextPainter(text: TextSpan(text: label, style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.6))), textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(i * (w + gap) + w / 2 - tp.width / 2, h + 4));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => true;
}
