// Novena ronda de la auditoría, con el modelo de la ronda 10: «Ya lo pagué»
// guarda un pago hecho fuera de Plata con el monto exacto que el aviso decía
// que faltaba, y no se recalcula (G2 y G3), la fila y el aviso usan la misma
// cifra (M1), «Sí, registrar el pago» propone lo que falta (M2) y las marcas
// de las versiones anteriores se migran una sola vez.
//
// Los valores esperados están escritos a mano en cada caso (los casos X del
// informe del Árbitro, adv9.py).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plata/core/crypto_store.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/core/periods.dart';
import 'package:plata/core/storage.dart';
import 'package:plata/model/models.dart';

DateTime d(int y, int m, int day, [int h = 12]) => DateTime(y, m, day, h);

/// Pesos en unidades menores (centavos).
int pesos(int v) => v * 100;

final DateTime nov15 = DateTime(2026, 11, 15);
final DateTime dec15 = DateTime(2026, 12, 15);

void main() {
  late Directory tmp;
  DateTime today = d(2026, 12, 10);
  int ids = 0;

  setUp(() async {
    today = d(2026, 12, 10);
    tmp = await Directory.systemTemp.createTemp('plata_r9');
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

  // Desde la ronda 12, un abono sin vínculo que puede ser el pago hecho fuera
  // de Plata de un extracto marcado se toma provisionalmente por ese pago y
  // queda la pregunta. En estas pruebas un abono anotado después de marcar es
  // otro pago: se contesta «Es otro pago».
  Future<Tx> pay(Ledger l, int amount, DateTime date, {DateTime? statement}) async {
    ids += 1;
    final Tx t = await l.addTx(Tx(id: 'p$ids', kind: TxKind.transfer, amountMinor: amount, accountId: 'bank', toAccountId: 'tc', date: date, statementOf: statement == null ? null : dayKey(statement)));
    for (int i = 0; i < 12 && l.txs.any((Tx x) => x.id == t.id && x.outsidePending); i++) {
      l.answerOutsideMatch(t, same: false);
    }
    return t;
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
  int debt(Ledger l) => -l.balanceMinor('tc', before: DateTime(2040));

  test('G2, caso X1: con una devolución, «Ya lo pagué» guarda lo que el aviso decía que faltaba', () async {
    final Ledger l = await n1();
    final Account tc = l.account('tc')!;
    await l.addTx(Tx(id: 'r', kind: TxKind.income, amountMinor: pesos(40000), accountId: 'tc', categoryId: 'c_food', date: d(2026, 12, 1)));
    // El aviso cuenta la devolución: faltan 60.000.
    expect(l.cardDue(tc).overdueMinor, pesos(60000));
    l.markStatementPaid(tc, nov15);
    expect(l.outsidePayment(tc, nov15), pesos(60000));
    // 1.300.000 − 40.000 (devolución) − 60.000 (fuera).
    expect(december(l), pesos(1200000));
    expect(debt(l), pesos(1200000));
    l.dispose();
  });

  test('G3, caso X2: corregir la fecha de un abono no cambia lo pagado fuera', () async {
    final Ledger l = await n1();
    final Account tc = l.account('tc')!;
    final Tx t = await pay(l, pesos(40000), d(2026, 12, 9));
    expect(l.cardDue(tc).overdueMinor, pesos(60000));
    l.markStatementPaid(tc, nov15);
    expect(december(l), pesos(1200000));
    today = d(2026, 12, 14);
    t.date = d(2026, 12, 11);
    l.updateTx(t);
    expect(l.outsidePayment(tc, nov15), pesos(60000));
    expect(december(l), pesos(1200000));
    // Ni editar el monto lo cambia: lo pagado fuera se cambia en la fila.
    t.amountMinor = pesos(30000);
    l.updateTx(t);
    expect(l.outsidePayment(tc, nov15), pesos(60000));
    l.dispose();
  });

  test('G3, caso X3: mover el corte a un día posterior no cambia la deuda', () async {
    today = d(2026, 11, 23);
    final Ledger l = await newLedger();
    final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 5, payDay: 20));
    await l.addTx(Tx(id: 'a', kind: TxKind.expense, amountMinor: pesos(900000), accountId: 'tc', date: d(2026, 10, 10)));
    await l.addTx(Tx(id: 'b', kind: TxKind.expense, amountMinor: pesos(200000), accountId: 'tc', date: d(2026, 11, 12)));
    l.setStatementMinimum(tc, DateTime(2026, 11, 5), pesos(100000));
    await pay(l, pesos(40000), d(2026, 11, 15));
    expect(l.cardDue(tc).overdueMinor, pesos(60000));
    l.markStatementPaid(tc, DateTime(2026, 11, 5));
    expect(debt(l), pesos(1000000));
    today = d(2026, 12, 1);
    tc.cutDay = 25;
    l.moveCardCut(tc, 5, oldPayDay: 20);
    // La marca del 23 nov va al extracto del 25 oct, que ya había cerrado.
    expect(l.outsidePayments(tc, DateTime(2026, 10, 25)).single.statementOf, '2026-10-25');
    expect(l.outsidePayment(tc, DateTime(2026, 10, 25)), pesos(60000));
    expect(debt(l), pesos(1000000));
    expect(l.nextPayment(tc, now: DateTime(2026, 12, 1)).dueMinor, pesos(1000000));
    l.dispose();
  });

  test('G3, caso X3b: corte 10 → 15 después de marcar con lo anotado', () async {
    today = d(2026, 11, 20);
    final Ledger l = await newLedger();
    final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 10, payDay: 30));
    await l.addTx(Tx(id: 'a', kind: TxKind.expense, amountMinor: pesos(900000), accountId: 'tc', date: d(2026, 10, 20)));
    l.setStatementMinimum(tc, DateTime(2026, 11, 10), pesos(100000));
    await pay(l, pesos(40000), d(2026, 11, 12));
    l.markStatementPaid(tc, DateTime(2026, 11, 10));
    expect(l.outsidePayment(tc, DateTime(2026, 11, 10)), pesos(60000));
    expect(debt(l), pesos(800000));
    today = d(2026, 11, 25);
    tc.cutDay = 15;
    l.moveCardCut(tc, 10, oldPayDay: 30);
    expect(l.outsidePayment(tc, nov15), pesos(60000));
    expect(debt(l), pesos(800000));
    l.dispose();
  });

  test('M1, caso X4: la fila sin marca y el aviso rojo dicen la misma cifra', () async {
    final Ledger l = await n1();
    final Account tc = l.account('tc')!;
    await pay(l, pesos(40000), d(2026, 12, 5), statement: nov15);
    await pay(l, pesos(30000), d(2026, 12, 6));
    expect(l.cardDue(tc).overdueMinor, pesos(30000));
    expect(l.statementMissing(tc, nov15), pesos(30000));
    l.dispose();
  });

  test('M2, caso X5: registrar el pago después de marcar propone lo que faltaba, y reemplaza lo pagado fuera', () async {
    final Ledger l = await n1();
    final Account tc = l.account('tc')!;
    await pay(l, pesos(40000), d(2026, 12, 9));
    l.markStatementPaid(tc, nov15);
    final int proposed = l.outsidePayment(tc, nov15);
    expect(proposed, pesos(60000));
    await pay(l, proposed, d(2026, 12, 7), statement: nov15);
    expect(l.outsidePayment(tc, nov15), 0);
    expect(december(l), pesos(1200000));
    l.dispose();
  });

  test('caso X6: volver a marcar un extracto ya marcado no cambia nada; desmarcar y marcar guarda lo que falta ese día', () async {
    today = d(2026, 11, 25);
    final Ledger l = await n1();
    final Account tc = l.account('tc')!;
    l.markStatementPaid(tc, nov15);
    today = d(2026, 11, 30);
    await pay(l, pesos(50000), d(2026, 11, 30));
    expect(december(l), pesos(1150000));
    today = d(2026, 12, 2);
    expect(l.markStatementPaid(tc, nov15), isFalse);
    expect(december(l), pesos(1150000));
    l.markStatementPaid(tc, nov15, paid: false);
    l.markStatementPaid(tc, nov15);
    expect(l.outsidePayment(tc, nov15), pesos(50000));
    l.dispose();
  });

  test('caso X7: una marca vieja (sin monto) se convierte una sola vez con la regla de entonces', () async {
    today = d(2026, 12, 20);
    final Ledger l = await n1();
    final Account tc = l.account('tc')!;
    tc.paidStatements.add('2026-11-15');
    await pay(l, pesos(40000), d(2026, 12, 1));
    await pay(l, pesos(30000), d(2026, 12, 9));
    await l.flush();
    final Ledger again = Ledger(l.store, clock: () => today);
    await again.load();
    final Account back = again.account('tc')!;
    // Hasta la fecha límite real (lun 7 dic): 40.000 completan; fuera 60.000.
    expect(back.paidStatements, isEmpty);
    expect(back.outsidePayments, isEmpty);
    final Tx out = again.outsidePayments(back, nov15).single;
    expect(out.amountMinor, pesos(60000));
    expect(dateOnly(out.date), DateTime(2026, 12, 7));
    expect(again.statement(back, date: dec15).dueMinor, pesos(1170000));
    // Guardado y vuelto a abrir, no se migra otra vez.
    again.save();
    await again.flush();
    final Ledger third = Ledger(l.store, clock: () => today);
    await third.load();
    expect(third.txs.where((Tx t) => t.isOutsidePayment), hasLength(1));
    third.dispose();
    again.dispose();
    l.dispose();
  });

  test('caso X8: dos extractos marcados y un abono que cubre los dos', () async {
    today = d(2027, 1, 10);
    final Ledger l = await n1();
    final Account tc = l.account('tc')!;
    await l.addTx(Tx(id: 'c3', kind: TxKind.expense, amountMinor: pesos(200000), accountId: 'tc', date: d(2026, 12, 20)));
    l.setStatementMinimum(tc, dec15, pesos(80000));
    await pay(l, pesos(150000), d(2026, 12, 20));
    l.markStatementPaid(tc, nov15, on: DateTime(2026, 12, 21));
    l.markStatementPaid(tc, dec15, on: DateTime(2027, 1, 4));
    expect(l.outsidePayment(tc, nov15), 0);
    expect(l.outsidePayment(tc, dec15), pesos(30000));
    final CardStatement far = l.statement(tc, date: DateTime(2030));
    expect(debt(l), far.balanceMinor + far.legacyMinor);
    l.dispose();
  });

  test('caso X10: un pago vinculado no se suelta al cambiar el corte', () async {
    today = d(2026, 11, 12);
    final Ledger l = await newLedger();
    final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 10, payDay: 30));
    await l.addTx(Tx(id: 'a', kind: TxKind.expense, amountMinor: pesos(900000), accountId: 'tc', date: d(2026, 9, 20)));
    l.setStatementMinimum(tc, DateTime(2026, 10, 10), pesos(80000));
    final Tx t = await pay(l, pesos(50000), d(2026, 11, 11), statement: DateTime(2026, 11, 10));
    tc.cutDay = 15;
    l.moveCardCut(tc, 10, oldPayDay: 30);
    expect(t.statementOf, '2026-10-15');
    l.dispose();
  });

  test('caso X11b: un mínimo anotado con «Todavía no» va al extracto que la persona tenía ese día', () async {
    today = d(2026, 11, 12);
    final Ledger l = await newLedger();
    final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 10, payDay: 30));
    await l.addTx(Tx(id: 'a', kind: TxKind.expense, amountMinor: pesos(500000), accountId: 'tc', date: d(2026, 9, 1)));
    await l.addTx(Tx(id: 'b', kind: TxKind.expense, amountMinor: pesos(900000), accountId: 'tc', date: d(2026, 10, 20)));
    l.setStatementMinimum(tc, DateTime(2026, 11, 10), pesos(90000));
    tc.cutDay = 15;
    l.moveCardCut(tc, 10, oldPayDay: 30);
    // Con el corte el 15, el extracto que tenía el 12 nov era el del 15 oct,
    // que vencía el 30 oct, y contestó que no lo había pagado.
    expect(tc.statementMinimums.keys, <String>['2026-10-15']);
    final CardDue due = l.cardDue(tc);
    expect(due.overdueMinor, pesos(90000));
    expect(due.overdueSince, DateTime(2026, 10, 30));
    l.dispose();
  });

  test('lo pagado fuera entra en el patrimonio y en el flujo de la tarjeta, no en ingresos', () async {
    final Ledger l = await n1();
    final Account tc = l.account('tc')!;
    final int before = l.netWorthMinor();
    l.markStatementPaid(tc, nov15);
    expect(l.netWorthMinor(), before + pesos(100000));
    final Period month = Period(DateTime(2026, 12), DateTime(2027));
    expect(l.totals(month).incomeMinor, 0);
    final AccountFlow flow = l.cashFlow(month).firstWhere((AccountFlow f) => f.account.id == 'tc');
    expect(flow.inMinor, pesos(100000));
    l.dispose();
  });
}
