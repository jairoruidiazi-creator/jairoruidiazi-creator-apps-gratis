import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../logic/timer_engine.dart';
import '../../model/workout.dart';
import '../catalog.dart';
import '../widgets/common.dart';
import 'runner_screen.dart';
import 'timer_page.dart';
import 'timer_texts.dart';

/// Editor de un entrenamiento: intervalos y bloques que se repiten, anidados
/// hasta tres niveles (por ejemplo, series de rondas de trabajo y descanso).
class WorkoutEditorScreen extends StatefulWidget {
  const WorkoutEditorScreen({super.key, required this.workout, this.isNew = false});

  final Workout workout;
  final bool isNew;

  static Future<void> open(BuildContext context, {required Workout workout, bool isNew = false}) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkoutEditorScreen(workout: workout, isNew: isNew), fullscreenDialog: isNew));

  @override
  State<WorkoutEditorScreen> createState() => _WorkoutEditorScreenState();
}

/// Bloques dentro de bloques: hasta tres niveles.
const int kMaxBlockDepth = 3;

class _WorkoutEditorScreenState extends State<WorkoutEditorScreen> {
  late final Workout _w = widget.workout.copy();
  late final TextEditingController _name = TextEditingController(text: _w.name);
  bool _dirty = false;
  bool _nameError = false;

  @override
  void initState() {
    super.initState();
    _dirty = widget.isNew;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _changed(VoidCallback f) => setState(() {
        f();
        _dirty = true;
      });

  bool _store() {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = true);
      return false;
    }
    _w.name = name;
    AppScope.read(context).timers.updateWorkout(_w.copy());
    _dirty = false;
    return true;
  }

  void _save() {
    if (_store()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _start() async {
    final Services s = AppScope.read(context);
    if (!_store()) {
      return;
    }
    if (TimerEngine.flatten(_w.nodes).isEmpty) {
      showSnack(context, t(context, 'Agrega al menos un intervalo.', 'Add at least one interval.'));
      return;
    }
    final bool ok = await RunnerScreen.confirmReplace(context);
    if (!ok || !mounted) {
      return;
    }
    s.timer.startWorkout(s.timers.workoutById(_w.id) ?? _w);
    unawaited(s.notices.askNotifications());
    await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const RunnerScreen()));
  }

  Future<void> _delete() async {
    final Services s = AppScope.read(context);
    final bool ok = await confirm(context, title: t(context, '¿Borrar este entrenamiento?', 'Delete this workout?'), message: _w.name, yes: t(context, 'Borrar', 'Delete'), destructive: true);
    if (!ok || !mounted) {
      return;
    }
    s.timers.removeWorkout(_w.id);
    _dirty = false;
    Navigator.of(context).pop();
  }

  void _duplicate() {
    final Services s = AppScope.read(context);
    final Workout copy = Workout.fromJson(_w.toJson()..['id'] = newId());
    copy.name = s.settings.spanish ? '${_name.text.trim()} (copia)' : '${_name.text.trim()} (copy)';
    copy.createdAt = clock.now();
    s.timers.addWorkout(copy);
    showSnack(context, t(context, 'Entrenamiento duplicado.', 'Workout duplicated.'));
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) {
      return true;
    }
    return confirm(context, title: t(context, '¿Salir sin guardar?', 'Leave without saving?'), message: t(context, 'Los cambios de este entrenamiento se pierden.', 'The changes to this workout will be lost.'), yes: t(context, 'Salir', 'Leave'), destructive: true);
  }

  Future<void> _editStep(List<TimerNode> list, int index) async {
    final IntervalStep current = list[index] as IntervalStep;
    final IntervalStep? edited = await _StepSheet.show(context, current);
    if (edited != null) {
      _changed(() => list[index] = edited);
    }
  }

  Future<void> _addStep(List<TimerNode> list) async {
    final bool es = isSpanish(context);
    // Alterna trabajo y descanso según el último intervalo de la lista.
    StepKind kind = StepKind.work;
    for (int i = list.length - 1; i >= 0; i--) {
      final TimerNode n = list[i];
      if (n is IntervalStep) {
        kind = n.kind == StepKind.work ? StepKind.rest : StepKind.work;
        break;
      }
    }
    final IntervalStep fresh = IntervalStep(name: TimerTexts.kind(kind, es), seconds: kind == StepKind.rest ? 15 : 30, kind: kind);
    final IntervalStep? edited = await _StepSheet.show(context, fresh, isNew: true);
    if (edited != null) {
      _changed(() => list.add(edited));
    }
  }

  Future<void> _addBlock(List<TimerNode> list) async {
    final bool es = isSpanish(context);
    final RepeatBlock block = RepeatBlock(repeats: 3, children: <TimerNode>[
      IntervalStep(name: TimerTexts.kind(StepKind.work, es), seconds: 30, kind: StepKind.work),
      IntervalStep(name: TimerTexts.kind(StepKind.rest, es), seconds: 15, kind: StepKind.rest),
    ]);
    final RepeatBlock? edited = await _BlockSheet.show(context, block, isNew: true);
    if (edited != null) {
      _changed(() => list.add(edited));
    }
  }

  Future<void> _editBlock(List<TimerNode> list, int index) async {
    final RepeatBlock current = list[index] as RepeatBlock;
    final RepeatBlock? edited = await _BlockSheet.show(context, current);
    if (edited != null) {
      _changed(() {
        current.name = edited.name;
        current.repeats = edited.repeats;
        current.skipLastRest = edited.skipLastRest;
      });
    }
  }

  void _nodeAction(List<TimerNode> list, int index, String action) {
    final bool es = isSpanish(context);
    switch (action) {
      case 'up':
        if (index > 0) {
          _changed(() {
            final TimerNode n = list.removeAt(index);
            list.insert(index - 1, n);
          });
        }
        break;
      case 'down':
        if (index < list.length - 1) {
          _changed(() {
            final TimerNode n = list.removeAt(index);
            list.insert(index + 1, n);
          });
        }
        break;
      case 'duplicate':
        _changed(() => list.insert(index + 1, list[index].clone()));
        break;
      case 'delete':
        final TimerNode removed = list[index];
        _changed(() => list.removeAt(index));
        showSnack(context, es ? 'Se quitó un elemento.' : 'An item was removed.', actionLabel: es ? 'Deshacer' : 'Undo', onAction: () {
          if (mounted) {
            _changed(() => list.insert(index.clamp(0, list.length), removed));
          }
        });
        break;
    }
  }

  Widget _menu(List<TimerNode> list, int index, String name) {
    final bool es = isSpanish(context);
    return PopupMenuButton<String>(
      tooltip: es ? 'Opciones de $name' : 'Options for $name',
      onSelected: (String a) => _nodeAction(list, index, a),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        if (index > 0) PopupMenuItem<String>(value: 'up', child: Text(es ? 'Subir' : 'Move up')),
        if (index < list.length - 1) PopupMenuItem<String>(value: 'down', child: Text(es ? 'Bajar' : 'Move down')),
        PopupMenuItem<String>(value: 'duplicate', child: Text(es ? 'Duplicar' : 'Duplicate')),
        PopupMenuItem<String>(value: 'delete', child: Text(es ? 'Quitar' : 'Remove')),
      ],
    );
  }

  List<Widget> _nodes(List<TimerNode> list, int depth) {
    final bool es = isSpanish(context);
    final ThemeData theme = Theme.of(context);
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < list.length; i++) {
      final TimerNode n = list[i];
      if (n is IntervalStep) {
        final Color c = Color(n.color ?? defaultStepColor(n.kind));
        final String name = n.name.trim().isEmpty ? TimerTexts.kind(n.kind, es) : n.name.trim();
        final String sub = '${formatClock(n.seconds)} · ${TimerTexts.kind(n.kind, es)} · ${TimerTexts.sound(n.sound == CueSound.auto ? defaultStepSound(n.kind) : n.sound, es)}';
        out.add(Card(
          margin: const EdgeInsets.symmetric(vertical: 3),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _editStep(list, i),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
              child: Row(
                children: <Widget>[
                  ExcludeSemantics(child: Container(width: 14, height: 40, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(7)))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      label: '$name. $sub',
                      excludeSemantics: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(name, style: theme.textTheme.titleMedium),
                          Text(sub, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                  _menu(list, i, name),
                ],
              ),
            ),
          ),
        ));
      } else if (n is RepeatBlock) {
        final String label = n.name.trim().isEmpty ? (es ? 'Bloque' : 'Block') : n.name.trim();
        final String head = es ? '$label · repetir ${n.repeats} ${n.repeats == 1 ? 'vez' : 'veces'}' : '$label · repeat ${n.repeats} ${n.repeats == 1 ? 'time' : 'times'}';
        final String sub = n.skipLastRest ? (es ? 'Sin el último descanso' : 'Skips the last rest') : (es ? 'Con todos los descansos' : 'Keeps every rest');
        out.add(Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          color: theme.colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 0, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _editBlock(list, i),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.repeat, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Semantics(
                          label: '$head. $sub',
                          excludeSemantics: true,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(head, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                Text(sub, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _menu(list, i, label),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 10, right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      ..._nodes(n.children, depth + 1),
                      _addButtons(n.children, depth + 1),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ));
      }
    }
    return out;
  }

  Widget _addButtons(List<TimerNode> list, int depth) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: <Widget>[
        TextButton.icon(onPressed: () => _addStep(list), icon: const Icon(Icons.add), label: Text(t(context, 'Intervalo', 'Interval'))),
        if (depth < kMaxBlockDepth) TextButton.icon(onPressed: () => _addBlock(list), icon: const Icon(Icons.repeat), label: Text(t(context, 'Bloque que se repite', 'Repeating block'))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool es = isSpanish(context);
    final ThemeData theme = Theme.of(context);
    final List<TimerSegment> segs = TimerEngine.flatten(_w.nodes);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          return;
        }
        final NavigatorState nav = Navigator.of(context);
        if (await _confirmDiscard()) {
          _dirty = false;
          nav.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isNew ? t(context, 'Nuevo entrenamiento', 'New workout') : t(context, 'Entrenamiento', 'Workout')),
          actions: <Widget>[
            TextButton(onPressed: _save, child: Text(t(context, 'Guardar', 'Save'))),
            if (!widget.isNew)
              PopupMenuButton<String>(
                tooltip: t(context, 'Más opciones', 'More options'),
                onSelected: (String v) {
                  if (v == 'duplicate') {
                    _duplicate();
                  } else if (v == 'delete') {
                    unawaited(_delete());
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(value: 'duplicate', child: Text(t(context, 'Duplicar', 'Duplicate'))),
                  PopupMenuItem<String>(value: 'delete', child: Text(t(context, 'Borrar', 'Delete'))),
                ],
              ),
          ],
        ),
        body: ReadableWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
            children: <Widget>[
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: t(context, 'Nombre', 'Name'), errorText: _nameError ? t(context, 'Escribe un nombre', 'Enter a name') : null, border: const OutlineInputBorder()),
                onChanged: (_) => setState(() {
                  _dirty = true;
                  _nameError = false;
                }),
              ),
              const SizedBox(height: 12),
              Text(segs.isEmpty ? t(context, 'Todavía no hay intervalos.', 'No intervals yet.') : TimerTexts.summary(segs, es), style: theme.textTheme.titleMedium),
              if (segs.length >= kMaxSegments) Text(t(context, 'Son demasiadas repeticiones: se usan los primeros 3000 intervalos.', 'Too many repetitions: only the first 3,000 intervals are used.'), style: TextStyle(color: theme.colorScheme.error)),
              if (segs.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: ExcludeSemantics(child: SegmentBar(segments: segs, height: 14))),
              SectionHeader(t(context, 'Intervalos', 'Intervals')),
              ..._nodes(_w.nodes, 0),
              _addButtons(_w.nodes, 0),
              SectionHeader(t(context, 'Al terminar', 'At the end')),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  for (final CueSound snd in const <CueSound>[CueSound.gong, CueSound.bell, CueSound.horn, CueSound.beep, CueSound.none])
                    ChoiceChip(
                      label: Text(TimerTexts.sound(snd, es)),
                      selected: _w.finishSound == snd,
                      onSelected: (_) {
                        _changed(() => _w.finishSound = snd);
                        unawaited(AppScope.read(context).cues.sound(snd));
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(onPressed: segs.isEmpty ? null : _start, icon: const Icon(Icons.play_arrow), label: Text(t(context, 'Guardar e iniciar', 'Save and start'))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hoja para editar un intervalo.
class _StepSheet extends StatefulWidget {
  const _StepSheet({required this.step, required this.isNew});

  final IntervalStep step;
  final bool isNew;

  static Future<IntervalStep?> show(BuildContext context, IntervalStep step, {bool isNew = false}) {
    return showModalBottomSheet<IntervalStep>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext _) => _StepSheet(step: step, isNew: isNew),
    );
  }

  @override
  State<_StepSheet> createState() => _StepSheetState();
}

class _StepSheetState extends State<_StepSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.step.name);
  late StepKind _kind = widget.step.kind;
  late int _seconds = widget.step.seconds;
  late CueSound _sound = widget.step.sound;
  late int? _color = widget.step.color;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool es = isSpanish(context);
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(widget.isNew ? t(context, 'Nuevo intervalo', 'New interval') : t(context, 'Intervalo', 'Interval'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: t(context, 'Nombre (lo dice la voz)', 'Name (spoken by the voice)'), border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Text(t(context, 'Tipo', 'Type'), style: theme.textTheme.titleSmall),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                for (final StepKind k in StepKind.values)
                  ChoiceChip(
                    label: Text(TimerTexts.kind(k, es)),
                    selected: _kind == k,
                    onSelected: (_) => setState(() {
                      final String old = TimerTexts.kind(_kind, es);
                      if (_name.text.trim().isEmpty || _name.text.trim() == old) {
                        _name.text = TimerTexts.kind(k, es);
                      }
                      _kind = k;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(t(context, 'Duración', 'Duration'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            DurationChoice(seconds: _seconds, minSeconds: 1, maxSeconds: 4 * 3600, onChanged: (int v) => setState(() => _seconds = v)),
            const SizedBox(height: 12),
            Text(t(context, 'Sonido al empezar', 'Sound at the start'), style: theme.textTheme.titleSmall),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                for (final CueSound snd in CueSound.values)
                  ChoiceChip(
                    label: Text(TimerTexts.sound(snd, es)),
                    selected: _sound == snd,
                    onSelected: (_) {
                      setState(() => _sound = snd);
                      unawaited(AppScope.read(context).cues.sound(snd == CueSound.auto ? defaultStepSound(_kind) : snd));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t(context, 'Color propio', 'Custom color')),
              subtitle: Text(t(context, 'Si no, usa el color del tipo.', 'Otherwise the type color is used.')),
              value: _color != null,
              onChanged: (bool v) => setState(() => _color = v ? kColors.first.value : null),
            ),
            if (_color != null) ColorChoice(selected: _color!, onChanged: (int v) => setState(() => _color = v)),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: <Widget>[
                TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t(context, 'Cancelar', 'Cancel'))),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(IntervalStep(
                    id: widget.step.id,
                    name: _name.text.trim().isEmpty ? TimerTexts.kind(_kind, es) : _name.text.trim(),
                    seconds: _seconds,
                    kind: _kind,
                    color: _color,
                    sound: _sound,
                  )),
                  child: Text(widget.isNew ? t(context, 'Agregar', 'Add') : t(context, 'Listo', 'Done')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Hoja para editar un bloque que se repite.
class _BlockSheet extends StatefulWidget {
  const _BlockSheet({required this.block, required this.isNew});

  final RepeatBlock block;
  final bool isNew;

  static Future<RepeatBlock?> show(BuildContext context, RepeatBlock block, {bool isNew = false}) {
    return showModalBottomSheet<RepeatBlock>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext _) => _BlockSheet(block: block, isNew: isNew),
    );
  }

  @override
  State<_BlockSheet> createState() => _BlockSheetState();
}

class _BlockSheetState extends State<_BlockSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.block.name);
  late int _repeats = widget.block.repeats;
  late bool _skip = widget.block.skipLastRest;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(widget.isNew ? t(context, 'Nuevo bloque que se repite', 'New repeating block') : t(context, 'Bloque que se repite', 'Repeating block'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: t(context, 'Nombre de la vuelta (opcional)', 'Name of each pass (optional)'), hintText: t(context, 'Ronda, serie, circuito…', 'Round, set, circuit…'), border: const OutlineInputBorder()),
            ),
            LabeledControl(
              label: t(context, 'Repeticiones', 'Repetitions'),
              child: NumberStepper(value: _repeats, min: 1, max: 99, onChanged: (int v) => setState(() => _repeats = v), label: t(context, 'Repeticiones', 'Repetitions')),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t(context, 'Omitir el último descanso', 'Skip the last rest')),
              subtitle: Text(t(context, 'En la última vuelta no se hace el descanso con que termina el bloque.', 'On the last pass, the rest that ends the block is skipped.')),
              value: _skip,
              onChanged: (bool v) => setState(() => _skip = v),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: <Widget>[
                TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t(context, 'Cancelar', 'Cancel'))),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(RepeatBlock(id: widget.block.id, name: _name.text.trim(), repeats: _repeats, skipLastRest: _skip, children: widget.block.children)),
                  child: Text(widget.isNew ? t(context, 'Agregar', 'Add') : t(context, 'Listo', 'Done')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
