// Séptima ronda de la auditoría: el pago vinculado a un extracto (decisión
// de diseño de la ronda 8), el abono supuesto hasta la fecha límite real, el
// abono adelantado (G2), el cambio del día de corte (G3), el próximo pago con
// el día de pago junto al corte (M3) y las copias viejas sin vínculo.
//
// Los valores esperados están calculados a mano en cada caso (no con la
// regla del libro): compras de $1.000.000 (20 oct) y $300.000 (20 nov), corte
// el 15 y pago el 5 (el sáb 5 dic se corre al lun 7), mínimo de $100.000 del
// extracto del 15 nov.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plata/core/crypto_store.dart';
import 'package:plata/core/ledger.dart';
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
    tmp = await Directory.systemTemp.createTemp('plata_r7');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<Ledger> newLedger() async {
    final Directory dir = await tmp.createTemp('l');
    final Ledger l = Ledger(EncryptedStore(JsonStore(root: dir), await CryptoBox.fromKeyStore(MemoryKeyStore())), clock: () => today);
    await l.load();
    await l.addAccount(Account(id: 'bank', name: 'Ahorros', type: AccountType.bank, initialMinor: pesos(20000000)));
    return l;
  }

  /// Abono a la tarjeta desde Ahorros; con [statement], vinculado a ese
  /// extracto (como lo guarda «Registrar el pago» de su fila).
  Future<Tx> pay(Ledger l, int amount, DateTime date, {DateTime? statement}) {
    ids += 1;
    return l.addTx(Tx(id: 'p$ids', kind: TxKind.transfer, amountMinor: amount, accountId: 'bank', toAccountId: 'tc', date: date, statementOf: statement == null ? null : dayKey(statement)));
  }

  /// La tarjeta del caso N1, con el extracto del 15 nov marcado «Ya lo pagué».
  Future<Ledger> n1({bool marked = true, int cutDay = 15, int payDay = 5}) async {
    final Ledger l = await newLedger();
    final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: cutDay, payDay: payDay));
    await l.addTx(Tx(id: 'c1', kind: TxKind.expense, amountMinor: pesos(1000000), accountId: 'tc', date: d(2026, 10, 20)));
    await l.addTx(Tx(id: 'c2', kind: TxKind.expense, amountMinor: pesos(300000), accountId: 'tc', date: d(2026, 11, 20)));
    l.setStatementMinimum(tc, nov15, pesos(100000));
    if (marked) {
      l.markStatementPaid(tc, nov15);
    }
    return l;
  }

  int december(Ledger l) => l.statement(l.account('tc')!, date: dec15).dueMinor;

  group('G2: abonos adelantados con el extracto marcado', () {
    // Pagó el mínimo fuera de Plata ($100.000) y abona X después de la fecha
    // límite real: el extracto del 15 dic es 1.300.000 − 100.000 − X.
    final Map<DateTime, int> cases = <DateTime, int>{
      d(2026, 12, 10): pesos(100000),
      d(2026, 12, 12): pesos(50000),
      d(2026, 12, 14): pesos(300000),
      d(2026, 12, 15): pesos(500000),
    };
    cases.forEach((DateTime date, int amount) {
      test('un abono de ${amount ~/ 100} el ${date.day} dic baja el próximo pago exactamente eso', () async {
        final Ledger l = await n1();
        expect(december(l), pesos(1200000));
        await pay(l, amount, date);
        expect(december(l), pesos(1200000) - amount);
        // También el «Próximo pago» de ese día.
        expect(l.nextPayment(l.account('tc')!, now: date).dueMinor, pesos(1200000) - amount);
        l.dispose();
      });
    });

    test('lo anotado hasta la fecha límite real es parte del mínimo marcado (regla de la decisión)', () async {
      // Anotó $40.000 el 30 nov y marcó «Ya lo pagué»: el pago de fuera
      // completa el mínimo con $60.000. Pendiente: 1.300.000 − 100.000.
      final Ledger l = await n1();
      await pay(l, pesos(40000), d(2026, 11, 30));
      expect(december(l), pesos(1200000));
      l.dispose();
    });
  });

  group('pago vinculado al extracto', () {
    for (final DateTime date in <DateTime>[d(2026, 12, 1), d(2026, 12, 7), d(2026, 12, 8), d(2026, 12, 16), d(2026, 12, 22), d(2027, 1, 5)]) {
      test('registrado el ${date.day}/${date.month} reemplaza el abono supuesto: 1.200.000', () async {
        final Ledger l = await n1();
        final Account tc = l.account('tc')!;
        await pay(l, pesos(100000), date, statement: nov15);
        expect(december(l), pesos(1200000));
        expect(l.statement(tc, date: nov15).paymentsMinor, pesos(100000));
        expect(l.statementPayments(tc, nov15), hasLength(1));
        today = date.isAfter(d(2026, 12, 15)) ? date : d(2026, 12, 15);
        expect(l.nextPayment(tc, now: today).dueMinor, pesos(1200000));
        expect(l.cardDue(tc, now: today).overdue, isFalse);
        l.dispose();
      });
    }

    test('caso B: el pago registrado desde la fila después del corte siguiente', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      today = d(2026, 12, 22);
      await pay(l, pesos(100000), d(2026, 12, 22), statement: nov15);
      expect(l.nextPayment(tc, now: d(2026, 12, 22)).dueMinor, pesos(1200000));
      l.dispose();
    });

    test('vinculado y además un abono adelantado: cada uno cuenta una vez', () async {
      final Ledger l = await n1();
      await pay(l, pesos(100000), d(2026, 12, 7), statement: nov15);
      await pay(l, pesos(300000), d(2026, 12, 14));
      expect(december(l), pesos(900000));
      l.dispose();
    });

    test('borrar el pago vinculado devuelve el abono supuesto; editarlo cambia la cifra', () async {
      final Ledger l = await n1();
      final Tx p = await pay(l, pesos(100000), d(2026, 12, 22), statement: nov15);
      expect(december(l), pesos(1200000));
      p.amountMinor = pesos(1000000);
      l.updateTx(p);
      expect(december(l), pesos(300000));
      await l.deleteTx(p.id);
      expect(december(l), pesos(1200000));
      expect(l.statementPayments(l.account('tc')!, nov15), isEmpty);
      l.dispose();
    });

    test('si el movimiento ya no va a la tarjeta, el vínculo no cuenta', () async {
      final Ledger l = await n1();
      await l.addAccount(Account(id: 'cash', name: 'Efectivo', type: AccountType.cash));
      final Tx p = await pay(l, pesos(100000), d(2026, 12, 22), statement: nov15);
      p.toAccountId = 'cash';
      l.updateTx(p);
      expect(december(l), pesos(1200000));
      expect(l.statementPayments(l.account('tc')!, nov15), isEmpty);
      l.dispose();
    });

    test('sin marcar, el pago vinculado cuenta para la mora de su extracto aunque su fecha sea de antes del corte', () async {
      final Ledger l = await n1(marked: false);
      final Account tc = l.account('tc')!;
      expect(l.cardDue(tc, now: DateTime(2026, 12, 9)).overdueMinor, pesos(100000));
      await pay(l, pesos(100000), d(2026, 11, 10), statement: nov15);
      expect(l.cardDue(tc, now: DateTime(2026, 12, 9)).overdue, isFalse);
      // Y no cuenta para el extracto siguiente: es el pago del 15 nov.
      expect(december(l), pesos(1200000));
      l.dispose();
    });

    test('una copia no lleva el vínculo', () async {
      final Ledger l = await n1();
      final Tx p = await pay(l, pesos(100000), d(2026, 12, 7), statement: nov15);
      final Tx copy = await l.duplicateTx(p, date: d(2026, 12, 20));
      expect(copy.statementOf, isNull);
      l.dispose();
    });

    test('el vínculo se guarda; una copia vieja sin él se lee con la regla nueva', () async {
      final Tx linked = Tx(id: 'x', kind: TxKind.transfer, amountMinor: 1, accountId: 'bank', toAccountId: 'tc', date: d(2026, 12, 7), statementOf: '2026-11-15');
      expect(Tx.fromJson(linked.toJson()).statementOf, '2026-11-15');
      final Map<String, dynamic> old = linked.toJson()..remove('statementOf');
      expect(Tx.fromJson(old).statementOf, isNull);
      // Copia vieja: marcado y un pago del 4 dic sin vínculo (dentro de la
      // ventana): 1.200.000, sin contarlo dos veces.
      final Ledger l = await n1();
      await pay(l, pesos(100000), d(2026, 12, 4));
      expect(december(l), pesos(1200000));
      l.dispose();
    });
  });

  group('lo pagado más lo pendiente es el total facturado', () {
    // Cada escenario: lo que se pagó fuera de Plata (E), lo anotado y lo que
    // queda del extracto del 15 dic, calculado a mano. Siempre:
    // pendiente + E + anotado = 1.300.000.
    test('en cada escenario', () async {
      final List<String> failures = <String>[];
      Future<void> scenario(String name, {required int external, required bool marked, required List<_Logged> logged, required int pending}) async {
        final Ledger l = await n1(marked: marked);
        int sum = 0;
        for (final _Logged p in logged) {
          await pay(l, p.amount, p.date, statement: p.linked ? nov15 : null);
          sum += p.amount;
        }
        final int got = december(l);
        if (got != pending) {
          failures.add('$name: pendiente ${got ~/ 100}, esperado ${pending ~/ 100}');
        }
        if (got + external + sum != pesos(1300000)) {
          failures.add('$name: pendiente + pagado ${(got + external + sum) ~/ 100} ≠ 1.300.000');
        }
        l.dispose();
      }

      await scenario('mínimo pagado fuera, nada anotado', external: pesos(100000), marked: true, logged: <_Logged>[], pending: pesos(1200000));
      await scenario('mínimo fuera y abono de 200.000 el 12 dic', external: pesos(100000), marked: true, logged: <_Logged>[_Logged(pesos(200000), d(2026, 12, 12), linked: false)], pending: pesos(1000000));
      await scenario('60.000 fuera y 40.000 anotados el 30 nov', external: pesos(60000), marked: true, logged: <_Logged>[_Logged(pesos(40000), d(2026, 11, 30), linked: false)], pending: pesos(1200000));
      await scenario('pago registrado desde la fila el 22 dic', external: 0, marked: true, logged: <_Logged>[_Logged(pesos(100000), d(2026, 12, 22), linked: true)], pending: pesos(1200000));
      await scenario('desde la fila el 7 dic y abono de 300.000 el 14 dic', external: 0, marked: true, logged: <_Logged>[_Logged(pesos(100000), d(2026, 12, 7), linked: true), _Logged(pesos(300000), d(2026, 12, 14), linked: false)], pending: pesos(900000));
      await scenario('mínimo fuera y quincena de 500.000 el 15 dic', external: pesos(100000), marked: true, logged: <_Logged>[_Logged(pesos(500000), d(2026, 12, 15), linked: false)], pending: pesos(700000));
      await scenario('sin marcar, dos pagos anotados', external: 0, marked: false, logged: <_Logged>[_Logged(pesos(100000), d(2026, 12, 4), linked: false), _Logged(pesos(250000), d(2026, 12, 9), linked: false)], pending: pesos(950000));
      await scenario('pago total desde la fila después del corte', external: 0, marked: true, logged: <_Logged>[_Logged(pesos(1000000), d(2026, 12, 18), linked: true)], pending: pesos(300000));
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  });

  group('G3: cambiar el día de corte', () {
    test('caso C: 15 → 16 con el mínimo y la marca del extracto del 15 nov', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      tc.cutDay = 16;
      l.moveCardCut(tc, 15);
      final DateTime nov16 = DateTime(2026, 11, 16);
      expect(l.isStatementPaid(tc, nov16), isTrue);
      expect(l.statementMinimum(tc, nov16), pesos(100000));
      // Compras: 1.000.000 en el extracto del 16 nov, 300.000 en el del 16 dic.
      final CardDue due = l.cardDue(tc, now: DateTime(2026, 12, 10));
      expect(due.next.dueMinor, pesos(1200000));
      expect(due.overdue, isFalse);
      expect(due.unconfirmed, isFalse);
      l.dispose();
    });

    test('el pago vinculado pasa al extracto del mismo mes', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      final Tx p = await pay(l, pesos(100000), d(2026, 12, 22), statement: nov15);
      tc.cutDay = 10;
      l.moveCardCut(tc, 15);
      expect(p.statementOf, '2026-11-10');
      expect(l.statementPayments(tc, DateTime(2026, 11, 10)), hasLength(1));
      l.dispose();
    });

    test('caso C2: mínimo del último extracto, «Ya lo pagué» desde el aviso rojo, y el corte cambia a 16 y a 10', () async {
      today = d(2026, 11, 2);
      final Ledger l = await newLedger();
      final Account draft = Account(id: 'tc', name: 'Visa', type: AccountType.credit, initialMinor: -pesos(2000000), cutDay: 15, payDay: 5)..statementDueMinor = pesos(150000);
      draft.statementCut = l.referenceStatementCut(draft);
      final Account tc = await l.addAccount(draft);
      expect(tc.statementCut, DateTime(2026, 10, 15));
      expect(l.cardDue(tc, now: DateTime(2026, 11, 9)).overdueMinor, pesos(150000));
      l.markStatementPaid(tc, DateTime(2026, 10, 15));
      tc.cutDay = 16;
      l.moveCardCut(tc, 15);
      expect(tc.statementCut, DateTime(2026, 10, 16));
      expect(l.cardDue(tc, now: DateTime(2026, 11, 9)).overdue, isFalse);
      tc.cutDay = 10;
      l.moveCardCut(tc, 16);
      expect(tc.statementCut, DateTime(2026, 10, 10));
      expect(l.isStatementPaid(tc, DateTime(2026, 10, 10)), isTrue);
      for (final DateTime day in <DateTime>[DateTime(2026, 11, 9), DateTime(2026, 12, 9)]) {
        final CardDue due = l.cardDue(tc, now: day);
        expect(due.overdue, isFalse, reason: '$day');
        expect(due.unconfirmed, isFalse, reason: '$day');
      }
      l.dispose();
    });

    test('cambiar solo el día de pago no mueve nada', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      tc.payDay = 8;
      l.moveCardCut(tc, 15);
      expect(l.isStatementPaid(tc, nov15), isTrue);
      expect(l.statementMinimum(tc, nov15), pesos(100000));
      l.dispose();
    });
  });

  group('M3: día de pago igual o justo antes del corte', () {
    // Compras de 500.000 (20 sep, extracto del 15 oct) y 200.000 (20 oct,
    // extracto del 15 nov). El extracto del 15 oct vence el 15, el 14 o el 13
    // nov; el 15 nov 2026 es domingo y el 16 festivo: se corre al mar 17.
    final Map<int, DateTime> dueOct = <int, DateTime>{15: DateTime(2026, 11, 17), 14: DateTime(2026, 11, 17), 13: DateTime(2026, 11, 13)};
    dueOct.forEach((int payDay, DateTime due) {
      test('pago el $payDay: el extracto del 15 oct es el próximo hasta el ${due.day} nov', () async {
        today = d(2026, 11, 1);
        final Ledger l = await newLedger();
        final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: payDay));
        await l.addTx(Tx(id: 'a', kind: TxKind.expense, amountMinor: pesos(500000), accountId: 'tc', date: d(2026, 9, 20)));
        await l.addTx(Tx(id: 'b', kind: TxKind.expense, amountMinor: pesos(200000), accountId: 'tc', date: d(2026, 10, 20)));
        for (final DateTime day in <DateTime>[DateTime(2026, 11, 13), DateTime(2026, 11, 16), DateTime(2026, 11, 17), DateTime(2026, 11, 18)]) {
          final CardStatement next = l.nextPayment(tc, now: day);
          final bool before = !day.isAfter(due);
          expect(next.dueMinor, before ? pesos(500000) : pesos(700000), reason: '$day');
          expect(next.cycle.cut, before ? DateTime(2026, 10, 15) : DateTime(2026, 11, 15), reason: '$day');
        }
        l.dispose();
      });
    });
  });
}

/// Un abono anotado en un escenario: monto, fecha y si va vinculado al
/// extracto del 15 nov.
class _Logged {
  const _Logged(this.amount, this.date, {required this.linked});

  final int amount;
  final DateTime date;
  final bool linked;
}
