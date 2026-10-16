import '../model/models.dart';
import '../model/money.dart';
import 'ledger.dart';
import 'notifications.dart';
import 'periods.dart';
import 'settings.dart';

/// Programa los recordatorios locales a partir del libro: registro diario,
/// movimientos programados próximos y fechas de pago de tarjetas.
class Reminders {
  Reminders._();

  static const int dailyId = 1;

  static Future<void> sync({required Ledger ledger, required AppSettings settings, required Notifier notifier, DateTime? now, bool spanish = true}) async {
    final DateTime today = dateOnly(now ?? DateTime.now());
    await notifier.cancelAll();
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
      if (!when.isAfter(now ?? DateTime.now())) {
        continue;
      }
      final String amount = Money.format(s.amountMinor, ledger.account(s.accountId)?.currency ?? ledger.baseCurrency, showCents: settings.showCents);
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
      if (st.dueMinor <= 0 || !when.isAfter(now ?? DateTime.now())) {
        continue;
      }
      await notifier.scheduleAt(
        id: id++,
        when: when,
        title: spanish ? 'Pago de ${a.name}' : '${a.name} payment',
        body: spanish ? 'Vence el ${formatDate(pay, 'dd MMM')}: ${Money.format(st.dueMinor, a.currency, showCents: settings.showCents)}' : 'Due ${formatDate(pay, 'MMM dd', spanish: false)}: ${Money.format(st.dueMinor, a.currency, showCents: settings.showCents)}',
      );
    }
  }
}
