// Duodécima ronda de la auditoría (s12.py y uso12.py del Árbitro): la regla
// de la pregunta «¿Es el pago del extracto…?» es acotada y predecible. Un
// solo candidato (el extracto marcado más reciente), solo si el abono se
// anotó entre la marca y la fecha límite real del extracto siguiente, y no
// si hay un extracto más nuevo sin pagar; sin cadena; un abono pendiente
// nunca causa «Vencido»; editar sin cambiar el monto, la cuenta ni la fecha
// no vuelve a preguntar; y el remedio «Ya lo anoté en Plata» para quien anota
// después de la ventana.
//
// Los valores esperados están escritos a mano en cada caso.

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
    tmp = await Directory.systemTemp.createTemp('plata_r12');
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
  DateTime plus(DateTime x, int days) => DateTime(x.year, x.month, x.day + days, 12);

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

  /// Caso T1: nueve extractos (ene a sep) pagados desde otro banco y
  /// marcados; el del 15 oct, con su mínimo anotado, sin pagar.
  Future<Ledger> t1() async {
    today = d(2026, 1, 1);
    final Ledger l = await newLedger();
    final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
    for (int m = 1; m <= 10; m++) {
      final DateTime k = DateTime(2026, m, 15);
      await buy(l, pesos(300000), plus(k, -5));
      today = plus(k, 3);
      l.setStatementMinimum(tc, k, pesos(100000));
      if (m < 10) {
        today = plus(k, 18);
        l.markStatementPaid(tc, k);
      }
    }
    return l;
  }

  test('T1: el pago del extracto del 15 oct desde una cuenta de Plata no pregunta por ningún extracto marcado', () async {
    final Ledger l = await t1();
    final Account tc = l.account('tc')!;
    expect(l.txs.where((Tx t) => t.isOutsidePayment), hasLength(9));
    today = d(2026, 11, 3);
    final int before = debt(l);
    final Tx t = await l.addTx(transfer(pesos(100000), today));
    expect(t.outsidePending, isFalse);
    expect(l.pendingOutsideMatches(), isEmpty);
    expect(debt(l), before - pesos(100000));
    final CardDue due = l.cardDue(tc, now: DateTime(2026, 11, 6));
    expect(due.overdue, isFalse);
    l.dispose();
  });

  test('T1b: lo mismo con el programado automático: ni pregunta, ni deuda de más, ni «Vencido»', () async {
    final Ledger l = await t1();
    final Account tc = l.account('tc')!;
    today = d(2026, 11, 3);
    final int before = debt(l);
    await l.addScheduled(Scheduled(id: 'a', name: 'Pago Visa', kind: TxKind.transfer, amountMinor: pesos(100000), accountId: 'bank', toAccountId: 'tc', nextDate: d(2026, 11, 3)));
    final Tx t = l.processScheduled(now: d(2026, 11, 3)).single;
    expect(t.outsidePending, isFalse);
    expect(debt(l), before - pesos(100000));
    today = d(2026, 11, 6);
    expect(l.cardDue(tc).overdue, isFalse);
    l.dispose();
  });

  test('T2: una sola marca (15 mar) y el programado mensual de 100.000: ningún mes pregunta ni da «Vencido»', () async {
    today = d(2026, 1, 1);
    final Ledger l = await newLedger();
    final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
    int asked = 0;
    final List<String> overdue = <String>[];
    for (int m = 1; m <= 12; m++) {
      final DateTime k = DateTime(2026, m, 15);
      await buy(l, pesos(250000), plus(k, -6));
      today = plus(k, 2);
      l.setStatementMinimum(tc, k, pesos(100000));
      if (m == 3) {
        today = plus(k, 19);
        l.markStatementPaid(tc, k);
        continue;
      }
      today = d(2026, m + 1, 2);
      final Tx t = await l.addTx(transfer(pesos(100000), today));
      if (t.outsidePending) {
        asked += 1;
      }
      if (l.cardDue(tc, now: d(2026, m + 1, 8)).overdue) {
        overdue.add('$m');
      }
    }
    expect(asked, 0);
    expect(overdue, isEmpty);
    l.dispose();
  });

  test('un abono pendiente cuenta para el mínimo de su extracto natural: sin «Vencido» ni notificación de mora', () async {
    final Ledger l = await base();
    final Account tc = l.account('tc')!;
    // El 19 dic llega el programado automático (el 15 dic aún sin mínimo).
    today = d(2026, 12, 19);
    await l.addScheduled(Scheduled(id: 'a', name: 'Pago Visa', kind: TxKind.transfer, amountMinor: pesos(100000), accountId: 'bank', toAccountId: 'tc', nextDate: d(2026, 12, 19)));
    final Tx t = l.processScheduled(now: d(2026, 12, 19)).single;
    expect(t.outsidePending, isTrue);
    // Después se anota el mínimo del 15 dic; nadie contesta la pregunta.
    today = d(2026, 12, 20);
    l.setStatementMinimum(tc, dec15, pesos(100000));
    expect(l.statementMissing(tc, dec15), 0);
    final CardDue due = l.cardDue(tc, now: DateTime(2027, 1, 7));
    expect(due.overdue, isFalse);
    // Para la deuda cuenta una sola vez, tomado por el pago de fuera.
    expect(debt(l), pesos(1200000));
    l.dispose();
  });

  test('sin cadena: «Es otro pago» termina, no pregunta por otro extracto marcado', () async {
    final Ledger l = await base();
    final Account tc = l.account('tc')!;
    // Otro extracto marcado, más viejo, con pago de fuera.
    await buy(l, pesos(200000), d(2026, 9, 20));
    l.setStatementMinimum(tc, DateTime(2026, 10, 15), pesos(50000));
    l.markStatementPaid(tc, DateTime(2026, 10, 15));
    expect(l.txs.where((Tx t) => t.isOutsidePayment), hasLength(2));
    final Tx t = await l.addTx(transfer(pesos(50000), d(2026, 12, 9)));
    expect(l.pendingOutsideCut(t), nov15);
    l.answerOutsideMatch(t, same: false);
    final Tx stored = l.txs.firstWhere((Tx x) => x.id == t.id);
    expect(stored.outsidePending, isFalse);
    expect(stored.statementOf, isNull);
    expect(l.pendingOutsideMatches(), isEmpty);
    l.dispose();
  });

  test('T3: «Cambiar monto» a 0 suelta el provisional; «Es otro pago» ya no crea un pago de fuera', () async {
    final Ledger l = await base();
    final Account tc = l.account('tc')!;
    today = d(2026, 12, 9);
    await l.addScheduled(Scheduled(id: 'a', name: 'Abono', kind: TxKind.transfer, amountMinor: pesos(40000), accountId: 'bank', toAccountId: 'tc', nextDate: d(2026, 12, 9)));
    final Tx t = l.processScheduled(now: d(2026, 12, 9)).single;
    expect(t.outsideTaken, pesos(40000));
    l.setOutsidePayment(tc, nov15, 0);
    expect(l.txs.firstWhere((Tx x) => x.id == t.id).outsidePending, isFalse);
    l.answerOutsideMatch(t, same: false);
    expect(l.outsidePayment(tc, nov15), 0);
    // No pagó nada fuera y abonó 40.000.
    expect(debt(l), pesos(1260000));
    l.dispose();
  });

  test('T3b: borrar el pago de fuera suelta el provisional y no vuelve a marcar', () async {
    final Ledger l = await base();
    final Account tc = l.account('tc')!;
    today = d(2026, 12, 9);
    await l.addScheduled(Scheduled(id: 'a', name: 'Abono', kind: TxKind.transfer, amountMinor: pesos(40000), accountId: 'bank', toAccountId: 'tc', nextDate: d(2026, 12, 9)));
    final Tx t = l.processScheduled(now: d(2026, 12, 9)).single;
    await l.deleteTx(l.outsidePayments(tc, nov15).single.id);
    expect(l.isStatementPaid(tc, nov15), isFalse);
    expect(l.txs.firstWhere((Tx x) => x.id == t.id).outsidePending, isFalse);
    l.answerOutsideMatch(t, same: false);
    expect(l.isStatementPaid(tc, nov15), isFalse);
    expect(l.outsidePayment(tc, nov15), 0);
    expect(debt(l), pesos(1260000));
    l.dispose();
  });

  test('M2: «Deshacer» del favorito después de «Sí, es ese pago» devuelve lo pagado fuera', () async {
    final Ledger l = await base();
    final Account tc = l.account('tc')!;
    final TxTemplate tpl = await l.addTemplate(TxTemplate(id: 'tpl', name: 'Pago Visa', kind: TxKind.transfer, amountMinor: pesos(100000), accountId: 'bank', toAccountId: 'tc'));
    final Tx t = (await l.applyTemplate(tpl))!;
    l.answerOutsideMatch(t, same: true);
    expect(l.outsidePayment(tc, nov15), 0);
    await l.deleteTx(t.id, restoreOutside: true);
    expect(l.outsidePayment(tc, nov15), pesos(100000));
    expect(debt(l), pesos(1200000));
    l.dispose();
  });

  test('el caso del 19 dic de la ronda 11 sigue preguntando', () async {
    final Ledger l = await base();
    today = d(2026, 12, 19);
    final Tx t = await l.addTx(transfer(pesos(100000), today));
    expect(l.pendingOutsideCut(t), nov15);
    expect(debt(l), pesos(1200000));
    l.dispose();
  });

  test('remedio: anotado después de la ventana no pregunta; «Ya lo anoté en Plata» lo vincula y reemplaza lo de fuera', () async {
    final Ledger l = await base();
    final Account tc = l.account('tc')!;
    // El pago del 7 dic, anotado el 10 ene (después del mar 5 ene).
    today = d(2027, 1, 10);
    final Tx t = await l.addTx(transfer(pesos(100000), d(2026, 12, 7)));
    expect(t.outsidePending, isFalse);
    expect(debt(l), pesos(1100000));
    expect(l.unlinkedCreditsAfter(tc, nov15).map((Tx x) => x.id), contains(t.id));
    l.linkToStatement(t, nov15);
    final Tx stored = l.txs.firstWhere((Tx x) => x.id == t.id);
    expect(stored.statementOf, '2026-11-15');
    expect(l.outsidePayment(tc, nov15), 0);
    expect(l.isStatementPaid(tc, nov15), isTrue);
    expect(debt(l), pesos(1200000));
    l.dispose();
  });

  test('editar sin cambiar el monto, la cuenta ni la fecha no vuelve a preguntar; cambiar el monto sí lo revisa', () async {
    final Ledger l = await base();
    today = d(2026, 12, 9);
    final Tx t = await l.addTx(transfer(pesos(100000), today));
    l.answerOutsideMatch(t, same: false);
    // «Es otro pago» deja apartFrom: ni siquiera cambiando el monto pregunta.
    l.updateTx(Tx.fromJson(l.txs.firstWhere((Tx x) => x.id == t.id).toJson())..description = 'Quincena');
    expect(l.pendingOutsideMatches(), isEmpty);
    // Un abono anotado después de la ventana: editar la nota no pregunta.
    today = d(2027, 1, 10);
    final Tx late = await l.addTx(transfer(pesos(100000), d(2026, 12, 10)));
    l.updateTx(Tx.fromJson(late.toJson())..notes = 'pago');
    expect(l.pendingOutsideMatches(), isEmpty);
    l.dispose();
  });

  for (final bool noted in <bool>[true, false]) {
    test('uso mensual con un pago fijo desde ahorros (mínimo ${noted ? 'anotado' : 'sin anotar'}): sin marcas nunca pregunta; con una marca, a lo sumo una vez', () async {
      for (final int? markMonth in <int?>[null, 5]) {
        today = d(2025, 1, 1);
        final Ledger l = await newLedger();
        final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
        int asked = 0;
        int overdue = 0;
        for (int i = 0; i < 24; i++) {
          final DateTime k = DateTime(2025 + i ~/ 12, 1 + i % 12, 15);
          await buy(l, pesos(400000), plus(k, -8));
          today = plus(k, 2);
          if (noted || i == markMonth) {
            l.setStatementMinimum(tc, k, pesos(150000));
          }
          if (i == markMonth) {
            today = DateTime(k.year, k.month + 1, 3, 12);
            l.markStatementPaid(tc, k);
            continue;
          }
          today = DateTime(k.year, k.month + 1, 2, 12);
          final Tx t = await l.addTx(transfer(pesos(150000), today));
          if (t.outsidePending) {
            asked += 1;
            l.answerOutsideMatch(t, same: false);
          }
          if (l.cardDue(tc, now: DateTime(k.year, k.month + 1, 8)).overdue) {
            overdue += 1;
          }
        }
        expect(asked, markMonth == null ? 0 : lessThanOrEqualTo(1), reason: 'marca en el mes $markMonth');
        expect(overdue, 0, reason: 'marca en el mes $markMonth');
        l.dispose();
      }
    });
  }
}
