import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../model/models.dart';
import '../model/money.dart';
import 'ledger.dart';
import 'notifications.dart';
import 'periods.dart';
import 'settings.dart';

/// Un aviso que la sincronización quiere dejar programado.
class _Planned {
  const _Planned({required this.when, required this.title, required this.body, this.payload});

  final DateTime when;
  final String title;
  final String body;

  /// Para los avisos de pago pendiente: `o:<tarjeta>:<corte>`.
  final String? payload;
}

/// Programa los recordatorios locales a partir del libro: registro diario,
/// movimientos programados próximos, fechas de pago de tarjetas y pagos de
/// tarjeta vencidos.
class Reminders {
  Reminders._();

  static const int dailyId = 1;

  /// Ocurrencias que se agendan por adelantado de cada programado y de cada
  /// tarjeta, dentro de [horizonDays].
  static const int occurrencesAhead = 3;
  static const int horizonDays = 120;

  /// Días seguidos en que se recuerda un programado manual vencido.
  static const int overdueReminderDays = 3;

  /// Tope de avisos agendados: iOS guarda solo los 64 más próximos de cada app.
  static const int maxPlanned = 60;

  /// Id estable de un aviso a partir de su clave (`s:<programado>:<fecha>`,
  /// `c:<tarjeta>:<fecha de pago>`): el mismo aviso conserva su id entre una
  /// sincronización y otra, así que se reemplaza en lugar de duplicarse.
  static int idFor(String key) {
    int h = 0x811C9DC5;
    for (final int c in key.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7FFFFFFF;
    }
    return 1000 + h % 2000000000;
  }

  /// Si hay algo que avisar: el recordatorio diario, o programados con
  /// recordatorio y tarjetas con día de pago (con los avisos de pagos
  /// encendidos). Sin permiso de notificaciones, Inicio lo dice.
  static bool wanted(Ledger ledger, AppSettings settings) {
    if (settings.dailyReminder) {
      return true;
    }
    if (!settings.billReminders) {
      return false;
    }
    return ledger.scheduled.any((Scheduled s) => s.enabled && s.remindDaysBefore >= 0) || ledger.activeAccounts.any((Account a) => a.isCredit && a.payDay != null);
  }

  /// Sincroniza los avisos con el libro. Solo cancela los avisos programados
  /// que ya no tocan: los que ya se mostraron siguen en la bandeja aunque se
  /// anote algo nuevo. Con [private] (clave de acceso o saldos ocultos) los
  /// avisos no llevan montos y Android los oculta en la pantalla de bloqueo.
  static Future<void> sync({required Ledger ledger, required AppSettings settings, required Notifier notifier, DateTime? now, bool spanish = true, bool private = false}) async {
    final DateTime moment = now ?? clock.now();
    final DateTime today = dateOnly(moment);
    notifier.setLanguage(spanish: spanish);
    final List<int> pending = await notifier.pendingIds();
    if (ledger.readOnly) {
      for (final int id in pending) {
        await notifier.cancel(id);
      }
      return;
    }
    final Map<int, _Planned> planned = <int, _Planned>{};
    final List<MapEntry<String, _Planned>> overdue = <MapEntry<String, _Planned>>[];
    String amountOf(int minor, String currency) => Money.format(minor, currency, showCents: settings.showCents, spanish: spanish);
    if (settings.billReminders) {
      // Varias ocurrencias por adelantado: si la app no se abre durante un
      // ciclo, el aviso del siguiente igual llega (ver [maxPlanned]).
      for (final Scheduled s in ledger.scheduled) {
        if (!s.enabled || s.remindDaysBefore < 0) {
          continue; // sin recordatorio
        }
        final int days = s.remindDaysBefore;
        final String amount = amountOf(s.amountMinor, ledger.account(s.accountId)?.currency ?? ledger.baseCurrency);
        if (!s.autoPost && dateOnly(s.nextDate).isBefore(today)) {
          // Un programado manual vencido vuelve a recordarse unos días.
          final String date = spanish ? formatDate(s.nextDate, 'dd MMM') : formatDate(s.nextDate, 'MMM dd', spanish: false);
          for (int k = 1; k <= overdueReminderDays; k++) {
            final DateTime day = addDays(today, k);
            planned[idFor('p:${s.id}:${dayKey(s.nextDate)}:${dayKey(day)}')] = _Planned(
              when: DateTime(day.year, day.month, day.day, 9),
              title: spanish ? 'Pendiente: ${s.name}' : 'Pending: ${s.name}',
              body: private ? (spanish ? 'Tocaba el $date: anótalo o sáltalo en Plata.' : 'It was due on $date: log or skip it in Plata.') : (spanish ? '$amount, tocaba el $date: anótalo o sáltalo en Plata.' : '$amount, due on $date: log or skip it in Plata.'),
            );
          }
        }
        DateTime d = dateOnly(s.nextDate);
        for (int k = 0; k < occurrencesAhead; k++) {
          if (d.isAfter(addDays(today, horizonDays)) || (s.endDate != null && d.isAfter(dateOnly(s.endDate!)))) {
            break;
          }
          final DateTime when = DateTime(d.year, d.month, d.day - days, 9);
          if (when.isAfter(moment)) {
            final String title = spanish ? (days == 0 ? 'Hoy: ${s.name}' : 'Pronto: ${s.name}') : (days == 0 ? 'Today: ${s.name}' : 'Coming up: ${s.name}');
            final String date = spanish ? formatDate(d, 'dd MMM') : formatDate(d, 'MMM dd', spanish: false);
            final String body = private ? (spanish ? 'Vence el $date' : 'Due $date') : (spanish ? '$amount el $date' : '$amount on $date');
            planned[idFor('s:${s.id}:${dayKey(d)}')] = _Planned(when: when, title: title, body: body);
          }
          d = dateOnly(s.frequency.next(d, anchor: s.anchorDate));
        }
      }
      for (final Account a in ledger.activeAccounts) {
        if (!a.isCredit || a.payDay == null) {
          continue;
        }
        final CardDue due = ledger.cardDue(a, now: today);
        if (due.overdue) {
          // Vencido contra un pago mínimo que la persona anotó: se avisa de
          // inmediato, una sola vez por fecha límite. Sin mínimo conocido no
          // hay aviso de mora (ver Ledger.cardDue).
          // Tono prudente: es lo que dice lo anotado en Plata, y puede que el
          // pago se haya hecho fuera. El aviso trae «Ya lo pagué».
          final String since = spanish ? formatDate(due.overdueSince!, 'dd MMM') : formatDate(due.overdueSince!, 'MMM dd', spanish: false);
          final String amount = amountOf(due.overdueMinor, a.currency);
          overdue.add(MapEntry<String, _Planned>(
            'o:${a.id}:${dayKey(due.overdueSince!)}',
            _Planned(
              when: moment,
              title: spanish ? 'Revisa el pago de ${a.name}' : 'Check your ${a.name} payment',
              body: private
                  ? (spanish ? 'Según lo anotado en Plata, el pago mínimo que vencía el $since no está completo. Si ya pagaste, toca «Ya lo pagué».' : 'According to what you logged in Plata, the minimum payment due on $since is not complete. If you already paid, tap "I already paid".')
                  : (spanish ? 'Según lo anotado en Plata, faltan $amount del pago mínimo que vencía el $since. Si ya pagaste, toca «Ya lo pagué».' : 'According to what you logged in Plata, $amount of the minimum payment due on $since is missing. If you already paid, tap "I already paid".'),
              payload: 'o:${a.id}:${dayKey(due.statementCut!)}',
            ),
          ));
        }
        final CardStatement st = due.next;
        CardCycle cycle = st.cycle;
        for (int k = 0; k < occurrencesAhead; k++) {
          final DateTime pay = cycle.payDate;
          // La fecha que se dice y desde la que se cuenta el aviso es la real
          // (corrida si cae en un día no hábil), la misma del resto de la app.
          final DateTime real = ledger.effectivePayDate(a, pay);
          final DateTime when = DateTime(real.year, real.month, real.day - settings.billReminderDaysBefore, 9);
          // El primero lleva el capital estimado si hay algo que pagar; los
          // siguientes, solo la fecha, y solo si la tarjeta tiene deuda.
          final bool first = k == 0;
          final bool worth = first ? st.dueMinor > 0 : ledger.balanceMinor(a.id) < 0;
          if (worth && when.isAfter(moment)) {
            final String date = spanish ? formatDate(real, 'dd MMM') : formatDate(real, 'MMM dd', spanish: false);
            final String due0 = amountOf(st.dueMinor, a.currency);
            // Si hay un abono que Plata tomó por el pago hecho fuera de Plata y
            // nadie lo ha confirmado, el aviso lo recuerda: la cifra depende
            // de la respuesta.
            final String ask = first && ledger.pendingOutsideMatches(card: a).isNotEmpty ? (spanish ? '. Tienes un abono por confirmar en Plata' : '. You have a payment to confirm in Plata') : '';
            planned[idFor('c:${a.id}:${dayKey(pay)}')] = _Planned(
              when: when,
              title: spanish ? 'Pago de ${a.name}' : '${a.name} payment',
              // Es el capital estimado: el extracto del banco suma intereses y cuota de manejo.
              body: '${private || !first ? (spanish ? 'Vence el $date (revisa tu extracto)' : 'Due $date (check your statement)') : (spanish ? 'Vence el $date: unos $due0 de capital (revisa tu extracto)' : 'Due $date: about $due0 in principal (check your statement)')}$ask',
            );
          }
          cycle = CardCycle.current(a, addDays(cycle.cut, 1));
        }
      }
    }
    if (planned.length > maxPlanned) {
      // iOS solo guarda los 64 avisos más próximos de una app: se dejan los
      // más cercanos, con espacio para el diario.
      final List<MapEntry<int, _Planned>> sorted = planned.entries.toList()..sort((MapEntry<int, _Planned> x, MapEntry<int, _Planned> y) => x.value.when.compareTo(y.value.when));
      planned
        ..clear()
        ..addEntries(sorted.take(maxPlanned));
    }
    // Solo se cancelan los programados que ya no tocan; el diario se deja si
    // sigue encendido (cancelarlo quitaría también el de hoy de la bandeja).
    for (final int id in pending) {
      if (planned.containsKey(id) || (id == dailyId && settings.dailyReminder)) {
        continue;
      }
      await notifier.cancel(id);
    }
    if (settings.dailyReminder) {
      await notifier.scheduleDaily(
        id: dailyId,
        hour: settings.dailyReminderHour,
        minute: settings.dailyReminderMinute,
        title: spanish ? '¿Qué gastaste hoy?' : 'What did you spend today?',
        body: spanish ? 'Anota tus movimientos del día en Plata.' : 'Log today\'s transactions in Plata.',
        private: private,
      );
    }
    for (final MapEntry<int, _Planned> e in planned.entries) {
      await notifier.scheduleAt(id: e.key, when: e.value.when, title: e.value.title, body: e.value.body, private: private);
    }
    if (overdue.isNotEmpty) {
      final Set<String> told = settings.overdueNotified.toSet();
      bool changed = false;
      for (final MapEntry<String, _Planned> e in overdue) {
        if (told.contains(e.key)) {
          continue;
        }
        // Solo se da por avisado si de verdad se mostró (con permiso): si no,
        // se vuelve a intentar en la próxima sincronización.
        if (await notifier.showNow(id: idFor(e.key), title: e.value.title, body: e.value.body, private: private, payload: e.value.payload, paidButton: true)) {
          told.add(e.key);
          changed = true;
        }
      }
      if (changed) {
        // Solo se recuerdan los últimos avisos: una fecha límite no vuelve.
        final List<String> list = told.toList();
        settings.overdueNotified = list.length > 60 ? list.sublist(list.length - 60) : list;
        await settings.save();
      }
    }
  }
}

/// Mantiene los recordatorios al día: cada cambio del libro o de los ajustes
/// (un programado nuevo, un pago de tarjeta, otro idioma) los vuelve a
/// programar, agrupando los cambios seguidos en una sola sincronización.
class ReminderScheduler {
  ReminderScheduler({required this.ledger, required this.settings, required this.notifier, this.delay = const Duration(seconds: 2), bool Function()? private, this.privacy}) : _private = private ?? (() => settings.hideBalances);

  final Ledger ledger;
  final AppSettings settings;
  final Notifier notifier;
  final Duration delay;

  /// Si los avisos deben ir sin montos (clave de acceso o saldos ocultos).
  final bool Function() _private;

  /// Lo que puede cambiar [_private] fuera de los ajustes (el candado al
  /// poner o quitar la clave): solo se resincroniza si ese valor cambió, no
  /// con cada bloqueo y desbloqueo.
  final Listenable? privacy;
  bool? _lastPrivate;
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
    _lastPrivate = _private();
    privacy?.addListener(_privacyChanged);
  }

  void _privacyChanged() {
    final bool now = _private();
    if (now != _lastPrivate) {
      _lastPrivate = now;
      _changed();
    }
  }

  void stop() {
    if (!_started) {
      return;
    }
    _started = false;
    ledger.removeListener(_changed);
    settings.removeListener(_changed);
    privacy?.removeListener(_privacyChanged);
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
      await Reminders.sync(ledger: ledger, settings: settings, notifier: notifier, spanish: settings.spanish, private: _private());
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
