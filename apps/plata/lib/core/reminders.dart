import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../model/models.dart';
import '../model/money.dart';
import 'ledger.dart';
import 'notifications.dart';
import 'settings.dart';

/// Programa los recordatorios locales a partir del libro: registro diario,
/// movimientos programados próximos y fechas de pago de tarjetas.
class Reminders {
  Reminders._();

  static const int dailyId = 1;

  static Future<void> sync({required Ledger ledger, required AppSettings settings, required Notifier notifier, DateTime? now, bool spanish = true}) async {
    final DateTime moment = now ?? clock.now();
    final DateTime today = dateOnly(moment);
    notifier.setLanguage(spanish: spanish);
    await notifier.cancelAll();
    if (ledger.readOnly) {
      return;
    }
    if (settings.dailyReminder) {
      await notifier.scheduleDaily(
        id: dailyId,
        hour: settings.dailyReminderHour,
        minute: settings.dailyReminderMinute,
        title: spanish ? '¿Qué gastaste hoy?' : 'What did you spend today?',
        body: spanish ? 'Anota tus movimientos del día en Plata.' : 'Log today\'s transactions in Plata.',
      );
    }
    if (!settings.billReminders) {
      return;
    }
    int id = 100;
    for (final Scheduled s in ledger.upcoming(days: 45, now: today)) {
      if (s.remindDaysBefore < 0) {
        continue; // sin recordatorio
      }
      final int days = s.remindDaysBefore;
      final DateTime when = DateTime(s.nextDate.year, s.nextDate.month, s.nextDate.day - days, 9);
      if (!when.isAfter(moment)) {
        continue;
      }
      final String amount = Money.format(s.amountMinor, ledger.account(s.accountId)?.currency ?? ledger.baseCurrency, showCents: settings.showCents, spanish: spanish);
      await notifier.scheduleAt(
        id: id++,
        when: when,
        title: spanish ? (days == 0 ? 'Hoy: ${s.name}' : 'Pronto: ${s.name}') : (days == 0 ? 'Today: ${s.name}' : 'Coming up: ${s.name}'),
        body: spanish ? '$amount el ${formatDate(s.nextDate, 'dd MMM')}' : '$amount on ${formatDate(s.nextDate, 'MMM dd', spanish: false)}',
      );
      if (id > 180) {
        break;
      }
    }
    id = 200;
    for (final Account a in ledger.activeAccounts) {
      if (!a.isCredit || a.payDay == null) {
        continue;
      }
      final CardStatement st = ledger.nextPayment(a, now: today);
      final DateTime pay = st.cycle.payDate;
      final DateTime when = DateTime(pay.year, pay.month, pay.day - settings.billReminderDaysBefore, 9);
      if (st.dueMinor <= 0 || !when.isAfter(moment)) {
        continue;
      }
      final String due = Money.format(st.dueMinor, a.currency, showCents: settings.showCents, spanish: spanish);
      await notifier.scheduleAt(
        id: id++,
        when: when,
        title: spanish ? 'Pago de ${a.name}' : '${a.name} payment',
        // Es el capital estimado: el extracto del banco suma intereses y cuota de manejo.
        body: spanish ? 'Vence el ${formatDate(pay, 'dd MMM')}: unos $due de capital (revisa tu extracto)' : 'Due ${formatDate(pay, 'MMM dd', spanish: false)}: about $due in principal (check your statement)',
      );
    }
  }
}

/// Mantiene los recordatorios al día: cada cambio del libro o de los ajustes
/// (un programado nuevo, un pago de tarjeta, otro idioma) los vuelve a
/// programar, agrupando los cambios seguidos en una sola sincronización.
class ReminderScheduler {
  ReminderScheduler({required this.ledger, required this.settings, required this.notifier, this.delay = const Duration(seconds: 2)});

  final Ledger ledger;
  final AppSettings settings;
  final Notifier notifier;
  final Duration delay;
  Timer? _timer;
  bool _started = false;
  Future<void>? _running;

  /// Número de sincronizaciones hechas (para pruebas).
  int syncs = 0;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    ledger.addListener(_changed);
    settings.addListener(_changed);
  }

  void stop() {
    if (!_started) {
      return;
    }
    _started = false;
    ledger.removeListener(_changed);
    settings.removeListener(_changed);
    _timer?.cancel();
    _timer = null;
  }

  void _changed() {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(syncNow()));
  }

  /// Sincroniza ya (al arrancar y al volver a la app, cuando pudo cambiar el día).
  Future<void> syncNow() async {
    _timer?.cancel();
    _timer = null;
    final Future<void>? previous = _running;
    final Completer<void> done = Completer<void>();
    _running = done.future;
    try {
      if (previous != null) {
        await previous;
      }
      await Reminders.sync(ledger: ledger, settings: settings, notifier: notifier, spanish: settings.spanish);
      syncs += 1;
    } catch (e) {
      debugPrint('Recordatorios: $e');
    } finally {
      done.complete();
      if (identical(_running, done.future)) {
        _running = null;
      }
    }
  }
}
