// Décima ronda de la auditoría (casos A del Árbitro, adv10.py y split22.py):
// el pago hecho fuera de Plata es un movimiento de la tarjeta. «Ya lo pagué»
// lo crea por lo que faltaba; un abono sin vínculo que llega después
// pregunta si es ese pago (G1, A1); corregir un pago vinculado reemplaza lo
// de fuera en lo que subió (A4); no hay tope de marcas (G3, A2); de un
// extracto de antes de la tarjeta se pregunta si se pagó antes o después
// (G4, A3); al cambiar el corte los datos de un extracto se mueven juntos
// (G2, A6 y split22); la migración de las marcas viejas y de los pagos de
// fuera de la ronda 10 (idempotente), la versión del formato, y las
// propiedades P1, P6, P8 y P9 con secuencias al azar.
//
// Los valores esperados están escritos a mano en cada caso.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plata/core/crypto_store.dart';
import 'package:plata/core/exports.dart';
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
    tmp = await Directory.systemTemp.createTemp('plata_r10');
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

  Future<Ledger> reopen(Ledger l) async {
    final Ledger again = Ledger(l.store, clock: () => today);
    await again.load();
    return again;
  }

  Future<Tx> pay(Ledger l, int amount, DateTime date, {DateTime? statement}) {
    ids += 1;
    return l.addTx(Tx(id: 'p$ids', kind: TxKind.transfer, amountMinor: amount, accountId: 'bank', toAccountId: 'tc', date: date, statementOf: statement == null ? null : dayKey(statement)));
  }

  Future<void> buy(Ledger l, int amount, DateTime date) {
    ids += 1;
    return l.addTx(Tx(id: 'c$ids', kind: TxKind.expense, amountMinor: amount, accountId: 'tc', categoryId: 'c_food', date: date));
  }

  /// Compras de 1.000.000 (20 oct) y 300.000 (20 nov), corte el 15 y pago el
  /// 5 (el sáb 5 dic se corre al lun 7), mínimo de 100.000 del 15 nov.
  Future<Ledger> n1() async {
    final Ledger l = await newLedger();
    final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
    await buy(l, pesos(1000000), d(2026, 10, 20));
    await buy(l, pesos(300000), d(2026, 11, 20));
    l.setStatementMinimum(tc, nov15, pesos(100000));
    return l;
  }

  int december(Ledger l) => l.statement(l.account('tc')!, date: dec15).dueMinor;
  int debt(Ledger l) => -l.balanceMinor('tc', before: DateTime(2040));
  Tx byId(Ledger l, String id) => l.txs.firstWhere((Tx t) => t.id == id);

  group('el pago de fuera es un movimiento', () {
    test('«Ya lo pagué» crea un abono a la tarjeta que no sale de ninguna cuenta, con lo que faltaba y fecha de hoy', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      final int bank = l.balanceMinor('bank');
      expect(l.cardDue(tc).overdueMinor, pesos(100000));
      l.markStatementPaid(tc, nov15);
      final Tx out = l.outsidePayments(tc, nov15).single;
      expect(out.kind, TxKind.income);
      expect(out.accountId, 'tc');
      expect(out.toAccountId, isNull);
      expect(out.source, 'outside');
      expect(out.statementOf, '2026-11-15');
      expect(out.amountMinor, pesos(100000));
      expect(dateOnly(out.date), DateTime(2026, 12, 8));
      // El nombre se genera al mostrarlo, en el idioma actual (M4 de la ronda 11).
      expect(out.description, isEmpty);
      expect(Ledger.shownDescription(out, spanish: true), 'Pago hecho fuera de Plata');
      expect(Ledger.shownDescription(out, spanish: false), 'Payment made outside Plata');
      expect(l.balanceMinor('bank'), bank);
      expect(debt(l), pesos(1200000));
      expect(december(l), pesos(1200000));
      l.dispose();
    });

    test('aparece en la lista de la tarjeta, en la búsqueda y en la exportación; no cuenta como ingreso', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, nov15);
      final Tx out = l.outsidePayments(tc, nov15).single;
      expect(l.search(const TxFilter(accountIds: <String>{'tc'})), contains(out));
      expect(l.search(const TxFilter(text: 'fuera de plata')), <Tx>[out]);
      final List<List<String>> rows = Exports.rows(l, l.txs);
      final List<String> row = rows.firstWhere((List<String> r) => r.last == out.id);
      expect(row[6], 'Pago hecho fuera de Plata');
      expect(Exports.rows(l, l.txs, spanish: false).firstWhere((List<String> r) => r.last == out.id)[6], 'Payment made outside Plata');
      expect(row[15], 'outside');
      expect(Exports.csv(l, l.txs), contains('Pago hecho fuera de Plata'));
      final Period month = Period(DateTime(2026, 12), DateTime(2027));
      expect(l.totals(month).incomeMinor, 0);
      expect(l.totals(month).expenseMinor, 0);
      expect(l.byCategory(month, kind: CategoryKind.income), isEmpty);
      // Sin categoría, pero no es un movimiento por categorizar.
      expect(l.search(const TxFilter(onlyUncategorized: true)), isNot(contains(out)));
      l.dispose();
    });

    test('se edita y se borra como cualquier movimiento', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, nov15);
      final Tx out = l.outsidePayments(tc, nov15).single;
      l.updateTx(Tx.fromJson(out.toJson())..amountMinor = pesos(60000));
      expect(l.outsidePayment(tc, nov15), pesos(60000));
      expect(december(l), pesos(1240000));
      await l.deleteTx(out.id);
      expect(december(l), pesos(1300000));
      // Borrarlo es decir que no se pagó: el extracto deja de estar marcado.
      expect(l.isStatementPaid(tc, nov15), isFalse);
      expect(l.cardDue(tc).overdueMinor, pesos(100000));
      l.dispose();
    });

    test('«Cambiar monto» cambia lo pagado fuera; en cero borra el movimiento y deja la marca', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, nov15);
      l.setOutsidePayment(tc, nov15, pesos(40000));
      expect(l.outsidePayments(tc, nov15).single.amountMinor, pesos(40000));
      expect(december(l), pesos(1260000));
      l.setOutsidePayment(tc, nov15, pesos(1000000));
      expect(december(l), pesos(300000));
      l.setOutsidePayment(tc, nov15, 0);
      expect(l.outsidePayments(tc, nov15), isEmpty);
      expect(l.isStatementPaid(tc, nov15), isTrue);
      expect(december(l), pesos(1300000));
      l.dispose();
    });

    test('«Desmarcar» borra el movimiento', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, nov15);
      l.markStatementPaid(tc, nov15, paid: false);
      expect(l.txs.where((Tx t) => t.isOutsidePayment), isEmpty);
      expect(l.isStatementPaid(tc, nov15), isFalse);
      expect(debt(l), pesos(1300000));
      l.dispose();
    });

    test('un pago hecho fuera convertido en transferencia desde una cuenta deja de serlo y sigue vinculado', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, nov15);
      final Tx out = l.outsidePayments(tc, nov15).single;
      final Tx draft = Tx.fromJson(out.toJson())
        ..kind = TxKind.transfer
        ..accountId = 'bank'
        ..toAccountId = 'tc'
        ..source = 'manual';
      l.updateTx(draft);
      expect(l.outsidePayments(tc, nov15), isEmpty);
      expect(l.linkedPayments(tc, nov15), pesos(100000));
      expect(l.isStatementPaid(tc, nov15), isTrue);
      expect(december(l), pesos(1200000));
      l.dispose();
    });
  });

  group('G1: un abono sin vínculo después de «Ya lo pagué» (con la regla de la ronda 12)', () {
    test('caso A1: el aviso del banco del 7 dic, confirmado el 9: queda provisional y «Sí, es ese pago» lo confirma', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, nov15);
      today = d(2026, 12, 9);
      final Tx t = await pay(l, pesos(100000), d(2026, 12, 7));
      // Mientras no se contesta, cuenta una sola vez.
      expect(t.outsidePending, isTrue);
      expect(t.statementOf, '2026-11-15');
      expect(l.pendingOutsideMatches(card: tc), <Tx>[t]);
      expect(debt(l), pesos(1200000));
      l.answerOutsideMatch(t, same: true);
      expect(byId(l, t.id).outsidePending, isFalse);
      expect(byId(l, t.id).statementOf, '2026-11-15');
      expect(l.outsidePayments(tc, nov15), isEmpty);
      expect(l.isStatementPaid(tc, nov15), isTrue);
      expect(december(l), pesos(1200000));
      expect(debt(l), pesos(1200000));
      expect(l.cardDue(tc, now: DateTime(2026, 12, 9)).next.dueMinor, pesos(1200000));
      expect(l.pendingOutsideMatches(), isEmpty);
      l.dispose();
    });

    test('caso A1: «Es otro pago» lo deja aparte, devuelve lo de fuera y no vuelve a preguntar', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, nov15);
      final Tx t = await pay(l, pesos(100000), d(2026, 12, 9));
      l.answerOutsideMatch(t, same: false);
      final Tx kept = byId(l, t.id);
      expect(kept.statementOf, isNull);
      expect(kept.outsidePending, isFalse);
      expect(kept.apartFrom, <String>['2026-11-15']);
      expect(l.outsideCandidate(kept), isNull);
      expect(l.pendingOutsideMatches(), isEmpty);
      expect(l.outsidePayment(tc, nov15), pesos(100000));
      // Pagó 200.000 en total: 100.000 fuera y este.
      expect(december(l), pesos(1100000));
      // Se guarda (y se lee la forma de la ronda 11, un texto).
      expect(Tx.fromJson(kept.toJson()).apartFrom, <String>['2026-11-15']);
      expect(Tx.fromJson(kept.toJson()..['apartFrom'] = '2026-11-15').apartFrom, <String>['2026-11-15']);
      // Editarlo no vuelve a preguntar.
      l.updateTx(Tx.fromJson(kept.toJson())..description = 'Quincena');
      expect(byId(l, t.id).outsidePending, isFalse);
      expect(december(l), pesos(1100000));
      l.dispose();
    });

    test('caso A1b: «Abonar a la tarjeta» el mismo día de la marca también queda provisional', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, nov15);
      final Tx t = await pay(l, pesos(100000), d(2026, 12, 8));
      expect(l.pendingOutsideCut(t), nov15);
      l.answerOutsideMatch(t, same: true);
      expect(december(l), pesos(1200000));
      l.dispose();
    });

    test('un abono mayor que lo de fuera lo reemplaza y el resto baja la deuda', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, nov15);
      final Tx t = await pay(l, pesos(250000), d(2026, 12, 9));
      l.answerOutsideMatch(t, same: true);
      expect(l.outsidePayments(tc, nov15), isEmpty);
      expect(december(l), pesos(1050000));
      l.dispose();
    });

    test('regla sin ventana de días: B2 (19 dic) y meses después preguntan si cabe; N2 y las devoluciones no', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, nov15);
      final Tx refund = await l.addTx(Tx(id: 'r', kind: TxKind.income, amountMinor: pesos(30000), accountId: 'tc', categoryId: 'c_food', date: d(2026, 12, 9)));
      expect(refund.outsidePending, isFalse);
      // Antes del corte y más que lo de fuera: es de otro extracto.
      expect(l.outsideCandidate(Tx(id: 'x1', kind: TxKind.transfer, amountMinor: pesos(150000), accountId: 'bank', toAccountId: 'tc', date: d(2026, 11, 14))), isNull);
      // B2: el 19 dic con la fecha que propone el editor.
      today = d(2026, 12, 19);
      expect(l.outsideCandidate(Tx(id: 'x2', kind: TxKind.transfer, amountMinor: pesos(100000), accountId: 'bank', toAccountId: 'tc', date: d(2026, 12, 19))), nov15);
      // N2: el pago de 1.200.000 del extracto del 15 dic, el 16 dic.
      expect(l.outsideCandidate(Tx(id: 'x3', kind: TxKind.transfer, amountMinor: pesos(1200000), accountId: 'bank', toAccountId: 'tc', date: d(2026, 12, 16))), isNull);
      // Antes del corte siguiente, cualquier monto.
      expect(l.outsideCandidate(Tx(id: 'x4', kind: TxKind.transfer, amountMinor: pesos(1200000), accountId: 'bank', toAccountId: 'tc', date: d(2026, 12, 14))), nov15);
      // Meses después: si cabe en lo de fuera, sí; si no, no.
      today = d(2027, 3, 1);
      expect(l.outsideCandidate(Tx(id: 'x5', kind: TxKind.transfer, amountMinor: pesos(100000), accountId: 'bank', toAccountId: 'tc', date: d(2027, 3, 1))), nov15);
      expect(l.outsideCandidate(Tx(id: 'x6', kind: TxKind.transfer, amountMinor: pesos(300000), accountId: 'bank', toAccountId: 'tc', date: d(2027, 3, 1))), isNull);
      l.dispose();
    });

    test('caso A4: un pago vinculado corregido de 30.000 a 100.000 reemplaza lo de fuera en lo que subió', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, nov15);
      final Tx t = await pay(l, pesos(30000), d(2026, 12, 7), statement: nov15);
      expect(l.outsidePayment(tc, nov15), pesos(70000));
      l.updateTx(Tx.fromJson(t.toJson())..amountMinor = pesos(100000));
      expect(l.outsidePayment(tc, nov15), 0);
      expect(l.isStatementPaid(tc, nov15), isTrue);
      expect(december(l), pesos(1200000));
      // Bajarlo otra vez no inventa un pago de fuera: la deuda sube.
      l.updateTx(Tx.fromJson(byId(l, t.id).toJson())..amountMinor = pesos(80000));
      expect(l.outsidePayment(tc, nov15), 0);
      expect(december(l), pesos(1220000));
      l.dispose();
    });

    test('editar un abono provisional lo deja provisional con lo que toma recalculado; borrarlo devuelve lo de fuera', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, nov15);
      final Tx t = await pay(l, pesos(100000), d(2026, 12, 9));
      expect(december(l), pesos(1200000));
      l.updateTx(Tx.fromJson(t.toJson())..amountMinor = pesos(60000));
      expect(byId(l, t.id).outsidePending, isTrue);
      expect(l.outsidePayment(tc, nov15), pesos(40000));
      expect(december(l), pesos(1200000));
      await l.deleteTx(t.id);
      expect(l.outsidePayment(tc, nov15), pesos(100000));
      expect(december(l), pesos(1200000));
      l.dispose();
    });

    test('caso A5: registrado desde la fila y borrado: la deuda vuelve a 1.300.000 y queda la marca', () async {
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, nov15);
      final Tx t = await pay(l, pesos(100000), d(2026, 12, 7), statement: nov15);
      expect(l.outsidePayments(tc, nov15), isEmpty);
      await l.deleteTx(t.id);
      expect(december(l), pesos(1300000));
      expect(l.isStatementPaid(tc, nov15), isTrue);
      expect(l.cardDue(tc).overdue, isFalse);
      l.dispose();
    });
  });

  test('G3, caso A2: 27 marcas mensuales, cada una baja la deuda en lo que faltaba (sin tope)', () async {
    today = d(2025, 1, 1);
    final Ledger l = await newLedger();
    final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
    final DateTime start = DateTime(2025, 1, 15);
    for (int k = 0; k < 30; k++) {
      final DateTime cut = CardCycle.cutAfter(tc, start, k);
      await buy(l, pesos(200000), d(cut.year, cut.month, cut.day - 5));
    }
    final Set<int> drops = <int>{};
    for (int k = 0; k < 27; k++) {
      final DateTime cut = CardCycle.cutAfter(tc, start, k);
      final DateTime due = l.effectivePayDate(tc, CardCycle.current(tc, cut).payDate);
      today = d(due.year, due.month, due.day);
      l.setStatementMinimum(tc, cut, pesos(50000));
      final int before = debt(l);
      expect(l.markStatementPaid(tc, cut), isTrue, reason: '$cut');
      drops.add(before - debt(l));
    }
    expect(drops, <int>{pesos(50000)});
    expect(l.txs.where((Tx t) => t.isOutsidePayment), hasLength(27));
    expect(l.cardDue(tc).next.dueMinor, pesos(4250000));
    // Guardado y vuelto a abrir: siguen los 27.
    await l.flush();
    final Ledger again = await reopen(l);
    expect(again.txs.where((Tx t) => t.isOutsidePayment), hasLength(27));
    again.dispose();
    l.dispose();
  });

  group('G4: extractos de antes de que la tarjeta empezara en Plata', () {
    Future<Ledger> a3() async {
      today = d(2026, 11, 28);
      final Ledger l = await newLedger();
      final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, initialMinor: -pesos(910000), cutDay: 10, payDay: 30));
      l.setStatementMinimum(tc, DateTime(2026, 11, 10), pesos(90000));
      return l;
    }

    test('caso A3: con deuda inicial, «Ya lo pagué» pregunta; «Lo pagué antes» solo marca', () async {
      final Ledger l = await a3();
      final Account tc = l.account('tc')!;
      expect(l.markKind(tc, DateTime(2026, 11, 10)), MarkKind.ask);
      l.markStatementPaid(tc, DateTime(2026, 11, 10), payment: false);
      expect(debt(l), pesos(910000));
      expect(l.isStatementPaid(tc, DateTime(2026, 11, 10)), isTrue);
      expect(l.txs.where((Tx t) => t.isOutsidePayment), isEmpty);
      l.dispose();
    });

    test('caso A3: «Lo pagué después» es un pago: la deuda baja a 820.000', () async {
      final Ledger l = await a3();
      final Account tc = l.account('tc')!;
      l.markStatementPaid(tc, DateTime(2026, 11, 10), payment: true);
      expect(debt(l), pesos(820000));
      expect(l.outsidePayment(tc, DateTime(2026, 11, 10)), pesos(90000));
      l.dispose();
    });

    test('sin deuda inicial, un extracto de antes del primer movimiento solo se marca', () async {
      today = d(2026, 12, 8);
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      l.setStatementMinimum(tc, DateTime(2026, 9, 15), pesos(20000));
      expect(l.markKind(tc, DateTime(2026, 9, 15)), MarkKind.markOnly);
      l.markStatementPaid(tc, DateTime(2026, 9, 15));
      expect(l.isStatementPaid(tc, DateTime(2026, 9, 15)), isTrue);
      expect(debt(l), pesos(1300000));
      l.dispose();
    });

    test('el mínimo pendiente anotado al crear la tarjeta, pagado después, es un pago', () async {
      today = d(2026, 11, 2);
      final Ledger l = await newLedger();
      final Account draft = Account(id: 'tc', name: 'Visa', type: AccountType.credit, initialMinor: -pesos(3550000), cutDay: 15, payDay: 5)..statementDueMinor = pesos(450000);
      draft.statementCut = l.referenceStatementCut(draft);
      final Account tc = await l.addAccount(draft);
      expect(l.markKind(tc, DateTime(2026, 10, 15)), MarkKind.payment);
      l.markStatementPaid(tc, DateTime(2026, 10, 15));
      expect(debt(l), pesos(3100000));
      l.dispose();
    });
  });

  group('G2: al cambiar el corte, los datos de un extracto se mueven juntos', () {
    test('caso A6: corte 10 → 25 y pago 30 → 10 después de marcar: mínimo y pago de fuera juntos, sin «Vencido» falso', () async {
      today = d(2026, 11, 12);
      final Ledger l = await newLedger();
      final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 10, payDay: 30));
      await buy(l, pesos(600000), d(2026, 10, 1));
      await buy(l, pesos(300000), d(2026, 10, 28));
      await buy(l, pesos(200000), d(2026, 11, 20));
      l.setStatementMinimum(tc, DateTime(2026, 11, 10), pesos(90000));
      today = d(2026, 12, 1);
      expect(l.cardDue(tc).overdueMinor, pesos(90000));
      l.markStatementPaid(tc, DateTime(2026, 11, 10));
      today = d(2026, 12, 3);
      tc.cutDay = 25;
      tc.payDay = 10;
      l.moveCardCut(tc, 10, oldPayDay: 30);
      expect(tc.statementMinimums.keys.single, '2026-10-25');
      expect(l.outsidePayments(tc, DateTime(2026, 10, 25)).single.statementOf, '2026-10-25');
      expect(l.cardDue(tc).overdue, isFalse);
      expect(l.isStatementPaid(tc, DateTime(2026, 11, 25)), isFalse);
      // El 11 dic el extracto del 25 nov sigue sin pagar: aviso, no «al día».
      expect(l.cardDue(tc, now: DateTime(2026, 12, 11)).unconfirmedMinor, pesos(1010000));
      expect(debt(l), pesos(1010000));
      l.dispose();
    });

    test('caso split22: corte 5 → 9 después de marcar: ningún «Vencido» del extracto del 9 oct en 45 días', () async {
      today = d(2026, 11, 6);
      final Ledger l = await newLedger();
      final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 5, payDay: 8));
      await buy(l, pesos(300000), d(2026, 8, 10));
      await buy(l, pesos(200000), d(2026, 9, 9));
      await buy(l, pesos(500000), d(2026, 10, 9));
      l.setStatementMinimum(tc, DateTime(2026, 11, 5), pesos(90000));
      today = d(2026, 11, 10);
      expect(l.cardDue(tc).overdueMinor, pesos(90000));
      l.markStatementPaid(tc, DateTime(2026, 11, 5));
      today = d(2026, 11, 28);
      tc.cutDay = 9;
      l.moveCardCut(tc, 5, oldPayDay: 8);
      expect(tc.statementMinimums.keys.single, '2026-10-09');
      expect(l.outsidePayments(tc, DateTime(2026, 10, 9)).single.statementOf, '2026-10-09');
      expect(l.isStatementPaid(tc, DateTime(2026, 11, 9)), isFalse);
      final List<String> bad = <String>[];
      for (int k = 0; k < 45; k++) {
        final DateTime day = DateTime(2026, 11, 28 + k);
        final CardDue due = l.cardDue(tc, now: day);
        if (due.overdue && due.statementCut == DateTime(2026, 10, 9)) {
          bad.add(dayKey(day));
        }
      }
      expect(bad, isEmpty);
      l.dispose();
    });

    test('el choque se pregunta por cada extracto nuevo y los pagos de fuera de los dos quedan juntos', () async {
      today = d(2026, 11, 12);
      final Ledger l = await newLedger();
      final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 10, payDay: 30));
      await buy(l, pesos(900000), d(2026, 9, 20));
      tc.statementMinimums['2026-10-10'] = pesos(70000);
      tc.minimumsOn['2026-10-10'] = '2026-10-20';
      tc.statementMinimums['2026-11-10'] = pesos(90000);
      tc.minimumsOn['2026-11-10'] = '2026-11-12';
      final Map<DateTime, List<DateTime>> clash = l.cutMoveConflicts(tc, 15);
      expect(clash.keys, <DateTime>[DateTime(2026, 10, 15)]);
      expect(clash[DateTime(2026, 10, 15)], <DateTime>[DateTime(2026, 10, 10), DateTime(2026, 11, 10)]);
      tc.cutDay = 15;
      l.moveCardCut(tc, 10, keep: <DateTime, DateTime>{DateTime(2026, 10, 15): DateTime(2026, 10, 10)});
      expect(tc.statementMinimums, <String, int>{'2026-10-15': pesos(70000)});
      l.dispose();
    });
  });

  group('migración', () {
    test('una marca vieja sin monto pasa a ser un movimiento una sola vez', () async {
      today = d(2026, 12, 20);
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      tc.paidStatements.add('2026-11-15');
      await pay(l, pesos(40000), d(2026, 12, 1));
      await pay(l, pesos(30000), d(2026, 12, 9));
      await l.flush();
      final Ledger again = await reopen(l);
      final Account back = again.account('tc')!;
      expect(back.paidStatements, isEmpty);
      expect(again.outsidePayment(back, nov15), pesos(60000));
      expect(again.statement(back, date: dec15).dueMinor, pesos(1170000));
      again.save();
      await again.flush();
      final Ledger third = await reopen(again);
      expect(third.txs.where((Tx t) => t.isOutsidePayment), hasLength(1));
      third.dispose();
      again.dispose();
      l.dispose();
    });

    test('un pago de fuera guardado aparte (ronda 10) pasa a ser un movimiento con su monto y su día', () async {
      today = d(2026, 12, 20);
      final Ledger l = await n1();
      final Account tc = l.account('tc')!;
      // Lo que guardaba la versión anterior: el pago de fuera aparte.
      tc.outsidePayments.add(OutsidePayment(statement: '2026-11-15', amountMinor: pesos(70000), on: '2026-12-08'));
      l.save();
      await l.flush();
      final Ledger again = await reopen(l);
      final Account back = again.account('tc')!;
      expect(back.outsidePayments, isEmpty);
      final Tx out = again.outsidePayments(back, nov15).single;
      expect(out.amountMinor, pesos(70000));
      expect(dateOnly(out.date), DateTime(2026, 12, 8));
      expect(again.statement(back, date: dec15).dueMinor, pesos(1230000));
      again.save();
      await again.flush();
      final Ledger third = await reopen(again);
      expect(third.txs.where((Tx t) => t.isOutsidePayment), hasLength(1));
      third.dispose();
      again.dispose();
      l.dispose();
    });

    test('un pago de fuera de un extracto de antes de la tarjeta queda solo como marca', () async {
      today = d(2026, 11, 28);
      final Ledger l = await newLedger();
      final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, initialMinor: -pesos(910000), cutDay: 10, payDay: 30));
      l.setStatementMinimum(tc, DateTime(2026, 11, 10), pesos(90000));
      tc.outsidePayments.add(OutsidePayment(statement: '2026-11-10', amountMinor: pesos(90000), on: '2026-11-28'));
      l.save();
      await l.flush();
      final Ledger again = await reopen(l);
      final Account back = again.account('tc')!;
      expect(again.txs.where((Tx t) => t.isOutsidePayment), isEmpty);
      expect(again.isStatementPaid(back, DateTime(2026, 11, 10)), isTrue);
      expect(-again.balanceMinor('tc', before: DateTime(2040)), pesos(910000));
      again.dispose();
      l.dispose();
    });

    test('M2: el formato sube a la versión 2 y una versión más nueva no se abre', () async {
      final Ledger l = await n1();
      expect(LedgerSnapshot.currentVersion, 2);
      expect(l.toJson()['version'], 2);
      final Map<String, dynamic> json = jsonDecode(jsonEncode(l.toJson())) as Map<String, dynamic>;
      expect(LedgerSnapshot.parse(json).accounts, isNotEmpty);
      expect(() => LedgerSnapshot.parse(Map<String, dynamic>.from(json)..['version'] = 3), throwsFormatException);
      l.dispose();
    });
  });
  // Las propiedades P1, P6, P8 y P9 al azar, con la verdad llevada aparte, están
  // en round11_test.dart.
}
