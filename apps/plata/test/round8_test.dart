// Octava y novena ronda de la auditoría, con el modelo de la ronda 10: «Ya
// lo pagué» guarda un pago hecho fuera de Plata por lo que el aviso decía
// que faltaba (G2 de la ronda 8), el pago vinculado parcial (M1), el cambio
// del día de corte lleva cada dato al extracto que había cerrado el día en
// que se anotó (G1 de las rondas 8 y 9, con la corrección hecha el 12, 14,
// 16, 20 y 28 nov) y propiedades con secuencias al azar, P8 incluida.
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

  group('G2 (ronda 8): «Ya lo pagué» después de un abono anotado tarde', () {
    test('caso A2b: el aviso dice «faltan 60.000»; al marcar se guardan 60.000 fuera y el extracto del 15 dic es 1.200.000', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      await pay(l, pesos(40000), d(2026, 12, 9));
      expect(l.cardDue(tc, now: DateTime(2026, 12, 10)).overdueMinor, pesos(60000));
      l.markStatementPaid(tc, nov15, on: DateTime(2026, 12, 10));
      expect(l.outsidePayment(tc, nov15), pesos(60000));
      expect(december(l), pesos(1200000));
      // Un abono anotado después de marcar es aparte: baja exactamente su valor.
      await pay(l, pesos(200000), d(2026, 12, 12));
      expect(december(l), pesos(1000000));
      l.dispose();
    });

    for (final DateTime mark in <DateTime>[DateTime(2026, 12, 9), DateTime(2026, 12, 11), DateTime(2026, 12, 30)]) {
      test('abono el 9 dic y marca el ${mark.day} dic: faltaban 60.000', () async {
        today = d(2026, 12, 31);
        final Ledger l = await n1();
        await pay(l, pesos(40000), d(2026, 12, 9));
        l.markStatementPaid(l.account('tc')!, nov15, on: mark);
        expect(l.outsidePayment(l.account('tc')!, nov15), pesos(60000));
        expect(december(l), pesos(1200000));
        l.dispose();
      });
    }

    test('marca antes del abono: el abono es aparte', () async {
      final Ledger l = await n1();
      l.markStatementPaid(l.account('tc')!, nov15, on: DateTime(2026, 11, 25));
      await pay(l, pesos(40000), d(2026, 11, 30));
      // 1.300.000 − 100.000 (fuera) − 40.000.
      expect(december(l), pesos(1160000));
      l.dispose();
    });

    test('una sola regla: lo que completó el mínimo del 15 nov no cuenta otra vez para la mora del 15 dic', () async {
      today = d(2027, 1, 7);
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.setStatementMinimum(tc, dec15, pesos(50000));
      await pay(l, pesos(60000), d(2026, 12, 20));
      l.markStatementPaid(tc, nov15, on: DateTime(2026, 12, 21));
      expect(l.outsidePayment(tc, nov15), pesos(40000));
      expect(l.cardDue(tc, now: DateTime(2027, 1, 7)).overdueMinor, pesos(50000));
      l.dispose();
    });

    test('el pago hecho fuera es un movimiento con su día y su monto, y desmarcar lo borra', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, nov15, on: DateTime(2026, 12, 10));
      final Tx out = Tx.fromJson(l.outsidePayments(tc, nov15).single.toJson());
      expect(out.isOutsidePayment, isTrue);
      expect(out.statementOf, '2026-11-15');
      expect(out.amountMinor, pesos(100000));
      expect(dateOnly(out.date), DateTime(2026, 12, 10));
      expect(out.accountId, 'tc');
      expect(out.description, 'Pago hecho fuera de Plata');
      // Baja la deuda de la tarjeta, sin salir de ninguna cuenta.
      expect(l.balanceMinor('tc'), -pesos(1300000) + pesos(100000));
      expect(l.balanceMinor('bank'), pesos(50000000));
      l.markStatementPaid(tc, nov15, paid: false);
      expect(l.outsidePayments(tc, nov15), isEmpty);
      expect(l.balanceMinor('tc'), -pesos(1300000));
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
      expect(l.outsidePayment(tc, nov15), pesos(60000));
      expect(december(l), pesos(1200000));
      l.markStatementPaid(tc, nov15, paid: false);
      expect(l.outsidePayment(tc, nov15), 0);
      expect(l.cardDue(tc, now: DateTime(2026, 12, 8)).overdueMinor, pesos(60000));
      expect(l.statementMissing(tc, nov15, now: DateTime(2026, 12, 8)), pesos(60000));
      l.dispose();
    });

    test('vinculado completo: nada por fuera', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, nov15, on: DateTime(2026, 12, 4));
      await pay(l, pesos(100000), d(2026, 12, 22), statement: nov15);
      expect(l.outsidePayment(tc, nov15), 0);
      expect(december(l), pesos(1200000));
      l.dispose();
    });
  });

  group('G1 (rondas 8 y 9): el cambio de corte va por el día en que se anotó cada dato', () {
    /// Caso F1: corte 10 y pago 30; el 12 nov se anota el mínimo de 90.000
    /// del extracto del 10 nov y «Sí, ya lo pagué» (90.000 fuera). Después,
    /// el día [moveDay], se corrige el corte a 15.
    Future<Ledger> f1(DateTime moveDay) async {
      today = d(2026, 11, 12);
      final Ledger l = await newLedger();
      final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 10, payDay: 30));
      await l.addTx(Tx(id: 'a', kind: TxKind.expense, amountMinor: pesos(800000), accountId: 'tc', date: d(2026, 10, 20)));
      await l.addTx(Tx(id: 'b', kind: TxKind.expense, amountMinor: pesos(400000), accountId: 'tc', date: d(2026, 11, 13)));
      await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: pesos(250000), accountId: 'tc', date: d(2026, 11, 20)));
      l.setStatementMinimum(tc, DateTime(2026, 11, 10), pesos(90000));
      l.markStatementPaid(tc, DateTime(2026, 11, 10));
      today = d(moveDay.year, moveDay.month, moveDay.day);
      tc.cutDay = 15;
      l.moveCardCut(tc, 10, oldPayDay: 30);
      return l;
    }

    for (final DateTime moveDay in <DateTime>[DateTime(2026, 11, 12), DateTime(2026, 11, 14), DateTime(2026, 11, 16), DateTime(2026, 11, 20), DateTime(2026, 11, 28)]) {
      test('caso F1 corregido el ${moveDay.day} nov: la marca y el mínimo van al 15 oct, y el extracto del 15 nov es el próximo pago', () async {
        final Ledger l = await f1(moveDay);
        final Account tc = l.account('tc')!;
        final Tx out = l.outsidePayments(tc, DateTime(2026, 10, 15)).single;
        expect(out.statementOf, '2026-10-15');
        expect(dateOnly(out.date), DateTime(2026, 11, 12));
        expect(tc.statementMinimums, <String, int>{'2026-10-15': pesos(90000)});
        for (final DateTime day in <DateTime>[DateTime(2026, 11, 16), DateTime(2026, 11, 30)]) {
          if (day.isBefore(moveDay)) {
            continue;
          }
          final CardStatement next = l.nextPayment(tc, now: day);
          // 800.000 + 400.000 − los 90.000 pagados fuera; vence el lun 30 nov.
          expect(next.cycle.cut, nov15, reason: '$day');
          expect(next.dueMinor, pesos(1110000), reason: '$day');
        }
        // Sin pagar, el 1 dic no está «al día».
        expect(l.cardDue(tc, now: DateTime(2026, 12, 1)).unconfirmedMinor, pesos(1110000));
        if (!moveDay.isAfter(DateTime(2026, 11, 16))) {
          today = d(2026, 11, 16);
          final NoopNotifier n = NoopNotifier();
          await Reminders.sync(ledger: l, settings: AppSettings()..billReminders = true, notifier: n, now: d(2026, 11, 16, 8));
          expect(n.pending.values, contains(startsWith('at:2026-11-29T09:00:00.000:Pago de Visa:Vence el 30 nov')));
        }
        l.dispose();
      });
    }

    test('el extracto de referencia de la deuda inicial va por el día en que se anotó (F7)', () async {
      today = d(2026, 11, 12);
      final Ledger l = await newLedger();
      final Account draft = Account(id: 'tc', name: 'Visa', type: AccountType.credit, initialMinor: -pesos(1500000), cutDay: 10, payDay: 5)..statementDueMinor = pesos(120000);
      draft.statementCut = l.referenceStatementCut(draft);
      draft.statementNotedOn = '2026-11-12';
      final Account tc = await l.addAccount(draft);
      expect(tc.statementCut, DateTime(2026, 11, 10));
      expect(l.movedCut(15, DateTime(2026, 11, 10), DateTime(2026, 11, 12)), DateTime(2026, 10, 15));
      today = d(2026, 11, 25);
      expect(l.movedReference(tc, 15), DateTime(2026, 10, 15));
      tc.cutDay = 15;
      l.moveCardCut(tc, 10, oldPayDay: 5);
      expect(tc.statementCut, DateTime(2026, 10, 15));
      l.dispose();
    });

    test('dos mínimos en el mismo extracto: se avisa el choque y queda el elegido; los pagos se suman y los vínculos se conservan', () async {
      for (final bool newer in <bool>[true, false]) {
        today = d(2026, 10, 20);
        final Ledger l = await newLedger();
        final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 10, payDay: 30));
        await l.addTx(Tx(id: 'a', kind: TxKind.expense, amountMinor: pesos(900000), accountId: 'tc', date: d(2026, 9, 1)));
        // El del 10 oct se anotó el 20 oct; el del 10 nov, el 12 nov.
        l.setStatementMinimum(tc, DateTime(2026, 10, 10), pesos(70000));
        l.markStatementPaid(tc, DateTime(2026, 10, 10));
        today = d(2026, 11, 12);
        l.setStatementMinimum(tc, DateTime(2026, 11, 10), pesos(90000));
        final Tx linked = await pay(l, pesos(30000), d(2026, 11, 11), statement: DateTime(2026, 11, 10));
        l.markStatementPaid(tc, DateTime(2026, 11, 10));
        final Map<DateTime, List<DateTime>> clashes = l.cutMoveConflicts(tc, 15);
        expect(clashes.keys, <DateTime>[DateTime(2026, 10, 15)]);
        expect(clashes.values.single, <DateTime>[DateTime(2026, 10, 10), DateTime(2026, 11, 10)]);
        tc.cutDay = 15;
        l.moveCardCut(tc, 10, oldPayDay: 30, keep: <DateTime, DateTime>{DateTime(2026, 10, 15): newer ? DateTime(2026, 11, 10) : DateTime(2026, 10, 10)});
        expect(tc.statementMinimums, <String, int>{'2026-10-15': newer ? pesos(90000) : pesos(70000)});
        // Lo pagado fuera (70.000 y 60.000) se suma en el 15 oct.
        expect(l.outsidePayment(tc, DateTime(2026, 10, 15)), pesos(130000));
        // El pago vinculado no se suelta.
        expect(linked.statementOf, '2026-10-15');
        l.dispose();
      }
    });
  });

  // Secuencias al azar (compras, abonos, devoluciones, mínimos con «¿Ya lo
  // pagaste?», pagos vinculados, desmarcar, «Ya lo pagué» del aviso, borrar,
  // editar fechas y cambiar el corte y el pago). Se lleva aparte lo que la
  // persona de verdad pagó fuera de Plata. Después de cada operación:
  // - P1: la deuda de la tarjeta (con lo pagado fuera) es lo que queda del
  //   estado más la deuda aparte;
  // - P3: un extracto marcado nunca sale vencido;
  // - P6: ningún dato en un extracto sin cerrar, ni hoy ni el día en que se
  //   anotó;
  // - T: lo guardado como pagado fuera nunca pasa de lo pagado de verdad;
  // - P8: el próximo pago nunca es menor que lo que de verdad queda del
  //   extracto que vence (lo facturado hasta su corte menos todo lo pagado).
  test('propiedades P1, P3, P6, T y P8 con secuencias al azar', () async {
    final List<String> failures = <String>[];
    for (int seed = 0; seed < 60 && failures.length < 10; seed++) {
      final Random rnd = Random(seed);
      today = d(2026, 9, 1);
      final Ledger l = await newLedger();
      const List<int> days = <int>[1, 5, 10, 14, 15, 16, 20, 25, 28, 30, 31];
      final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: days[rnd.nextInt(days.length)], payDay: days[rnd.nextInt(days.length)]));
      await l.addTx(Tx(id: 'first', kind: TxKind.expense, amountMinor: pesos(100000), accountId: 'tc', date: d(2026, 9, 1)));
      // Lo pagado de verdad fuera de Plata, por extracto.
      Map<String, int> truth = <String, int>{};
      for (int i = 0; i < 30; i++) {
        today = d(today.year, today.month, today.day + 1 + rnd.nextInt(8));
        final CardCycle lastClosed = CardCycle.current(tc, today).previous(tc);
        final String k = dayKey(lastClosed.cut);
        final double op = rnd.nextDouble();
        String what;
        if (op < 0.22) {
          what = 'compra';
          await l.addTx(Tx(id: 'x$i', kind: TxKind.expense, amountMinor: pesos(10000 * (1 + rnd.nextInt(80))), accountId: 'tc', date: today));
        } else if (op < 0.36) {
          what = 'abono';
          await pay(l, pesos(10000 * (1 + rnd.nextInt(30))), today);
        } else if (op < 0.40) {
          what = 'devolución';
          await l.addTx(Tx(id: 'r$i', kind: TxKind.income, amountMinor: pesos(5000 * (1 + rnd.nextInt(10))), accountId: 'tc', categoryId: 'c_food', date: today));
        } else if (op < 0.52) {
          what = 'mínimo';
          l.setStatementMinimum(tc, lastClosed.cut, pesos(10000 * (2 + rnd.nextInt(15))));
          final int answer = rnd.nextInt(3);
          if (answer == 0) {
            l.markStatementPaid(tc, lastClosed.cut, paid: false);
            truth.remove(k);
          } else {
            if (l.markStatementPaid(tc, lastClosed.cut)) {
              truth[k] = l.outsidePayment(tc, lastClosed.cut);
            }
            if (answer == 2) {
              final int out = l.outsidePayment(tc, lastClosed.cut);
              if (out > 0) {
                await pay(l, out, today, statement: lastClosed.cut);
                truth[k] = (truth[k] ?? 0) - out < 0 ? 0 : (truth[k] ?? 0) - out;
              }
            }
          }
        } else if (op < 0.58) {
          what = 'desmarcar';
          l.markStatementPaid(tc, lastClosed.cut, paid: false);
          truth.remove(k);
        } else if (op < 0.66) {
          what = 'ya lo pagué del aviso';
          final CardDue due = l.cardDue(tc);
          if (due.overdue) {
            final int said = due.overdueMinor;
            l.markStatementPaid(tc, due.statementCut!, amount: said);
            truth[dayKey(due.statementCut!)] = said;
            if (l.outsidePayment(tc, due.statementCut!) != said) {
              failures.add('semilla $seed, op $i: T0 el aviso decía $said y se guardó ${l.outsidePayment(tc, due.statementCut!)}');
            }
          }
        } else if (op < 0.72) {
          what = 'borrar';
          final List<Tx> credits = l.txs.where((Tx t) => t.toAccountId == 'tc').toList();
          if (credits.isNotEmpty) {
            await l.deleteTx(credits[rnd.nextInt(credits.length)].id);
          }
        } else if (op < 0.80) {
          what = 'editar fecha';
          final List<Tx> credits = l.txs.where((Tx t) => t.toAccountId == 'tc').toList();
          if (credits.isNotEmpty) {
            final Tx t = credits[rnd.nextInt(credits.length)];
            final DateTime moved = d(t.date.year, t.date.month, t.date.day + rnd.nextInt(11) - 5);
            t.date = moved.isAfter(today) ? today : moved;
            l.updateTx(t);
          }
        } else {
          final int old = tc.cutDay!;
          final int oldPay = tc.payDay!;
          final List<int> others = days.where((int x) => x != old).toList();
          final int next = others[rnd.nextInt(others.length)];
          what = 'corte $old → $next';
          // Lo pagado de verdad va con su extracto (todos sus datos juntos).
          final Map<String, String> moves = l.cutMoves(tc, next, oldPayDay: oldPay);
          final Map<String, int> moved = <String, int>{};
          truth.forEach((String k, int v) {
            final String to = moves[k] ?? k;
            moved[to] = (moved[to] ?? 0) + v;
          });
          truth = moved;
          tc.cutDay = next;
          if (rnd.nextBool()) {
            tc.payDay = days[rnd.nextInt(days.length)];
          }
          l.moveCardCut(tc, old, oldPayDay: oldPay);
        }
        final String at = 'semilla $seed, op $i ($what, hoy ${dayKey(today)})';
        final DateTime now = dateOnly(today);
        for (final String key in tc.statementMinimums.keys) {
          final DateTime? on = DateTime.tryParse(tc.minimumsOn[key] ?? '');
          if (!DateTime.parse(key).isBefore(now) || (on != null && !DateTime.parse(key).isBefore(on))) {
            failures.add('$at: P6 mínimo en un extracto sin cerrar $key (anotado ${tc.minimumsOn[key]})');
          }
        }
        final List<Tx> outsideTxs = l.txs.where((Tx t) => t.isOutsidePayment).toList();
        for (final Tx p in outsideTxs) {
          if (!DateTime.parse(p.statementOf!).isBefore(dateOnly(p.date))) {
            failures.add('$at: P6 pago de fuera en un extracto sin cerrar ${p.statementOf} (marcado ${dayKey(p.date)})');
          }
        }
        final CardDue due = l.cardDue(tc);
        if (due.overdue && l.isStatementPaid(tc, due.statementCut!)) {
          failures.add('$at: P3 marcado y vencido');
        }
        final CardStatement far = l.statement(tc, date: DateTime(2030, 1, 1));
        final int debt = -l.balanceMinor('tc', before: DateTime(2030, 1, 2));
        if (debt != far.balanceMinor + far.legacyMinor) {
          failures.add('$at: P1 deuda ${debt ~/ 100} ≠ estado ${far.balanceMinor ~/ 100} + aparte ${far.legacyMinor ~/ 100}');
        }
        final int outside = outsideTxs.fold<int>(0, (int a, Tx p) => a + p.amountMinor);
        final int real = truth.values.fold<int>(0, (int a, int b) => a + b);
        if (outside > real) {
          failures.add('$at: T guardado fuera ${outside ~/ 100} > pagado fuera ${real ~/ 100}');
        }
        // P8: lo facturado hasta el corte del próximo pago (compras de una
        // cuota en el ciclo de su fecha; aquí no hay cuotas) menos todo lo
        // pagado de verdad hasta hoy.
        final DateTime cutNext = due.next.cycle.cut;
        int billed = 0;
        int paid = real;
        for (final Tx t in l.txs) {
          if (t.accountId == 'tc' && t.kind == TxKind.expense && !CardCycle.current(tc, t.date).cut.isAfter(cutNext)) {
            billed += t.amountMinor;
          }
          // Lo pagado fuera ya está en `real` (lo de verdad), no se suma otra vez.
          if (!t.isOutsidePayment && (t.toAccountId == 'tc' || (t.accountId == 'tc' && t.kind == TxKind.income)) && !dateOnly(t.date).isAfter(now)) {
            paid += t.amountMinor;
          }
        }
        final int pending = billed - paid > 0 ? billed - paid : 0;
        if (due.next.dueMinor < pending) {
          failures.add('$at: P8 próximo pago ${due.next.dueMinor ~/ 100} < pendiente real ${pending ~/ 100}');
        }
      }
      l.dispose();
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
