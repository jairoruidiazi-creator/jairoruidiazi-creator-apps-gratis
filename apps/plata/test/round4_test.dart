// Cuarta ronda de la auditoría: avances a cuotas (G1), la regla general de
// «vencido» solo contra un pago mínimo conocido, el ajuste de saldo fuera del
// próximo pago (M6), duplicados aviso ↔ programado en los dos sentidos (M1),
// varias ocurrencias de cada recordatorio (M2) y la copia previa a restaurar
// (M3).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plata/core/backups.dart';
import 'package:plata/core/crypto_store.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/core/notices.dart';
import 'package:plata/core/notifications.dart';
import 'package:plata/core/reminders.dart';
import 'package:plata/core/settings.dart';
import 'package:plata/core/storage.dart';
import 'package:plata/model/models.dart';

DateTime d(int y, int m, int day, [int h = 12]) => DateTime(y, m, day, h);

const String bancolombia = 'co.com.bancolombia.personas.superapp';

void main() {
  late Directory tmp;
  late Ledger l;
  DateTime today = d(2026, 10, 18);

  setUp(() async {
    today = d(2026, 10, 18);
    tmp = await Directory.systemTemp.createTemp('plata_r4');
    l = Ledger(EncryptedStore(JsonStore(root: tmp), await CryptoBox.fromKeyStore(MemoryKeyStore())), clock: () => today);
    await l.load();
    await l.addAccount(Account(id: 'bank', name: 'Ahorros', type: AccountType.bank, initialMinor: 2000000000));
  });

  tearDown(() async {
    l.dispose();
    await tmp.delete(recursive: true);
  });

  Future<Account> card() => l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
  Tx pay(String id, int minor, DateTime date) => Tx(id: id, kind: TxKind.transfer, amountMinor: minor, accountId: 'bank', toAccountId: 'tc', date: date);
  Future<List<String>> mora(DateTime now) async {
    final NoopNotifier n = NoopNotifier();
    await Reminders.sync(ledger: l, settings: AppSettings()..billReminders = true, notifier: n, now: now);
    return n.shown;
  }

  group('G1: avances a cuotas', () {
    test('el caso del Árbitro: avance de \$ 1.200.000 a 24 cuotas, pagar el mínimo del banco no deja la tarjeta vencida', () async {
      final Account tc = await card();
      final Tx advance = await l.addTx(Tx(id: 'avance', kind: TxKind.transfer, amountMinor: 120000000, accountId: 'tc', toAccountId: 'a_cash', date: d(2026, 10, 20), installments: 24));
      expect(advance.installments, 24);
      // El 20 nov: el próximo pago es la primera cuota, no el avance entero.
      final CardDue nov20 = l.cardDue(tc, now: DateTime(2026, 11, 20));
      expect(nov20.next.cycle.payDate, DateTime(2026, 12, 5));
      expect(nov20.next.advancesMinor, 5000000);
      expect(nov20.next.dueMinor, 5000000);
      // La deuda total sí es el avance entero.
      expect(l.balanceMinor('tc', before: DateTime(2026, 12, 1)), -120000000);
      // El 3 dic paga el mínimo del banco ($ 80.000 = 1/24 + intereses).
      l.setStatementMinimum(tc, DateTime(2026, 11, 15), 8000000);
      await l.addTx(pay('minimo', 8000000, d(2026, 12, 3)));
      final CardDue dec6 = l.cardDue(tc, now: DateTime(2026, 12, 6));
      expect(dec6.overdue, isFalse);
      expect(dec6.unconfirmed, isFalse);
      expect(await mora(DateTime(2026, 12, 6, 8)), isEmpty);
      // Las cuotas que faltan se ven como las de las compras.
      expect(l.remainingInstallments(advance, now: DateTime(2026, 12, 6)), 22);
    });

    test('un avance anotado a 1 cuota (como antes) ya no produce mora falsa: sin mínimo es informativo', () async {
      final Account tc = await card();
      await l.addTx(Tx(id: 'avance', kind: TxKind.transfer, amountMinor: 120000000, accountId: 'tc', toAccountId: 'a_cash', date: d(2026, 10, 20)));
      await l.addTx(pay('minimo', 8000000, d(2026, 12, 3)));
      final CardDue dec6 = l.cardDue(tc, now: DateTime(2026, 12, 6));
      expect(dec6.overdue, isFalse);
      expect(dec6.unconfirmed, isTrue);
      expect(dec6.unconfirmedMinor, 112000000);
      expect(await mora(DateTime(2026, 12, 6, 8)), isEmpty);
      // Con el mínimo del banco anotado y pagado, ni eso.
      l.setStatementMinimum(tc, DateTime(2026, 11, 15), 8000000);
      final CardDue paid = l.cardDue(tc, now: DateTime(2026, 12, 6));
      expect(paid.overdue, isFalse);
      expect(paid.unconfirmed, isFalse);
    });

    test('un avance desde una cuenta que no es tarjeta no lleva cuotas', () async {
      final Tx t = await l.addTx(Tx(id: 'x', kind: TxKind.transfer, amountMinor: 1000, accountId: 'bank', toAccountId: 'a_cash', date: d(2026, 10, 20), installments: 12));
      expect(t.installments, 1);
    });
  });

  group('Regla general: «vencido» solo contra un mínimo conocido', () {
    test('compra a cuotas que llegó por aviso a 1 cuota: sin mínimo no hay mora; con el mínimo pagado, al día', () async {
      final Account tc = await card();
      await l.addTx(Tx(id: 'tv', kind: TxKind.expense, amountMinor: 240000000, accountId: 'tc', date: d(2026, 10, 20), source: 'notice'));
      await l.addTx(pay('minimo', 15000000, d(2026, 12, 2)));
      final CardDue estimate = l.cardDue(tc, now: DateTime(2026, 12, 6));
      expect(estimate.overdue, isFalse);
      expect(estimate.unconfirmedMinor, 225000000);
      expect(await mora(DateTime(2026, 12, 6, 8)), isEmpty);
      l.setStatementMinimum(tc, DateTime(2026, 11, 15), 15000000);
      expect(l.cardDue(tc, now: DateTime(2026, 12, 6)).overdue, isFalse);
    });

    test('el caso que ya funcionaba: con el mínimo anotado y sin pagar, está vencido y avisa una vez', () async {
      final Account tc = await card();
      await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 50000000, accountId: 'tc', date: d(2026, 10, 20)));
      l.setStatementMinimum(tc, DateTime(2026, 11, 15), 5000000);
      // Pagó menos del mínimo después del corte.
      await l.addTx(pay('poco', 2000000, d(2026, 11, 20)));
      final CardDue dec6 = l.cardDue(tc, now: DateTime(2026, 12, 6));
      expect(dec6.overdue, isTrue);
      expect(dec6.overdueMinor, 3000000);
      expect(dec6.overdueSince, DateTime(2026, 12, 5));
      expect(await mora(DateTime(2026, 12, 6, 8)), <String>['Pago vencido: Visa']);
      // Un pago antes del corte ya está en el extracto (el mínimo lo tiene en
      // cuenta): no se suma a lo pagado después del corte.
      await l.addTx(pay('antes', 3000000, d(2026, 11, 10)));
      expect(l.cardDue(tc, now: DateTime(2026, 12, 6)).overdueMinor, 3000000);
      // Pagar de más que el mínimo deja la tarjeta al día.
      await l.addTx(pay('resto', 9000000, d(2026, 12, 7)));
      expect(l.cardDue(tc, now: DateTime(2026, 12, 8)).overdue, isFalse);
    });

    test('un reverso después del corte cuenta como abono; una devolución no crea mora', () async {
      final Account tc = await card();
      await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 50000000, accountId: 'tc', date: d(2026, 10, 20)));
      l.setStatementMinimum(tc, DateTime(2026, 11, 15), 5000000);
      await l.addTx(Tx(id: 'rev', kind: TxKind.income, amountMinor: 50000000, accountId: 'tc', categoryId: 'c_food', date: d(2026, 11, 18)));
      expect(l.cardDue(tc, now: DateTime(2026, 12, 6)).overdue, isFalse);
    });

    test('el mínimo anotado se guarda con la tarjeta', () async {
      final Account tc = await card();
      l.setStatementMinimum(tc, DateTime(2026, 11, 15), 5000000);
      await l.flush();
      final Ledger again = Ledger(l.store, clock: () => today);
      await again.load();
      expect(again.statementMinimum(again.account('tc')!, DateTime(2026, 11, 15)), 5000000);
      again.dispose();
    });
  });

  test('M6: «Ajustar saldo real» en una tarjeta no entra al próximo pago: va a la deuda aparte', () async {
    final Account tc = await card();
    await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 10000000, accountId: 'tc', date: d(2026, 10, 1)));
    // La deuda real es $ 1.100.000: el ajuste sube $ 1.000.000.
    final Tx adj = (await l.adjustBalance(tc, -110000000))!;
    expect(adj.isAdjustment, isTrue);
    expect(l.balanceMinor('tc'), -110000000);
    expect(l.nextPayment(tc).dueMinor, 10000000);
    // El estado siguiente solo trae lo que quedó del anterior: el ajuste no.
    final CardStatement nov = l.statement(tc, date: DateTime(2026, 11, 15));
    expect(nov.previousMinor, 10000000);
    expect(nov.chargesMinor, 0);
    expect(nov.legacyMinor, 100000000);
    expect(l.cardHasAdjustments(tc), isTrue);
    // Pagar lo del extracto deja la tarjeta al día, aunque no se anote el mínimo.
    await l.addTx(pay('p', 10000000, d(2026, 11, 3)));
    final CardDue nov6 = l.cardDue(tc, now: DateTime(2026, 11, 6));
    expect(nov6.overdue, isFalse);
    expect(nov6.unconfirmed, isFalse);
    // Un ajuste hacia abajo baja primero la deuda aparte; lo que sobra queda
    // a favor en el estado (y las líneas siguen sumando).
    today = d(2026, 11, 6);
    await l.adjustBalance(tc, 20000000);
    final CardStatement after = l.statement(tc, date: DateTime(2026, 11, 15));
    expect(after.legacyMinor, 0);
    expect(after.creditMinor, 20000000);
    expect(after.previousMinor + after.chargesMinor - after.paymentsMinor + after.toLegacyMinor, after.balanceMinor);
    // Un ajuste no cuenta como pago contra el mínimo.
    l.setStatementMinimum(tc, DateTime(2026, 10, 15), 30000000);
    expect(l.cardDue(tc, now: DateTime(2026, 11, 7)).overdueMinor, 20000000);
  });

  group('M1: duplicados aviso ↔ programado, en los dos sentidos', () {
    late AppSettings settings;
    late NoticeService svc;

    Future<void> twoBancolombia() async {
      await l.addAccount(Account(id: 'ah1', name: 'Ahorros 1', type: AccountType.bank, bank: 'bancolombia'));
      await l.addAccount(Account(id: 'ah2', name: 'Ahorros 2', type: AccountType.bank, bank: 'bancolombia'));
    }

    setUp(() {
      settings = AppSettings()..noticesEnabled = true;
      svc = NoticeService(bridge: FakeNoticeBridge(), ledger: l, settings: settings);
    });

    int charges() => l.txs.where((Tx t) => t.amountMinor == 9000000).length;

    test('B (de fábrica): el aviso llega el 4 y la app se abre el 4 y el 5: un solo cargo', () async {
      await l.addAccount(Account(id: 'ah', name: 'Ahorros', type: AccountType.bank, bank: 'bancolombia', last4: '7310'));
      final Scheduled s = await l.addScheduled(Scheduled(id: 'net', name: 'Internet', kind: TxKind.expense, amountMinor: 9000000, accountId: 'ah', nextDate: DateTime(2026, 11, 5)));
      await svc.handle(RawNotice(package: bancolombia, title: 'Bancolombia', text: r'Bancolombia: Pagaste $90.000 a CLARO HOGAR desde tu cuenta *7310.', time: d(2026, 11, 4, 10)));
      final InboxItem notice = l.pendingInbox.single;
      expect(notice.duplicateOf, 'programado:net');
      l.processScheduled(now: DateTime(2026, 11, 4));
      l.processScheduled(now: DateTime(2026, 11, 5));
      expect(charges(), 0);
      expect(s.nextDate, DateTime(2026, 11, 5));
      // Al confirmar el aviso queda un cargo, y el programado sigue retenido.
      await l.acceptInbox(notice, accountId: 'ah');
      l.processScheduled(now: DateTime(2026, 11, 6));
      expect(charges(), 1);
      expect(l.noticeDuplicateFor(s), isNotNull);
    });

    test('C: «Anotar sin preguntar» encendido pero con dos cuentas del banco: un solo cargo', () async {
      settings.noticesAutoPost = true;
      await twoBancolombia();
      await l.addScheduled(Scheduled(id: 'net', name: 'Internet', kind: TxKind.expense, amountMinor: 9000000, accountId: 'ah1', nextDate: DateTime(2026, 11, 5)));
      await svc.handle(RawNotice(package: bancolombia, title: 'Bancolombia', text: r'Bancolombia: Pagaste $90.000 a CLARO HOGAR.', time: d(2026, 11, 4, 10)));
      expect(l.pendingInbox.single.accountId, isNull);
      l.processScheduled(now: DateTime(2026, 11, 5));
      expect(charges(), 0);
      expect(l.pendingInbox.single.duplicateOf, isNotNull);
    });

    test('F: el débito llega el 5 a las 6:00 en vivo y la app vuelve a las 9:00: un solo cargo', () async {
      await l.addAccount(Account(id: 'ah', name: 'Ahorros', type: AccountType.bank, bank: 'bancolombia', last4: '7310'));
      await l.addScheduled(Scheduled(id: 'net', name: 'Internet', kind: TxKind.expense, amountMinor: 9000000, accountId: 'ah', nextDate: DateTime(2026, 11, 5)));
      await svc.handle(RawNotice(package: bancolombia, title: 'Bancolombia', text: r'Bancolombia: Pagaste $90.000 a CLARO HOGAR desde tu cuenta *7310.', time: d(2026, 11, 5, 6)));
      l.processScheduled(now: d(2026, 11, 5, 9));
      expect(charges(), 0);
      expect(l.pendingInbox, hasLength(1));
    });

    test('D: el programado se anotó primero; al confirmar el aviso se encuentra el cargo igual', () async {
      await l.addAccount(Account(id: 'ah', name: 'Ahorros', type: AccountType.bank, bank: 'bancolombia', last4: '7310'));
      await l.addScheduled(Scheduled(id: 'net', name: 'Internet', kind: TxKind.expense, amountMinor: 9000000, accountId: 'ah', nextDate: DateTime(2026, 11, 5)));
      l.processScheduled(now: DateTime(2026, 11, 5));
      expect(charges(), 1);
      await svc.handle(RawNotice(package: bancolombia, title: 'Bancolombia', text: r'Bancolombia: Pagaste $90.000 a CLARO HOGAR desde tu cuenta *7310.', time: d(2026, 11, 5, 18)));
      expect(l.pendingInbox.single.duplicateOf, isNotNull);
      final Tx draft = Tx(id: 'nuevo', kind: TxKind.expense, amountMinor: 9000000, accountId: 'ah', date: d(2026, 11, 5, 18));
      expect(l.similarTx(draft), isNotNull);
    });
  });

  test('M2: cada programado y cada tarjeta dejan agendadas varias ocurrencias, sin pasar el tope de iOS', () async {
    final Account tc = await card();
    await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 10000000, accountId: 'tc', date: d(2026, 10, 10)));
    await l.addScheduled(Scheduled(id: 'arr', name: 'Arriendo', kind: TxKind.expense, amountMinor: 150000000, accountId: 'bank', nextDate: DateTime(2026, 11, 1)));
    final NoopNotifier n = NoopNotifier();
    await Reminders.sync(ledger: l, settings: AppSettings()..billReminders = true, notifier: n, now: d(2026, 10, 18, 8));
    for (final String key in <String>['s:arr:2026-11-01', 's:arr:2026-12-01', 's:arr:2027-01-01', 'c:tc:2026-11-05', 'c:tc:2026-12-05', 'c:tc:2027-01-05']) {
      expect(n.pending.keys, contains(Reminders.idFor(key)), reason: key);
    }
    // Los de más adelante no prometen un monto que todavía no se conoce.
    expect(n.pending[Reminders.idFor('c:tc:2026-12-05')], isNot(contains(r'$')));
    // Un programado manual vencido se recuerda los días siguientes.
    await l.addScheduled(Scheduled(id: 'man', name: 'Administración', kind: TxKind.expense, amountMinor: 30000000, accountId: 'bank', nextDate: DateTime(2026, 10, 10), autoPost: false));
    await Reminders.sync(ledger: l, settings: AppSettings()..billReminders = true, notifier: n, now: d(2026, 10, 18, 8));
    expect(n.pending.values.where((String x) => x.contains('Pendiente: Administración')), hasLength(Reminders.overdueReminderDays));
    // Con muchos programados, no más de 60 agendados.
    for (int i = 0; i < 40; i++) {
      await l.addScheduled(Scheduled(id: 'x$i', name: 'Cuota $i', kind: TxKind.expense, amountMinor: 1000, accountId: 'bank', nextDate: DateTime(2026, 11, 2)));
    }
    final NoopNotifier m = NoopNotifier();
    await Reminders.sync(ledger: l, settings: AppSettings()..billReminders = true, notifier: m, now: d(2026, 10, 18, 8));
    expect(m.pending.length, lessThanOrEqualTo(Reminders.maxPlanned));
    expect(tc.payDay, 5);
  });

  test('M3: restaurar dos veces el mismo día no pisa la copia de antes de la primera', () async {
    final JsonStore store = JsonStore(root: tmp);
    final BackupManager bm = BackupManager(store: store, ledger: l, settings: AppSettings());
    await bm.autoBackup(force: true, now: d(2026, 10, 18, 8));
    await l.addTx(Tx(id: 'd', kind: TxKind.expense, amountMinor: 100, accountId: 'bank', date: d(2026, 10, 18)));
    final String? first = await bm.autoBackup(beforeRestore: true, now: d(2026, 10, 18, 9));
    final String? second = await bm.autoBackup(beforeRestore: true, now: d(2026, 10, 18, 9));
    expect(first, isNot(second));
    final List<String> all = await bm.listAutoBackups();
    expect(all, containsAll(<String>[first!, second!, 'backups/plata-2026-10-18.json.enc']));
    expect(((await bm.readAutoBackup(first))!['txs'] as List<dynamic>), hasLength(1));
  });
}
