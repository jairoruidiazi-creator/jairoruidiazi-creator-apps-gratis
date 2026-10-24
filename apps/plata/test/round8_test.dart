// Octava ronda de la auditoría: el cambio del día de corte nunca deja datos
// en un extracto sin cerrar (G1), «Ya lo pagué» guarda su día y lo anotado
// antes de marcar es parte del pago (G2), el pago vinculado parcial (M1) y
// propiedades con secuencias al azar que incluyen cambios de corte (M2).
//
// Los valores esperados están escritos a mano en cada caso.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:plata/core/crypto_store.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/core/notifications.dart';
import 'package:plata/core/periods.dart';
import 'package:plata/core/reminders.dart';
import 'package:plata/core/settings.dart';
import 'package:plata/core/storage.dart';
import 'package:plata/model/models.dart';

DateTime d(int y, int m, int day, [int h = 12]) => DateTime(y, m, day, h);

/// Pesos en unidades menores (centavos).
int pesos(int v) => v * 100;

final DateTime nov15 = DateTime(2026, 11, 15);
final DateTime dec15 = DateTime(2026, 12, 15);

void main() {
  late Directory tmp;
  DateTime today = d(2026, 12, 20);
  int ids = 0;

  setUp(() async {
    today = d(2026, 12, 20);
    tmp = await Directory.systemTemp.createTemp('plata_r8');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<Ledger> newLedger() async {
    final Directory dir = await tmp.createTemp('l');
    final Ledger l = Ledger(EncryptedStore(JsonStore(root: dir), await CryptoBox.fromKeyStore(MemoryKeyStore())), clock: () => today);
    await l.load();
    await l.addAccount(Account(id: 'bank', name: 'Ahorros', type: AccountType.bank, initialMinor: pesos(50000000)));
    return l;
  }

  Future<Tx> pay(Ledger l, int amount, DateTime date, {DateTime? statement}) {
    ids += 1;
    return l.addTx(Tx(id: 'p$ids', kind: TxKind.transfer, amountMinor: amount, accountId: 'bank', toAccountId: 'tc', date: date, statementOf: statement == null ? null : dayKey(statement)));
  }

  /// Compras de 1.000.000 (20 oct) y 300.000 (20 nov), corte el 15 y pago el
  /// 5 (el sáb 5 dic se corre al lun 7), mínimo de 100.000 del 15 nov.
  Future<Ledger> n1() async {
    final Ledger l = await newLedger();
    final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
    await l.addTx(Tx(id: 'c1', kind: TxKind.expense, amountMinor: pesos(1000000), accountId: 'tc', date: d(2026, 10, 20)));
    await l.addTx(Tx(id: 'c2', kind: TxKind.expense, amountMinor: pesos(300000), accountId: 'tc', date: d(2026, 11, 20)));
    l.setStatementMinimum(tc, nov15, pesos(100000));
    return l;
  }

  int december(Ledger l) => l.statement(l.account('tc')!, date: dec15).dueMinor;

  group('G2: «Ya lo pagué» después de un abono anotado tarde', () {
    test('caso A2b: el aviso dice «faltan 60.000»; al marcar, el extracto del 15 dic es 1.200.000', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      await pay(l, pesos(40000), d(2026, 12, 9));
      expect(l.cardDue(tc, now: DateTime(2026, 12, 10)).overdueMinor, pesos(60000));
      l.markStatementPaid(tc, nov15, on: DateTime(2026, 12, 10));
      // Pagó fuera los 60.000 que faltaban: en total 100.000.
      expect(l.assumedPayment(tc, nov15), pesos(60000));
      expect(december(l), pesos(1200000));
      // Un abono anotado después de marcar es aparte: baja exactamente su valor.
      await pay(l, pesos(200000), d(2026, 12, 12));
      expect(december(l), pesos(1000000));
      l.dispose();
    });

    for (final DateTime mark in <DateTime>[DateTime(2026, 12, 9), DateTime(2026, 12, 11), DateTime(2026, 12, 30)]) {
      test('abono el 9 dic y marca el ${mark.day} dic: el abono es parte del mínimo', () async {
        today = d(2026, 12, 31);
        final Ledger l = await n1();
        await pay(l, pesos(40000), d(2026, 12, 9));
        l.markStatementPaid(l.account('tc')!, nov15, on: mark);
        expect(december(l), pesos(1200000));
        l.dispose();
      });
    }

    test('abono antes de la fecha límite y marca antes de él: el abono es aparte', () async {
      final Ledger l = await n1();
      l.markStatementPaid(l.account('tc')!, nov15, on: DateTime(2026, 11, 25));
      await pay(l, pesos(40000), d(2026, 11, 30));
      // 1.300.000 − 100.000 (fuera) − 40.000.
      expect(december(l), pesos(1160000));
      l.dispose();
    });

    test('abono antes de la fecha límite y marca después: el abono es parte del mínimo', () async {
      final Ledger l = await n1();
      await pay(l, pesos(40000), d(2026, 11, 30));
      l.markStatementPaid(l.account('tc')!, nov15, on: DateTime(2026, 12, 4));
      expect(december(l), pesos(1200000));
      l.dispose();
    });

    test('tope: lo anotado después de la fecha límite del extracto siguiente no completa el mínimo', () async {
      today = d(2027, 1, 20);
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      await pay(l, pesos(40000), d(2027, 1, 8));
      l.markStatementPaid(tc, nov15, on: DateTime(2027, 1, 10));
      expect(l.assumedPayment(tc, nov15), pesos(100000));
      expect(december(l), pesos(1200000));
      // Es del extracto del 15 ene (vence el 5 feb).
      expect(l.statement(tc, date: DateTime(2027, 1, 15)).dueMinor, pesos(1160000));
      l.dispose();
    });

    test('una sola regla: lo que completó el mínimo marcado no cuenta otra vez para la mora del siguiente', () async {
      today = d(2027, 1, 7);
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.setStatementMinimum(tc, dec15, pesos(50000));
      await pay(l, pesos(60000), d(2026, 12, 20));
      l.markStatementPaid(tc, nov15, on: DateTime(2026, 12, 21));
      // Los 60.000 completaron el mínimo del 15 nov: el del 15 dic sigue sin pagar.
      expect(l.cardDue(tc, now: DateTime(2027, 1, 7)).overdueMinor, pesos(50000));
      l.dispose();
    });

    test('la marca guarda su día; una marca sin día vale hasta la fecha límite real', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, nov15, on: DateTime(2026, 12, 10));
      final Account back = Account.fromJson(tc.toJson());
      expect(back.paidOn['2026-11-15'], '2026-12-10');
      expect(l.statementMarkedOn(back, nov15), DateTime(2026, 12, 10));
      tc.paidOn.clear();
      expect(l.statementMarkedOn(tc, nov15), DateTime(2026, 12, 7));
      // Desmarcar borra el día.
      l.markStatementPaid(tc, nov15, on: DateTime(2026, 12, 10));
      l.markStatementPaid(tc, nov15, paid: false);
      expect(tc.paidOn, isEmpty);
      l.dispose();
    });
  });

  group('M1: pago vinculado parcial', () {
    test('marcado y 40.000 vinculados: siguen 60.000 por fuera; desmarcado, faltan 60.000', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, nov15, on: DateTime(2026, 12, 4));
      await pay(l, pesos(40000), d(2026, 12, 7), statement: nov15);
      expect(l.linkedPayments(tc, nov15), pesos(40000));
      expect(l.assumedPayment(tc, nov15), pesos(60000));
      expect(december(l), pesos(1200000));
      l.markStatementPaid(tc, nov15, paid: false);
      expect(l.assumedPayment(tc, nov15), 0);
      expect(l.cardDue(tc, now: DateTime(2026, 12, 8)).overdueMinor, pesos(60000));
      l.dispose();
    });

    test('vinculado completo: nada por fuera', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, nov15, on: DateTime(2026, 12, 4));
      await pay(l, pesos(100000), d(2026, 12, 22), statement: nov15);
      expect(l.assumedPayment(tc, nov15), 0);
      expect(december(l), pesos(1200000));
      l.dispose();
    });
  });

  group('G1: cambiar el día de corte nunca deja datos en un extracto sin cerrar', () {
    /// Caso F1 del Árbitro: corte 10 y pago 30; el 12 nov se anota el mínimo
    /// de 90.000 del extracto del 10 nov, «Sí, ya lo pagué», y se corrige el
    /// corte a 15.
    Future<Ledger> f1() async {
      today = d(2026, 11, 12);
      final Ledger l = await newLedger();
      final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 10, payDay: 30));
      await l.addTx(Tx(id: 'a', kind: TxKind.expense, amountMinor: pesos(800000), accountId: 'tc', date: d(2026, 10, 20)));
      await l.addTx(Tx(id: 'b', kind: TxKind.expense, amountMinor: pesos(400000), accountId: 'tc', date: d(2026, 11, 13)));
      await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: pesos(250000), accountId: 'tc', date: d(2026, 11, 20)));
      l.setStatementMinimum(tc, DateTime(2026, 11, 10), pesos(90000));
      l.markStatementPaid(tc, DateTime(2026, 11, 10));
      tc.cutDay = 15;
      l.moveCardCut(tc, 10);
      return l;
    }

    test('caso F1: la marca y el mínimo pasan al 15 oct, ya cerrado', () async {
      final Ledger l = await f1();
      final Account tc = l.account('tc')!;
      expect(tc.paidStatements, <String>['2026-10-15']);
      expect(tc.statementMinimums, <String, int>{'2026-10-15': pesos(90000)});
      expect(tc.paidOn.keys, <String>['2026-10-15']);
      l.dispose();
    });

    test('caso F1: el extracto del 15 nov sigue siendo el próximo pago, con su recordatorio', () async {
      final Ledger l = await f1();
      final Account tc = l.account('tc')!;
      for (final DateTime day in <DateTime>[DateTime(2026, 11, 16), DateTime(2026, 11, 30)]) {
        final CardStatement next = l.nextPayment(tc, now: day);
        // 800.000 + 400.000, que vence el lun 30 nov.
        expect(next.cycle.cut, nov15, reason: '$day');
        expect(next.dueMinor, pesos(1200000), reason: '$day');
      }
      // Sin pagar, el 1 dic no está «al día».
      expect(l.cardDue(tc, now: DateTime(2026, 12, 1)).unconfirmedMinor, pesos(1200000));
      today = d(2026, 11, 16);
      final NoopNotifier n = NoopNotifier();
      await Reminders.sync(ledger: l, settings: AppSettings()..billReminders = true, notifier: n, now: d(2026, 11, 16, 8));
      expect(n.pending.values, contains(startsWith('at:2026-11-29T09:00:00.000:Pago de Visa:Vence el 30 nov')));
      l.dispose();
    });

    test('el extracto de referencia de la deuda inicial tampoco queda sin cerrar (F7)', () async {
      today = d(2026, 11, 12);
      final Ledger l = await newLedger();
      final Account draft = Account(id: 'tc', name: 'Visa', type: AccountType.credit, initialMinor: -pesos(1500000), cutDay: 10, payDay: 5)..statementDueMinor = pesos(120000);
      draft.statementCut = l.referenceStatementCut(draft);
      final Account tc = await l.addAccount(draft);
      expect(tc.statementCut, DateTime(2026, 11, 10));
      expect(l.movedCut(15, DateTime(2026, 11, 10)), DateTime(2026, 10, 15));
      tc.cutDay = 15;
      l.moveCardCut(tc, 10);
      expect(tc.statementCut, DateTime(2026, 10, 15));
      l.dispose();
    });

    test('dos extractos en el mismo: se avisa el choque y se deja el elegido', () async {
      for (final bool newer in <bool>[true, false]) {
        today = d(2026, 11, 12);
        final Ledger l = await newLedger();
        final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 10, payDay: 30));
        l.setStatementMinimum(tc, DateTime(2026, 10, 10), pesos(70000));
        l.setStatementMinimum(tc, DateTime(2026, 11, 10), pesos(90000));
        l.markStatementPaid(tc, DateTime(2026, 10, 10));
        final Tx linked = await pay(l, pesos(70000), d(2026, 10, 25), statement: DateTime(2026, 10, 10));
        final Map<DateTime, List<DateTime>> clashes = l.cutMoveConflicts(tc, 15);
        expect(clashes.keys, <DateTime>[DateTime(2026, 10, 15)]);
        expect(clashes.values.single, <DateTime>[DateTime(2026, 10, 10), DateTime(2026, 11, 10)]);
        tc.cutDay = 15;
        l.moveCardCut(tc, 10, keepNewer: newer);
        expect(tc.statementMinimums, <String, int>{'2026-10-15': newer ? pesos(90000) : pesos(70000)});
        // La marca era del 10 oct: queda solo si se deja ese.
        expect(tc.paidStatements, newer ? isEmpty : <String>['2026-10-15']);
        // Su pago vinculado queda como abono normal si se descarta.
        expect(linked.statementOf, newer ? isNull : '2026-10-15');
        l.dispose();
      }
    });
  });

  // Secuencias al azar (compras, abonos, mínimos con «¿Ya lo pagaste?»,
  // pagos vinculados, desmarcar, «Ya lo pagué» del aviso, borrar y cambiar
  // el corte y el pago). Después de cada operación:
  // - P6: ninguna marca ni mínimo en un extracto que no ha cerrado;
  // - P3: un extracto marcado nunca sale vencido;
  // - P1: la deuda de la tarjeta es lo que queda del estado más lo que se da
  //   por pagado fuera de Plata (el dinero no aparece ni desaparece).
  test('propiedades con secuencias al azar y cambios de corte', () async {
    final List<String> failures = <String>[];
    for (int seed = 0; seed < 60 && failures.length < 10; seed++) {
      final Random rnd = Random(seed);
      today = d(2026, 9, 1);
      final Ledger l = await newLedger();
      const List<int> days = <int>[1, 5, 10, 14, 15, 16, 20, 25, 28, 30, 31];
      final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: days[rnd.nextInt(days.length)], payDay: days[rnd.nextInt(days.length)]));
      await l.addTx(Tx(id: 'first', kind: TxKind.expense, amountMinor: pesos(100000), accountId: 'tc', date: d(2026, 9, 1)));
      for (int i = 0; i < 30; i++) {
        today = d(today.year, today.month, today.day + 1 + rnd.nextInt(8));
        final CardCycle lastClosed = CardCycle.current(tc, today).previous(tc);
        final double op = rnd.nextDouble();
        String what;
        if (op < 0.25) {
          what = 'compra';
          await l.addTx(Tx(id: 'x$i', kind: TxKind.expense, amountMinor: pesos(10000 * (1 + rnd.nextInt(80))), accountId: 'tc', date: today));
        } else if (op < 0.42) {
          what = 'abono';
          await pay(l, pesos(10000 * (1 + rnd.nextInt(60))), today);
        } else if (op < 0.55) {
          what = 'mínimo';
          final int minimum = pesos(10000 * (2 + rnd.nextInt(15)));
          l.setStatementMinimum(tc, lastClosed.cut, minimum);
          final int answer = rnd.nextInt(3);
          if (answer == 0) {
            l.markStatementPaid(tc, lastClosed.cut, paid: false);
          } else {
            l.markStatementPaid(tc, lastClosed.cut);
            if (answer == 2) {
              await pay(l, minimum, today, statement: lastClosed.cut);
            }
          }
        } else if (op < 0.62) {
          what = 'registrar parcial';
          if (l.isStatementPaid(tc, lastClosed.cut)) {
            await pay(l, pesos(10000), today, statement: lastClosed.cut);
          }
        } else if (op < 0.68) {
          what = 'desmarcar';
          l.markStatementPaid(tc, lastClosed.cut, paid: false);
        } else if (op < 0.74) {
          what = 'ya lo pagué del aviso';
          final CardDue due = l.cardDue(tc);
          if (due.overdue) {
            l.markStatementPaid(tc, due.statementCut!);
          }
        } else if (op < 0.80) {
          what = 'borrar';
          final List<Tx> credits = l.txs.where((Tx t) => t.toAccountId == 'tc').toList();
          if (credits.isNotEmpty) {
            await l.deleteTx(credits[rnd.nextInt(credits.length)].id);
          }
        } else {
          final int old = tc.cutDay!;
          final List<int> others = days.where((int x) => x != old).toList();
          final int next = others[rnd.nextInt(others.length)];
          what = 'corte $old → $next';
          tc.cutDay = next;
          if (rnd.nextBool()) {
            tc.payDay = days[rnd.nextInt(days.length)];
          }
          l.moveCardCut(tc, old, keepNewer: rnd.nextBool());
        }
        final String at = 'semilla $seed, op $i ($what, hoy ${dayKey(today)})';
        for (final String key in <String>[...tc.statementMinimums.keys, ...tc.paidStatements]) {
          if (!DateTime.parse(key).isBefore(dateOnly(today))) {
            failures.add('$at: P6 dato en un extracto sin cerrar $key');
          }
        }
        final CardDue due = l.cardDue(tc);
        if (due.overdue && l.isStatementPaid(tc, due.statementCut!)) {
          failures.add('$at: P3 marcado y vencido');
        }
        // P1: firstCut es el ciclo del movimiento más antiguo de la tarjeta.
        final DateTime first = CardCycle.current(tc, l.txs.where((Tx t) => t.accountId == 'tc' || t.toAccountId == 'tc').map((Tx t) => t.date).reduce((DateTime a, DateTime b) => a.isBefore(b) ? a : b)).cut;
        int assumed = 0;
        for (final String key in tc.paidStatements) {
          final DateTime cut = DateTime.parse(key);
          if (!cut.isBefore(first)) {
            assumed += l.assumedPayment(tc, cut);
          }
        }
        final CardStatement far = l.statement(tc, date: DateTime(2030, 1, 1));
        final int debt = -l.balanceMinor('tc', before: DateTime(2030, 1, 2));
        if (debt != far.balanceMinor + far.legacyMinor + assumed) {
          failures.add('$at: P1 deuda ${debt ~/ 100} ≠ estado ${far.balanceMinor ~/ 100} + aparte ${far.legacyMinor ~/ 100} + fuera ${assumed ~/ 100}');
        }
      }
      l.dispose();
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
