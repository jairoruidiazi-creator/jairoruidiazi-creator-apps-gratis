// Quinta ronda de la auditoría: el mínimo que ya se pagó (G1, los dos
// caminos de minimo_sim5), los festivos de Colombia y la fecha límite corrida
// (M2), el programado que queda retenido por un aviso confirmado (M1) y la
// notificación prudente con «Ya lo pagué».

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plata/core/crypto_store.dart';
import 'package:plata/core/holidays.dart';
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
  group('M2: festivos de Colombia', () {
    List<String> days(int year) => (ColombianHolidays.of(year).toList()..sort()).map((DateTime x) => '${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}').toList();

    test('Pascua', () {
      expect(ColombianHolidays.easter(2024), DateTime(2024, 3, 31));
      expect(ColombianHolidays.easter(2025), DateTime(2025, 4, 20));
      expect(ColombianHolidays.easter(2026), DateTime(2026, 4, 5));
      expect(ColombianHolidays.easter(2027), DateTime(2027, 3, 28));
    });

    test('2024, 2025 y 2026, como los calendarios publicados', () {
      expect(days(2024), <String>['01-01', '01-08', '03-25', '03-28', '03-29', '05-01', '05-13', '06-03', '06-10', '07-01', '07-20', '08-07', '08-19', '10-14', '11-04', '11-11', '12-08', '12-25']);
      // En 2025 San Pedro y el Sagrado Corazón caen el mismo lunes, 30 de junio.
      expect(days(2025), <String>['01-01', '01-06', '03-24', '04-17', '04-18', '05-01', '06-02', '06-23', '06-30', '07-20', '08-07', '08-18', '10-13', '11-03', '11-17', '12-08', '12-25']);
      // 2026 trae la Virgen de Chiquinquirá (9 jul, corrida al lunes 13).
      expect(days(2026), <String>['01-01', '01-12', '03-23', '04-02', '04-03', '05-01', '05-18', '06-08', '06-15', '06-29', '07-13', '07-20', '08-07', '08-17', '10-12', '11-02', '11-16', '12-08', '12-25']);
    });

    test('siguiente día hábil: sábados, domingos y festivos', () {
      expect(ColombianHolidays.nextBusinessDay(DateTime(2026, 12, 5)), DateTime(2026, 12, 7)); // sábado
      expect(ColombianHolidays.nextBusinessDay(DateTime(2026, 11, 1)), DateTime(2026, 11, 3)); // domingo y lunes festivo
      expect(ColombianHolidays.nextBusinessDay(DateTime(2026, 12, 8)), DateTime(2026, 12, 9)); // martes festivo
      expect(ColombianHolidays.nextBusinessDay(DateTime(2026, 4, 2)), DateTime(2026, 4, 6)); // Jueves y Viernes Santo
      expect(ColombianHolidays.nextBusinessDay(DateTime(2026, 11, 5)), DateTime(2026, 11, 5)); // jueves hábil
    });
  });

  group('con un libro', () {
    late Directory tmp;
    late Ledger l;
    DateTime today = d(2026, 10, 18);

    setUp(() async {
      today = d(2026, 10, 18);
      tmp = await Directory.systemTemp.createTemp('plata_r5');
      l = Ledger(EncryptedStore(JsonStore(root: tmp), await CryptoBox.fromKeyStore(MemoryKeyStore())), clock: () => today);
      await l.load();
      await l.addAccount(Account(id: 'bank', name: 'Ahorros', type: AccountType.bank, initialMinor: 2000000000));
    });

    tearDown(() async {
      l.dispose();
      await tmp.delete(recursive: true);
    });

    Future<List<String>> mora(DateTime now, {NoopNotifier? notifier}) async {
      final NoopNotifier n = notifier ?? NoopNotifier();
      await Reminders.sync(ledger: l, settings: AppSettings()..billReminders = true, notifier: n, now: now);
      return n.shown;
    }

    test('G1, camino a: crear la tarjeta después de pagar el mínimo y contestar «Sí, ya lo pagué»', () async {
      // El editor guarda 0: de ese extracto no vence nada.
      final Account tc = Account(id: 'tc', name: 'Visa', type: AccountType.credit, initialMinor: -355000000, cutDay: 15, payDay: 5)..statementDueMinor = 0;
      tc.statementCut = l.referenceStatementCut(tc);
      await l.addAccount(tc);
      expect(l.nextPayment(tc, now: DateTime(2026, 11, 1)).dueMinor, 0);
      final CardDue nov6 = l.cardDue(tc, now: DateTime(2026, 11, 6));
      expect(nov6.overdue, isFalse);
      expect(nov6.unconfirmed, isFalse);
      expect(await mora(DateTime(2026, 11, 6, 8)), isEmpty);
    });

    test('G1, camino a con el mínimo anotado y marcado como pagado: ni próximo pago ni mora', () async {
      final Account tc = Account(id: 'tc', name: 'Visa', type: AccountType.credit, initialMinor: -355000000, cutDay: 15, payDay: 5)..statementDueMinor = 45000000;
      tc.statementCut = l.referenceStatementCut(tc);
      await l.addAccount(tc);
      l.markStatementPaid(tc, DateTime(2026, 10, 15));
      expect(l.nextPayment(tc, now: DateTime(2026, 11, 1)).cycle.payDate, DateTime(2026, 12, 5));
      // El mínimo marcado como pagado ya no se arrastra al extracto siguiente.
      expect(l.nextPayment(tc, now: DateTime(2026, 11, 1)).dueMinor, 0);
      expect(l.cardDue(tc, now: DateTime(2026, 11, 6)).overdue, isFalse);
      expect(await mora(DateTime(2026, 11, 6, 8)), isEmpty);
      // Se guarda con la tarjeta.
      await l.flush();
      final Ledger again = Ledger(l.store, clock: () => today);
      await again.load();
      expect(again.isStatementPaid(again.account('tc')!, DateTime(2026, 10, 15)), isTrue);
      again.dispose();
    });

    test('G1, camino b: pago hecho en el banco sin anotar; «Pagué solo el mínimo» no enciende la mora', () async {
      final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
      await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 50000000, accountId: 'tc', date: d(2026, 10, 20)));
      // El 5 dic 2026 es sábado: la fecha real es el lunes 7.
      final CardDue info = l.cardDue(tc, now: DateTime(2026, 12, 8));
      expect(info.unconfirmedMinor, 50000000);
      expect(info.overdue, isFalse);
      // «Pagué solo el mínimo: anotarlo» anota el mínimo ya pagado.
      l.setStatementMinimum(tc, DateTime(2026, 11, 15), 5000000);
      l.markStatementPaid(tc, DateTime(2026, 11, 15));
      final CardDue after = l.cardDue(tc, now: DateTime(2026, 12, 8));
      expect(after.overdue, isFalse);
      expect(after.unconfirmed, isFalse);
      expect(await mora(DateTime(2026, 12, 8, 8)), isEmpty);
      // Si contestó «Todavía no» y no paga, la mora sí es real.
      l.markStatementPaid(tc, DateTime(2026, 11, 15), paid: false);
      expect(l.cardDue(tc, now: DateTime(2026, 12, 8)).overdueMinor, 5000000);
    });

    test('M2: con la fecha límite en sábado, no hay mora el domingo; el lunes hábil es el último día', () async {
      final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
      await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 50000000, accountId: 'tc', date: d(2026, 10, 20)));
      l.setStatementMinimum(tc, DateTime(2026, 11, 15), 5000000);
      expect(l.effectivePayDate(tc, DateTime(2026, 12, 5)), DateTime(2026, 12, 7));
      for (final DateTime day in <DateTime>[DateTime(2026, 12, 6), DateTime(2026, 12, 7)]) {
        final CardDue due = l.cardDue(tc, now: day);
        expect(due.overdue, isFalse, reason: '$day');
        expect(due.next.cycle.cut, DateTime(2026, 11, 15), reason: '$day');
      }
      expect(await mora(DateTime(2026, 12, 6, 8)), isEmpty);
      final CardDue tue = l.cardDue(tc, now: DateTime(2026, 12, 8));
      expect(tue.overdueSince, DateTime(2026, 12, 7));
      // La notificación es prudente y trae «Ya lo pagué», con el extracto.
      final NoopNotifier n = NoopNotifier();
      expect(await mora(DateTime(2026, 12, 8, 8), notifier: n), <String>['Revisa el pago de Visa']);
      expect(n.log.last, contains('Según lo anotado en Plata'));
      final int id = n.payloads.keys.single;
      expect(n.payloads[id], 'o:tc:2026-11-15');
      expect(n.withPaidButton, contains(id));
      // Una tarjeta en dólares de un libro en dólares no usa los festivos de Colombia.
      l.rates.rates['USD'] = 4000;
      l.changeBaseCurrency('USD');
      final Account usd = await l.addAccount(Account(id: 'tcu', name: 'Visa USD', type: AccountType.credit, currency: 'USD', cutDay: 15, payDay: 5));
      expect(l.effectivePayDate(usd, DateTime(2026, 12, 5)), DateTime(2026, 12, 5));
    });

    test('M1: el aviso confirmado avanza el programado, y los meses siguientes se anotan solos', () async {
      await l.addAccount(Account(id: 'ah', name: 'Ahorros', type: AccountType.bank, bank: 'bancolombia', last4: '7310'));
      final Scheduled s = await l.addScheduled(Scheduled(id: 'net', name: 'Internet', kind: TxKind.expense, amountMinor: 9000000, accountId: 'ah', nextDate: DateTime(2026, 11, 5)));
      final NoticeService svc = NoticeService(bridge: FakeNoticeBridge(), ledger: l, settings: AppSettings()..noticesEnabled = true);
      await svc.handle(RawNotice(package: bancolombia, title: 'Bancolombia', text: r'Bancolombia: Pagaste $90.000 a CLARO HOGAR desde tu cuenta *7310.', time: d(2026, 11, 4, 10)));
      l.processScheduled(now: DateTime(2026, 11, 5));
      final Tx confirmed = (await l.acceptInbox(l.pendingInbox.single, accountId: 'ah'))!;
      expect(confirmed.scheduledId, 'net');
      expect(s.nextDate, DateTime(2026, 12, 5));
      // Diciembre y enero sin aviso: se anotan solos.
      l.processScheduled(now: DateTime(2027, 1, 6));
      expect(l.txs.where((Tx t) => t.amountMinor == 9000000), hasLength(3));
      expect(s.nextDate, DateTime(2027, 2, 5));
    });

    test('M1 (H2): con «Anotar sin preguntar» y cuenta segura, los avisos de cada mes no dejan el programado atrás', () async {
      await l.addAccount(Account(id: 'ah', name: 'Ahorros', type: AccountType.bank, bank: 'bancolombia', last4: '7310'));
      final Scheduled s = await l.addScheduled(Scheduled(id: 'net', name: 'Internet', kind: TxKind.expense, amountMinor: 9000000, accountId: 'ah', nextDate: DateTime(2026, 11, 5)));
      final NoticeService svc = NoticeService(bridge: FakeNoticeBridge(), ledger: l, settings: AppSettings()
        ..noticesEnabled = true
        ..noticesAutoPost = true);
      // El aviso del 4 nov llega marcado como posible duplicado del programado
      // y queda para confirmar; al confirmarlo, el programado avanza.
      await svc.handle(RawNotice(package: bancolombia, title: 'Bancolombia', text: r'Bancolombia: Pagaste $90.000 a CLARO HOGAR desde tu cuenta *7310.', time: d(2026, 11, 4, 10)));
      await l.acceptInbox(l.pendingInbox.single, accountId: 'ah');
      expect(s.nextDate, DateTime(2026, 12, 5));
      l.processScheduled(now: DateTime(2026, 12, 4));
      await svc.handle(RawNotice(package: bancolombia, title: 'Bancolombia', text: r'Bancolombia: Pagaste $90.000 a CLARO HOGAR desde tu cuenta *7310.', time: d(2026, 12, 4, 10)));
      await l.acceptInbox(l.pendingInbox.single, accountId: 'ah');
      l.processScheduled(now: DateTime(2026, 12, 6));
      expect(l.txs.where((Tx t) => t.amountMinor == 9000000), hasLength(2));
      expect(s.nextDate, DateTime(2027, 1, 5));
    });
  });
}
