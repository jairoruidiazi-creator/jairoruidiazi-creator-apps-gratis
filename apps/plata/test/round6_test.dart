// Sexta ronda de la auditoría: «Ya lo pagué» nunca cuenta el pago dos veces
// (G1, caso N1 de minimo_sim6), una sola fecha efectiva para el próximo
// pago, la ventana de abonos, el abono supuesto y los recordatorios (G2, caso
// N2), y la simulación de todas las combinaciones de mínimo anotado o no,
// «Ya lo pagué», fecha del pago y fecha corrida o no.

import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plata/core/crypto_store.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/core/notifications.dart';
import 'package:plata/core/reminders.dart';
import 'package:plata/core/settings.dart';
import 'package:plata/core/storage.dart';
import 'package:plata/model/models.dart';
import 'package:plata/ui/more/cards_screen.dart';

DateTime d(int y, int m, int day, [int h = 12]) => DateTime(y, m, day, h);

/// Pesos en unidades menores (centavos).
int pesos(int v) => v * 100;

void main() {
  late Directory tmp;
  DateTime today = d(2026, 12, 20);

  Future<Ledger> newLedger() async {
    final Directory dir = await tmp.createTemp('l');
    final Ledger l = Ledger(EncryptedStore(JsonStore(root: dir), await CryptoBox.fromKeyStore(MemoryKeyStore())), clock: () => today);
    await l.load();
    await l.addAccount(Account(id: 'bank', name: 'Ahorros', type: AccountType.bank, initialMinor: pesos(20000000)));
    return l;
  }

  Future<Tx> pay(Ledger l, int amount, DateTime date, {String id = 'p'}) => l.addTx(Tx(id: id, kind: TxKind.transfer, amountMinor: amount, accountId: 'bank', toAccountId: 'tc', date: date));

  setUp(() async {
    today = d(2026, 12, 20);
    tmp = await Directory.systemTemp.createTemp('plata_r6');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('G1: «Ya lo pagué» y el pago registrado después', () {
    /// Caso N1: compras de $1.000.000 (20 oct) y $300.000 (20 nov), mínimo de
    /// $100.000 del extracto del 15 nov, marcado como pagado.
    Future<Ledger> n1() async {
      final Ledger l = await newLedger();
      final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
      await l.addTx(Tx(id: 'c1', kind: TxKind.expense, amountMinor: pesos(1000000), accountId: 'tc', date: d(2026, 10, 20)));
      await l.addTx(Tx(id: 'c2', kind: TxKind.expense, amountMinor: pesos(300000), accountId: 'tc', date: d(2026, 11, 20)));
      l.setStatementMinimum(tc, DateTime(2026, 11, 15), pesos(100000));
      l.markStatementPaid(tc, DateTime(2026, 11, 15));
      return l;
    }

    final Map<String, DateTime> n1Dates = <String, DateTime>{
      'con la fecha de hoy (8 dic, después de la fecha límite)': d(2026, 12, 8),
      'con la fecha límite real (lun 7 dic)': d(2026, 12, 7),
      'con la fecha nominal (sáb 5 dic)': d(2026, 12, 5),
      'antes de la fecha límite (1 dic)': d(2026, 12, 1),
    };
    for (final MapEntry<String, DateTime> c in n1Dates.entries) {
      test('caso N1: el pago registrado ${c.key} reemplaza al abono supuesto', () async {
        final Ledger l = await n1();
        final Account tc = l.account('tc')!;
        // Marcado y sin registrar: el abono supuesto es el mínimo.
        expect(l.statement(tc, date: DateTime(2026, 12, 15)).dueMinor, pesos(1200000));
        await pay(l, pesos(100000), c.value);
        // Registrado: es el pago de verdad, no un segundo pago.
        expect(l.statement(tc, date: DateTime(2026, 12, 15)).dueMinor, pesos(1200000));
        expect(l.cardDue(tc, now: DateTime(2026, 12, 9)).overdue, isFalse);
        expect(l.cardDue(tc, now: DateTime(2026, 12, 9)).unconfirmed, isFalse);
        expect(l.nextPayment(tc, now: DateTime(2026, 12, 9)).dueMinor, pesos(1200000));
        l.dispose();
      });
    }

    test('caso N1: un pago mayor que el mínimo cuenta completo, una sola vez', () async {
      final Ledger l = await n1();
        final Account tc = l.account('tc')!;
      await pay(l, pesos(1000000), d(2026, 12, 8));
      expect(l.statement(tc, date: DateTime(2026, 12, 15)).dueMinor, pesos(300000));
      l.dispose();
    });

    test('una devolución de una compra no reemplaza al pago supuesto', () async {
      final Ledger l = await n1();
        final Account tc = l.account('tc')!;
      expect(l.category('c_food'), isNotNull);
      await l.addTx(Tx(id: 'r', kind: TxKind.income, amountMinor: pesos(50000), accountId: 'tc', categoryId: 'c_food', date: d(2026, 12, 2)));
      // El mínimo pagado y la devolución: 1.300.000 − 100.000 − 50.000.
      expect(l.statement(tc, date: DateTime(2026, 12, 15)).dueMinor, pesos(1150000));
      l.dispose();
    });

    test('desmarcar deja de suponer el pago', () async {
      final Ledger l = await n1();
        final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, DateTime(2026, 11, 15), paid: false);
      expect(l.statement(tc, date: DateTime(2026, 12, 15)).dueMinor, pesos(1300000));
      expect(l.cardDue(tc, now: DateTime(2026, 12, 9)).overdueMinor, pesos(100000));
      l.dispose();
    });

    test('el registro propone la fecha límite real del extracto (o hoy, si no ha llegado)', () async {
      final Ledger l = await newLedger();
      final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
      final DateTime cut = DateTime(2026, 11, 15);
      await withClock(Clock.fixed(d(2026, 12, 9)), () async {
        expect(proposedPaymentDate(l, tc, cut), d(2026, 12, 7));
      });
      await withClock(Clock.fixed(d(2026, 12, 2)), () async {
        expect(proposedPaymentDate(l, tc, cut), d(2026, 12, 2));
      });
      l.dispose();
    });
  });

  group('G2: una sola fecha efectiva', () {
    /// Caso N2: extracto del 15 nov por $800.000 que vence el sáb 5 dic,
    /// corrido al lun 7.
    Future<Ledger> n2({int? minimum}) async {
      final Ledger l = await newLedger();
      final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
      await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: pesos(800000), accountId: 'tc', date: d(2026, 10, 20)));
      if (minimum != null) {
        l.setStatementMinimum(tc, DateTime(2026, 11, 15), minimum);
      }
      return l;
    }

    for (final DateTime day in <DateTime>[d(2026, 12, 6), d(2026, 12, 7)]) {
      test('caso N2: el pago del ${day.day} dic es para el extracto que vence el lunes 7', () async {
        final Ledger l = await n2();
        final Account tc = l.account('tc')!;
        expect(l.nextPayment(tc, now: day).dueMinor, pesos(800000));
        await pay(l, pesos(800000), day);
        expect(l.statement(tc, date: DateTime(2026, 11, 15)).paymentsMinor, pesos(800000));
        expect(l.statement(tc, date: DateTime(2026, 11, 15)).dueMinor, 0);
        expect(l.nextPayment(tc, now: day).dueMinor, 0);
        for (final DateTime later in <DateTime>[d(2026, 12, 8), d(2026, 12, 14)]) {
          final CardDue due = l.cardDue(tc, now: later);
          expect(due.overdue, isFalse, reason: '$later');
          expect(due.unconfirmed, isFalse, reason: '$later');
        }
        l.dispose();
      });
    }

    test('caso N2 con mínimo: pagado el domingo o el lunes, no hay mora', () async {
      final Ledger l = await n2(minimum: pesos(80000));
      final Account tc = l.account('tc')!;
      await pay(l, pesos(80000), d(2026, 12, 6));
      expect(l.cardDue(tc, now: DateTime(2026, 12, 8)).overdue, isFalse);
      l.dispose();
    });

    test('el abono supuesto se mide con la misma ventana: un extracto marcado y pagado el lunes corrido no se cuenta dos veces', () async {
      final Ledger l = await n2(minimum: pesos(80000));
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, DateTime(2026, 11, 15));
      await pay(l, pesos(80000), d(2026, 12, 7));
      expect(l.statement(tc, date: DateTime(2026, 11, 15)).paymentsMinor, pesos(80000));
      expect(l.statement(tc, date: DateTime(2026, 12, 15)).dueMinor, pesos(720000));
      l.dispose();
    });

    test('el recordatorio de la tarjeta se cuenta desde la fecha corrida', () async {
      final Ledger l = await n2();
        final Account tc = l.account('tc')!;
      final NoopNotifier n = NoopNotifier();
      await Reminders.sync(ledger: l, settings: AppSettings()..billReminders = true, notifier: n, now: d(2026, 11, 20, 8));
      // Un día antes del lunes 7, no un día antes del sábado 5.
      expect(n.pending.values, contains(startsWith('at:2026-12-06T09:00:00.000:Pago de Visa:Vence el 07 dic')));
      expect(n.pending.values.where((String e) => e.startsWith('at:2026-12-04')), isEmpty);
      expect(tc.payDay, 5);
      l.dispose();
    });
  });

  // Simulación: cada combinación de mínimo anotado o no, «Ya lo pagué» o no,
  // pago (ninguno, el mínimo o el total) registrado antes, en o después de la
  // fecha nominal o efectiva (el mismo día o días después, con su fecha), y
  // fecha corrida (pago el 5: sáb 5 → lun 7) o no (pago el 3: jue 3). Cada día
  // del 20 nov al 14 dic se compara lo que dice Plata con lo esperado.
  test('simulación: ninguna combinación da una cifra o un aviso falso', () async {
    final int purchase1 = pesos(1000000); // 20 oct, extracto del 15 nov
    final int purchase2 = pesos(300000); // 20 nov, extracto del 15 dic
    final int minimum = pesos(100000);
    int combos = 0;
    final List<String> failures = <String>[];
    for (final int payDay in <int>[5, 3]) {
      final DateTime nominal = DateTime(2026, 12, payDay);
      final DateTime effective = payDay == 5 ? DateTime(2026, 12, 7) : nominal;
      final List<DateTime> dates = payDay == 5
          ? <DateTime>[DateTime(2026, 12, 1), nominal, DateTime(2026, 12, 6), effective, DateTime(2026, 12, 9)]
          : <DateTime>[DateTime(2026, 12, 1), nominal, DateTime(2026, 12, 9)];
      final List<_Pay?> payments = <_Pay?>[
        null,
        for (final int amount in <int>[minimum, purchase1])
          for (final DateTime date in dates)
            for (final DateTime registered in <DateTime>[date, DateTime(2026, 12, 10)]) _Pay(amount, date, registered),
      ];
      for (final bool known in <bool>[false, true]) {
        for (final bool marked in <bool>[false, true]) {
          // «Ya lo pagué» siempre va con un mínimo: lo anota el que pregunta,
          // y el aviso rojo solo existe con un mínimo conocido.
          if (marked && !known) {
            continue;
          }
          for (final _Pay? p in payments) {
            combos += 1;
            final String label = 'pago el $payDay, mínimo ${known ? 'anotado' : 'sin anotar'}, ${marked ? 'marcado' : 'sin marcar'}, ${p == null ? 'sin pago' : 'pago ${p.amount ~/ 100} del ${p.date.day} dic registrado el ${p.registered.day}'}';
            final Ledger l = await newLedger();
            final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: payDay));
            await l.addTx(Tx(id: 'c1', kind: TxKind.expense, amountMinor: purchase1, accountId: 'tc', date: d(2026, 10, 20)));
            await l.addTx(Tx(id: 'c2', kind: TxKind.expense, amountMinor: purchase2, accountId: 'tc', date: d(2026, 11, 20)));
            if (known) {
              l.setStatementMinimum(tc, DateTime(2026, 11, 15), minimum);
            }
            if (marked) {
              l.markStatementPaid(tc, DateTime(2026, 11, 15));
            }
            bool added = false;
            for (DateTime day = DateTime(2026, 11, 20); !day.isAfter(DateTime(2026, 12, 14)); day = DateTime(day.year, day.month, day.day + 1)) {
              if (p != null && !added && !day.isBefore(p.registered)) {
                await pay(l, p.amount, d(p.date.year, p.date.month, p.date.day));
                added = true;
              }
              final int logged = added ? p!.amount : 0;
              final int counted = marked && known ? (logged > minimum ? logged : minimum) : logged;
              final bool late = day.isAfter(effective);
              // Próximo pago: el extracto del 15 nov hasta su fecha límite real
              // (si no está marcado y queda algo), después el ciclo en curso.
              final int expectedNext = !late && !marked && purchase1 - logged > 0 ? purchase1 - logged : purchase1 + purchase2 - counted;
              final int expectedOverdue = late && known && !marked && logged < minimum ? minimum - logged : 0;
              final int expectedUnconfirmed = late && !known && !marked && purchase1 - logged > 0 ? purchase1 - logged : 0;
              final CardDue due = l.cardDue(tc, now: day);
              final String at = '$label, día ${day.day}/${day.month}';
              if (due.next.dueMinor != expectedNext) {
                failures.add('$at: próximo pago ${due.next.dueMinor ~/ 100}, esperado ${expectedNext ~/ 100}');
              }
              if (due.overdueMinor != expectedOverdue) {
                failures.add('$at: vencido ${due.overdueMinor ~/ 100}, esperado ${expectedOverdue ~/ 100}');
              }
              if (due.overdueMinor > 0 && due.overdueSince != effective) {
                failures.add('$at: vencido desde ${due.overdueSince}, esperado $effective');
              }
              if (due.unconfirmedMinor != expectedUnconfirmed) {
                failures.add('$at: sin confirmar ${due.unconfirmedMinor ~/ 100}, esperado ${expectedUnconfirmed ~/ 100}');
              }
            }
            // El extracto de diciembre nunca cuenta el pago dos veces.
            final int december = l.statement(tc, date: DateTime(2026, 12, 15)).dueMinor;
            final int counted = marked && known ? ((p?.amount ?? 0) > minimum ? p!.amount : minimum) : (p?.amount ?? 0);
            if (december != purchase1 + purchase2 - counted) {
              failures.add('$label: extracto del 15 dic ${december ~/ 100}, esperado ${(purchase1 + purchase2 - counted) ~/ 100}');
            }
            // La notificación de mora sale solo si la mora es real.
            final NoopNotifier n = NoopNotifier();
            await Reminders.sync(ledger: l, settings: AppSettings()..billReminders = true, notifier: n, now: d(2026, 12, 11, 8));
            final bool lateReal = known && !marked && (p?.amount ?? 0) < minimum;
            if (n.shown.isNotEmpty != lateReal) {
              failures.add('$label: notificación de mora ${n.shown}, esperada ${lateReal ? 'sí' : 'no'}');
            }
            l.dispose();
          }
        }
      }
    }
    expect(failures, isEmpty, reason: failures.take(20).join('\n'));
    expect(combos, 102);
  });
}

/// Un pago de la simulación: monto, fecha del pago y día en que se registra.
class _Pay {
  const _Pay(this.amount, this.date, this.registered);

  final int amount;
  final DateTime date;
  final DateTime registered;
}
