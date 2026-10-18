import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/ledger.dart';
import '../../core/periods.dart';
import '../../core/reminders.dart';
import '../../model/money.dart';
import '../widgets/adaptive.dart';

/// Ajustes generales.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _syncReminders(Services s) => Reminders.sync(ledger: s.ledger, settings: s.settings, notifier: s.notifier, spanish: s.settings.spanish);

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[s.settings, s.ledger]),
      builder: (BuildContext context, Widget? _) {
        final Ledger l = s.ledger;
        final ColorScheme cs = Theme.of(context).colorScheme;
        final List<String> currencies = <String>{l.baseCurrency, ...s.settings.extraCurrencies, 'COP', 'USD'}.toList();
        return ReadableScaffold(
          appBar: AppBar(title: Text(t(context, 'Ajustes', 'Settings'))),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: <Widget>[
              _header(context, t(context, 'Periodo', 'Period')),
              ListTile(
                leading: const Icon(Icons.calendar_view_month_outlined),
                title: Text(t(context, 'Cómo cuentas el mes', 'How you count the month')),
                subtitle: Text(l.periodSpec.mode == PeriodMode.quincena ? t(context, 'Por quincenas (1–15 y 16–fin)', 'Fortnights (1–15 and 16–end)') : (l.periodSpec.startDay == 1 ? t(context, 'Mes calendario', 'Calendar month') : t(context, 'Mes que empieza el día ${l.periodSpec.startDay}', 'Month starting on day ${l.periodSpec.startDay}'))),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pickPeriod(context, s),
              ),
              _header(context, t(context, 'Dinero', 'Money')),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(t(context, 'Moneda base', 'Base currency')),
                subtitle: Text('${l.baseCurrency} · ${Money.info(l.baseCurrency).name}'),
                trailing: DropdownButton<String>(
                  value: l.baseCurrency,
                  underline: const SizedBox.shrink(),
                  items: <DropdownMenuItem<String>>[for (final String c in currencies) DropdownMenuItem<String>(value: c, child: Text(c))],
                  onChanged: (String? v) {
                    if (v == null || v == l.baseCurrency) {
                      return;
                    }
                    l.baseCurrency = v;
                    l.rates.rates.clear();
                    l.rates.manual.clear();
                    l.rates.updatedAt = null;
                    l.save();
                    if (!s.settings.extraCurrencies.contains(v)) {
                      s.settings.extraCurrencies = <String>[...s.settings.extraCurrencies, v];
                      s.settings.save();
                    }
                  },
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.pin_outlined),
                value: s.settings.showCents,
                onChanged: (bool v) {
                  s.settings.showCents = v;
                  s.settings.save();
                },
                title: Text(t(context, 'Mostrar centavos', 'Show cents')),
                subtitle: Text(t(context, 'En pesos normalmente no hacen falta.', 'Usually not needed for pesos.')),
              ),
              _header(context, t(context, 'Recordatorios', 'Reminders')),
              SwitchListTile(
                secondary: const Icon(Icons.alarm_outlined),
                value: s.settings.dailyReminder,
                onChanged: (bool v) async {
                  if (v && !await s.notifier.requestPermission()) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Sin permiso de notificaciones no se pueden mostrar recordatorios.', 'Reminders need the notifications permission.'))));
                    }
                    return;
                  }
                  s.settings.dailyReminder = v;
                  await s.settings.save();
                  await _syncReminders(s);
                },
                title: Text(t(context, 'Recordatorio diario para anotar', 'Daily reminder to log')),
                subtitle: Text('${s.settings.dailyReminderHour.toString().padLeft(2, '0')}:${s.settings.dailyReminderMinute.toString().padLeft(2, '0')}'),
              ),
              if (s.settings.dailyReminder)
                ListTile(
                  leading: const SizedBox(width: 24),
                  title: Text(t(context, 'Hora del recordatorio', 'Reminder time')),
                  trailing: const Icon(Icons.schedule),
                  onTap: () async {
                    final TimeOfDay? tod = await showTimePicker(context: context, initialTime: TimeOfDay(hour: s.settings.dailyReminderHour, minute: s.settings.dailyReminderMinute));
                    if (tod != null) {
                      s.settings.dailyReminderHour = tod.hour;
                      s.settings.dailyReminderMinute = tod.minute;
                      await s.settings.save();
                      await _syncReminders(s);
                    }
                  },
                ),
              SwitchListTile(
                secondary: const Icon(Icons.event_available_outlined),
                value: s.settings.billReminders,
                onChanged: (bool v) async {
                  if (v && !await s.notifier.requestPermission()) {
                    return;
                  }
                  s.settings.billReminders = v;
                  await s.settings.save();
                  await _syncReminders(s);
                },
                title: Text(t(context, 'Avisar pagos programados y tarjetas', 'Remind scheduled payments and cards')),
                subtitle: Text(t(context, 'Un aviso antes de cada programado y de la fecha límite de pago de las tarjetas.', 'A notice before each scheduled item and before each card payment due date.')),
              ),
              if (s.settings.billReminders)
                ListTile(
                  leading: const SizedBox(width: 24),
                  title: Text(t(context, 'Aviso de tarjetas', 'Card notice')),
                  trailing: DropdownButton<int>(
                    value: <int>[0, 1, 2, 3, 5].contains(s.settings.billReminderDaysBefore) ? s.settings.billReminderDaysBefore : 1,
                    underline: const SizedBox.shrink(),
                    items: <DropdownMenuItem<int>>[for (final int d in <int>[0, 1, 2, 3, 5]) DropdownMenuItem<int>(value: d, child: Text(d == 0 ? t(context, 'El mismo día', 'Same day') : t(context, '$d día${d == 1 ? '' : 's'} antes', '$d day${d == 1 ? '' : 's'} before')))],
                    onChanged: (int? v) async {
                      s.settings.billReminderDaysBefore = v ?? 1;
                      await s.settings.save();
                      await _syncReminders(s);
                    },
                  ),
                ),
              _header(context, t(context, 'Apariencia', 'Appearance')),
              ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: Text(t(context, 'Tema', 'Theme')),
                trailing: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: <ButtonSegment<String>>[
                    ButtonSegment<String>(value: 'system', label: Text(t(context, 'Auto', 'Auto'))),
                    const ButtonSegment<String>(value: 'light', icon: Icon(Icons.light_mode_outlined)),
                    const ButtonSegment<String>(value: 'dark', icon: Icon(Icons.dark_mode_outlined)),
                  ],
                  selected: <String>{s.settings.themeMode},
                  onSelectionChanged: (Set<String> v) {
                    s.settings.themeMode = v.first;
                    s.settings.save();
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.language),
                title: Text(t(context, 'Idioma', 'Language')),
                trailing: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const <ButtonSegment<String>>[
                    ButtonSegment<String>(value: 'es', label: Text('Español')),
                    ButtonSegment<String>(value: 'en', label: Text('English')),
                  ],
                  selected: <String>{s.settings.language},
                  onSelectionChanged: (Set<String> v) {
                    s.settings.language = v.first;
                    s.settings.save();
                  },
                ),
              ),
              Padding(padding: const EdgeInsets.all(16), child: Text(t(context, 'Las categorías ya creadas conservan su nombre al cambiar de idioma.', 'Existing categories keep their names when you switch language.'), style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)))),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, String text) => Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 13)));

  Future<void> _pickPeriod(BuildContext context, Services s) async {
    final Ledger l = s.ledger;
    PeriodMode mode = l.periodSpec.mode;
    int day = l.periodSpec.startDay;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => AlertDialog(
          title: Text(t(context, 'Periodo de la app', 'App period')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SegmentedButton<PeriodMode>(
                showSelectedIcon: false,
                segments: <ButtonSegment<PeriodMode>>[
                  ButtonSegment<PeriodMode>(value: PeriodMode.month, label: Text(t(context, 'Mensual', 'Monthly'))),
                  ButtonSegment<PeriodMode>(value: PeriodMode.quincena, label: Text(t(context, 'Quincenal', 'Fortnightly'))),
                ],
                selected: <PeriodMode>{mode},
                onSelectionChanged: (Set<PeriodMode> v) => setState(() => mode = v.first),
              ),
              const SizedBox(height: 8),
              Text(mode == PeriodMode.month ? t(context, 'El mes empieza el día que elijas (por ejemplo tu día de pago).', 'The month starts on the day you choose (for example your payday).') : t(context, 'Del 1 al 15 y del 16 a fin de mes.', '1st–15th and 16th–end of month.'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
              const SizedBox(height: 8),
              if (mode == PeriodMode.month)
                Row(
                  children: <Widget>[
                    Expanded(child: Text(t(context, 'Día de inicio', 'Start day'))),
                    DropdownButton<int>(
                      value: day.clamp(1, 28),
                      items: <DropdownMenuItem<int>>[for (int d = 1; d <= 28; d++) DropdownMenuItem<int>(value: d, child: Text('$d'))],
                      onChanged: (int? v) => setState(() => day = v ?? day),
                    ),
                  ],
                ),
            ],
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t(context, 'Cancelar', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t(context, 'Aceptar', 'OK'))),
          ],
        ),
      ),
    );
    if (ok == true) {
      l.periodSpec = PeriodSpec(mode: mode, startDay: day.clamp(1, 28));
      l.save();
    }
  }
}
