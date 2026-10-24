// Comprobación final después de la ronda 13 (s_hint, s_hint_follow y s_final
// del Árbitro): el aviso «¿Es el pago del extracto del …? Elegir» sale solo
// para un pago anotado tarde (G1), el remedio advierte cuando el abono es el
// pago del mes, y «Deshacer» del remedio deshace solo lo que hizo (M-a).

import 'dart:convert';
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
  DateTime today = d(2026, 12, 8);
  int ids = 0;

  setUp(() async {
    today = d(2026, 12, 8);
    tmp = await Directory.systemTemp.createTemp('plata_final');
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

  /// s_hint: paga [fixed] cada mes desde Plata (dos días antes de la fecha
  /// límite) y un solo mes (feb 2025) lo pagó fuera y tocó «Ya lo pagué» por
  /// [outside]. Cuenta los avisos en 24 meses, apuntándolos como la pantalla.
  Future<int> fixedPaymentHints(int fixed, int outside, {required bool noteMinimum}) async {
    today = d(2025, 1, 1);
    final Ledger l = await newLedger();
    final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
    DateTime k = DateTime(2025, 1, 15);
    int hints = 0;
    for (int i = 0; i < 24; i++) {
      today = d(k.year, k.month, k.day - 7);
      await buy(l, pesos(600000), today);
      today = d(k.year, k.month, k.day + 2);
      if (noteMinimum) {
        l.setStatementMinimum(tc, k, i == 1 ? outside : pesos(200000));
      }
      final DateTime due = l.effectivePayDate(tc, CardCycle.current(tc, k).payDate);
      if (i == 1) {
        today = d(due.year, due.month, due.day - 1);
        l.markStatementPaid(tc, k, amount: outside);
      } else {
        today = d(due.year, due.month, due.day - 2);
        final Tx t = await l.addTx(transfer(fixed, today));
        if (t.outsidePending) {
          l.answerOutsideMatch(t, same: false);
        }
        final DateTime? h = l.outsideHint(t);
        if (h != null) {
          hints += 1;
          l.noteOutsideHintShown(tc, h);
        }
      }
      k = CardCycle.cutAfter(tc, k, 1);
    }
    l.dispose();
    return hints;
  }

  group('G1: el aviso no sale en los pagos normales del mes', () {
    test('pago fijo desde Plata y una sola marca vieja: a lo sumo un aviso en 23 pagos (antes, 22)', () async {
      expect(await fixedPaymentHints(pesos(250000), pesos(300000), noteMinimum: true), lessThanOrEqualTo(1));
      expect(await fixedPaymentHints(pesos(250000), pesos(300000), noteMinimum: false), lessThanOrEqualTo(1));
      expect(await fixedPaymentHints(pesos(200000), pesos(200000), noteMinimum: true), lessThanOrEqualTo(1));
    });

    test('el pago anotado tarde avisa una sola vez por extracto, y eso se guarda; desmarcar lo olvida', () async {
      final Ledger l = await base();
      final Account tc = l.account('tc')!;
      today = d(2027, 1, 10);
      final Tx late = await l.addTx(transfer(pesos(100000), d(2026, 12, 7)));
      expect(late.outsidePending, isFalse);
      expect(l.outsideHint(late), nov15);
      l.noteOutsideHintShown(tc, nov15);
      expect(l.outsideHint(late), isNull);
      final Tx other = await l.addTx(transfer(pesos(50000), d(2026, 12, 7)));
      expect(l.outsideHint(other), isNull);
      await l.flush();
      final Ledger again = Ledger(l.store, clock: () => today);
      await again.load();
      expect(again.account('tc')!.outsideHinted, <String>['2026-11-15']);
      again.dispose();
      l.markStatementPaid(tc, nov15, paid: false);
      expect(tc.outsideHinted, isEmpty);
      l.dispose();
    });

    test('después de «Es otro pago» no hay aviso, ni por ese extracto ni por otro', () async {
      final Ledger l = await base();
      today = d(2026, 12, 9);
      final Tx t = await l.addTx(transfer(pesos(100000), today));
      expect(t.outsidePending, isTrue);
      l.answerOutsideMatch(t, same: false);
      expect(t.apartFrom, contains('2026-11-15'));
      expect(l.outsideHint(t), isNull);
      l.dispose();
    });

    test('más de 120 días después de la marca no avisa', () async {
      final Ledger l = await base();
      today = d(2027, 4, 8);
      final Tx t = await l.addTx(transfer(pesos(100000), d(2026, 12, 7)));
      expect(l.outsideHint(t), isNull);
      today = d(2027, 4, 7);
      final Tx u = await l.addTx(transfer(pesos(100000), d(2026, 12, 7)));
      expect(l.outsideHint(u), nov15);
      l.dispose();
    });
  });

  test('s_hint_follow: el pago de abril no avisa por febrero, y el remedio advierte que dejaría abril sin pagar', () async {
    today = d(2025, 1, 1);
    final Ledger l = await newLedger();
    final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
    DateTime k = DateTime(2025, 1, 15);
    late DateTime feb;
    late Tx april;
    for (int i = 0; i < 4; i++) {
      today = d(k.year, k.month, k.day - 7);
      await buy(l, pesos(600000), today);
      today = d(k.year, k.month, k.day + 2);
      l.setStatementMinimum(tc, k, pesos(i == 1 ? 300000 : 200000));
      final DateTime due = l.effectivePayDate(tc, CardCycle.current(tc, k).payDate);
      if (i == 1) {
        today = d(due.year, due.month, due.day - 1);
        l.markStatementPaid(tc, k);
        feb = k;
      } else {
        today = d(due.year, due.month, due.day - 2);
        final Tx t = await l.addTx(transfer(pesos(250000), today));
        expect(l.outsideHint(t), isNull, reason: 'pago del extracto del $k');
        april = t;
      }
      k = CardCycle.cutAfter(tc, k, 1);
    }
    final DateTime apr15 = DateTime(2025, 4, 15);
    expect(l.unlinkedCreditsAfter(tc, feb).map((Tx t) => t.id), contains(april.id));
    expect(l.linkLeavesShort(april, feb), apr15);
    // Sin seguir nada, abril está pagado.
    today = d(2025, 5, 8);
    expect(l.cardDue(tc).overdue, isFalse);
    l.dispose();
  });

  group('M-a y M-d: «Deshacer» del remedio', () {
    /// s_final, U2–U6: compra de 400.000 el 20 dic, mínimo de 120.000 del 15
    /// dic, y el pago del 15 nov anotado el 20 ene con fecha 7 dic, vinculado
    /// con el remedio.
    Future<List<Object>> linked() async {
      final Ledger l = await base();
      final Account tc = l.account('tc')!;
      today = d(2027, 1, 20);
      await buy(l, pesos(400000), d(2026, 12, 20));
      l.setStatementMinimum(tc, dec15, pesos(120000));
      final Tx n = await l.addTx(transfer(pesos(100000), d(2026, 12, 7)));
      expect(n.outsidePending, isFalse);
      final OutsideLinkUndo undo = l.linkToStatement(n, nov15)!;
      expect(l.outsidePayment(tc, nov15), 0);
      return <Object>[l, tc, n, undo];
    }

    test('U1: enseguida, todo queda como estaba', () async {
      final List<Object> s = await linked();
      final Ledger l = s[0] as Ledger;
      final Tx n = s[2] as Tx;
      expect(l.undoLinkToStatement(s[3] as OutsideLinkUndo), isTrue);
      expect(l.txs.firstWhere((Tx x) => x.id == n.id).statementOf, isNull);
      expect(l.outsidePayment(s[1] as Account, nov15), pesos(100000));
      expect(debt(l), pesos(1500000));
      l.dispose();
    });

    /// Todo lo de la tarjeta, para comparar antes y después de «Deshacer».
    String card(Ledger l) => jsonEncode(<Object>[
          l.account('tc')!.toJson(),
          for (final Tx x in l.txs)
            if (x.accountId == 'tc' || x.toAccountId == 'tc') x.toJson(),
        ]);

    test('M-d: si algo de la tarjeta cambió después del vínculo, «Deshacer» no deshace nada', () async {
      const List<String> ops = <String>['U2 pago del 15 dic', 'U3 «Ya lo pagué» del 15 dic', 'U4 editar el elegido', 'U5 borrar el elegido', 'U6 abono nuevo', 'U7 «Desmarcar»', 'U8 «Cambiar monto»', 'U9 otro pago del 15 nov', 'mínimo', 'día de corte'];
      for (final String op in ops) {
        final List<Object> s = await linked();
        final Ledger l = s[0] as Ledger;
        final Account tc = s[1] as Account;
        final Tx n = s[2] as Tx;
        final OutsideLinkUndo undo = s[3] as OutsideLinkUndo;
        expect(l.canUndoLink(undo), isTrue, reason: op);
        if (op.startsWith('U2')) {
          await l.addTx(Tx(id: 'x', kind: TxKind.transfer, amountMinor: pesos(120000), accountId: 'bank', toAccountId: 'tc', date: d(2027, 1, 5), statementOf: '2026-12-15'));
        } else if (op.startsWith('U3')) {
          l.markStatementPaid(tc, dec15);
        } else if (op.startsWith('U4')) {
          l.updateTx(Tx.fromJson(l.txs.firstWhere((Tx x) => x.id == n.id).toJson())..amountMinor = pesos(90000));
        } else if (op.startsWith('U5')) {
          await l.deleteTx(n.id);
        } else if (op.startsWith('U6')) {
          await l.addTx(transfer(pesos(50000), d(2027, 1, 20)));
        } else if (op.startsWith('U7')) {
          l.markStatementPaid(tc, nov15, paid: false);
        } else if (op.startsWith('U8')) {
          l.setOutsidePayment(tc, nov15, pesos(50000));
        } else if (op.startsWith('U9')) {
          await l.addTx(Tx(id: 'y', kind: TxKind.transfer, amountMinor: pesos(30000), accountId: 'bank', toAccountId: 'tc', date: d(2027, 1, 10), statementOf: '2026-11-15'));
        } else if (op == 'mínimo') {
          l.setStatementMinimum(tc, dec15, pesos(130000));
        } else {
          final int? old = tc.cutDay;
          tc.cutDay = 20;
          l.moveCardCut(tc, old);
        }
        final String before = card(l);
        final int owed = debt(l);
        expect(l.canUndoLink(undo), isFalse, reason: op);
        expect(l.undoLinkToStatement(undo), isFalse, reason: op);
        expect(card(l), before, reason: op);
        expect(debt(l), owed, reason: op);
        l.dispose();
      }
    });

    test('X2: un provisional al que el vínculo le quitó contesta «Es otro pago»: «Deshacer» no deshace y no pierde lo pagado fuera', () async {
      final Ledger l = await base();
      final Account tc = l.account('tc')!;
      today = d(2026, 12, 20);
      final Tx p = await l.addTx(transfer(pesos(60000), today));
      expect(p.outsidePending, isTrue);
      today = d(2026, 12, 21);
      ids += 1;
      final Tx t = await l.addTx(Tx(id: 'p$ids', kind: TxKind.transfer, amountMinor: pesos(100000), accountId: 'bank', toAccountId: 'tc', date: d(2026, 12, 7), apartFrom: <String>['2026-11-15']));
      expect(t.outsidePending, isFalse);
      final OutsideLinkUndo undo = l.linkToStatement(t, nov15)!;
      l.answerOutsideMatch(l.txs.firstWhere((Tx x) => x.id == p.id), same: false);
      final String before = card(l);
      expect(l.undoLinkToStatement(undo), isFalse);
      expect(card(l), before);
      // Lo de fuera del 15 nov quedó reemplazado por el abono elegido: no se
      // pierde ni se cuenta dos veces.
      expect(l.statementPayments(tc, nov15).map((Tx x) => x.id), contains(t.id));
      expect(l.statementMissing(tc, nov15), 0);
      expect(debt(l), pesos(1300000 - 100000 - 60000));
      l.dispose();
    });

    test('E7 con «Deshacer»: vincular el pago de abril a febrero, «Ya lo pagué» de abril y «Deshacer»: no deshace ni cuenta dos veces', () async {
      today = d(2025, 1, 1);
      final Ledger l = await newLedger();
      final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
      DateTime k = DateTime(2025, 1, 15);
      late Tx april;
      for (int i = 0; i < 4; i++) {
        today = d(k.year, k.month, k.day - 7);
        await buy(l, pesos(600000), today);
        today = d(k.year, k.month, k.day + 2);
        l.setStatementMinimum(tc, k, pesos(i == 1 ? 300000 : 200000));
        final DateTime due = l.effectivePayDate(tc, CardCycle.current(tc, k).payDate);
        if (i == 1) {
          today = d(due.year, due.month, due.day - 1);
          l.markStatementPaid(tc, k);
        } else {
          today = d(due.year, due.month, due.day - 2);
          april = await l.addTx(transfer(pesos(250000), today));
        }
        k = CardCycle.cutAfter(tc, k, 1);
      }
      final DateTime feb15 = DateTime(2025, 2, 15);
      final DateTime apr15 = DateTime(2025, 4, 15);
      today = d(2025, 5, 8);
      expect(l.linkLeavesShort(april, feb15), apr15);
      final OutsideLinkUndo undo = l.linkToStatement(april, feb15)!;
      expect(l.cardDue(tc).overdueMinor, pesos(200000));
      l.markStatementPaid(tc, apr15);
      final String before = card(l);
      final int owed = debt(l);
      expect(l.undoLinkToStatement(undo), isFalse);
      expect(card(l), before);
      expect(debt(l), owed);
      // Cada pago cuenta una vez: 250.000 (ene) + 50.000 de fuera de feb que
      // quedan + 250.000 (mar) + 250.000 (abr, vinculado a feb) + 200.000 de
      // fuera de abr.
      expect(owed, pesos(2400000 - 1000000));
      expect(l.cardDue(tc).overdue, isFalse);
      l.dispose();
    });
  });
}
