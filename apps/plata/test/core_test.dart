import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plata/core/backups.dart';
import 'package:plata/core/bank_rules.dart';
import 'package:plata/core/crypto_store.dart';
import 'package:plata/core/exports.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/core/lock.dart';
import 'package:plata/core/notices.dart';
import 'package:plata/core/notifications.dart';
import 'package:plata/core/periods.dart';
import 'package:plata/core/rates.dart';
import 'package:plata/core/reminders.dart';
import 'package:plata/core/settings.dart';
import 'package:plata/core/storage.dart';
import 'package:plata/model/models.dart';
import 'package:plata/model/money.dart';
import 'package:plata/ui/widgets/amount_keypad.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime d(int y, int m, int day, [int h = 12]) => DateTime(y, m, day, h);

Future<Ledger> newLedger(Directory dir, {DateTime Function()? clock}) async {
  final JsonStore store = JsonStore(root: dir);
  final CryptoBox box = await CryptoBox.fromKeyStore(MemoryKeyStore());
  final Ledger l = Ledger(EncryptedStore(store, box), clock: clock ?? () => d(2026, 10, 16));
  await l.load();
  return l;
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('plata_test');
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  group('Dinero', () {
    test('formato colombiano sin centavos y con símbolo', () {
      expect(Money.format(123456700, 'COP'), r'$ 1.234.567');
      expect(Money.format(123456750, 'COP', showCents: true), r'$ 1.234.567,50');
      expect(Money.format(-500000, 'COP'), '−\$ 5.000'); // signo menos tipográfico
      expect(Money.format(123450, 'USD'), r'US$ 1.234,50');
      expect(Money.format(0, 'COP'), r'$ 0');
    });

    test('compacto', () {
      expect(Money.format(150000000, 'COP', compact: true), contains('1,5'));
      expect(Money.format(150000000, 'COP', compact: true), contains('M'));
      expect(Money.format(1230000, 'COP', compact: true), contains('mil'));
    });

    test('parse acepta formatos locales y extranjeros', () {
      expect(Money.parse('45.000'), 4500000);
      expect(Money.parse('45.000,00'), 4500000);
      expect(Money.parse('100,000.00'), 10000000);
      expect(Money.parse('12.5'), 1250);
      expect(Money.parse(r'$ 1.234.567'), 123456700);
      expect(Money.parse('-20'), -2000);
      expect(Money.parse('abc'), isNull);
    });

    test('la calculadora suma, resta y evalúa de izquierda a derecha', () {
      final Calc c = Calc();
      for (final String k in '12000+3000'.split('')) {
        c.press(k);
      }
      expect(c.expression, '12.000 + 3.000');
      c.press('=');
      expect(c.valueMinor, 1500000);
      c.press('−');
      c.press('5');
      c.press('0');
      c.press('0');
      c.press('0');
      expect(c.hasPendingOp, isTrue);
      c.press('=');
      expect(c.valueMinor, 1000000);
      c.press('C');
      expect(c.valueMinor, 0);
      c.press('7');
      c.press(',');
      c.press('5');
      expect(c.valueMinor, 750);
      c.press('⌫');
      c.press('⌫');
      expect(c.valueMinor, 700);
    });
  });

  group('Periodos', () {
    test('mes que empieza el día de pago', () {
      const PeriodSpec spec = PeriodSpec(startDay: 25);
      final Period p = spec.containing(d(2026, 10, 10));
      expect(p.start, DateTime(2026, 9, 25));
      expect(p.end, DateTime(2026, 10, 25));
      expect(spec.containing(d(2026, 10, 25)).start, DateTime(2026, 10, 25));
      expect(spec.shift(p, 1).start, DateTime(2026, 10, 25));
      expect(spec.shift(p, -1).start, DateTime(2026, 8, 25));
      expect(spec.lastN(d(2026, 10, 10), 3).map((Period x) => x.start.month).toList(), <int>[7, 8, 9]);
    });

    test('quincenas', () {
      const PeriodSpec spec = PeriodSpec(mode: PeriodMode.quincena);
      expect(spec.containing(d(2026, 2, 3)).end, DateTime(2026, 2, 16));
      final Period second = spec.containing(d(2026, 2, 20));
      expect(second.start, DateTime(2026, 2, 16));
      expect(second.end, DateTime(2026, 3, 1));
      expect(spec.label(second), '16–28 feb');
      expect(spec.shift(second, 1).start, DateTime(2026, 3, 1));
      expect(spec.shift(second, -1).start, DateTime(2026, 2, 1));
    });

    test('frecuencia quincenal cae el 15 y el último día', () {
      const Frequency f = Frequency(unit: FrequencyUnit.quincena);
      expect(f.next(DateTime(2026, 1, 15)), DateTime(2026, 1, 31));
      expect(f.next(DateTime(2026, 1, 31)), DateTime(2026, 2, 15));
      expect(f.next(DateTime(2026, 2, 15)), DateTime(2026, 2, 28));
      expect(f.next(DateTime(2026, 2, 3)), DateTime(2026, 2, 15));
    });

    test('frecuencia mensual conserva el día ancla en meses cortos', () {
      const Frequency f = Frequency();
      final DateTime anchor = DateTime(2026, 1, 31);
      final DateTime feb = f.next(anchor, anchor: anchor);
      expect(feb, DateTime(2026, 2, 28));
      expect(f.next(feb, anchor: anchor), DateTime(2026, 3, 31));
      expect(const Frequency(every: 3).next(DateTime(2026, 11, 10), anchor: DateTime(2026, 11, 10)), DateTime(2027, 2, 10));
      expect(const Frequency(unit: FrequencyUnit.week, every: 2).next(DateTime(2026, 1, 1)), DateTime(2026, 1, 15));
      expect(const Frequency(unit: FrequencyUnit.year).next(DateTime(2024, 2, 29), anchor: DateTime(2024, 2, 29)), DateTime(2025, 2, 28));
    });

    test('periodos de presupuesto', () {
      final Budget weekly = Budget(id: 'w', name: 'w', amountMinor: 1, period: BudgetPeriod.week, startDate: DateTime(2026, 10, 5));
      expect(BudgetPeriods.containing(weekly, d(2026, 10, 16)).start, DateTime(2026, 10, 12));
      expect(BudgetPeriods.containing(weekly, d(2026, 10, 1)).start, DateTime(2026, 9, 28));
      final Budget monthly = Budget(id: 'm', name: 'm', amountMinor: 1, startDate: DateTime(2026, 1, 20));
      expect(BudgetPeriods.containing(monthly, d(2026, 10, 16)).start, DateTime(2026, 9, 20));
      final Budget yearly = Budget(id: 'y', name: 'y', amountMinor: 1, period: BudgetPeriod.year, startDate: DateTime(2025, 3, 1));
      expect(BudgetPeriods.containing(yearly, d(2026, 2, 10)).start, DateTime(2025, 3, 1));
      expect(BudgetPeriods.containing(yearly, d(2026, 3, 1)).start, DateTime(2026, 3, 1));
      final Budget custom = Budget(id: 'c', name: 'c', amountMinor: 1, period: BudgetPeriod.custom, customDays: 10, startDate: DateTime(2026, 10, 1));
      expect(BudgetPeriods.containing(custom, d(2026, 10, 16)).start, DateTime(2026, 10, 11));
      expect(BudgetPeriods.previous(custom, BudgetPeriods.containing(custom, d(2026, 10, 16))).start, DateTime(2026, 10, 1));
    });

    test('ciclo de tarjeta: corte 15, pago 5', () {
      final Account card = Account(id: 'tc', name: 'TC', type: AccountType.credit, cutDay: 15, payDay: 5);
      final CardCycle c = CardCycle.current(card, d(2026, 10, 16));
      expect(c.start, DateTime(2026, 10, 16));
      expect(c.cut, DateTime(2026, 11, 15));
      expect(c.payDate, DateTime(2026, 12, 5));
      final CardCycle prev = c.previous(card);
      expect(prev.start, DateTime(2026, 9, 16));
      expect(prev.cut, DateTime(2026, 10, 15));
      expect(prev.payDate, DateTime(2026, 11, 5));
      // Corte 31 en febrero se recorta al 28.
      final Account c31 = Account(id: 'x', name: 'x', type: AccountType.credit, cutDay: 31, payDay: 20);
      expect(CardCycle.current(c31, d(2026, 2, 10)).cut, DateTime(2026, 2, 28));
      expect(CardCycle.current(c31, d(2026, 2, 10)).payDate, DateTime(2026, 3, 20));
    });
  });

  group('Libro', () {
    test('siembra categorías y efectivo, guarda cifrado y recarga', () async {
      final Ledger l = await newLedger(tmp);
      expect(l.accounts.map((Account a) => a.id), contains('a_cash'));
      expect(l.roots(CategoryKind.expense), isNotEmpty);
      expect(l.category('c_food'), isNotNull);
      await l.addTx(Tx(id: 't1', kind: TxKind.expense, amountMinor: 1200000, accountId: 'a_cash', date: d(2026, 10, 10), description: 'Mercado', categoryId: 'c_food'));
      await l.flush();
      final File f = File('${tmp.path}/plata/ledger.json');
      expect(await f.exists(), isTrue);
      final Uint8List raw = await f.readAsBytes();
      expect(CryptoBox.isEncrypted(raw), isTrue);
      expect(utf8.decode(raw, allowMalformed: true), isNot(contains('Mercado')));
      // Con otra llave no se puede leer.
      final JsonStore store2 = JsonStore(root: tmp);
      final CryptoBox other = await CryptoBox.fromKeyStore(MemoryKeyStore());
      await expectLater(EncryptedStore(store2, other).readJson('ledger.json'), throwsA(isA<DecryptException>()));
      final Ledger locked = Ledger(EncryptedStore(store2, other));
      await locked.load();
      expect(locked.readOnly, isTrue);
      locked.save();
      await locked.flush();
      expect(await f.readAsBytes(), raw); // no se sobrescribió
      // Con la misma llave, sí.
      final Ledger again = Ledger(EncryptedStore(store2, l.store.box));
      await again.load();
      expect(again.txs.single.description, 'Mercado');
      expect(again.txs.single.amountMinor, 1200000);
      l.dispose();
    });

    test('saldos: efectivo, débito enlazado, bolsillos, tarjeta y patrimonio', () async {
      final Ledger l = await newLedger(tmp);
      final Account bank = await l.addAccount(Account(id: 'bank', name: 'Ahorros', type: AccountType.bank, initialMinor: 100000000));
      final Account debit = await l.addAccount(Account(id: 'deb', name: 'Débito', type: AccountType.debit, linkedAccountId: 'bank'));
      final Account pocket = await l.addAccount(Account(id: 'poc', name: 'Vacaciones', type: AccountType.pocket, parentId: 'bank'));
      final Account card = await l.addAccount(Account(id: 'tc', name: 'TC', type: AccountType.credit, cutDay: 15, payDay: 5));
      await l.addTx(Tx(id: '1', kind: TxKind.expense, amountMinor: 5000000, accountId: debit.id, date: d(2026, 10, 1), categoryId: 'c_food'));
      await l.addTx(Tx(id: '2', kind: TxKind.transfer, amountMinor: 20000000, accountId: bank.id, toAccountId: pocket.id, date: d(2026, 10, 2)));
      await l.addTx(Tx(id: '3', kind: TxKind.expense, amountMinor: 3000000, accountId: card.id, date: d(2026, 10, 3), categoryId: 'c_transport'));
      await l.addTx(Tx(id: '4', kind: TxKind.income, amountMinor: 1000000, accountId: 'a_cash', date: d(2026, 10, 4), categoryId: 'c_salary'));
      expect(l.balanceMinor(bank.id), 100000000 - 5000000 - 20000000);
      expect(l.balanceMinor(pocket.id), 20000000);
      expect(l.balanceWithPockets(bank.id), 100000000 - 5000000);
      expect(l.balanceMinor(card.id), -3000000);
      expect(l.debtMinor(), 3000000);
      expect(l.netWorthMinor(), 100000000 - 5000000 - 3000000 + 1000000);
      expect(l.effectiveAccountId(debit.id), bank.id);
      l.dispose();
    });

    test('búsqueda, sugerencias y etiquetas', () async {
      final Ledger l = await newLedger(tmp);
      await l.addTx(Tx(id: '1', kind: TxKind.expense, amountMinor: 450000, accountId: 'a_cash', date: d(2026, 10, 1), description: 'Tinto Juan Valdez', categoryId: 'c_food', tags: <String>['oficina']));
      await l.addTx(Tx(id: '2', kind: TxKind.expense, amountMinor: 450000, accountId: 'a_cash', date: d(2026, 10, 2), description: 'Tinto Juan Valdez', categoryId: 'c_food'));
      await l.addTx(Tx(id: '3', kind: TxKind.expense, amountMinor: 3500000, accountId: 'a_cash', date: d(2026, 9, 2), description: 'Taxi aeropuerto', categoryId: 'c_transport', payee: 'Taxis Libres'));
      expect(l.search(const TxFilter(text: 'tinto')).length, 2);
      expect(l.search(const TxFilter(text: '35.000')).single.id, '3');
      expect(l.search(const TxFilter(text: 'libres')).single.id, '3');
      expect(l.search(const TxFilter(categoryIds: <String>{'c_transport'})).single.id, '3');
      expect(l.search(TxFilter(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 1))).single.id, '1');
      expect(l.search(const TxFilter(minMinor: 1000000)).single.id, '3');
      expect(l.search(const TxFilter(tags: <String>{'oficina'})).single.id, '1');
      final List<Suggestion> s = l.suggest('tin');
      expect(s.first.description, 'Tinto Juan Valdez');
      expect(s.first.categoryId, 'c_food');
      expect(s.first.amountMinor, 450000);
      expect(l.allTags, <String>{'oficina'});
      l.dispose();
    });

    test('totales por periodo, categorías y tendencia', () async {
      final Ledger l = await newLedger(tmp);
      await l.addTx(Tx(id: '1', kind: TxKind.income, amountMinor: 300000000, accountId: 'a_cash', date: d(2026, 10, 1), categoryId: 'c_salary'));
      await l.addTx(Tx(id: '2', kind: TxKind.expense, amountMinor: 80000000, accountId: 'a_cash', date: d(2026, 10, 5), categoryId: 'c_housing_rent'));
      await l.addTx(Tx(id: '3', kind: TxKind.expense, amountMinor: 20000000, accountId: 'a_cash', date: d(2026, 10, 6), categoryId: 'c_food'));
      await l.addTx(Tx(id: '4', kind: TxKind.expense, amountMinor: 1000000, accountId: 'a_cash', date: d(2026, 9, 6), categoryId: 'c_food'));
      final Period oct = l.periodSpec.containing(d(2026, 10, 16));
      final PeriodTotals t = l.totals(oct);
      expect(t.incomeMinor, 300000000);
      expect(t.expenseMinor, 100000000);
      expect(t.netMinor, 200000000);
      final List<CategoryTotal> cats = l.byCategory(oct);
      expect(cats.first.categoryId, 'c_housing'); // arriendo se agrupa en su raíz
      expect(cats.first.amountMinor, 80000000);
      expect(cats[1].categoryId, 'c_food');
      final List<PeriodTotals> tr = l.trend(3);
      expect(tr.length, 3);
      expect(tr.last.expenseMinor, 100000000);
      expect(tr[1].expenseMinor, 1000000);
      final List<AccountFlow> flow = l.cashFlow(oct);
      expect(flow.single.inMinor, 300000000);
      expect(flow.single.outMinor, 100000000);
      l.dispose();
    });

    test('presupuesto con arrastre y reembolsos', () async {
      final Ledger l = await newLedger(tmp, clock: () => d(2026, 10, 16));
      final Budget b = await l.addBudget(Budget(id: 'b', name: 'Mercado', amountMinor: 50000000, categoryIds: <String>['c_food'], startDate: DateTime(2026, 8, 1), rollover: true));
      await l.addTx(Tx(id: '1', kind: TxKind.expense, amountMinor: 40000000, accountId: 'a_cash', date: d(2026, 8, 10), categoryId: 'c_food'));
      await l.addTx(Tx(id: '2', kind: TxKind.expense, amountMinor: 60000000, accountId: 'a_cash', date: d(2026, 9, 10), categoryId: 'c_food'));
      await l.addTx(Tx(id: '3', kind: TxKind.expense, amountMinor: 10000000, accountId: 'a_cash', date: d(2026, 10, 10), categoryId: 'c_food'));
      await l.addTx(Tx(id: '4', kind: TxKind.income, amountMinor: 2000000, accountId: 'a_cash', date: d(2026, 10, 11), categoryId: 'c_food', description: 'Devolución'));
      await l.addTx(Tx(id: '5', kind: TxKind.expense, amountMinor: 99999900, accountId: 'a_cash', date: d(2026, 10, 12), categoryId: 'c_transport'));
      final BudgetProgress p = l.progress(b);
      expect(p.carryMinor, 10000000 - 10000000); // ago +10M, sep −10M
      expect(p.spentMinor, 8000000);
      expect(p.limitMinor, 50000000);
      expect(p.availableMinor, 42000000);
      expect(p.over, isFalse);
      // Presupuesto global sin categorías: cuenta todo el gasto, y el reembolso
      // descuenta igual que en Informes.
      final Budget all = await l.addBudget(Budget(id: 'all', name: 'Todo', amountMinor: 100000000, startDate: DateTime(2026, 10, 1)));
      expect(l.progress(all).spentMinor, 10000000 + 99999900 - 2000000);
      expect(l.progress(all).over, isTrue);
      l.dispose();
    });

    test('programados: autoPost avanza; manual queda vencido; fin de serie', () async {
      DateTime now = d(2026, 10, 16);
      final Ledger l = await newLedger(tmp, clock: () => now);
      await l.addScheduled(Scheduled(id: 's1', name: 'Arriendo', kind: TxKind.expense, amountMinor: 150000000, accountId: 'a_cash', categoryId: 'c_housing_rent', nextDate: DateTime(2026, 10, 1), frequency: const Frequency()));
      await l.addScheduled(Scheduled(id: 's2', name: 'Internet', kind: TxKind.expense, amountMinor: 9000000, accountId: 'a_cash', categoryId: 'c_housing_internet_tv', nextDate: DateTime(2026, 10, 10), autoPost: false));
      await l.addScheduled(Scheduled(id: 's3', name: 'Quincena', kind: TxKind.income, amountMinor: 200000000, accountId: 'a_cash', categoryId: 'c_salary_paycheck', nextDate: DateTime(2026, 9, 30), frequency: const Frequency(unit: FrequencyUnit.quincena)));
      await l.addScheduled(Scheduled(id: 's4', name: 'Curso', kind: TxKind.expense, amountMinor: 100, accountId: 'a_cash', nextDate: DateTime(2026, 10, 1), frequency: const Frequency(unit: FrequencyUnit.week), endDate: DateTime(2026, 10, 9)));
      final List<Tx> posted = l.processScheduled();
      // s1: 1 oct; s3: 30 sep y 15 oct; s4: 1 y 8 oct (el 15 ya pasa el fin).
      expect(posted.where((Tx t) => t.scheduledId == 's1').length, 1);
      expect(posted.where((Tx t) => t.scheduledId == 's3').length, 2);
      expect(posted.where((Tx t) => t.scheduledId == 's4').length, 2);
      expect(posted.where((Tx t) => t.scheduledId == 's2'), isEmpty);
      final Scheduled s1 = l.scheduled.firstWhere((Scheduled s) => s.id == 's1');
      expect(s1.nextDate, DateTime(2026, 11, 1));
      final Scheduled s2 = l.scheduled.firstWhere((Scheduled s) => s.id == 's2');
      expect(s2.nextDate, DateTime(2026, 10, 10));
      expect(l.upcoming(days: 7).map((Scheduled s) => s.id), contains('s2'));
      final Scheduled s3 = l.scheduled.firstWhere((Scheduled s) => s.id == 's3');
      expect(s3.nextDate, DateTime(2026, 10, 31));
      final Scheduled s4 = l.scheduled.firstWhere((Scheduled s) => s.id == 's4');
      expect(s4.enabled, isFalse);
      // Segunda pasada no duplica.
      expect(l.processScheduled(), isEmpty);
      // Anotar manualmente el pendiente lo avanza.
      await l.postScheduled(s2);
      expect(s2.nextDate, DateTime(2026, 11, 10));
      expect(l.txs.where((Tx t) => t.scheduledId == 's2').length, 1);
      now = d(2026, 11, 2);
      expect(l.processScheduled().map((Tx t) => t.scheduledId), contains('s1'));
      l.dispose();
    });

    test('estado de cuenta de tarjeta con cuotas y pagos', () async {
      final Ledger l = await newLedger(tmp, clock: () => d(2026, 10, 20));
      final Account card = await l.addAccount(Account(id: 'tc', name: 'TC', type: AccountType.credit, cutDay: 15, payDay: 5, creditLimitMinor: 500000000));
      await l.addAccount(Account(id: 'bank', name: 'Banco', type: AccountType.bank, initialMinor: 100000000));
      // Compra a 3 cuotas el 1 de septiembre: la primera se factura en el corte
      // del 15 de septiembre, la segunda el 15 de octubre y la tercera el 15 de noviembre.
      await l.addTx(Tx(id: 'c1', kind: TxKind.expense, amountMinor: 30000000, accountId: 'tc', date: d(2026, 9, 1), installments: 3, categoryId: 'c_household', description: 'Nevera'));
      // Compra normal dentro del ciclo actual (16 oct – 15 nov).
      await l.addTx(Tx(id: 'c2', kind: TxKind.expense, amountMinor: 5000000, accountId: 'tc', date: d(2026, 10, 18), categoryId: 'c_food'));
      // Pago del 17 de octubre: es para el estado que cortó el 15 (se paga el 5 de noviembre).
      await l.addTx(Tx(id: 'p1', kind: TxKind.transfer, amountMinor: 2000000, accountId: 'bank', toAccountId: 'tc', date: d(2026, 10, 17)));
      final CardStatement sep = l.statement(card, date: DateTime(2026, 9, 15));
      expect(sep.installmentsMinor, 10000000);
      final CardStatement prev = l.statement(card, date: DateTime(2026, 10, 15));
      expect(prev.previousMinor, 10000000); // la primera cuota, sin pagar
      expect(prev.installmentsMinor, 10000000);
      expect(prev.purchasesMinor, 0);
      expect(prev.paymentsMinor, 2000000);
      expect(prev.dueMinor, 18000000);
      final CardStatement st = l.statement(card);
      expect(st.cycle.cut, DateTime(2026, 11, 15));
      expect(st.previousMinor, 18000000); // lo que quedó del estado anterior
      expect(st.purchasesMinor, 5000000);
      expect(st.installmentsMinor, 10000000);
      expect(st.paymentsMinor, 0);
      expect(st.dueMinor, 33000000);
      // El próximo pago es el del ciclo cerrado mientras no pase el 5 de noviembre.
      expect(l.nextPayment(card).cycle.payDate, DateTime(2026, 11, 5));
      expect(l.nextPayment(card).dueMinor, 18000000);
      expect(l.nextPayment(card, now: DateTime(2026, 11, 6)).cycle.payDate, DateTime(2026, 12, 5));
      expect(l.remainingInstallments(l.tx('c1')!, now: DateTime(2026, 9, 20)), 1);
      expect(l.remainingInstallments(l.tx('c1')!), 0); // la 3.ª se factura en este ciclo
      expect(l.balanceMinor('tc'), -(30000000 + 5000000) + 2000000);
      l.dispose();
    });

    test('bandeja de avisos: duplicados, adivinar cuenta y aceptar', () async {
      final Ledger l = await newLedger(tmp);
      await l.addAccount(Account(id: 'nq', name: 'Nequi', type: AccountType.wallet, bank: 'nequi'));
      await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, bank: 'bancolombia', last4: '4321', cutDay: 10, payDay: 25));
      final InboxItem a = await l.addInbox(InboxItem(id: 'i1', bank: 'nequi', kind: TxKind.expense, amountMinor: 1500000, receivedAt: d(2026, 10, 16, 9), merchant: 'Rappi', rawText: 'Pagaste 15.000 en Rappi'));
      final InboxItem dup = await l.addInbox(InboxItem(id: 'i2', bank: 'nequi', kind: TxKind.expense, amountMinor: 1500000, receivedAt: d(2026, 10, 16, 9), merchant: 'Rappi', rawText: 'Pagaste 15.000 en Rappi'));
      expect(identical(a, dup), isTrue);
      expect(l.inbox.length, 1);
      expect(a.accountId, 'nq');
      final InboxItem b = await l.addInbox(InboxItem(id: 'i3', bank: 'bancolombia', kind: TxKind.expense, amountMinor: 8000000, receivedAt: d(2026, 10, 16, 10), merchant: 'EXITO', last4: '4321', rawText: 'Compra por 80.000 en EXITO con tarjeta *4321'));
      expect(b.accountId, 'tc');
      final Tx? tx = await l.acceptInbox(b, categoryId: 'c_food');
      expect(tx, isNotNull);
      expect(tx!.accountId, 'tc');
      expect(tx.source, 'notice');
      expect(b.status, 'accepted');
      expect(l.pendingInbox.length, 1);
      l.dismissInbox(a);
      expect(l.pendingInbox, isEmpty);
      l.dispose();
    });

    test('un libro dañado deja la app en solo lectura en vez de empezar de cero', () async {
      final JsonStore store = JsonStore(root: tmp);
      await store.writeBytes('ledger.json', <int>[1, 2, 3, 4, 5]);
      final CryptoBox box = await CryptoBox.fromKeyStore(MemoryKeyStore());
      final Ledger l = Ledger(EncryptedStore(store, box), clock: () => d(2026, 10, 16));
      await l.load();
      expect(l.readOnly, isTrue);
      await l.addTx(Tx(id: 'x', kind: TxKind.expense, amountMinor: 100, accountId: 'a_cash', date: d(2026, 10, 16)));
      await l.flush();
      expect(await store.readBytes('ledger.json'), <int>[1, 2, 3, 4, 5]);
      l.dispose();
    });

    test('las fotos de recibos se borran con su movimiento y las huérfanas a los 30 días', () async {
      DateTime now = d(2026, 10, 16);
      final Ledger l = await newLedger(tmp, clock: () => now);
      final EncryptedStore es = l.store;
      await es.writeBytes('attachments/a.jpg.enc', <int>[9, 9, 9]);
      await es.writeBytes('attachments/b.jpg.enc', <int>[8, 8, 8]);
      await es.writeBytes('attachments/huerfana.jpg.enc', <int>[7]);
      await l.addTx(Tx(id: 't1', kind: TxKind.expense, amountMinor: 100, accountId: 'a_cash', date: d(2026, 10, 10), attachments: <String>['attachments/a.jpg.enc', 'attachments/no-esta.jpg.enc']));
      await l.addTx(Tx(id: 't2', kind: TxKind.expense, amountMinor: 200, accountId: 'a_cash', date: d(2026, 10, 11), attachments: <String>['attachments/b.jpg.enc']));
      expect(await es.readBytes('attachments/a.jpg.enc'), <int>[9, 9, 9]);
      await l.pruneAttachments();
      // La huérfana se guarda un tiempo (puede volver a usarse si se deshace
      // una restauración, M19 de la segunda ronda) y se borra a los 30 días.
      expect(await es.store.list('attachments'), <String>['attachments/a.jpg.enc', 'attachments/b.jpg.enc', 'attachments/huerfana.jpg.enc']);
      expect(l.tx('t1')!.attachments, <String>['attachments/a.jpg.enc']);
      now = d(2026, 11, 16);
      await l.pruneAttachments();
      expect(await es.store.list('attachments'), <String>['attachments/a.jpg.enc', 'attachments/b.jpg.enc']);
      await l.deleteTx('t2');
      expect(await es.store.list('attachments'), <String>['attachments/a.jpg.enc']);
      l.dispose();
    });

    test('plantillas y conversión a moneda base', () async {
      final Ledger l = await newLedger(tmp);
      await l.addAccount(Account(id: 'usd', name: 'Dólares', type: AccountType.savings, currency: 'USD', initialMinor: 10000));
      l.rates.rates['USD'] = 4000;
      expect(l.toBase(10000, 'USD'), 40000000);
      expect(l.netWorthMinor(), 40000000);
      final TxTemplate tpl = await l.addTemplate(TxTemplate(id: 'tp', name: 'Bus', amountMinor: 310000, accountId: 'a_cash', categoryId: 'c_transport'));
      final Tx? tx = await l.applyTemplate(tpl);
      expect(tx, isNotNull);
      expect(tx!.description, 'Bus');
      expect(tpl.uses, 1);
      expect(l.balanceMinor('a_cash'), -310000);
      l.dispose();
    });
  });

  group('Avisos bancarios', () {
    test('reconoce compras, ingresos y descarta ruido', () {
      final BankSuggestion? s1 = BankRules.parse(packageName: 'co.com.bancolombia.personas.superapp', title: 'Bancolombia', text: r'Bancolombia: Compraste $85.900 en EXITO CALLE 80 con tu tarjeta *4321 el 16/10/2026 a las 19:02.');
      expect(s1, isNotNull);
      expect(s1!.kind, TxKind.expense);
      expect(s1.amountMinor, 8590000);
      expect(s1.last4, '4321');
      expect(s1.merchant.toUpperCase(), contains('EXITO'));
      final BankSuggestion? s2 = BankRules.parse(packageName: 'com.nequi.MobileApp', title: 'Nequi', text: r'¡Te llegó plata! Juan Pérez te envió $120.000. Ya está disponible en tu Nequi.');
      expect(s2, isNotNull);
      expect(s2!.kind, TxKind.income);
      expect(s2.amountMinor, 12000000);
      final BankSuggestion? s3 = BankRules.parse(packageName: 'com.davivienda.daviplataapp', title: 'DaviPlata', text: 'Tu clave dinámica es 482913. No la compartas.');
      expect(s3, isNull);
      final BankSuggestion? s4 = BankRules.parse(packageName: 'com.whatsapp', title: 'Juan', text: r'Te debo $50.000');
      expect(s4, isNull);
      final BankSuggestion? s5 = BankRules.parse(packageName: 'co.com.bancolombia.personas.superapp', title: 'Bancolombia', text: r'Compra rechazada por $20.000 en NETFLIX. Fondos insuficientes.');
      expect(s5, isNull);
    });
  });

  group('Exportar y respaldar', () {
    test('CSV y XLSX contienen los movimientos', () async {
      final Ledger l = await newLedger(tmp);
      await l.addTx(Tx(id: '1', kind: TxKind.expense, amountMinor: 1234500, accountId: 'a_cash', date: d(2026, 10, 10), description: 'Mercado, "La 14"', categoryId: 'c_food'));
      await l.addTx(Tx(id: '2', kind: TxKind.income, amountMinor: 500000000, accountId: 'a_cash', date: d(2026, 10, 1), categoryId: 'c_salary'));
      final String csv = Exports.csv(l, l.txs);
      final List<String> lines = const LineSplitter().convert(csv);
      expect(lines.length, 3);
      expect(lines.first, contains('fecha'));
      expect(csv, contains('"Mercado, ""La 14"""'));
      expect(csv, contains('12345.00'));
      final Uint8List bytes = Exports.csvBytes(l, l.txs);
      expect(bytes.sublist(0, 3), <int>[0xEF, 0xBB, 0xBF]);
      final Uint8List xlsx = Exports.xlsx(l, l.txs);
      final Archive a = ZipDecoder().decodeBytes(xlsx);
      final List<String> names = a.files.map((ArchiveFile f) => f.name).toList();
      expect(names, containsAll(<String>['[Content_Types].xml', 'xl/workbook.xml', 'xl/worksheets/sheet1.xml', 'xl/worksheets/sheet2.xml']));
      final String sheet = utf8.decode(a.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
      expect(sheet, contains('Mercado, &quot;La 14&quot;'));
      expect(sheet, contains('<v>-12345.0</v>'));
      l.dispose();
    });

    test('copia cifrada con contraseña: ida y vuelta, contraseña mala y manipulación', () async {
      final Ledger l = await newLedger(tmp);
      final AppSettings settings = AppSettings();
      await l.addTx(Tx(id: '1', kind: TxKind.expense, amountMinor: 700000, accountId: 'a_cash', date: d(2026, 10, 10), description: 'Almuerzo'));
      final BackupManager bm = BackupManager(store: l.store.store, ledger: l, settings: settings);
      final Uint8List enc = await bm.exportEncrypted('clave-larga');
      expect(BackupManager.isEncryptedBackup(enc), isTrue);
      expect(utf8.decode(enc, allowMalformed: true), isNot(contains('Almuerzo')));
      final Map<String, dynamic> back = await BackupManager.decode(enc, passphrase: 'clave-larga');
      expect((back['txs'] as List<dynamic>).length, 1);
      await expectLater(BackupManager.decode(enc, passphrase: 'otra'), throwsA(anything));
      final Uint8List tampered = Uint8List.fromList(enc);
      tampered[tampered.length - 20] ^= 0x55;
      await expectLater(BackupManager.decode(tampered, passphrase: 'clave-larga'), throwsA(anything));
      final Uint8List plain = bm.exportPlain();
      expect(BackupManager.isEncryptedBackup(plain), isFalse);
      final Map<String, dynamic> fromPlain = await BackupManager.decode(plain);
      expect((fromPlain['txs'] as List<dynamic>).length, 1);
      // Restaurar reemplaza.
      await l.deleteTx('1');
      expect(l.txs, isEmpty);
      await bm.restore(back);
      expect(l.txs.single.description, 'Almuerzo');
      // Copia automática diaria: una por día, conserva 7.
      for (int i = 0; i < 9; i++) {
        final String? rel = await bm.autoBackup(now: DateTime(2026, 10, 1 + i));
        expect(rel, isNotNull);
      }
      expect(await bm.autoBackup(now: DateTime(2026, 10, 9)), isNull);
      expect((await bm.listAutoBackups()).length, 7);
      l.dispose();
    });

    test('caja criptográfica: cifra, descifra y detecta manipulación', () async {
      final MemoryKeyStore ks = MemoryKeyStore();
      final CryptoBox a = await CryptoBox.fromKeyStore(ks);
      final CryptoBox b = await CryptoBox.fromKeyStore(ks);
      final Uint8List enc = await a.encrypt(utf8.encode('hola plata'));
      expect(CryptoBox.isEncrypted(enc), isTrue);
      expect(utf8.decode(await b.decrypt(enc)), 'hola plata');
      final Uint8List enc2 = await a.encrypt(utf8.encode('hola plata'));
      expect(enc2, isNot(equals(enc))); // nonce distinto
      enc[enc.length - 1] ^= 1;
      await expectLater(a.decrypt(enc), throwsA(anything));
    });
  });

  group('Tasas, recordatorios y bloqueo', () {
    test('TRM de datos.gov.co y cruces del BCE', () async {
      final MockClient client = MockClient((http.Request r) async {
        if (r.url.host == 'www.datos.gov.co') {
          return http.Response(jsonEncode(<Map<String, String>>[<String, String>{'valor': '4123.45', 'vigenciadesde': '2026-10-16T00:00:00.000'}]), 200);
        }
        if (r.url.host == 'api.frankfurter.dev') {
          return http.Response(jsonEncode(<String, dynamic>{'base': 'USD', 'rates': <String, double>{'EUR': 0.9, 'MXN': 18.0}}), 200);
        }
        return http.Response('no', 500);
      });
      final RateService rs = RateService(client: client);
      final RateTable table = RateTable();
      final bool ok = await rs.refresh(table, base: 'COP', currencies: <String>{'USD', 'EUR'}, now: d(2026, 10, 16));
      expect(ok, isTrue);
      expect(table.rates['USD'], closeTo(4123.45, 0.001));
      expect(table.rates['EUR'], closeTo(4123.45 / 0.9, 0.01));
      expect(table.source, contains('TRM'));
      expect(table.rateFor('USD', 'COP'), closeTo(4123.45, 0.001));
      table.manual['USD'] = 4000;
      expect(table.rateFor('USD', 'COP'), 4000);
      // Sin red: falso y la tabla queda igual.
      final RateService dead = RateService(client: MockClient((_) async => http.Response('x', 503)));
      expect(await dead.refresh(RateTable(), base: 'COP', currencies: <String>{'USD'}), isFalse);
    });

    test('M9: las monedas que el BCE no publica salen de ExchangeRate-API y se rotulan', () async {
      final List<String> hosts = <String>[];
      final MockClient client = MockClient((http.Request r) async {
        hosts.add(r.url.host);
        if (r.url.host == 'www.datos.gov.co') {
          return http.Response(jsonEncode(<Map<String, String>>[<String, String>{'valor': '4000', 'vigenciadesde': '2026-10-16T00:00:00.000'}]), 200);
        }
        if (r.url.host == 'api.frankfurter.dev') {
          return http.Response(jsonEncode(<String, dynamic>{'base': 'USD', 'rates': <String, double>{'EUR': 0.9}}), 200);
        }
        if (r.url.host == 'open.er-api.com') {
          return http.Response(jsonEncode(<String, dynamic>{'result': 'success', 'rates': <String, double>{'PEN': 3.7, 'EUR': 0.91}}), 200);
        }
        return http.Response('no', 500);
      });
      final RateTable table = RateTable();
      expect(await RateService(client: client).refresh(table, base: 'COP', currencies: <String>{'EUR', 'PEN'}, now: d(2026, 10, 16)), isTrue);
      expect(hosts, isNot(contains('api.frankfurter.app')));
      expect(table.origins['USD'], RateOrigin.trm);
      expect(table.origins['EUR'], RateOrigin.ecb);
      expect(table.origins['PEN'], RateOrigin.erApi);
      expect(table.rates['EUR'], closeTo(4000 / 0.9, 0.01));
      expect(table.rates['PEN'], closeTo(4000 / 3.7, 0.01));
      expect(table.source, 'TRM + BCE + ExchangeRate-API');
    });

    test('recordatorios: diario, programados y pago de tarjeta', () async {
      final Ledger l = await newLedger(tmp, clock: () => d(2026, 10, 16));
      final AppSettings settings = AppSettings()
        ..dailyReminder = true
        ..billReminders = true
        ..billReminderDaysBefore = 2;
      await l.addAccount(Account(id: 'tc', name: 'TC', type: AccountType.credit, cutDay: 15, payDay: 5));
      await l.addTx(Tx(id: '1', kind: TxKind.expense, amountMinor: 5000000, accountId: 'tc', date: d(2026, 10, 1)));
      await l.addScheduled(Scheduled(id: 's', name: 'Arriendo', kind: TxKind.expense, amountMinor: 1, accountId: 'a_cash', nextDate: DateTime(2026, 10, 20), remindDaysBefore: 1));
      await l.addScheduled(Scheduled(id: 'n', name: 'Sin aviso', kind: TxKind.expense, amountMinor: 1, accountId: 'a_cash', nextDate: DateTime(2026, 10, 21), remindDaysBefore: -1));
      final NoopNotifier n = NoopNotifier();
      await Reminders.sync(ledger: l, settings: settings, notifier: n, now: d(2026, 10, 16, 8));
      // Nada se cancela en bloque: los avisos ya mostrados siguen en la bandeja (M7).
      expect(n.log, isNot(contains('cancelAll')));
      expect(n.log.where((String x) => x.startsWith('daily:20:30:')).length, 1);
      expect(n.log.any((String x) => x.startsWith('at:2026-10-19T09:00') && x.contains('Arriendo')), isTrue);
      expect(n.log.any((String x) => x.contains('Sin aviso')), isFalse);
      // Pago de la TC: corte 15 oct, pago 5 nov → aviso el 3 nov.
      expect(n.log.any((String x) => x.startsWith('at:2026-11-03T09:00')), isTrue);
      l.dispose();
    });

    test('clave de acceso con esperas crecientes', () async {
      final AppLock lock = AppLock(MemoryKeyStore(), biometricsAvailable: false);
      await lock.load();
      expect(lock.enabled, isFalse);
      expect(lock.locked, isFalse);
      await lock.setPasscode('2468');
      expect(lock.enabled, isTrue);
      expect(lock.passcodeLength, 4);
      lock.lockNow();
      expect(lock.locked, isTrue);
      expect(await lock.verify('0000'), isFalse);
      expect(await lock.verify('0000'), isFalse);
      expect(await lock.verify('0000'), isFalse);
      expect(lock.waitSeconds, greaterThan(0));
      expect(await lock.verify('2468'), isFalse); // bloqueado por la espera
      // Cerrar y abrir la app no borra la espera (M14).
      final AppLock again = AppLock(lock.keys, biometricsAvailable: false);
      await again.load();
      expect(again.enabled, isTrue);
      expect(again.locked, isTrue);
      expect(again.waitSeconds, greaterThan(0));
      expect(await again.verify('2468'), isFalse);
      await withClock(Clock.fixed(DateTime.now().add(const Duration(seconds: 31))), () async {
        expect(again.waitSeconds, 0);
        expect(await again.verify('2468'), isTrue);
      });
      expect(again.locked, isFalse);
      await again.clearPasscode();
      expect(again.enabled, isFalse);
    });

    test('avisos: el servicio deja sugerencias en la bandeja y respeta el ajuste', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final Ledger l = await newLedger(tmp);
      final AppSettings settings = AppSettings()..noticesEnabled = true;
      final FakeNoticeBridge bridge = FakeNoticeBridge();
      bridge.pending.add(RawNotice(package: 'com.nequi.MobileApp', title: 'Nequi', text: r'Pagaste $12.500 en Tostao. Tu saldo es $80.000', time: d(2026, 10, 16, 8)));
      final NoticeService svc = NoticeService(bridge: bridge, ledger: l, settings: settings);
      await svc.start();
      expect(l.pendingInbox.length, 1);
      expect(l.pendingInbox.single.amountMinor, 1250000);
      bridge.controller.add(RawNotice(package: 'com.nequi.MobileApp', title: 'Nequi', text: r'Pagaste $3.000 en Bus. Tu saldo es $77.000', time: d(2026, 10, 16, 9)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(l.pendingInbox.length, 2);
      await svc.stop();
      settings.noticesEnabled = false;
      bridge.pending.add(RawNotice(package: 'com.nequi.MobileApp', title: 'Nequi', text: r'Pagaste $1.000 en X', time: d(2026, 10, 16, 10)));
      expect(await svc.pull(), 0);
      l.dispose();
    });
  });
}
