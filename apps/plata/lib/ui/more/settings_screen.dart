import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/ledger.dart';
import '../../core/periods.dart';
import '../../core/reminders.dart';
import '../../model/models.dart';
import '../../model/money.dart';
import '../widgets/adaptive.dart';
import '../widgets/common.dart';
import 'erase_screen.dart';

/// Ajustes generales.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  Future<void> _syncReminders(Services s) => Reminders.sync(ledger: s.ledger, settings: s.settings, notifier: s.notifier, spanish: s.settings.spanish, private: s.settings.hideBalances || s.lock.enabled);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver de los ajustes del sistema el permiso pudo cambiar.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    if (!mounted) {
      return;
    }
    final Services s = AppScope.of(context);
    s.settings.setNotificationsAllowed(await s.notifier.permissionStatus());
  }

  Future<void> _grant(Services s) async {
    bool ok = await s.notifier.requestPermission();
    if (!ok) {
      // Negado antes: el sistema ya no pregunta; se abren sus ajustes.
      await s.notifier.openSettings();
      ok = await s.notifier.permissionStatus() ?? false;
    }
    s.settings.setNotificationsAllowed(ok);
  }

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
                subtitle: Text(l.periodSpec.mode == PeriodMode.quincena ? t(context, 'Por quincenas (1–15 y 16–fin)', 'Twice a month (1st–15th and 16th–end)') : (l.periodSpec.startDay == 1 ? t(context, 'Mes calendario', 'Calendar month') : t(context, 'Mes que empieza el día ${l.periodSpec.startDay}', 'Month starting on day ${l.periodSpec.startDay}'))),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pickPeriod(context, s),
              ),
              _header(context, t(context, 'Dinero', 'Money')),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(t(context, 'Moneda base', 'Base currency')),
                subtitle: Text('${l.baseCurrency} · ${Money.info(l.baseCurrency).nameFor(spanish: s.settings.spanish)}'),
                trailing: DropdownButton<String>(
                  value: l.baseCurrency,
                  underline: const SizedBox.shrink(),
                  items: <DropdownMenuItem<String>>[for (final String c in currencies) DropdownMenuItem<String>(value: c, child: Text(c))],
                  onChanged: (String? v) async {
                    if (v == null || v == l.baseCurrency) {
                      return;
                    }
                    final bool es = s.settings.spanish;
                    final String old = l.baseCurrency;
                    final double? r = l.rateToBase(v);
                    if ((r == null || r <= 0) && l.hasMoneyData) {
                      // Sin la tasa entre las dos monedas, los saldos y los topes no se
                      // pueden convertir: no se cambia nada.
                      await showDialog<void>(
                        context: context,
                        builder: (BuildContext c) => AlertDialog(
                          title: Text(t(c, 'Falta la tasa de $v', 'The $v rate is missing')),
                          content: Text(t(c, 'Para pasar todo a $v hace falta saber cuántos $old vale 1 $v. Actualiza las tasas en Más › Monedas (con internet) o escríbela a mano allí, y vuelve a intentarlo.', 'To move everything to $v the app needs to know how many $old 1 $v is worth. Refresh the rates under More › Currencies (online) or type it by hand there, and try again.')),
                          actions: <Widget>[FilledButton(onPressed: () => Navigator.pop(c), child: Text(t(c, 'Entendido', 'Got it')))],
                        ),
                      );
                      return;
                    }
                    if (!context.mounted) {
                      return;
                    }
                    final bool ok = await confirm(
                      context,
                      t(context, '¿Cambiar la moneda base a $v?', 'Change the base currency to $v?'),
                      r == null
                          ? t(context, 'Los totales, informes y presupuestos se mostrarán en $v.', 'Totals, reports and budgets will be shown in $v.')
                          : t(context, 'Los totales, informes y presupuestos se mostrarán en $v. Se convierten con la tasa guardada (1 $v = ${Money.formatRate(r, spanish: es)} $old), y los topes de los presupuestos también.', 'Totals, reports and budgets will be shown in $v. They are converted at the saved rate (1 $v = ${Money.formatRate(r, spanish: es)} $old), and so are budget caps.'),
                      yes: t(context, 'Cambiar', 'Change'),
                    );
                    if (!ok) {
                      return;
                    }
                    try {
                      l.changeBaseCurrency(v);
                    } on TxRejected {
                      return;
                    }
                    s.settings.extraCurrencies = <String>{...s.settings.extraCurrencies, old}.where((String c) => c != v).toList();
                    await s.settings.save();
                    final Set<String> foreign = <String>{...s.settings.extraCurrencies, ...l.accounts.map((Account a) => a.currency)}..remove(v);
                    if (s.settings.ratesAuto && foreign.isNotEmpty) {
                      try {
                        if (await s.rates.refresh(l.rates, base: v, currencies: foreign)) {
                          l.save();
                        }
                      } catch (_) {
                        // Sin conexión: quedan las tasas convertidas; se actualizan al abrir la app o desde Más › Monedas.
                      }
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
              _permissionTile(context, s),
              SwitchListTile(
                secondary: const Icon(Icons.alarm_outlined),
                value: s.settings.dailyReminder,
                onChanged: (bool v) async {
                  if (v && !await ensureNotifications(context, force: true, why: t(context, 'Para recordarte anotar tus gastos cada día, Plata necesita permiso para mostrar notificaciones.', 'To remind you to log your spending every day, Plata needs permission to show notifications.'))) {
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
                  if (v && !await ensureNotifications(context, force: true, why: t(context, 'Para avisarte antes de tus pagos programados y de la fecha límite de tus tarjetas, Plata necesita permiso para mostrar notificaciones.', 'To remind you before your scheduled payments and card due dates, Plata needs permission to show notifications.'))) {
                    return;
                  }
                  s.settings.billReminders = v;
                  await s.settings.save();
                  await _syncReminders(s);
                },
                title: Text(t(context, 'Avisar pagos programados y tarjetas', 'Remind scheduled payments and cards')),
                subtitle: Text(t(context, 'Un aviso antes de cada programado y de la fecha límite de pago de las tarjetas, y otro si un pago de tarjeta se vence.', 'A notice before each scheduled item and card payment due date, and another if a card payment becomes overdue.')),
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
                    l.applyLanguage(v.first == 'es');
                  },
                ),
              ),
              Padding(padding: const EdgeInsets.all(16), child: Text(t(context, 'Las categorías de fábrica cambian de idioma; las que creaste o les cambiaste el nombre se quedan como están.', 'Built-in categories switch language; the ones you created or renamed stay as they are.'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
              _header(context, t(context, 'Tus datos', 'Your data')),
              ListTile(
                leading: Icon(Icons.delete_forever_outlined, color: cs.error),
                title: Text(t(context, 'Borrar todos los datos', 'Erase all data')),
                subtitle: Text(t(context, 'Cuentas, movimientos, fotos, copias automáticas, avisos y la clave. La app queda como recién instalada.', 'Accounts, transactions, photos, automatic copies, notices and the passcode. The app is left as if just installed.')),
                onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const EraseAllScreen())),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Estado real del permiso de notificaciones, con un botón para darlo.
  Widget _permissionTile(BuildContext context, Services s) {
    final bool? allowed = s.settings.notificationsAllowed;
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(allowed == false ? Icons.notifications_off_outlined : Icons.notifications_outlined, color: allowed == false ? cs.error : null),
      title: Text(t(context, 'Permiso de notificaciones', 'Notification permission')),
      subtitle: Text(allowed == true
          ? t(context, 'Concedido: los recordatorios aparecen.', 'Granted: reminders show up.')
          : (allowed == false ? t(context, 'Sin permiso: los recordatorios no aparecen.', 'Not granted: reminders do not show up.') : t(context, 'No se pudo comprobar.', 'Could not be checked.'))),
      trailing: allowed == true ? null : TextButton(onPressed: () => _grant(s), child: Text(t(context, 'Dar permiso', 'Grant'))),
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
                  ButtonSegment<PeriodMode>(value: PeriodMode.quincena, label: Text(t(context, 'Quincenal', 'Twice a month'))),
                ],
                selected: <PeriodMode>{mode},
                onSelectionChanged: (Set<PeriodMode> v) => setState(() => mode = v.first),
              ),
              const SizedBox(height: 8),
              Text(mode == PeriodMode.month ? t(context, 'El mes empieza el día que elijas (por ejemplo tu día de pago).', 'The month starts on the day you choose (for example your payday).') : t(context, 'Del 1 al 15 y del 16 a fin de mes.', '1st–15th and 16th–end of month.'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
