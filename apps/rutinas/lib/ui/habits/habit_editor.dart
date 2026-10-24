import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../logic/habit_logic.dart';
import '../../model/habit.dart';
import '../catalog.dart';
import '../widgets/common.dart';
import 'habit_texts.dart';

/// Crear o editar un hábito.
class HabitEditorScreen extends StatefulWidget {
  const HabitEditorScreen({super.key, this.habit, this.template});

  /// Hábito a editar (se trabaja sobre una copia); null para uno nuevo.
  final Habit? habit;

  /// Para uno nuevo: copia el nombre, el ícono, el color y los avisos de otro
  /// (cuando se quiere medir un hábito de otra forma).
  final Habit? template;

  static Future<void> open(BuildContext context, {Habit? habit, Habit? template}) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HabitEditorScreen(habit: habit, template: template), fullscreenDialog: true));

  @override
  State<HabitEditorScreen> createState() => _HabitEditorScreenState();
}

/// Sugerencias para empezar rápido (rellenan el formulario).
class _Suggestion {
  const _Suggestion(this.es, this.en, this.kind, this.icon, this.color, {this.goal = 1, this.unitEs = '', this.unitEn = '', this.freq = const Frequency()});

  final String es;
  final String en;
  final HabitKind kind;
  final String icon;
  final int color;
  final int goal;
  final String unitEs;
  final String unitEn;
  final Frequency freq;
}

const List<_Suggestion> _suggestions = <_Suggestion>[
  _Suggestion('Beber agua', 'Drink water', HabitKind.count, 'water_drop', 0xFF1565C0, goal: 8, unitEs: 'vasos', unitEn: 'glasses'),
  _Suggestion('Meditar', 'Meditate', HabitKind.timed, 'self_improvement', 0xFF6A1B9A, goal: 600),
  _Suggestion('Leer', 'Read', HabitKind.check, 'menu_book', 0xFF00796B),
  _Suggestion('Caminar', 'Walk', HabitKind.timed, 'directions_walk', 0xFF2E7D32, goal: 1800),
  _Suggestion('Ir al gimnasio', 'Go to the gym', HabitKind.check, 'fitness_center', 0xFFC62828, freq: Frequency(type: FrequencyType.perWeek, n: 3)),
  _Suggestion('Cepillarse los dientes', 'Brush teeth', HabitKind.timed, 'clean_hands', 0xFF00727D, goal: 120),
  _Suggestion('Dejar de fumar', 'Quit smoking', HabitKind.negative, 'smoke_free', 0xFF455A64),
];

class _HabitEditorScreenState extends State<HabitEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _unit;
  late final TextEditingController _notes;
  late HabitKind _kind;
  late FrequencyType _freqType;
  late List<int> _weekdays;
  int _everyN = 2;
  int _perWeek = 3;
  int _perMonth = 10;
  late int _goal;
  late int _minutes;
  late DateTime _start;
  late List<int> _reminders;
  late int _nag;
  late String _icon;
  late int _color;
  bool _nameError = false;

  bool get _editing => widget.habit != null;

  @override
  void initState() {
    super.initState();
    final Habit? h = widget.habit ?? widget.template;
    final DateTime today = dateOnly(clock.now());
    _name = TextEditingController(text: h?.name ?? '');
    _unit = TextEditingController(text: h?.unit ?? '');
    _notes = TextEditingController(text: h?.notes ?? '');
    _kind = h?.kind ?? HabitKind.check;
    final Frequency f = (h?.frequency ?? const Frequency()).normalized();
    _freqType = f.type;
    _weekdays = f.type == FrequencyType.weekdays ? List<int>.of(f.weekdays) : <int>[today.weekday];
    if (f.type == FrequencyType.everyN) {
      _everyN = f.n;
    } else if (f.type == FrequencyType.perWeek) {
      _perWeek = f.n;
    } else if (f.type == FrequencyType.perMonth) {
      _perMonth = f.n;
    }
    _goal = h != null && h.kind == HabitKind.count ? h.goal : 8;
    _minutes = h != null && h.kind == HabitKind.timed ? (h.goal / 60).round().clamp(1, 600) : 10;
    _start = widget.habit?.startDate ?? today;
    _reminders = List<int>.of(h?.reminders ?? const <int>[]);
    _nag = h?.nagMinutes ?? 0;
    _icon = h?.icon ?? 'task_alt';
    _color = h?.color ?? kColors.first.value;
  }

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _apply(_Suggestion s, bool es) {
    setState(() {
      _name.text = es ? s.es : s.en;
      _kind = s.kind;
      _icon = s.icon;
      _color = s.color;
      _freqType = s.freq.type;
      if (s.freq.type == FrequencyType.perWeek) {
        _perWeek = s.freq.n;
      }
      if (s.kind == HabitKind.count) {
        _goal = s.goal;
        _unit.text = es ? s.unitEs : s.unitEn;
      } else if (s.kind == HabitKind.timed) {
        _minutes = (s.goal / 60).round();
      }
      _nameError = false;
    });
  }

  Frequency _frequency() {
    switch (_freqType) {
      case FrequencyType.daily:
        return const Frequency();
      case FrequencyType.weekdays:
        return Frequency(type: FrequencyType.weekdays, weekdays: _weekdays).normalized();
      case FrequencyType.everyN:
        return Frequency(type: FrequencyType.everyN, n: _everyN).normalized();
      case FrequencyType.perWeek:
        return Frequency(type: FrequencyType.perWeek, n: _perWeek).normalized();
      case FrequencyType.perMonth:
        return Frequency(type: FrequencyType.perMonth, n: _perMonth).normalized();
    }
  }

  Future<void> _save() async {
    final Services s = AppScope.read(context);
    final String name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = true);
      return;
    }
    if (_freqType == FrequencyType.weekdays && _weekdays.isEmpty) {
      showSnack(context, t(context, 'Elige al menos un día de la semana.', 'Pick at least one day of the week.'));
      return;
    }
    final Habit? old = widget.habit;
    final DateTime today = dateOnly(clock.now());
    final Habit h = old?.copy() ?? Habit(id: newId(), name: name, startDate: _start, createdAt: clock.now());
    // Con registros, el tipo no cambia: cambiaría lo que significan (veces,
    // segundos o recaídas). El editor ni lo deja elegir.
    final HabitKind kind = old != null && s.habits.hasValues(old.id) ? old.kind : _kind;
    final Frequency frequency = kind == HabitKind.negative ? const Frequency() : _frequency();
    final int goal = kind == HabitKind.count ? _goal : (kind == HabitKind.timed ? _minutes * 60 : 1);
    h.name = name;
    h.startDate = dateOnly(_start);
    if (old == null || kind != old.kind) {
      // Nuevo, o un tipo distinto sin nada anotado: no hay historia que cuidar.
      h.kind = kind;
      h.frequency = frequency;
      h.goal = goal;
      h.pastRules.clear();
    } else {
      // La frecuencia y la meta nuevas rigen desde hoy: los días anteriores
      // se siguen evaluando con la regla que tenían.
      h.changeRule(frequency: frequency, goal: goal, today: today, since: HabitLogic.effectiveStart(h, s.habits.entriesOf(h.id)));
    }
    h.unit = kind == HabitKind.count ? _unit.text.trim() : '';
    h.icon = _icon;
    h.color = _color;
    h.reminders = (_reminders.toSet().toList()..sort());
    h.nagMinutes = kind == HabitKind.negative ? 0 : _nag;
    h.notes = _notes.text.trim();
    if (_editing) {
      s.habits.update(h);
    } else {
      s.habits.add(h);
    }
    if (h.reminders.isNotEmpty) {
      unawaited(s.notices.askNotifications());
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _addReminder() async {
    final TimeOfDay? picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      final int m = picked.hour * 60 + picked.minute;
      if (!_reminders.contains(m)) {
        _reminders.add(m);
        _reminders.sort();
      }
    });
  }

  Future<void> _pickStart() async {
    final DateTime today = dateOnly(clock.now());
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year + 1, 12, 31),
    );
    if (d != null && mounted) {
      setState(() => _start = dateOnly(d));
    }
  }

  Future<void> _pickIcon() async {
    final bool es = isSpanish(context);
    final String? id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (BuildContext ctx, ScrollController controller) => GridView.extent(
          controller: controller,
          maxCrossAxisExtent: 64,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          children: <Widget>[
            for (final HabitIcon i in kHabitIcons)
              Semantics(
                button: true,
                selected: i.id == _icon,
                label: i.label(es),
                child: InkResponse(
                  onTap: () => Navigator.of(ctx).pop(i.id),
                  child: ExcludeSemantics(
                    child: Center(
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i.id == _icon ? Color(_color) : Theme.of(ctx).colorScheme.surfaceContainerHighest,
                        ),
                        child: Icon(i.icon, color: i.id == _icon ? onColor(Color(_color)) : Theme.of(ctx).colorScheme.onSurface),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (id != null && mounted) {
      setState(() => _icon = id);
    }
  }

  /// Otra forma de medirlo: un hábito nuevo con el mismo nombre, ícono y
  /// color; el de ahora se queda con su historia.
  Future<void> _newInstead() async {
    final Habit? h = widget.habit;
    if (h == null) {
      return;
    }
    final NavigatorState nav = Navigator.of(context);
    nav.pop();
    await nav.push(MaterialPageRoute<void>(builder: (_) => HabitEditorScreen(template: h), fullscreenDialog: true));
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final bool es = s.settings.spanish;
    final ThemeData theme = Theme.of(context);
    final Habit? old = widget.habit;
    final bool kindLocked = old != null && s.habits.hasValues(old.id);
    // ¿Cambia la regla de un hábito que ya tiene días contados?
    final DateTime today = dateOnly(clock.now());
    final RuleChange change = old != null && _kind == old.kind && _kind != HabitKind.negative && today.isAfter(HabitLogic.effectiveStart(old, s.habits.entriesOf(old.id)))
        ? HabitLogic.ruleChange(old, _frequency(), _kind == HabitKind.count ? _goal : (_kind == HabitKind.timed ? _minutes * 60 : 1), today)
        : RuleChange.none;
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? t(context, 'Editar hábito', 'Edit habit') : t(context, 'Nuevo hábito', 'New habit')),
        actions: <Widget>[
          TextButton(onPressed: _save, child: Text(t(context, 'Guardar', 'Save'))),
        ],
      ),
      body: ReadableWidth(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: <Widget>[
            if (!_editing) ...<Widget>[
              SectionHeader(t(context, 'Ideas para empezar', 'Ideas to start')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: <Widget>[
                    for (final _Suggestion sg in _suggestions)
                      ActionChip(
                        avatar: Icon(habitIconFor(sg.icon).icon, size: 18),
                        label: Text(es ? sg.es : sg.en),
                        onPressed: () => _apply(sg, es),
                      ),
                  ],
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Semantics(
                    button: true,
                    label: t(context, 'Ícono: ${habitIconFor(_icon).label(true)}. Cambiar', 'Icon: ${habitIconFor(_icon).label(false)}. Change'),
                    child: InkResponse(
                      onTap: _pickIcon,
                      radius: 30,
                      child: ExcludeSemantics(child: HabitAvatar(icon: _icon, color: _color, size: 52)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: t(context, 'Nombre', 'Name'),
                        hintText: t(context, 'Por ejemplo, leer 20 páginas', 'For example, read 20 pages'),
                        errorText: _nameError ? t(context, 'Escribe un nombre', 'Enter a name') : null,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        if (_nameError) {
                          setState(() => _nameError = false);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            SectionHeader(t(context, 'Tipo', 'Type')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  for (final HabitKind k in HabitKind.values)
                    if (!kindLocked || k == _kind)
                      ChoiceChip(
                        label: Text(HabitTexts.kind(k, es)),
                        selected: _kind == k,
                        onSelected: (_) {
                          if (!kindLocked) {
                            setState(() => _kind = k);
                          }
                        },
                      ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(HabitTexts.kindHelp(_kind, es), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            if (kindLocked)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      t(context, 'El tipo no se puede cambiar porque el hábito ya tiene días anotados: cambiaría lo que significan. Para medirlo de otra forma, crea un hábito nuevo; este se queda con su historia.', 'The type cannot change because the habit already has days logged: it would change what they mean. To measure it another way, create a new habit; this one keeps its history.'),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    TextButton.icon(onPressed: _newInstead, icon: const Icon(Icons.add), label: Text(t(context, 'Crear un hábito nuevo', 'Create a new habit'))),
                  ],
                ),
              ),
            if (_kind == HabitKind.count) ...<Widget>[
              LabeledControl(
                label: t(context, 'Meta diaria', 'Daily goal'),
                child: NumberStepper(value: _goal, min: 1, max: 999, onChanged: (int v) => setState(() => _goal = v), label: t(context, 'Meta diaria', 'Daily goal')),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: TextField(
                  controller: _unit,
                  decoration: InputDecoration(labelText: t(context, 'Unidad (opcional)', 'Unit (optional)'), hintText: t(context, 'vasos, páginas, flexiones…', 'glasses, pages, push-ups…'), border: const OutlineInputBorder()),
                ),
              ),
            ],
            if (_kind == HabitKind.timed)
              LabeledControl(
                label: t(context, 'Minutos al día', 'Minutes a day'),
                child: NumberStepper(value: _minutes, min: 1, max: 600, onChanged: (int v) => setState(() => _minutes = v), label: t(context, 'Minutos al día', 'Minutes a day')),
              ),
            if (_kind != HabitKind.negative) ...<Widget>[
              SectionHeader(t(context, 'Frecuencia', 'Frequency')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: <Widget>[
                    for (final FrequencyType f in FrequencyType.values)
                      ChoiceChip(
                        label: Text(_freqLabel(f, es)),
                        selected: _freqType == f,
                        onSelected: (_) => setState(() => _freqType = f),
                      ),
                  ],
                ),
              ),
              if (_freqType == FrequencyType.weekdays)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: WeekdayChoice(selected: _weekdays, weekStart: s.settings.weekStart, onChanged: (List<int> v) => setState(() => _weekdays = v)),
                ),
              if (_freqType == FrequencyType.everyN)
                LabeledControl(
                  label: t(context, 'Cada cuántos días', 'Once every'),
                  help: t(context, 'Basta con una vez en cada bloque de días.', 'Once in each block of days is enough.'),
                  child: NumberStepper(value: _everyN, min: 2, max: 365, onChanged: (int v) => setState(() => _everyN = v), label: t(context, 'Días del bloque', 'Days in each block'), format: (int v) => es ? '$v días' : '$v days'),
                ),
              if (_freqType == FrequencyType.perWeek)
                LabeledControl(
                  label: t(context, 'Veces por semana', 'Times a week'),
                  help: t(context, 'Cualquier día de la semana.', 'Any day of the week.'),
                  child: NumberStepper(value: _perWeek, min: 1, max: 7, onChanged: (int v) => setState(() => _perWeek = v), label: t(context, 'Veces por semana', 'Times a week')),
                ),
              if (_freqType == FrequencyType.perMonth)
                LabeledControl(
                  label: t(context, 'Veces al mes', 'Times a month'),
                  help: t(context, 'Cualquier día del mes.', 'Any day of the month.'),
                  child: NumberStepper(value: _perMonth, min: 1, max: 31, onChanged: (int v) => setState(() => _perMonth = v), label: t(context, 'Veces al mes', 'Times a month')),
                ),
            ],
            if (change != RuleChange.none)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  change == RuleChange.revert
                      ? t(context, 'Vuelve a la regla que tenía hasta ayer: los días pasados y la racha quedan como estaban.', 'Back to the rule it had until yesterday: past days and the streak stay as they were.')
                      : change == RuleChange.restartsStreak
                      ? t(context, 'El cambio rige desde hoy: los días anteriores se siguen contando con la frecuencia que tenían. La racha se cuenta en otra unidad, así que empieza de nuevo desde hoy; lo cumplido sigue en el calendario y en el cumplimiento.', 'The change applies from today: earlier days still count with the frequency they had. The streak is counted in a different unit, so it starts again from today; what you did stays in the calendar and the success rate.')
                      : t(context, 'El cambio rige desde hoy: los días anteriores se siguen contando con la frecuencia y la meta que tenían, y la racha no se recalcula.', 'The change applies from today: earlier days still count with the frequency and goal they had, and the streak is not recalculated.'),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: Text(t(context, 'Empieza', 'Starts')),
              subtitle: Text(formatLongDate(_start, spanish: es)),
              onTap: _pickStart,
            ),
            SectionHeader(t(context, 'Avisos', 'Reminders')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  for (final int m in _reminders)
                    InputChip(
                      label: Text(formatMinuteOfDay(m, spanish: es)),
                      deleteButtonTooltipMessage: t(context, 'Quitar aviso', 'Remove reminder'),
                      onDeleted: () => setState(() => _reminders.remove(m)),
                    ),
                  ActionChip(avatar: const Icon(Icons.add_alarm, size: 18), label: Text(t(context, 'Agregar hora', 'Add time')), onPressed: _addReminder),
                ],
              ),
            ),
            if (_reminders.isNotEmpty && _kind != HabitKind.negative) ...<Widget>[
              SwitchListTile(
                title: Text(t(context, 'Insistir hasta marcarlo', 'Keep reminding until done')),
                subtitle: Text(_nag == 0
                    ? t(context, 'Un solo aviso por hora elegida.', 'One alert per chosen time.')
                    : (es
                        ? 'Repite el aviso cada $_nag min mientras no esté hecho, hasta la siguiente hora de aviso o la medianoche. El teléfono guarda hasta ${s.notices.limits.nagCap} repeticiones: si no abres Rutinas, puede parar antes.'
                        : 'Repeats the alert every $_nag min until it is done, up to the next alert time or midnight. The phone keeps up to ${s.notices.limits.nagCap} repeats: if you do not open Rutinas, it may stop sooner.')),
                value: _nag > 0,
                onChanged: (bool v) => setState(() => _nag = v ? 15 : 0),
              ),
              if (_nag > 0)
                LabeledControl(
                  label: t(context, 'Cada cuántos minutos', 'Alert every'),
                  child: NumberStepper(value: _nag, min: 1, max: 60, onChanged: (int v) => setState(() => _nag = v), label: t(context, 'Minutos entre avisos', 'Minutes between alerts'), format: (int v) => '$v min'),
                ),
            ],
            SectionHeader(t(context, 'Color', 'Color')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ColorChoice(selected: _color, onChanged: (int v) => setState(() => _color = v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                controller: _notes,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: t(context, 'Para qué lo haces (opcional)', 'Why you do it (optional)'), border: const OutlineInputBorder()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: Text(t(context, 'Guardar hábito', 'Save habit'))),
            ),
          ],
        ),
      ),
    );
  }

  static String _freqLabel(FrequencyType f, bool es) {
    switch (f) {
      case FrequencyType.daily:
        return es ? 'Todos los días' : 'Every day';
      case FrequencyType.weekdays:
        return es ? 'Algunos días' : 'Some days';
      case FrequencyType.everyN:
        return es ? 'Cada N días' : 'Every N days';
      case FrequencyType.perWeek:
        return es ? 'Veces por semana' : 'Times a week';
      case FrequencyType.perMonth:
        return es ? 'Veces al mes' : 'Times a month';
    }
  }
}
