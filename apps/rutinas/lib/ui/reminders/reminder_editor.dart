import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../logic/recurrence.dart';
import '../../model/reminder.dart';
import '../widgets/common.dart';
import 'reminder_texts.dart';

/// Crear o editar un recordatorio: fecha y hora, repetición e insistencia.
class ReminderEditorScreen extends StatefulWidget {
  const ReminderEditorScreen({super.key, this.reminder});

  final Reminder? reminder;

  static Future<void> open(BuildContext context, {Reminder? reminder}) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReminderEditorScreen(reminder: reminder), fullscreenDialog: true));

  @override
  State<ReminderEditorScreen> createState() => _ReminderEditorScreenState();
}

class _ReminderEditorScreenState extends State<ReminderEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late DateTime _date;
  late TimeOfDay _time;
  late RecurrenceType _type;
  int _everyN = 1;
  late List<int> _weekdays;
  late int _nag;
  bool _titleError = false;

  bool get _editing => widget.reminder != null;

  @override
  void initState() {
    super.initState();
    final Reminder? r = widget.reminder;
    final DateTime now = clock.now();
    // Por defecto, la próxima hora en punto.
    final DateTime base = r?.dueAt ?? DateTime(now.year, now.month, now.day, now.hour + 1);
    _title = TextEditingController(text: r?.title ?? '');
    _notes = TextEditingController(text: r?.notes ?? '');
    _date = dateOnly(base);
    _time = TimeOfDay(hour: base.hour, minute: base.minute);
    final Recurrence rec = (r?.recurrence ?? const Recurrence()).normalized();
    _type = rec.type;
    _everyN = rec.type == RecurrenceType.everyNDays ? rec.n : 1;
    _weekdays = rec.type == RecurrenceType.weekdays ? List<int>.of(rec.weekdays) : <int>[base.weekday];
    _nag = r?.nagMinutes ?? 0;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  DateTime get _when => DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  Recurrence _recurrence() {
    switch (_type) {
      case RecurrenceType.once:
        return const Recurrence();
      case RecurrenceType.everyNDays:
        return Recurrence(type: _type, n: _everyN).normalized();
      case RecurrenceType.weekdays:
        return Recurrence(type: _type, weekdays: _weekdays).normalized();
      case RecurrenceType.monthlyDay:
        return Recurrence(type: _type, day: _date.day).normalized();
      case RecurrenceType.monthlyLast:
        return const Recurrence(type: RecurrenceType.monthlyLast);
      case RecurrenceType.yearly:
        return Recurrence(type: _type, month: _date.month, day: _date.day).normalized();
    }
  }

  Future<void> _save() async {
    final Services s = AppScope.read(context);
    final String title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = true);
      return;
    }
    if (_type == RecurrenceType.weekdays && _weekdays.isEmpty) {
      showSnack(context, t(context, 'Elige al menos un día de la semana.', 'Pick at least one day of the week.'));
      return;
    }
    final DateTime now = clock.now();
    final Recurrence rec = _recurrence();
    DateTime due = Recurrences.align(rec, _when);
    if (rec.repeats && !due.isAfter(now)) {
      // Una serie que empieza en el pasado arranca en su próxima ocurrencia.
      due = Recurrences.next(rec, due, now) ?? due;
    }
    final bool changedTime = widget.reminder == null || widget.reminder!.dueAt != due;
    if (!rec.repeats && !due.isAfter(now) && changedTime) {
      showSnack(context, t(context, 'Esa hora ya pasó: elige una hora futura.', 'That time has passed: pick a future time.'));
      return;
    }
    final Reminder r = widget.reminder == null ? Reminder(id: newId(), title: title, dueAt: due, createdAt: now) : Reminder.fromJson(widget.reminder!.toJson());
    r.title = title;
    r.notes = _notes.text.trim();
    r.dueAt = due;
    r.recurrence = rec;
    r.nagMinutes = _nag;
    if (changedTime) {
      r.snoozedUntil = null;
      r.doneAt = null;
    }
    if (_editing) {
      s.reminders.update(r);
    } else {
      s.reminders.add(r);
    }
    unawaited(s.notices.askNotifications());
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _delete() async {
    final Services s = AppScope.read(context);
    final Reminder? r = widget.reminder;
    if (r == null) {
      return;
    }
    final bool ok = await confirm(context, title: t(context, '¿Borrar el recordatorio?', 'Delete the reminder?'), message: r.title, yes: t(context, 'Borrar', 'Delete'), destructive: true);
    if (!ok || !mounted) {
      return;
    }
    unawaited(s.notices.dismissReminder(r, r.alertAt));
    s.reminders.remove(r.id);
    Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final DateTime now = clock.now();
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(dateOnly(now)) ? dateOnly(now) : _date,
      firstDate: dateOnly(now).isBefore(_date) ? dateOnly(now) : _date,
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (d != null && mounted) {
      setState(() {
        _date = dateOnly(d);
        if (_type != RecurrenceType.weekdays) {
          _weekdays = <int>[_date.weekday];
        }
      });
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? tm = await showTimePicker(context: context, initialTime: _time);
    if (tm != null && mounted) {
      setState(() => _time = tm);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final bool es = s.settings.spanish;
    final ThemeData theme = Theme.of(context);
    final MaterialLocalizations ml = MaterialLocalizations.of(context);
    final Recurrence rec = _recurrence();
    final DateTime preview = Recurrences.align(rec, _when);
    String? recHelp;
    if (_type == RecurrenceType.monthlyDay && _date.day > 28) {
      recHelp = es ? 'En los meses que no tienen día ${_date.day}, suena el último día del mes.' : 'In months without a day ${_date.day}, it rings on the last day of the month.';
    } else if (_type == RecurrenceType.yearly && _date.month == 2 && _date.day == 29) {
      recHelp = es ? 'En los años no bisiestos suena el 28 de febrero.' : 'In non-leap years it rings on February 28.';
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? t(context, 'Recordatorio', 'Reminder') : t(context, 'Nuevo recordatorio', 'New reminder')),
        actions: <Widget>[
          if (_editing) IconButton(tooltip: t(context, 'Borrar', 'Delete'), icon: const Icon(Icons.delete_outline), onPressed: _delete),
          TextButton(onPressed: _save, child: Text(t(context, 'Guardar', 'Save'))),
        ],
      ),
      body: ReadableWidth(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: t(context, '¿Qué te recuerdo?', 'What should I remind you?'),
                  hintText: t(context, 'Tomar la pastilla, pagar el arriendo…', 'Take the pill, pay the rent…'),
                  errorText: _titleError ? t(context, 'Escribe qué hay que hacer', 'Enter what needs doing') : null,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_titleError) {
                    setState(() => _titleError = false);
                  }
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: Text(t(context, 'Fecha', 'Date')),
              subtitle: Text(formatWeekdayDate(_date, spanish: es)),
              onTap: _pickDate,
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(t(context, 'Hora', 'Time')),
              subtitle: Text(ml.formatTimeOfDay(_time, alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))),
              onTap: _pickTime,
            ),
            SectionHeader(t(context, 'Repetir', 'Repeat')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  for (final RecurrenceType ty in RecurrenceType.values)
                    ChoiceChip(
                      label: Text(ReminderTexts.typeLabel(ty, es)),
                      selected: _type == ty,
                      onSelected: (_) => setState(() => _type = ty),
                    ),
                ],
              ),
            ),
            if (_type == RecurrenceType.everyNDays)
              LabeledControl(
                label: t(context, 'Cada cuántos días', 'Every how many days'),
                child: NumberStepper(value: _everyN, min: 1, max: 365, onChanged: (int v) => setState(() => _everyN = v), label: t(context, 'Días', 'Days')),
              ),
            if (_type == RecurrenceType.weekdays)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: WeekdayChoice(selected: _weekdays, weekStart: s.settings.weekStart, onChanged: (List<int> v) => setState(() => _weekdays = v)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                rec.repeats ? '${ReminderTexts.recurrence(rec, es, s.settings.weekStart)}. ${es ? 'Primera vez' : 'First time'}: ${ReminderTexts.when(preview, clock.now(), es)}.' : '${ReminderTexts.when(preview, clock.now(), es)}.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (recHelp != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(recHelp, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            SectionHeader(t(context, 'Insistir', 'Keep reminding')),
            SwitchListTile(
              title: Text(t(context, 'Repetir el aviso hasta marcarlo hecho', 'Repeat the alert until marked done')),
              subtitle: Text(_nag == 0 ? t(context, 'Un solo aviso a la hora elegida.', 'A single alert at the chosen time.') : ReminderTexts.nag(_nag, es)),
              value: _nag > 0,
              onChanged: (bool v) => setState(() => _nag = v ? 5 : 0),
            ),
            if (_nag > 0)
              LabeledControl(
                label: t(context, 'Cada cuántos minutos', 'Every how many minutes'),
                help: t(context, 'De 1 a 60 minutos.', 'From 1 to 60 minutes.'),
                child: NumberStepper(value: _nag, min: 1, max: 60, onChanged: (int v) => setState(() => _nag = v), label: t(context, 'Minutos entre avisos', 'Minutes between alerts')),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                controller: _notes,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: t(context, 'Notas (opcional)', 'Notes (optional)'), border: const OutlineInputBorder()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: Text(t(context, 'Guardar recordatorio', 'Save reminder'))),
            ),
          ],
        ),
      ),
    );
  }
}
