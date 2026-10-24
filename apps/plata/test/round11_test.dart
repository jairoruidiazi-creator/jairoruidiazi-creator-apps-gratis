// Undécima ronda de la auditoría (G1-bis y M1 a M4 del Árbitro, g1bis.py,
// m_edit.py y azar11.py): la pregunta «¿Es el pago del extracto…?» sale por
// todos los caminos, sin ventana de días. El libro decide en un solo sitio
// (`addTx`, `updateTx`, `applyTemplate`, `processScheduled`): un abono sin
// vínculo que puede ser el pago hecho fuera de Plata de un extracto marcado
// se toma provisionalmente por ese pago (cuenta una sola vez) y la pregunta
// queda pendiente hasta que se conteste: enseguida en los caminos con
// pantalla, en Inicio y en Tarjetas en los automáticos.
//
// Los valores esperados están escritos a mano en cada caso. La propiedad al
// azar lleva la verdad aparte (cada pago real) y contesta con la verdad: no
// la define la respuesta de la app.

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

/// Un pago real que la persona hizo (lo que de verdad pasó).
class _Pay {
  _Pay(this.amount, this.cut, {required this.plata});

  final int amount;
  String cut;
  final bool plata;
  bool logged = false;
  String? txId;
  String? outId;
}

void main() {
  late Directory tmp;
  DateTime today = d(2026, 12, 8);
  int ids = 0;

  setUp(() async {
    today = d(2026, 12, 8);
    tmp = await Directory.systemTemp.createTemp('plata_r11');
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
  int december(Ledger l) => l.statement(l.account('tc')!, date: dec15).dueMinor;

  /// El caso del Árbitro: compras de 1.000.000 (20 oct) y 300.000 (20 nov),
  /// mínimo de 100.000 del extracto del 15 nov (vence el lun 7 dic). Paga
  /// 100.000 el 7 dic desde ahorros y el 8 dic toca «Ya lo pagué». Hay
  /// además el extracto del 15 oct (100.000) pagado el 5 nov: el pago del
  /// mes pasado, para «Duplicar hoy».
  Future<Ledger> base() async {
    today = d(2026, 12, 8);
    final Ledger l = await newLedger();
    final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
    await buy(l, pesos(100000), d(2026, 9, 20));
    await l.addTx(Tx(id: 'prev', kind: TxKind.transfer, amountMinor: pesos(100000), accountId: 'bank', toAccountId: 'tc', date: d(2026, 11, 5), description: 'Pago Visa'));
    await buy(l, pesos(1000000), d(2026, 10, 20));
    await buy(l, pesos(300000), d(2026, 11, 20));
    l.setStatementMinimum(tc, nov15, pesos(100000));
    expect(l.cardDue(tc).overdueMinor, pesos(100000));
    l.markStatementPaid(tc, nov15);
    expect(debt(l), pesos(1200000));
    return l;
  }

  group('G1-bis: la pregunta llega por todos los caminos, el 8 y el 19 dic', () {
    for (final DateTime day in <DateTime>[d(2026, 12, 8), d(2026, 12, 19)]) {
      final Map<String, Future<Tx> Function(Ledger l)> paths = <String, Future<Tx> Function(Ledger l)>{
        'editor (botón +, «Abonar a la tarjeta», aviso confirmado)': (Ledger l) => l.addTx(transfer(pesos(100000), day)),
        'favorito de un toque': (Ledger l) async {
          final TxTemplate tpl = await l.addTemplate(TxTemplate(id: 'tpl', name: 'Pago Visa', kind: TxKind.transfer, amountMinor: pesos(100000), accountId: 'bank', toAccountId: 'tc'));
          return (await l.applyTemplate(tpl, date: day))!;
        },
        '«Anotar ahora» de un programado': (Ledger l) async {
          final Scheduled s = await l.addScheduled(Scheduled(id: 's', name: 'Pago Visa', kind: TxKind.transfer, amountMinor: pesos(100000), accountId: 'bank', toAccountId: 'tc', nextDate: DateTime(2027, 1, 5), autoPost: false));
          return l.postScheduled(s, date: day);
        },
        '«Duplicar hoy» del pago del mes pasado': (Ledger l) => l.duplicateTx(l.txs.firstWhere((Tx t) => t.id == 'prev'), date: day),
        'programado automático': (Ledger l) async {
          await l.addScheduled(Scheduled(id: 'a', name: 'Pago Visa', kind: TxKind.transfer, amountMinor: pesos(100000), accountId: 'bank', toAccountId: 'tc', nextDate: day));
          return l.processScheduled(now: day).single;
        },
        'aviso del banco anotado sin pantalla': (Ledger l) async {
          final InboxItem item = InboxItem(id: 'n', bank: 'bancolombia', kind: TxKind.income, amountMinor: pesos(100000), receivedAt: day, accountId: 'tc', merchant: 'Abono tarjeta');
          l.inbox.add(item);
          return (await l.acceptInbox(item))!;
        },
      };
      for (final MapEntry<String, Future<Tx> Function(Ledger l)> path in paths.entries) {
        test('${path.key}, el ${day.day} dic: cuenta una sola vez (1.200.000) y pregunta; «Sí» lo confirma', () async {
          final Ledger l = await base();
          today = day;
          final Tx t = await path.value(l);
          final Tx stored = l.txs.firstWhere((Tx x) => x.id == t.id);
          expect(stored.outsidePending, isTrue, reason: 'pregunta pendiente');
          expect(l.pendingOutsideCut(stored), nov15);
          expect(l.pendingOutsideMatches(), <Tx>[stored]);
          expect(debt(l), pesos(1200000));
          expect(december(l), pesos(1200000));
          // La persona contesta con la verdad: es ese pago.
          l.answerOutsideMatch(stored, same: true);
          expect(l.pendingOutsideMatches(), isEmpty);
          expect(debt(l), pesos(1200000));
          expect(december(l), pesos(1200000));
          expect(l.isStatementPaid(l.account('tc')!, nov15), isTrue);
          l.dispose();
        });
      }
    }

    test('B2 con «Es otro pago» (pagó dos veces de verdad): 1.100.000', () async {
      final Ledger l = await base();
      today = d(2026, 12, 19);
      final Tx t = await l.addTx(transfer(pesos(100000), d(2026, 12, 19)));
      l.answerOutsideMatch(t, same: false);
      expect(debt(l), pesos(1100000));
      expect(december(l), pesos(1100000));
      l.dispose();
    });

    test('un programado automático sin contestar sigue contando una sola vez meses después', () async {
      final Ledger l = await base();
      await l.addScheduled(Scheduled(id: 'a', name: 'Pago Visa', kind: TxKind.transfer, amountMinor: pesos(100000), accountId: 'bank', toAccountId: 'tc', nextDate: d(2026, 12, 9)));
      l.processScheduled(now: d(2026, 12, 9));
      for (final DateTime day in <DateTime>[d(2027, 1, 10), d(2027, 2, 16), d(2027, 6, 1)]) {
        today = day;
        expect(l.pendingOutsideMatches(), hasLength(1), reason: '$day');
        expect(debt(l), pesos(1200000), reason: '$day');
      }
      l.dispose();
    });

    test('N2 / M4: el pago del extracto siguiente (1.200.000 el 16 dic) no pregunta', () async {
      final Ledger l = await base();
      today = d(2026, 12, 16);
      final Tx t = await l.addTx(transfer(pesos(1200000), d(2026, 12, 16)));
      expect(t.outsidePending, isFalse);
      expect(t.statementOf, isNull);
      expect(debt(l), 0);
      l.dispose();
    });

    test('«Es otro pago» de un abono provisional devuelve lo de fuera y la deuda baja', () async {
      final Ledger l = await base();
      today = d(2026, 12, 9);
      await l.addScheduled(Scheduled(id: 'a', name: 'Pago Visa', kind: TxKind.transfer, amountMinor: pesos(100000), accountId: 'bank', toAccountId: 'tc', nextDate: d(2026, 12, 9)));
      final Tx t = l.processScheduled(now: d(2026, 12, 9)).single;
      expect(debt(l), pesos(1200000));
      l.answerOutsideMatch(t, same: false);
      expect(l.outsidePayment(l.account('tc')!, nov15), pesos(100000));
      expect(debt(l), pesos(1100000));
      l.dispose();
    });

    test('borrar un abono provisional (o «Deshacer» del favorito) devuelve lo de fuera', () async {
      final Ledger l = await base();
      final Tx t = await l.addTx(transfer(pesos(100000), d(2026, 12, 8)));
      await l.deleteTx(t.id);
      expect(l.outsidePayment(l.account('tc')!, nov15), pesos(100000));
      expect(debt(l), pesos(1200000));
      l.dispose();
    });

    test('un abono confirmado le quita a uno provisional lo que tomó, y «Es otro» del provisional ya no devuelve nada', () async {
      final Ledger l = await base();
      final Account tc = l.account('tc')!;
      // Un abono automático de 60.000 que es otro pago (sin contestar)…
      await l.addScheduled(Scheduled(id: 'a', name: 'Abono', kind: TxKind.transfer, amountMinor: pesos(60000), accountId: 'bank', toAccountId: 'tc', nextDate: d(2026, 12, 8)));
      final Tx other = l.processScheduled(now: d(2026, 12, 8)).single;
      expect(l.outsidePayment(tc, nov15), pesos(40000));
      // …y el pago de verdad, registrado desde la fila.
      await l.addTx(transfer(pesos(100000), d(2026, 12, 7))..statementOf = '2026-11-15');
      expect(l.outsidePayment(tc, nov15), 0);
      l.answerOutsideMatch(other, same: false);
      expect(l.outsidePayment(tc, nov15), 0);
      // Pagó 100.000 (el del 7 dic) y 60.000 aparte.
      expect(debt(l), pesos(1140000));
      l.dispose();
    });

    test('«Desmarcar» suelta los abonos provisionales: son abonos aparte', () async {
      final Ledger l = await base();
      final Account tc = l.account('tc')!;
      final Tx t = await l.addTx(transfer(pesos(100000), d(2026, 12, 8)));
      l.markStatementPaid(tc, nov15, paid: false);
      final Tx stored = l.txs.firstWhere((Tx x) => x.id == t.id);
      expect(stored.outsidePending, isFalse);
      expect(stored.statementOf, isNull);
      expect(debt(l), pesos(1200000));
      expect(l.pendingOutsideMatches(), isEmpty);
      l.dispose();
    });

    test('el aviso de pago de la tarjeta recuerda el abono por confirmar', () async {
      final Ledger l = await base();
      await l.addTx(transfer(pesos(100000), d(2026, 12, 8)));
      final NoopNotifier n = NoopNotifier();
      await Reminders.sync(ledger: l, settings: AppSettings()..billReminders = true, notifier: n, now: d(2026, 12, 8, 8));
      expect(n.pending.values.where((String e) => e.contains('Pago de Visa') && e.contains('Tienes un abono por confirmar en Plata')), isNotEmpty);
      l.dispose();
    });
  });

  test('M1 (m_edit): un abono anotado antes de marcar ya contó en lo que faltaba: no se pregunta por él', () async {
    today = d(2026, 12, 1);
    final Ledger l = await newLedger();
    final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
    await buy(l, pesos(1000000), d(2026, 10, 20));
    await buy(l, pesos(300000), d(2026, 11, 20));
    l.setStatementMinimum(tc, nov15, pesos(100000));
    final Tx p = await l.addTx(transfer(pesos(50000), d(2026, 12, 1)));
    today = d(2026, 12, 8);
    expect(l.cardDue(tc).overdueMinor, pesos(50000));
    l.markStatementPaid(tc, nov15);
    expect(p.apartFrom, <String>['2026-11-15']);
    expect(l.outsideCandidate(p), isNull);
    expect(l.pendingOutsideMatches(), isEmpty);
    // Editarlo (la descripción) no pregunta ni cambia nada.
    today = d(2026, 12, 10);
    l.updateTx(Tx.fromJson(p.toJson())..description = 'Abono');
    expect(l.pendingOutsideMatches(), isEmpty);
    expect(debt(l), pesos(1200000));
    l.dispose();
  });

  test('M4: el nombre del pago de fuera se genera en el idioma actual; los guardados con texto fijo se limpian al abrir', () async {
    final Ledger l = await base();
    final Account tc = l.account('tc')!;
    final Tx out = l.outsidePayments(tc, nov15).single;
    expect(out.description, isEmpty);
    expect(Ledger.shownDescription(out, spanish: false), 'Payment made outside Plata');
    // Uno de la ronda 11, con el nombre guardado en inglés.
    out.description = 'Payment made outside Plata';
    l.save();
    await l.flush();
    final Ledger again = Ledger(l.store, clock: () => today);
    await again.load();
    final Tx back = again.outsidePayments(again.account('tc')!, nov15).single;
    expect(back.description, isEmpty);
    expect(Ledger.shownDescription(back, spanish: true), 'Pago hecho fuera de Plata');
    // Una descripción propia se respeta.
    back.description = 'Pagado en el cajero';
    expect(Ledger.shownDescription(back, spanish: true), 'Pagado en el cajero');
    again.dispose();
    l.dispose();
  });

  // Secuencias al azar como azar11.py del Árbitro. La verdad se lleva aparte:
  // cada pago real (monto, si salió de una cuenta de Plata, de qué extracto
  // es) y si un abono es dinero nuevo. La persona contesta siempre con la
  // verdad; los caminos automáticos dejan la pregunta pendiente y la persona
  // la contesta al abrir la app (si la abre). Después de cada paso:
  // - P1: deuda = lo que queda del estado de cuenta a futuro + deuda aparte;
  // - P6: ningún pago de fuera en un extracto que no había cerrado su día;
  // - P8: la deuda de Plata nunca es menor que la real;
  // - P9: nunca mayor que la real, salvo lo documentado: subir un pago
  //   vinculado reemplaza lo de fuera (A4) y un abono provisional que en
  //   verdad es otro pago, mientras su pregunta está pendiente.
  for (final Map<String, Object> config in <Map<String, Object>>[
    <String, Object>{'name': 'base', 'auto': 0.15, 'visit': 0.5, 'today': 0.5},
    <String, Object>{'name': 'siempre con pantalla y la fecha de hoy', 'auto': 0.0, 'visit': 0.5, 'today': 1.0},
    <String, Object>{'name': 'siempre automático y nunca abre la app', 'auto': 1.0, 'visit': 0.0, 'today': 0.5},
  ]) {
    test('propiedades P1, P6, P8 y P9 al azar con la verdad aparte (${config['name']})', () async {
      final double autoP = config['auto']! as double;
      final double visitP = config['visit']! as double;
      final double todayP = config['today']! as double;
      final List<String> failures = <String>[];
      int outsideSeen = 0;
      int answered = 0;
      for (int seed = 0; seed < 60 && failures.length < 10; seed++) {
        final Random rnd = Random(500 + seed);
        today = d(2026, 3, 1);
        final Ledger l = await newLedger();
        final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 1 + rnd.nextInt(28), payDay: 1 + rnd.nextInt(28)));
        int real = 0;
        int documented = 0;
        final List<_Pay> pays = <_Pay>[];
        final Set<String> others = <String>{};
        bool truthSame(Tx t, DateTime k) {
          final Iterable<_Pay> p = pays.where((_Pay x) => x.txId == t.id);
          return p.isNotEmpty && p.first.cut == dayKey(k) && !others.contains(t.id);
        }

        void settle(String id) {
          for (int i = 0; i < 12; i++) {
            final Iterable<Tx> found = l.txs.where((Tx x) => x.id == id && x.outsidePending);
            if (found.isEmpty) {
              return;
            }
            answered += 1;
            l.answerOutsideMatch(found.first, same: truthSame(found.first, l.pendingOutsideCut(found.first)!));
          }
        }

        DateTime effDue(DateTime cut) => l.effectivePayDate(tc, CardCycle.current(tc, cut).payDate);
        const List<String> ops = <String>['compra', 'compra', 'compra', 'compra', 'abono', 'abono', 'abono', 'devolución', 'paga y marca', 'paga y marca', 'paga y marca', 'anotar', 'anotar', 'anotar', 'visita', 'visita', 'registrar', 'cambiar', 'corte', 'mínimo', 'editar abono'];
        for (int i = 0; i < 45; i++) {
          today = d(today.year, today.month, today.day + 1 + rnd.nextInt(9));
          final DateTime now = dateOnly(today);
          final DateTime lc = CardCycle.current(tc, now).previous(tc).cut;
          final String op = ops[rnd.nextInt(ops.length)];
          if (op == 'compra') {
            final int a = pesos(50000 * (1 + rnd.nextInt(8)));
            await buy(l, a, d(now.year, now.month, now.day - rnd.nextInt(4)));
            real += a;
          } else if (op == 'devolución') {
            final int a = pesos(20000 * (1 + rnd.nextInt(3)));
            ids += 1;
            await l.addTx(Tx(id: 'r$ids', kind: TxKind.income, amountMinor: a, accountId: 'tc', categoryId: 'c_food', date: today));
            real -= a;
          } else if (op == 'abono') {
            // Dinero nuevo desde una cuenta de Plata.
            final int a = pesos(20000 * (1 + rnd.nextInt(6)));
            final Tx t = await l.addTx(transfer(a, d(now.year, now.month, now.day - rnd.nextInt(3))));
            others.add(t.id);
            real -= a;
            if (rnd.nextDouble() >= autoP) {
              settle(t.id);
            }
          } else if (op == 'mínimo') {
            if (!tc.statementMinimums.containsKey(dayKey(lc))) {
              l.setStatementMinimum(tc, lc, pesos(30000 * (1 + rnd.nextInt(5))));
            }
          } else if (op == 'paga y marca') {
            // Pagó lo que faltaba (desde Plata sin anotarlo, o desde otro
            // banco) y toca «Ya lo pagué».
            final CardDue due = l.cardDue(tc);
            DateTime? k = due.overdueMinor > 0 ? due.statementCut : null;
            if (k == null && tc.statementMinimums.containsKey(dayKey(lc)) && !l.isStatementPaid(tc, lc) && (l.statementMissing(tc, lc) ?? 0) > 0) {
              k = lc;
            }
            if (k != null && !l.isStatementPaid(tc, k)) {
              final int miss = l.statementMissing(tc, k) ?? 0;
              if (miss > 0 && l.markKind(tc, k) == MarkKind.payment) {
                real -= miss;
                l.markStatementPaid(tc, k);
                final _Pay p = _Pay(miss, dayKey(k), plata: rnd.nextDouble() < 0.6);
                p.outId = l.outsidePayments(tc, k).last.id;
                pays.add(p);
              }
            }
          } else if (op == 'anotar') {
            // Anota después un pago real que salió de una cuenta de Plata.
            final List<_Pay> cand = pays.where((_Pay p) => p.plata && !p.logged).toList();
            if (cand.isNotEmpty) {
              final _Pay p = cand[rnd.nextInt(cand.length)];
              p.logged = true;
              final DateTime k = DateTime.parse(p.cut);
              final DateTime real0 = effDue(k).isAfter(now) ? now : effDue(k);
              final DateTime date = rnd.nextDouble() < todayP || !real0.isAfter(k) ? now : real0;
              final Tx t = await l.addTx(transfer(p.amount, d(date.year, date.month, date.day)));
              p.txId = t.id;
              if (rnd.nextDouble() >= autoP) {
                settle(t.id);
              }
            }
          } else if (op == 'visita') {
            if (rnd.nextDouble() < visitP) {
              for (final Tx t in l.pendingOutsideMatches()) {
                settle(t.id);
              }
            }
          } else if (op == 'registrar') {
            final List<_Pay> cand = pays.where((_Pay p) => p.plata && !p.logged).toList();
            if (cand.isNotEmpty) {
              final _Pay p = cand[rnd.nextInt(cand.length)];
              final Iterable<Tx> out = l.txs.where((Tx x) => x.id == p.outId);
              if (out.isNotEmpty) {
                final DateTime k = CardCycle.current(tc, DateTime.parse(out.first.statementOf!)).cut;
                p.logged = true;
                final DateTime on = effDue(k).isAfter(now) ? now : effDue(k);
                final Tx t = await l.addTx(transfer(out.first.amountMinor, d(on.year, on.month, on.day))..statementOf = dayKey(k));
                p.txId = t.id;
              }
            }
          } else if (op == 'cambiar') {
            // «Cambiar monto»: pagó fuera de verdad más (otro pago real).
            final List<Tx> outs = l.txs.where((Tx t) => t.isOutsidePayment).toList();
            if (outs.isNotEmpty) {
              final DateTime k = CardCycle.current(tc, DateTime.parse(outs[rnd.nextInt(outs.length)].statementOf!)).cut;
              final int extra = pesos(10000 * (1 + rnd.nextInt(5)));
              real -= extra;
              l.setOutsidePayment(tc, k, l.outsidePayment(tc, k) + extra);
            }
          } else if (op == 'editar abono') {
            // Corrige hacia arriba un abono vinculado: pagó más desde Plata.
            final List<Tx> linked = l.txs.where((Tx t) => t.statementOf != null && !t.isOutsidePayment && t.toAccountId == 'tc').toList();
            if (linked.isNotEmpty) {
              final Tx t = linked[rnd.nextInt(linked.length)];
              final int add = pesos(10000 * (1 + rnd.nextInt(3)));
              final DateTime k = CardCycle.current(tc, DateTime.parse(t.statementOf!)).cut;
              if (!t.outsidePending || truthSame(t, k)) {
                // Documentado (A4): subir un pago vinculado reemplaza lo de fuera.
                final int held = l.pendingOutsideMatches(card: tc, cut: k).where((Tx o) => o.id != t.id).fold<int>(0, (int a, Tx o) => a + (o.outsideTaken ?? 0));
                final int room = l.outsidePayment(tc, k) + held;
                documented += add < room ? add : room;
              }
              l.updateTx(Tx.fromJson(t.toJson())..amountMinor = t.amountMinor + add);
              real -= add;
            }
          } else {
            final int old = tc.cutDay!;
            final int oldPay = tc.payDay!;
            final int next = 1 + rnd.nextInt(28);
            if (next != old) {
              final Map<String, String> moves = l.cutMoves(tc, next, oldPayDay: oldPay);
              for (final _Pay p in pays) {
                p.cut = moves[p.cut] ?? p.cut;
              }
            }
            tc.cutDay = next;
            if (rnd.nextInt(10) < 3) {
              tc.payDay = 1 + rnd.nextInt(28);
            }
            l.moveCardCut(tc, old, oldPayDay: oldPay);
          }
          final String at = 'semilla $seed, paso $i ($op, hoy ${dayKey(now)}, corte ${tc.cutDay}, pago ${tc.payDay})';
          final CardStatement far = l.statement(tc, date: DateTime(2032));
          final int plata = debt(l);
          if (plata != far.balanceMinor + far.legacyMinor) {
            failures.add('$at: P1 deuda ${plata ~/ 100} ≠ estado ${far.balanceMinor ~/ 100} + aparte ${far.legacyMinor ~/ 100}');
          }
          for (final Tx o in l.txs.where((Tx t) => t.isOutsidePayment)) {
            if (!CardCycle.current(tc, DateTime.parse(o.statementOf!)).cut.isBefore(dateOnly(o.date))) {
              failures.add('$at: P6 pago de fuera en el extracto ${o.statementOf}, del ${dayKey(o.date)}');
            }
          }
          if (plata < real) {
            failures.add('$at: P8 deuda de Plata ${plata ~/ 100} < real ${real ~/ 100}');
          }
          final int pendingOther = l.pendingOutsideMatches().where((Tx t) => !truthSame(t, l.pendingOutsideCut(t)!)).fold<int>(0, (int a, Tx t) => a + (t.outsideTaken ?? 0));
          if (plata > real + documented + pendingOther) {
            failures.add('$at: P9 deuda de Plata ${plata ~/ 100} > real ${real ~/ 100} + documentado ${documented ~/ 100} + pendiente que es otro ${pendingOther ~/ 100}');
          }
        }
        outsideSeen += l.txs.where((Tx t) => t.isOutsidePayment).length;
        l.dispose();
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
      expect(outsideSeen, greaterThan(10));
      if (autoP < 1 || visitP > 0) {
        expect(answered, greaterThan(5));
      }
    });
  }
}
