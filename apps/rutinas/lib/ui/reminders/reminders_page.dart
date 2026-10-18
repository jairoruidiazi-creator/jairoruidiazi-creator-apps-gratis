import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/dates.dart';
import '../../core/notifications.dart';
import '../../logic/recurrence.dart';
import '../../model/reminder.dart';
import '../widgets/common.dart';
import 'reminder_editor.dart';
import 'reminder_texts.dart';

/// Pestaña de recordatorios: vencidos, de hoy, próximos y hechos, con las
/// cuentas regresivas rápidas ("avísame en 10 min") arriba.
class RemindersPage extends StatefulWidget {
  const RemindersPage({super.key, required this.today});

  final DateTime today;

  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  Timer? _ticker;
  bool _showDone = false;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Con la pestaña a la vista, las cuentas regresivas se ven correr segundo a
  /// segundo y lo demás se actualiza cada medio minuto.
  void _schedule(Services s, bool visible) {
    if (!visible) {
      _ticker?.cancel();
      _ticker = null;
      _period = null;
      return;
    }
    final DateTime now = clock.now();
    final bool fast = s.reminders.pending.any((Reminder r) => r.isCountdown || r.alertAt.difference(now).inMinutes.abs() < 60);
    final Duration period = fast ? const Duration(seconds: 1) : const Duration(seconds: 30);
    if (_ticker != null && _period == period) {
      return;
    }
    _ticker?.cancel();
    _period = period;
    _ticker = Timer.periodic(period, (Timer _) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Duration? _period;

  Future<void> _quick(Services s, int minutes) async {
    final bool es = s.settings.spanish;
    final String title = es ? 'Cuenta regresiva de ${formatDurationShort(minutes * 60, spanish: true)}' : '${formatDurationShort(minutes * 60, spanish: false)} countdown';
    s.reminders.addCountdown(seconds: minutes * 60, title: title, nagMinutes: s.settings.countdownNag);
    unawaited(s.notices.askNotifications());
    final int nag = s.settings.countdownNag;
    showSnack(context, es ? 'Te aviso en ${formatDurationShort(minutes * 60, spanish: true)} y repito el aviso cada $nag min hasta que toques Hecho.' : 'I will remind you in ${formatDurationShort(minutes * 60, spanish: false)} and repeat the alert every $nag min until you tap Done.');
  }

  Future<void> _otherCountdown(Services s) async {
    int minutes = 20;
    final int? picked = await showDialog<int>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setLocal) => AlertDialog(
          title: Text(t(context, 'Avísame en…', 'Remind me in…')),
          content: SingleChildScrollView(
            child: NumberStepper(
              value: minutes,
              min: 1,
              max: 24 * 60,
              label: t(context, 'Minutos', 'Minutes'),
              format: (int v) => formatDurationShort(v * 60, spanish: s.settings.spanish),
              onChanged: (int v) => setLocal(() => minutes = v),
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(t(context, 'Cancelar', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(minutes), child: Text(t(context, 'Empezar', 'Start'))),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      await _quick(s, picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'Recordatorios', 'Reminders'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-reminder',
        onPressed: () => ReminderEditorScreen.open(context),
        icon: const Icon(Icons.add_alert_outlined),
        label: Text(t(context, 'Recordatorio', 'Reminder')),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[s.reminders, s.notices, s.settings]),
        builder: (BuildContext context, Widget? _) {
          _schedule(s, Visibility.of(context));
          return _body(context, s);
        },
      ),
    );
  }

  Widget _body(BuildContext context, Services s) {
    final bool es = s.settings.spanish;
    final DateTime now = clock.now();
    final List<Reminder> pending = s.reminders.pending;
    final List<Reminder> overdue = <Reminder>[];
    final List<Reminder> today = <Reminder>[];
    final List<Reminder> later = <Reminder>[];
    for (final Reminder r in pending) {
      if (!r.alertAt.isAfter(now)) {
        overdue.add(r);
      } else if (sameDay(r.alertAt, now)) {
        today.add(r);
      } else {
        later.add(r);
      }
    }
    final List<Reminder> done = s.reminders.completed;
    final NoticePermissions p = s.notices.permissions;
    // Si no caben todos los avisos en lo que guarda el teléfono y lo cubierto
    // no llega a tres días (lo que el cupo de iOS garantiza siempre), se dice
    // aquí hasta cuándo llegan; Ajustes lo muestra siempre que no cabe todo.
    final DateTime? covered = s.notices.coveredUntil;
    return ReadableWidth(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 104),
        children: <Widget>[
          if (p.notifications == false)
            _Banner(
              icon: Icons.notifications_off_outlined,
              text: t(context, 'Las notificaciones de Rutinas están apagadas: los recordatorios no podrán sonar.', 'Rutinas notifications are turned off: reminders will not be able to ring.'),
              action: t(context, 'Activar', 'Turn on'),
              onAction: () async {
                final bool ok = await s.notices.askNotifications(force: true);
                if (!ok) {
                  await s.notices.openSystemSettings();
                }
              },
            )
          else if (p.exactAlarmsApply && !p.exactAlarms && pending.isNotEmpty)
            _Banner(
              icon: Icons.alarm_off,
              text: t(context, 'Sin el permiso «Alarmas y recordatorios», con la pantalla apagada Android puede entregar los avisos hasta una hora tarde.', 'Without the "Alarms & reminders" permission, Android can deliver alerts up to an hour late with the screen off.'),
              action: t(context, 'Permitir', 'Allow'),
              onAction: () => unawaited(s.notices.askExactAlarms()),
            ),
          if (covered != null && covered.isBefore(now.add(const Duration(days: 3))))
            _Banner(
              icon: Icons.event_busy_outlined,
              text: es
                  ? 'Tienes más avisos de los que el teléfono puede guardar: están programados hasta el ${formatShortDate(covered, spanish: true)} a las ${formatTime(covered, spanish: true)}. Abre Rutinas antes de esa hora para que sigan llegando.'
                  : 'You have more alerts than the phone can hold: they are scheduled until ${formatShortDate(covered, spanish: false)} at ${formatTime(covered, spanish: false)}. Open Rutinas before then so they keep arriving.',
            ),
          _QuickCountdown(onPick: (int m) => _quick(s, m), onOther: () => _otherCountdown(s), nag: s.settings.countdownNag, cap: s.notices.limits.nagCap),
          if (pending.isEmpty)
            EmptyState(
              icon: Icons.notifications_none,
              title: t(context, 'Nada pendiente', 'Nothing pending'),
              message: t(context, 'Crea un recordatorio con su hora y, si quieres, que insista mientras no lo marques hecho.', 'Create a reminder with its time and, if you like, have it repeat while it is not marked done.'),
            ),
          if (overdue.isNotEmpty) ...<Widget>[
            SectionHeader('${t(context, 'Vencidos', 'Overdue')} (${overdue.length})'),
            for (final Reminder r in overdue) ReminderTile(reminder: r, now: now),
          ],
          if (today.isNotEmpty) ...<Widget>[
            SectionHeader(t(context, 'Hoy', 'Today')),
            for (final Reminder r in today) ReminderTile(reminder: r, now: now),
          ],
          if (later.isNotEmpty) ...<Widget>[
            SectionHeader(t(context, 'Próximos', 'Upcoming')),
            for (final Reminder r in later) ReminderTile(reminder: r, now: now),
          ],
          if (done.isNotEmpty) ...<Widget>[
            SectionHeader(
              '${t(context, 'Hechos', 'Done')} (${done.length})',
              trailing: Wrap(
                children: <Widget>[
                  TextButton(onPressed: () => setState(() => _showDone = !_showDone), child: Text(_showDone ? t(context, 'Ocultar', 'Hide') : t(context, 'Ver', 'Show'))),
                  if (_showDone)
                    TextButton(
                      onPressed: () async {
                        final bool ok = await confirm(context, title: t(context, '¿Borrar los hechos?', 'Clear done items?'), message: es ? 'Se borran ${done.length} recordatorios hechos.' : '${done.length} done reminders will be deleted.', yes: t(context, 'Borrar', 'Clear'), destructive: true);
                        if (ok) {
                          s.reminders.clearCompleted();
                        }
                      },
                      child: Text(t(context, 'Borrar', 'Clear')),
                    ),
                ],
              ),
            ),
            if (_showDone)
              for (final Reminder r in done.take(50)) ReminderTile(reminder: r, now: now),
          ],
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.action, this.onAction});

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon, color: cs.onTertiaryContainer),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: TextStyle(color: cs.onTertiaryContainer))),
              ],
            ),
            if (action != null) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: onAction, child: Text(action!))) else const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

/// "Avísame en 5 · 10 · 15 · 30 · 60 min" y que insista.
class _QuickCountdown extends StatelessWidget {
  const _QuickCountdown({required this.onPick, required this.onOther, required this.nag, required this.cap});

  final ValueChanged<int> onPick;
  final VoidCallback onOther;

  /// Cada cuántos minutos insiste (Ajustes) y cuántas repeticiones guarda el
  /// sistema si la app no está abierta.
  final int nag;
  final int cap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.hourglass_bottom, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(t(context, 'Avísame en…', 'Remind me in…'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Text(
                isSpanish(context)
                    ? 'Una cuenta regresiva que suena al terminar y repite el aviso cada $nag min hasta que la apagues. Si Rutinas no está abierta cuando suena, repite hasta $cap veces.'
                    : 'A countdown that rings when time is up and repeats every $nag min until you turn it off. If Rutinas is not open when it rings, it repeats up to $cap times.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                for (final int m in const <int>[5, 10, 15, 30, 60])
                  ActionChip(
                    label: Text('$m min'),
                    tooltip: isSpanish(context) ? 'Avísame en $m minutos' : 'Remind me in $m minutes',
                    onPressed: () => onPick(m),
                  ),
                ActionChip(avatar: const Icon(Icons.more_time, size: 18), label: Text(t(context, 'Otro', 'Other')), onPressed: onOther),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Un recordatorio en la lista: marcar hecho, posponer, editar.
class ReminderTile extends StatelessWidget {
  const ReminderTile({super.key, required this.reminder, required this.now});

  final Reminder reminder;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final bool es = s.settings.spanish;
    final ThemeData theme = Theme.of(context);
    final Reminder r = reminder;
    final bool overdue = ReminderLogic.isOverdue(r, now);
    final List<String> info = <String>[];
    if (r.done) {
      info.add(es ? 'Hecho: ${ReminderTexts.when(r.doneAt!, now, true)}' : 'Done: ${ReminderTexts.when(r.doneAt!, now, false)}');
    } else if (r.isCountdown) {
      final int left = r.alertAt.difference(now).inSeconds;
      info.add(left > 0 ? (es ? 'Suena en ${formatClock(left)}' : 'Rings in ${formatClock(left)}') : ReminderTexts.ringingSince(r.alertAt, now, es));
    } else {
      info.add('${ReminderTexts.when(r.alertAt, now, es)} · ${formatRelative(r.alertAt, now, spanish: es)}');
      if (r.snoozedUntil != null) {
        info.add(es ? 'Pospuesto (era ${formatTime(r.dueAt, spanish: true)})' : 'Snoozed (was ${formatTime(r.dueAt, spanish: false)})');
      }
    }
    if (!r.done && r.recurrence.repeats) {
      info.add(ReminderTexts.recurrence(r.recurrence, es, s.settings.weekStart));
    }
    if (!r.done && r.nagMinutes > 0) {
      info.add(ReminderTexts.nag(r.nagMinutes, es));
    }
    if (r.notes.trim().isNotEmpty && !r.done) {
      info.add(r.notes.trim());
    }
    final Color accent = overdue ? theme.colorScheme.error : theme.colorScheme.primary;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => ReminderEditorScreen.open(context, reminder: r),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Row(
            children: <Widget>[
              if (r.done)
                IconButton(
                  tooltip: r.isCountdown ? t(context, 'Repetir la cuenta regresiva', 'Restart the countdown') : t(context, 'Marcar pendiente', 'Mark as pending'),
                  icon: Icon(r.isCountdown ? Icons.replay : Icons.check_circle, color: theme.colorScheme.primary),
                  onPressed: () {
                    if (r.isCountdown) {
                      s.reminders.restartCountdown(r.id);
                    } else {
                      s.reminders.reopen(r.id);
                    }
                  },
                )
              else
                IconButton(
                  tooltip: r.isCountdown ? t(context, 'Apagar', 'Turn off') : t(context, 'Marcar hecho', 'Mark done'),
                  icon: Icon(r.isCountdown ? Icons.alarm_off : Icons.radio_button_unchecked, color: accent),
                  onPressed: () {
                    final Map<String, dynamic>? before = s.reminders.complete(r.id);
                    // Fuera del panel todos sus avisos, también los de veces anteriores.
                    unawaited(s.notices.dismissReminder(r));
                    if (before != null) {
                      showSnack(
                        context,
                        r.recurrence.repeats && !r.done ? (es ? 'Hecho. El siguiente: ${ReminderTexts.when(r.dueAt, clock.now(), true)}.' : 'Done. Next: ${ReminderTexts.when(r.dueAt, clock.now(), false)}.') : t(context, 'Hecho', 'Done'),
                        actionLabel: t(context, 'Deshacer', 'Undo'),
                        onAction: () => s.reminders.restore(before),
                      );
                    }
                  },
                ),
              Expanded(
                child: Semantics(
                  label: '${r.title}. ${info.join('. ')}',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(r.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, decoration: r.done ? TextDecoration.lineThrough : null)),
                        for (int i = 0; i < info.length; i++)
                          Text(info[i], style: theme.textTheme.bodyMedium?.copyWith(color: i == 0 && overdue ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant, fontWeight: i == 0 && overdue ? FontWeight.w600 : null)),
                      ],
                    ),
                  ),
                ),
              ),
              // Posponer solo lo que ya sonó o suena dentro de una hora: en uno
              // de dentro de días lo haría sonar antes de tiempo.
              if (ReminderLogic.canSnooze(r, now))
                PopupMenuButton<int>(
                  tooltip: t(context, 'Posponer', 'Snooze'),
                  icon: const Icon(Icons.snooze),
                  onSelected: (int minutes) {
                    if (minutes == _tomorrow) {
                      final DateTime n = clock.now();
                      s.reminders.snoozeUntil(r.id, DateTime(n.year, n.month, n.day + 1, 9));
                    } else {
                      s.reminders.snooze(r.id, minutes);
                    }
                    unawaited(s.notices.dismissReminder(r));
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
                    for (final int m in const <int>[5, 10, 30, 60, 180])
                      PopupMenuItem<int>(value: m, child: Text(es ? 'Posponer ${formatDurationShort(m * 60, spanish: true)}' : 'Snooze ${formatDurationShort(m * 60, spanish: false)}')),
                    PopupMenuItem<int>(value: _tomorrow, child: Text(es ? 'Mañana a las ${formatTimeOfDay(9, 0, spanish: true)}' : 'Tomorrow at ${formatTimeOfDay(9, 0, spanish: false)}')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Valor de la opción «Mañana a las 9:00» en el menú de posponer.
  static const int _tomorrow = -1;
}
