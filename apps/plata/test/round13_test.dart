// Decimotercera ronda de la auditoría (s13a.py del Árbitro): el aviso que no
// bloquea cuando un abono cabe en lo pagado fuera pero no preguntó (M1), el
// «Deshacer» del remedio (M2, caso E7) y el pago de fuera que vuelve con su
// id y su fecha (M3).

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
  DateTime today = d(2026, 12, 8);
  int ids = 0;

  setUp(() async {
    today = d(2026, 12, 8);
    tmp = await Directory.systemTemp.createTemp('plata_r13');
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

  Tx transfer(int amount, DateTime date) {
    ids += 1;
    return Tx(id: 'p$ids', kind: TxKind.transfer, amountMinor: amount, accountId: 'bank', toAccountId: 'tc', date: date);
  }

  Future<void> buy(Ledger l, int amount, DateTime date) {
    ids += 1;
    return l.addTx(Tx(id: 'c$ids', kind: TxKind.expense, amountMinor: amount, accountId: 'tc', categoryId: 'c_food', date: date));
  }

  int debt(Ledger l) => -l.balanceMinor('tc', before: DateTime(2040));

  /// Compras de 1.000.000 (20 oct) y 300.000 (20 nov), mínimo de 100.000 del
  /// extracto del 15 nov, marcado «Ya lo pagué» el 8 dic.
  Future<Ledger> base() async {
    today = d(2026, 12, 8);
    final Ledger l = await newLedger();
    final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
    await buy(l, pesos(1000000), d(2026, 10, 20));
    await buy(l, pesos(300000), d(2026, 11, 20));
    l.setStatementMinimum(tc, nov15, pesos(100000));
    l.markStatementPaid(tc, nov15);
    return l;
  }

  group('M1: aviso que no bloquea', () {
    test('E3: con el mínimo del 15 dic anotado no pregunta, y tampoco avisa (es el pago del 15 dic); el remedio lo advierte', () async {
      final Ledger l = await base();
      final Account tc = l.account('tc')!;
      today = d(2026, 12, 17);
      l.setStatementMinimum(tc, dec15, pesos(120000));
      today = d(2026, 12, 19);
      final Tx t = await l.addTx(transfer(pesos(100000), today));
      expect(t.outsidePending, isFalse);
      // Comprobación final (G1): el extracto del 15 dic, más nuevo, tiene su
      // mínimo sin pagar sin este abono: no hay aviso, y elegirlo en el
      // remedio dejaría el 15 dic sin pagar.
      expect(l.outsideHint(t), isNull);
      expect(l.linkLeavesShort(t, nov15), dec15);
      expect(l.pendingOutsideMatches(), isEmpty);
      expect(debt(l), pesos(1100000));
      l.dispose();
    });

    test('anotado después de la ventana: el aviso sugiere; un monto que no cabe, una devolución o un abono con pregunta no', () async {
      final Ledger l = await base();
      today = d(2027, 1, 10);
      final Tx late = await l.addTx(transfer(pesos(100000), d(2026, 12, 7)));
      expect(late.outsidePending, isFalse);
      expect(l.outsideHint(late), nov15);
      final Tx big = await l.addTx(transfer(pesos(300000), d(2027, 1, 10)));
      expect(l.outsideHint(big), isNull);
      final Tx refund = await l.addTx(Tx(id: 'r', kind: TxKind.income, amountMinor: pesos(30000), accountId: 'tc', categoryId: 'c_food', date: today));
      expect(l.outsideHint(refund), isNull);
      today = d(2026, 12, 9);
      final Tx asked = await l.addTx(transfer(pesos(100000), today));
      expect(asked.outsidePending, isTrue);
      expect(l.outsideHint(asked), isNull);
      l.dispose();
    });

    test('E2: dos extractos marcados y el pago del viejo con fecha antes del corte del nuevo: el aviso sugiere el viejo', () async {
      today = d(2026, 10, 17);
      final Ledger l = await newLedger();
      final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
      await buy(l, pesos(800000), d(2026, 9, 20));
      await buy(l, pesos(600000), d(2026, 10, 20));
      l.setStatementMinimum(tc, DateTime(2026, 10, 15), pesos(80000));
      today = d(2026, 11, 4);
      l.markStatementPaid(tc, DateTime(2026, 10, 15));
      today = d(2026, 11, 17);
      l.setStatementMinimum(tc, nov15, pesos(60000));
      today = d(2026, 11, 20);
      l.markStatementPaid(tc, nov15);
      today = d(2026, 11, 25);
      final Tx t = await l.addTx(transfer(pesos(80000), d(2026, 11, 4)));
      expect(t.outsidePending, isFalse);
      expect(l.outsideHint(t), DateTime(2026, 10, 15));
      expect(l.statementsWithOutside(tc), <DateTime>[nov15, DateTime(2026, 10, 15)]);
      l.linkToStatement(t, DateTime(2026, 10, 15));
      expect(debt(l), pesos(1260000));
      l.dispose();
    });
  });

  test('M2, caso E7: el remedio elegido por error se deshace y el extracto del 15 dic deja de estar vencido', () async {
    final Ledger l = await base();
    final Account tc = l.account('tc')!;
    final String outId = l.outsidePayments(tc, nov15).single.id;
    today = d(2026, 12, 17);
    l.setStatementMinimum(tc, dec15, pesos(120000));
    today = d(2027, 1, 4);
    final Tx n = await l.addTx(transfer(pesos(120000), today));
    expect(l.statementMissing(tc, dec15), 0);
    final OutsideLinkUndo undo = l.linkToStatement(n, nov15)!;
    today = d(2027, 1, 8);
    expect(l.statementMissing(tc, dec15), pesos(120000));
    expect(l.cardDue(tc).overdueMinor, pesos(120000));
    l.undoLinkToStatement(undo);
    expect(l.txs.firstWhere((Tx x) => x.id == n.id).statementOf, isNull);
    expect(l.outsidePayments(tc, nov15).single.id, outId);
    expect(l.outsidePayment(tc, nov15), pesos(100000));
    expect(l.statementMissing(tc, dec15), 0);
    expect(l.cardDue(tc).overdue, isFalse);
    expect(debt(l), pesos(1080000));
    l.dispose();
  });

  test('M3: «Es otro pago» devuelve el pago de fuera con su id y su fecha (la de la marca), y la ventana no se corre', () async {
    final Ledger l = await base();
    final Account tc = l.account('tc')!;
    final Tx out = l.outsidePayments(tc, nov15).single;
    today = d(2026, 12, 9);
    await l.addScheduled(Scheduled(id: 'a', name: 'Pago', kind: TxKind.transfer, amountMinor: pesos(100000), accountId: 'bank', toAccountId: 'tc', nextDate: d(2026, 12, 9)));
    final Tx t = l.processScheduled(now: d(2026, 12, 9)).single;
    expect(l.outsidePayments(tc, nov15), isEmpty);
    today = d(2026, 12, 24);
    l.answerOutsideMatch(t, same: false);
    final Tx back = l.outsidePayments(tc, nov15).single;
    expect(back.id, out.id);
    expect(dateOnly(back.date), DateTime(2026, 12, 8));
    expect(back.amountMinor, pesos(100000));
    expect(tc.outsideGone, isEmpty);
    // La ventana sigue empezando el 8 dic.
    expect(l.outsideCandidate(Tx(id: 'x', kind: TxKind.transfer, amountMinor: pesos(50000), accountId: 'bank', toAccountId: 'tc', date: d(2026, 12, 20), loggedOn: d(2026, 12, 20))), nov15);
    // Sobrevive a guardar y abrir.
    await l.flush();
    final Ledger again = Ledger(l.store, clock: () => today);
    await again.load();
    expect(again.outsidePayments(again.account('tc')!, nov15).single.id, out.id);
    again.dispose();
    l.dispose();
  });
}
