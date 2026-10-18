import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/dates.dart';
import '../../logic/templates.dart';
import '../../logic/timer_engine.dart';
import '../../model/workout.dart';
import '../widgets/common.dart';
import 'countdown_view.dart';
import 'runner_screen.dart';
import 'stopwatch_view.dart';
import 'timer_texts.dart';
import 'workout_editor.dart';

/// Pestaña del temporizador: entrenamientos por intervalos, cronómetro y
/// cuenta regresiva.
class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<String> labels = <String>[t(context, 'Intervalos', 'Intervals'), t(context, 'Cronómetro', 'Stopwatch'), t(context, 'Cuenta regresiva', 'Countdown')];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final bool fixed = _tabsFit(context, labels, box.maxWidth);
        return Scaffold(
          appBar: AppBar(
            title: Text(t(context, 'Temporizador', 'Timer')),
            bottom: TabBar(
              controller: _tabs,
              isScrollable: !fixed,
              tabAlignment: fixed ? TabAlignment.fill : TabAlignment.start,
              labelPadding: fixed ? const EdgeInsets.symmetric(horizontal: _kFixedTabPadding) : null,
              tabs: <Widget>[for (final String l in labels) Tab(text: l)],
            ),
          ),
          floatingActionButton: _tabs.index == 0
              ? FloatingActionButton.extended(
                  heroTag: 'fab-workout',
                  onPressed: () => showTemplateSheet(context),
                  icon: const Icon(Icons.add),
                  label: Text(t(context, 'Entrenamiento', 'Workout')),
                )
              : null,
          body: TabBarView(
            controller: _tabs,
            children: const <Widget>[
              WorkoutsTab(),
              StopwatchView(),
              CountdownView(),
            ],
          ),
        );
      },
    );
  }

  /// Las tres pestañas van a lo ancho si sus nombres caben enteros; con el
  /// texto muy grande, la barra de pestañas se desplaza.
  static bool _tabsFit(BuildContext context, List<String> labels, double width) {
    final ThemeData theme = Theme.of(context);
    final TextStyle style = theme.tabBarTheme.labelStyle ?? theme.textTheme.titleSmall ?? const TextStyle(fontSize: 14);
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    double widest = 0;
    for (final String l in labels) {
      final TextPainter tp = TextPainter(text: TextSpan(text: l, style: style), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
      widest = math.max(widest, tp.width);
      tp.dispose();
    }
    return (widest + 2 * _kFixedTabPadding) * labels.length <= width;
  }
}

/// Margen a cada lado del nombre de una pestaña fija.
const double _kFixedTabPadding = 8;

/// Elegir una plantilla para un entrenamiento nuevo.
Future<void> showTemplateSheet(BuildContext context) async {
  final Services s = AppScope.read(context);
  final bool es = s.settings.spanish;
  final WorkoutTemplate? picked = await showModalBottomSheet<WorkoutTemplate>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (BuildContext ctx) => SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(t(context, 'Empezar desde', 'Start from'), style: Theme.of(ctx).textTheme.titleLarge),
          ),
          for (final WorkoutTemplate tpl in WorkoutTemplate.values)
            ListTile(
              leading: Icon(_templateIcon(tpl)),
              title: Text(TimerTexts.template(tpl, es)),
              subtitle: Text(TimerTexts.templateHelp(tpl, es)),
              onTap: () => Navigator.of(ctx).pop(tpl),
            ),
        ],
      ),
    ),
  );
  if (picked == null || !context.mounted) {
    return;
  }
  final Workout w = WorkoutTemplates.create(picked, spanish: es, now: clock.now());
  await WorkoutEditorScreen.open(context, workout: w, isNew: true);
}

IconData _templateIcon(WorkoutTemplate t) {
  switch (t) {
    case WorkoutTemplate.hiit:
      return Icons.local_fire_department;
    case WorkoutTemplate.tabata:
      return Icons.timer;
    case WorkoutTemplate.circuit:
      return Icons.loop;
    case WorkoutTemplate.custom:
      return Icons.tune;
  }
}

/// Lista de entrenamientos y el historial reciente.
class WorkoutsTab extends StatelessWidget {
  const WorkoutsTab({super.key});

  Future<void> _start(BuildContext context, Workout w) async {
    final Services s = AppScope.read(context);
    final bool ok = await RunnerScreen.beforeStart(context);
    if (!ok || !context.mounted) {
      return;
    }
    if (!s.timer.startWorkout(w)) {
      showSnack(context, t(context, 'Este entrenamiento no tiene intervalos.', 'This workout has no intervals.'));
      return;
    }
    unawaited(s.notices.askNotifications());
    await RunnerScreen.open(context);
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[s.timers, s.settings]),
      builder: (BuildContext context, Widget? _) {
        final bool es = s.settings.spanish;
        final List<Workout> list = s.timers.sortedWorkouts;
        final List<WorkoutSession> history = List<WorkoutSession>.of(s.timers.sessions)..sort((WorkoutSession a, WorkoutSession b) => b.startedAt.compareTo(a.startedAt));
        if (list.isEmpty) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 104),
            children: <Widget>[
              EmptyState(
                icon: Icons.fitness_center,
                title: t(context, 'Arma tu primer entrenamiento', 'Build your first workout'),
                message: t(context, 'Intervalos con su color, voz que los anuncia y bloques que se repiten. Empieza desde una plantilla:', 'Colored intervals, a voice that announces them and repeating blocks. Start from a template:'),
              ),
              for (final WorkoutTemplate tpl in WorkoutTemplate.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  child: FilledButton.tonalIcon(
                    onPressed: () => WorkoutEditorScreen.open(context, workout: WorkoutTemplates.create(tpl, spanish: es, now: clock.now()), isNew: true),
                    icon: Icon(_templateIcon(tpl)),
                    label: Text(TimerTexts.template(tpl, es)),
                  ),
                ),
            ],
          );
        }
        return ReadableWidth(
          child: ListView(
            padding: const EdgeInsets.only(top: 6, bottom: 104),
            children: <Widget>[
              for (final Workout w in list) _WorkoutCard(workout: w, onStart: () => _start(context, w)),
              if (history.isNotEmpty) ...<Widget>[
                SectionHeader(t(context, 'Historial', 'History')),
                for (final WorkoutSession h in history.take(8))
                  ListTile(
                    leading: Icon(h.completed ? Icons.check_circle_outline : Icons.timelapse, color: h.completed ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline),
                    title: Text(h.name),
                    subtitle: Text('${formatShortDate(h.startedAt, spanish: es)}, ${formatTime(h.startedAt, spanish: es)} · ${formatDurationShort(h.activeSeconds, spanish: es)}${h.completed ? '' : (es ? ' · sin terminar' : ' · not finished')}'),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.workout, required this.onStart});

  final Workout workout;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final bool es = isSpanish(context);
    final ThemeData theme = Theme.of(context);
    final List<TimerSegment> segs = TimerEngine.flatten(workout.nodes);
    final int total = TimerEngine.totalSeconds(segs);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => WorkoutEditorScreen.open(context, workout: workout),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Semantics(
                      label: '${workout.name}. ${TimerTexts.summary(segs, es)}',
                      excludeSemantics: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(workout.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          Text(TimerTexts.summary(segs, es), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                  FilledButton.icon(onPressed: segs.isEmpty ? null : onStart, icon: const Icon(Icons.play_arrow), label: Text(t(context, 'Iniciar', 'Start'))),
                ],
              ),
              const SizedBox(height: 10),
              if (total > 0) ExcludeSemantics(child: SegmentBar(segments: segs)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra con los intervalos en su color y proporción.
class SegmentBar extends StatelessWidget {
  const SegmentBar({super.key, required this.segments, this.height = 10});

  final List<TimerSegment> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final int total = TimerEngine.totalSeconds(segments);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: CustomPaint(painter: _SegmentPainter(segments, total)),
      ),
    );
  }
}

class _SegmentPainter extends CustomPainter {
  _SegmentPainter(this.segments, this.total);

  final List<TimerSegment> segments;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) {
      return;
    }
    double x = 0;
    for (final TimerSegment s in segments) {
      final double w = size.width * s.seconds / total;
      canvas.drawRect(Rect.fromLTWH(x, 0, w + 0.5, size.height), Paint()..color = Color(s.color));
      x += w;
    }
  }

  @override
  bool shouldRepaint(_SegmentPainter old) => old.segments != segments || old.total != total;
}
