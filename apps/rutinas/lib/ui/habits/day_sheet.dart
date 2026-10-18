import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/dates.dart';
import '../../logic/habit_logic.dart';
import '../../model/habit.dart';
import '../widgets/common.dart';
import 'habit_texts.dart';

/// Hoja para editar el registro de un día: valor, día saltado y nota.
class DaySheet {
  DaySheet._();

  static Future<void> show(BuildContext context, Habit habit, DateTime day) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext _) => _DayEditor(habit: habit, day: dateOnly(day)),
    );
  }
}

class _DayEditor extends StatefulWidget {
  const _DayEditor({required this.habit, required this.day});

  final Habit habit;
  final DateTime day;

  @override
  State<_DayEditor> createState() => _DayEditorState();
}

class _DayEditorState extends State<_DayEditor> {
  late int _value;
  late bool _skipped;
  late final TextEditingController _note;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) {
      return;
    }
    _loaded = true;
    final HabitEntry? e = AppScope.read(context).habits.entry(widget.habit.id, widget.day);
    _value = e?.value ?? 0;
    _skipped = e?.skipped ?? false;
    _note = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final Services s = AppScope.read(context);
    final Habit h = widget.habit;
    // La meta que regía ese día (pudo cambiar después).
    final bool done = !h.isNegative && _value >= h.targetOn(widget.day);
    s.habits.setDay(h.id, widget.day, value: _value, skipped: _skipped && !done, note: _note.text);
    if (done) {
      unawaited(s.notices.dismissHabit(h, widget.day));
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bool es = isSpanish(context);
    final ThemeData theme = Theme.of(context);
    final Habit h = widget.habit;
    final int target = h.targetOn(widget.day);
    final bool done = !h.isNegative && _value >= target;
    Widget valueControl;
    switch (h.kind) {
      case HabitKind.check:
        valueControl = SwitchListTile(
          title: Text(t(context, 'Hecho', 'Done')),
          value: _value >= 1,
          onChanged: (bool v) => setState(() => _value = v ? 1 : 0),
        );
        break;
      case HabitKind.count:
        valueControl = LabeledControl(
          label: HabitTexts.unit(h, 2, es),
          help: es ? 'Meta: $target' : 'Goal: $target',
          child: NumberStepper(value: _value, min: 0, max: 9999, onChanged: (int v) => setState(() => _value = v), label: HabitTexts.unit(h, 2, es)),
        );
        break;
      case HabitKind.timed:
        final int minutes = (_value / 60).round();
        valueControl = LabeledControl(
          label: t(context, 'Minutos', 'Minutes'),
          help: es ? 'Meta: ${HabitTexts.minutesOf(target, true)} min' : 'Goal: ${HabitTexts.minutesOf(target, false)} min',
          child: NumberStepper(value: minutes, min: 0, max: 24 * 60, onChanged: (int v) => setState(() => _value = v * 60), label: t(context, 'Minutos', 'Minutes')),
        );
        break;
      case HabitKind.negative:
        valueControl = LabeledControl(
          label: t(context, 'Recaídas', 'Slips'),
          help: t(context, 'Si recaíste este día, anótalo: la racha se recalcula.', 'If you slipped that day, log it: the streak is recalculated.'),
          child: NumberStepper(value: _value, min: 0, max: 99, onChanged: (int v) => setState(() => _value = v), label: t(context, 'Recaídas', 'Slips')),
        );
        break;
    }
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: <Widget>[
                  HabitAvatar(icon: h.icon, color: h.color, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(h.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text(formatWeekdayDate(widget.day, spanish: es), style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            valueControl,
            if (!h.isNegative)
              SwitchListTile(
                title: Text(t(context, 'Saltar este día', 'Skip this day')),
                subtitle: Text(done ? t(context, 'Ya está hecho.', 'It is already done.') : t(context, 'Por enfermedad, viaje o descanso: no rompe la racha.', 'For illness, travel or rest: it does not break the streak.')),
                value: _skipped && !done,
                onChanged: done ? null : (bool v) => setState(() => _skipped = v),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _note,
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: t(context, 'Nota del día', 'Note for the day'), border: const OutlineInputBorder()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t(context, 'Cancelar', 'Cancel'))),
                  FilledButton(onPressed: _save, child: Text(t(context, 'Guardar', 'Save'))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Texto corto del estado de un día para los lectores de pantalla.
String dayStatusLabel(DayStatus s, bool es) {
  switch (s) {
    case DayStatus.done:
      return es ? 'hecho' : 'done';
    case DayStatus.partial:
      return es ? 'a medias' : 'partly done';
    case DayStatus.skipped:
      return es ? 'saltado' : 'skipped';
    case DayStatus.missed:
      return es ? 'no se hizo' : 'missed';
    case DayStatus.notDue:
      return es ? 'no tocaba' : 'not due';
    case DayStatus.pending:
      return es ? 'pendiente' : 'pending';
    case DayStatus.relapse:
      return es ? 'recaída' : 'slip';
    case DayStatus.clean:
      return es ? 'sin recaer' : 'no slip';
    case DayStatus.beforeStart:
      return es ? 'antes de empezar' : 'before the start';
    case DayStatus.future:
      return es ? 'todavía no llega' : 'not yet';
    case DayStatus.paused:
      return es ? 'archivado' : 'archived';
  }
}
