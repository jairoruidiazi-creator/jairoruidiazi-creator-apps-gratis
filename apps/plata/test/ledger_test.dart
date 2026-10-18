// Cálculos del libro: los hallazgos de dinero del informe de auditoría (B1,
// B2, G1, G2, G4, G5 y los menores M5–M8, M11, M15, M18, M20, M21 y M25).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plata/core/crypto_store.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/core/periods.dart';
import 'package:plata/core/storage.dart';
import 'package:plata/model/models.dart';

DateTime d(int y, int m, int day, [int h = 12]) => DateTime(y, m, day, h);

Future<Ledger> newLedger(Directory dir, {DateTime Function()? clock}) async {
  final CryptoBox box = await CryptoBox.fromKeyStore(MemoryKeyStore());
  final Ledger l = Ledger(EncryptedStore(JsonStore(root: dir), box), clock: clock ?? () => d(2026, 10, 16));
  await l.load();
  return l;
}

Matcher rejected(TxProblem p, {String? currency}) {
  TypeMatcher<TxRejected> m = isA<TxRejected>().having((TxRejected e) => e.problem, 'problem', p);
  if (currency != null) {
    m = m.having((TxRejected e) => e.currency, 'currency', currency);
  }
  return throwsA(m);
}

void main() {
  late Directory tmp;
  late Ledger l;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('plata_ledger');
    l = await newLedger(tmp);
  });

  tearDown(() async {
    l.dispose();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> pesosYDolares() async {
    await l.addAccount(Account(id: 'bank', name: 'Ahorros', type: AccountType.bank, initialMinor: 1000000000));
    await l.addAccount(Account(id: 'usd', name: 'Dólares', type: AccountType.savings, currency: 'USD'));
  }

  group('B1: transferencias entre monedas', () {
    test('acreditan lo convertido con la tasa guardada y el patrimonio no cambia', () async {
      await pesosYDolares();
      l.rates.rates['USD'] = 4000;
      final int before = l.netWorthMinor();
      final Tx t = await l.addTx(Tx(id: 't', kind: TxKind.transfer, amountMinor: 40000000, accountId: 'bank', toAccountId: 'usd', date: d(2026, 10, 10)));
      expect(t.toAmountMinor, 10000); // US$ 100,00
      expect(t.toAmountAuto, isTrue);
      expect(l.balanceMinor('usd'), 10000);
      expect(l.balanceMinor('bank'), 1000000000 - 40000000);
      expect(l.netWorthMinor(), before);
      final List<AccountFlow> flow = l.cashFlow(l.periodSpec.containing(d(2026, 10, 16)));
      expect(flow.firstWhere((AccountFlow f) => f.account.id == 'usd').inMinor, 10000);
    });

    test('el monto recibido escrito a mano manda sobre la tasa', () async {
      await pesosYDolares();
      l.rates.rates['USD'] = 4000;
      final Tx t = await l.addTx(Tx(id: 't', kind: TxKind.transfer, amountMinor: 40000000, accountId: 'bank', toAccountId: 'usd', toAmountMinor: 9800, date: d(2026, 10, 10)));
      expect(t.toAmountMinor, 9800);
      expect(t.toAmountAuto, isFalse);
      expect(l.balanceMinor('usd'), 9800);
    });

    test('sin tasa no se anota y se dice qué moneda falta', () async {
      await l.addAccount(Account(id: 'bank', name: 'Ahorros', type: AccountType.bank));
      await l.addAccount(Account(id: 'eur', name: 'Euros', type: AccountType.savings, currency: 'EUR'));
      await expectLater(l.addTx(Tx(id: 't', kind: TxKind.transfer, amountMinor: 100000, accountId: 'bank', toAccountId: 'eur', date: d(2026, 10, 10))), rejected(TxProblem.missingRate, currency: 'EUR'));
      expect(l.txs, isEmpty);
      expect(l.balanceMinor('eur'), 0);
    });

    test('los programados convierten igual; sin tasa quedan vencidos, no se pierden', () async {
      await pesosYDolares();
      await l.addScheduled(Scheduled(id: 's', name: 'Ahorro en dólares', kind: TxKind.transfer, amountMinor: 40000000, accountId: 'bank', toAccountId: 'usd', nextDate: DateTime(2026, 10, 1)));
      await l.addScheduled(Scheduled(id: 'fijo', name: 'Con monto fijo', kind: TxKind.transfer, amountMinor: 20000000, accountId: 'bank', toAccountId: 'usd', toAmountMinor: 4900, nextDate: DateTime(2026, 10, 2)));
      final List<Tx> first = l.processScheduled();
      // El de monto recibido fijo no necesita tasa; el otro espera.
      expect(first.single.scheduledId, 'fijo');
      expect(first.single.toAmountMinor, 4900);
      final Scheduled s = l.scheduled.firstWhere((Scheduled x) => x.id == 's');
      expect(s.enabled, isTrue);
      expect(s.nextDate, DateTime(2026, 10, 1));
      l.rates.rates['USD'] = 4000;
      final List<Tx> posted = l.processScheduled();
      expect(posted.single.scheduledId, 's');
      expect(posted.single.toAmountMinor, 10000);
      expect(l.balanceMinor('usd'), 14900);
    });

    test('los favoritos convierten igual; sin tasa ni monto recibido abren el editor', () async {
      await pesosYDolares();
      final TxTemplate tpl = await l.addTemplate(TxTemplate(id: 'tp', name: 'A dólares', kind: TxKind.transfer, amountMinor: 40000000, accountId: 'bank', toAccountId: 'usd'));
      expect(await l.applyTemplate(tpl), isNull);
      expect(l.txs, isEmpty);
      tpl.toAmountMinor = 9800;
      final Tx? t = await l.applyTemplate(tpl);
      expect(t!.toAmountMinor, 9800);
      expect(l.balanceMinor('usd'), 9800);
    });

    test('pagar una tarjeta sale de una cuenta en su misma moneda', () async {
      await pesosYDolares();
      final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
      final Account tcUsd = await l.addAccount(Account(id: 'tcu', name: 'Visa USD', type: AccountType.credit, currency: 'USD', cutDay: 15, payDay: 5));
      expect(l.paymentSourceFor(tc, preferredId: 'bank')!.id, 'bank');
      expect(l.paymentSourceFor(tc, preferredId: 'usd')!.currency, 'COP');
      expect(l.paymentSourceFor(tcUsd, preferredId: 'bank')!.id, 'usd');
      l.setArchived(l.account('usd')!, true);
      expect(l.paymentSourceFor(tcUsd), isNull);
    });
  });

  test('B2 y G4: la deuda inicial resta del patrimonio y del cupo, pero no se cobra entera en el próximo pago', () async {
    // Así la guarda el editor de cuentas: la deuda es negativa (ver app_test).
    final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, initialMinor: -100000000, creditLimitMinor: 500000000, cutDay: 15, payDay: 5));
    expect(l.balanceMinor('tc'), -100000000);
    expect(l.debtMinor(), 100000000);
    expect(l.availableCreditMinor(tc), 400000000);
    expect(l.netWorthMinor(), -100000000);
    // Sin el pago del último extracto, toda es deuda de antes de Plata: se
    // muestra aparte y no se suma a ningún estado de cuenta.
    final CardStatement st = l.statement(tc);
    expect(st.previousMinor, 0);
    expect(st.dueMinor, 0);
    expect(st.legacyMinor, 100000000);
    expect(l.nextPayment(tc).dueMinor, 0);
  });

  group('G1: estado de cuenta estimado de la tarjeta', () {
    late Account tc;

    setUp(() async {
      await l.addAccount(Account(id: 'bank', name: 'Ahorros', type: AccountType.bank, initialMinor: 1000000000));
      tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
    });

    test('la primera cuota llega en el primer corte después de la compra y las cuotas suman el total (M11)', () async {
      final Tx buy = await l.addTx(Tx(id: 'nevera', kind: TxKind.expense, amountMinor: 100000000, accountId: 'tc', date: d(2026, 9, 1), installments: 3, categoryId: 'c_household'));
      final List<int> billed = <int>[for (final DateTime cut in <DateTime>[DateTime(2026, 9, 15), DateTime(2026, 10, 15), DateTime(2026, 11, 15), DateTime(2026, 12, 15)]) l.statement(tc, date: cut).installmentsMinor];
      // En pesos, cada cuota es un número entero de pesos (M1 de la segunda
      // ronda) y la última lleva el sobrante.
      expect(billed, <int>[33333300, 33333300, 33333400, 0]);
      expect(billed.fold<int>(0, (int a, int b) => a + b), 100000000);
      expect(Ledger.installmentAmount(100000000, 3, 3), 33333334);
      // El 10 de septiembre ya se facturó la primera; faltan dos.
      expect(l.remainingInstallments(buy, now: DateTime(2026, 9, 10)), 2);
      expect(l.remainingInstallmentsMinor(buy, now: DateTime(2026, 9, 10)), 66666700);
      expect(l.remainingInstallments(buy, now: DateTime(2026, 11, 20)), 0);
    });

    test('lo que no se pagó pasa como saldo anterior; un abono de más queda a favor', () async {
      await l.addTx(Tx(id: 'c1', kind: TxKind.expense, amountMinor: 50000000, accountId: 'tc', date: d(2026, 9, 10)));
      await l.addTx(Tx(id: 'p1', kind: TxKind.transfer, amountMinor: 20000000, accountId: 'bank', toAccountId: 'tc', date: d(2026, 10, 1)));
      await l.addTx(Tx(id: 'c2', kind: TxKind.expense, amountMinor: 10000000, accountId: 'tc', date: d(2026, 10, 3)));
      final CardStatement sep = l.statement(tc, date: DateTime(2026, 9, 15));
      expect(sep.purchasesMinor, 50000000);
      expect(sep.paymentsMinor, 20000000); // pagado antes del 5 de octubre
      expect(sep.dueMinor, 30000000);
      final CardStatement oct = l.statement(tc, date: DateTime(2026, 10, 15));
      expect(oct.previousMinor, 30000000);
      expect(oct.purchasesMinor, 10000000);
      expect(oct.dueMinor, 40000000);
      final CardStatement next = l.nextPayment(tc, now: DateTime(2026, 10, 20));
      expect(next.cycle.payDate, DateTime(2026, 11, 5));
      expect(next.dueMinor, 40000000);
      // Abono de más el 20 de octubre: el estado de octubre queda a favor y el
      // de noviembre arranca con ese saldo a favor.
      await l.addTx(Tx(id: 'p2', kind: TxKind.transfer, amountMinor: 100000000, accountId: 'bank', toAccountId: 'tc', date: d(2026, 10, 20)));
      final CardStatement octPaid = l.statement(tc, date: DateTime(2026, 10, 15));
      expect(octPaid.dueMinor, 0);
      expect(octPaid.creditMinor, 60000000);
      final CardStatement nov = l.statement(tc, date: DateTime(2026, 11, 15));
      expect(nov.previousMinor, -60000000);
      expect(nov.creditMinor, 60000000);
      expect(nov.dueMinor, 0);
    });

    test('los avances en efectivo cuentan en el estado de cuenta', () async {
      await l.addTx(Tx(id: 'av', kind: TxKind.transfer, amountMinor: 20000000, accountId: 'tc', toAccountId: 'a_cash', date: d(2026, 10, 2)));
      final CardStatement st = l.statement(tc, date: DateTime(2026, 10, 15));
      expect(st.advancesMinor, 20000000);
      expect(st.dueMinor, 20000000);
      expect(l.balanceMinor('tc'), -20000000);
      expect(l.balanceMinor('a_cash'), 20000000);
    });

    test('M25: con corte 30 y pago 31, febrero no salta un mes ni deja ventanas vacías', () async {
      final Account c30 = await l.addAccount(Account(id: 'c30', name: 'Corte 30', type: AccountType.credit, cutDay: 30, payDay: 31));
      final CardCycle feb = CardCycle.current(c30, DateTime(2026, 2, 10));
      expect(feb.cut, DateTime(2026, 2, 28));
      expect(feb.payDate, DateTime(2026, 3, 1));
      final CardCycle mar = CardCycle.current(c30, DateTime(2026, 3, 10));
      expect(mar.payDate, DateTime(2026, 3, 31));
      expect(mar.previous(c30).payDate, isNot(mar.payDate));
      expect(CardCycle.payDateFor(DateTime(2026, 2, 28), 28, 30), DateTime(2026, 3, 2));
      expect(CardCycle.payDateFor(DateTime(2028, 2, 28), 28, 30), DateTime(2028, 2, 29)); // bisiesto
      // Un pago del 15 de marzo se aplica al estado que corta el 30 de marzo.
      await l.addTx(Tx(id: 'm', kind: TxKind.expense, amountMinor: 1000000, accountId: 'c30', date: d(2026, 3, 5)));
      await l.addTx(Tx(id: 'p', kind: TxKind.transfer, amountMinor: 400000, accountId: 'bank', toAccountId: 'c30', date: d(2026, 3, 15)));
      final CardStatement st = l.statement(c30, date: DateTime(2026, 3, 30));
      expect(st.paymentsMinor, 400000);
      expect(st.dueMinor, 600000);
    });
  });

  group('G2: cambiar la moneda base', () {
    test('convierte presupuestos, tasas y la tasa guardada de cada movimiento', () async {
      await l.addAccount(Account(id: 'usd', name: 'Dólares', type: AccountType.savings, currency: 'USD', initialMinor: 10000));
      l.rates.rates['USD'] = 4000;
      final Budget b = await l.addBudget(Budget(id: 'b', name: 'Mercado', amountMinor: 100000000, startDate: DateTime(2026, 10, 1)));
      await l.addTx(Tx(id: 'u', kind: TxKind.expense, amountMinor: 1000, accountId: 'usd', date: d(2026, 10, 10)));
      await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 4000000, accountId: 'a_cash', date: d(2026, 10, 11)));
      expect(l.progress(b).spentMinor, 4000000 + 4000000); // 40.000 pesos + US$ 10
      l.changeBaseCurrency('USD');
      expect(l.baseCurrency, 'USD');
      expect(b.amountMinor, 25000); // 1.000.000 pesos = US$ 250
      expect(l.rates.rates['COP'], closeTo(1 / 4000, 1e-12));
      expect(l.tx('u')!.rateToBase, closeTo(1, 1e-12));
      expect(l.toBase(400000000, 'COP'), 100000);
      // El gasto del presupuesto sigue siendo el mismo, ahora en dólares.
      expect(l.progress(b).spentMinor, 1000 + 1000);
    });

    test('sin tasa entre las dos monedas no cambia nada', () async {
      await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 4000000, accountId: 'a_cash', date: d(2026, 10, 11)));
      expect(() => l.changeBaseCurrency('EUR'), rejected(TxProblem.missingRate, currency: 'EUR'));
      expect(l.baseCurrency, 'COP');
    });

    test('un libro sin datos cambia de base sin tasa', () {
      l.changeBaseCurrency('USD');
      expect(l.baseCurrency, 'USD');
    });
  });

  test('G4: una transferencia sin destino no se anota (ni desde un favorito)', () async {
    await l.addAccount(Account(id: 'bank', name: 'Ahorros', type: AccountType.bank, initialMinor: 100000000));
    final TxTemplate tpl = await l.addTemplate(TxTemplate(id: 'tp', name: 'A Nequi', kind: TxKind.transfer, amountMinor: 5000000, accountId: 'bank'));
    expect(await l.applyTemplate(tpl), isNull);
    expect(l.txs, isEmpty);
    expect(l.balanceMinor('bank'), 100000000);
    await expectLater(l.addTx(Tx(id: 't', kind: TxKind.transfer, amountMinor: 5000000, accountId: 'bank', date: d(2026, 10, 10))), rejected(TxProblem.destination));
    await expectLater(l.addTx(Tx(id: 't', kind: TxKind.transfer, amountMinor: 5000000, accountId: 'bank', toAccountId: 'bank', date: d(2026, 10, 10))), rejected(TxProblem.sameAccount));
    expect(l.txs, isEmpty);
  });

  test('G5: lo pagado con una tarjeta débito cuadra en saldo, lista, informes y presupuestos', () async {
    await l.addAccount(Account(id: 'bank', name: 'Ahorros', type: AccountType.bank, initialMinor: 100000000));
    await l.addAccount(Account(id: 'deb', name: 'Débito', type: AccountType.debit, linkedAccountId: 'bank'));
    await l.addTx(Tx(id: 'x', kind: TxKind.expense, amountMinor: 5000000, accountId: 'deb', date: d(2026, 10, 5), categoryId: 'c_food'));
    final Period oct = l.periodSpec.containing(d(2026, 10, 16));
    expect(l.balanceMinor('bank'), 95000000);
    expect(l.search(const TxFilter(accountIds: <String>{'bank'})).map((Tx t) => t.id), <String>['x']);
    expect(l.totals(oct, accountId: 'bank').expenseMinor, 5000000);
    expect(l.byCategory(oct, accountId: 'bank').single.amountMinor, 5000000);
    final Budget bank = await l.addBudget(Budget(id: 'b', name: 'Banco', amountMinor: 100000000, accountId: 'bank', startDate: DateTime(2026, 10, 1)));
    expect(l.progress(bank).spentMinor, 5000000);
    // La débito ve lo suyo y el patrimonio no la cuenta dos veces.
    expect(l.search(const TxFilter(accountIds: <String>{'deb'})).length, 1);
    final Budget deb = await l.addBudget(Budget(id: 'bd', name: 'Débito', amountMinor: 100000000, accountId: 'deb', startDate: DateTime(2026, 10, 1)));
    expect(l.progress(deb).spentMinor, 5000000);
    expect(l.totals(oct, accountId: 'deb').expenseMinor, 5000000);
    expect(l.netWorthMinor(), 95000000);
  });

  test('M5: los compromisos fijos al mes se suman en la moneda base', () async {
    await pesosYDolares();
    l.rates.rates['USD'] = 4000;
    await l.addScheduled(Scheduled(id: 'arriendo', name: 'Arriendo', kind: TxKind.expense, amountMinor: 150000000, accountId: 'bank', nextDate: DateTime(2026, 11, 1)));
    await l.addScheduled(Scheduled(id: 'nube', name: 'Nube', kind: TxKind.expense, amountMinor: 1000, accountId: 'usd', nextDate: DateTime(2026, 11, 3)));
    await l.addScheduled(Scheduled(id: 'sueldo', name: 'Sueldo', kind: TxKind.income, amountMinor: 200000000, accountId: 'bank', nextDate: DateTime(2026, 10, 30), frequency: const Frequency(unit: FrequencyUnit.quincena)));
    await l.addScheduled(Scheduled(id: 'ahorro', name: 'Ahorro', kind: TxKind.transfer, amountMinor: 30000000, accountId: 'bank', toAccountId: 'usd', nextDate: DateTime(2026, 11, 2)));
    final MonthlyCommitments c = l.monthlyCommitments();
    expect(c.outMinor, 150000000 + 4000000); // US$ 10 = 40.000 pesos, no 10 pesos
    expect(c.inMinor, 400000000);
  });

  group('M6: reembolsos', () {
    test('descuentan del gasto en informes igual que en presupuestos, también en los globales', () async {
      await l.addTx(Tx(id: 'g', kind: TxKind.expense, amountMinor: 10000000, accountId: 'a_cash', date: d(2026, 10, 5), categoryId: 'c_food_groceries'));
      await l.addTx(Tx(id: 'r', kind: TxKind.income, amountMinor: 2000000, accountId: 'a_cash', date: d(2026, 10, 6), categoryId: 'c_food_groceries', description: 'Devolución'));
      await l.addTx(Tx(id: 's', kind: TxKind.income, amountMinor: 300000000, accountId: 'a_cash', date: d(2026, 10, 1), categoryId: 'c_salary'));
      final Period oct = l.periodSpec.containing(d(2026, 10, 16));
      final PeriodTotals t = l.totals(oct);
      expect(t.expenseMinor, 8000000);
      expect(t.incomeMinor, 300000000);
      expect(l.byCategory(oct).single.amountMinor, 8000000);
      expect(l.byCategory(oct, kind: CategoryKind.income).single.categoryId, 'c_salary');
      final Budget food = await l.addBudget(Budget(id: 'f', name: 'Comida', amountMinor: 50000000, categoryIds: <String>['c_food'], startDate: DateTime(2026, 10, 1)));
      final Budget all = await l.addBudget(Budget(id: 'a', name: 'Todo', amountMinor: 50000000, startDate: DateTime(2026, 10, 1)));
      expect(l.progress(food).spentMinor, 8000000);
      expect(l.progress(all).spentMinor, 8000000);
      // "Ver movimientos" muestra lo mismo que suma el presupuesto, subcategorías y reembolsos incluidos.
      final List<Tx> shown = l.budgetTxs(food, BudgetPeriods.containing(food, d(2026, 10, 16)));
      expect(shown.map((Tx x) => x.id).toSet(), <String>{'g', 'r'});
      expect(shown.fold<int>(0, (int a, Tx x) => a + l.budgetShare(food, x)), l.progress(food).spentMinor);
    });
  });

  test('M7: la división en categorías define el total y cada parte cuenta en su categoría', () async {
    final Tx t = await l.addTx(Tx(id: 'd', kind: TxKind.expense, amountMinor: 999, accountId: 'a_cash', date: d(2026, 10, 5), splits: <TxSplit>[const TxSplit(categoryId: 'c_food', amountMinor: 3000000), const TxSplit(categoryId: 'c_transport', amountMinor: 2000000)]));
    expect(t.amountMinor, 5000000);
    expect(t.categoryId, isNull);
    final Period oct = l.periodSpec.containing(d(2026, 10, 16));
    final Map<String?, int> byCat = <String?, int>{for (final CategoryTotal c in l.byCategory(oct)) c.categoryId: c.amountMinor};
    expect(byCat, <String?, int>{'c_food': 3000000, 'c_transport': 2000000});
    expect(l.balanceMinor('a_cash'), -5000000);
  });

  group('M8: tasa histórica', () {
    test('se conserva al editar, cambia al mover de moneda y al duplicar', () async {
      await l.addAccount(Account(id: 'usd', name: 'Dólares', type: AccountType.savings, currency: 'USD'));
      await l.addAccount(Account(id: 'eur', name: 'Euros', type: AccountType.savings, currency: 'EUR'));
      l.rates.rates['USD'] = 4000;
      l.rates.rates['EUR'] = 4500;
      final Tx t = await l.addTx(Tx(id: 'u', kind: TxKind.expense, amountMinor: 1000, accountId: 'usd', date: d(2026, 10, 10)));
      expect(t.rateToBase, 4000);
      l.rates.rates['USD'] = 4200;
      final Tx edited = t.copy(id: t.id, date: t.date)..description = 'Café';
      l.updateTx(edited);
      expect(l.tx('u')!.rateToBase, 4000);
      final Tx moved = l.tx('u')!.copy(id: 'u', date: t.date)..accountId = 'eur';
      l.updateTx(moved);
      expect(l.tx('u')!.currency, 'EUR');
      expect(l.tx('u')!.rateToBase, 4500);
      final Tx dup = await l.duplicateTx(l.tx('u')!);
      expect(dup.rateToBase, 4500);
      l.rates.rates['EUR'] = 4600;
      final Tx dup2 = await l.duplicateTx(l.tx('u')!);
      expect(dup2.rateToBase, 4600);
    });

    test('una cuenta que solo recibe transferencias está en uso', () async {
      await l.addAccount(Account(id: 'bank', name: 'Ahorros', type: AccountType.bank, initialMinor: 100000000));
      await l.addAccount(Account(id: 'poc', name: 'Bolsillo', type: AccountType.bank));
      expect(l.accountInUse('poc'), isFalse);
      await l.addTx(Tx(id: 't', kind: TxKind.transfer, amountMinor: 100, accountId: 'bank', toAccountId: 'poc', date: d(2026, 10, 10)));
      expect(l.accountInUse('poc'), isTrue);
    });
  });

  test('M15: ajustar el saldo real no cuenta como gasto ni ingreso', () async {
    final Tx? adj = await l.adjustBalance(l.account('a_cash')!, 2500000);
    expect(adj, isNotNull);
    expect(adj!.isAdjustment, isTrue);
    expect(l.balanceMinor('a_cash'), 2500000);
    final Period oct = l.periodSpec.containing(d(2026, 10, 16));
    expect(l.totals(oct).incomeMinor, 0);
    expect(l.byCategory(oct, kind: CategoryKind.income), isEmpty);
    final Budget all = await l.addBudget(Budget(id: 'a', name: 'Todo', amountMinor: 100, startDate: DateTime(2026, 10, 1)));
    await l.adjustBalance(l.account('a_cash')!, 1000000);
    expect(l.balanceMinor('a_cash'), 1000000);
    expect(l.progress(all).spentMinor, 0);
    expect(await l.adjustBalance(l.account('a_cash')!, 1000000), isNull);
  });

  test('M18: archivar una cuenta pausa sus programados y suelta sus favoritos', () async {
    await l.addAccount(Account(id: 'nq', name: 'Nequi', type: AccountType.wallet));
    final Scheduled s = await l.addScheduled(Scheduled(id: 's', name: 'Celular', kind: TxKind.expense, amountMinor: 5500000, accountId: 'nq', nextDate: DateTime(2026, 10, 1)));
    final Scheduled to = await l.addScheduled(Scheduled(id: 't', name: 'Recarga', kind: TxKind.transfer, amountMinor: 100, accountId: 'a_cash', toAccountId: 'nq', nextDate: DateTime(2026, 10, 1)));
    final TxTemplate tpl = await l.addTemplate(TxTemplate(id: 'tp', name: 'Bus', amountMinor: 310000, accountId: 'nq'));
    l.setArchived(l.account('nq')!, true);
    expect(s.enabled, isFalse);
    expect(to.enabled, isFalse);
    expect(tpl.accountId, isNull);
    expect(l.processScheduled(), isEmpty);
    expect(await l.applyTemplate(tpl), isNull);
    expect(l.txs, isEmpty);
  });

  test('M20 y M21: el saldo de hoy no incluye lo futuro y el fin de periodo es exclusivo', () async {
    await l.addTx(Tx(id: 'hoy', kind: TxKind.income, amountMinor: 100000, accountId: 'a_cash', date: d(2026, 10, 16, 23)));
    await l.addTx(Tx(id: 'futuro', kind: TxKind.expense, amountMinor: 30000, accountId: 'a_cash', date: d(2026, 10, 20)));
    await l.addTx(Tx(id: 'medianoche', kind: TxKind.expense, amountMinor: 5000, accountId: 'a_cash', date: DateTime(2026, 11, 1)));
    expect(l.balanceMinor('a_cash'), 100000);
    final Period oct = l.periodSpec.containing(d(2026, 10, 16));
    expect(l.balanceMinor('a_cash', before: oct.end), 70000);
    expect(oct.contains(DateTime(2026, 11, 1)), isFalse);
    // «Anotar ahora» un programado del 31 lo anota hoy (M23 de la segunda
    // ronda): con su fecha futura no contaría en el saldo de hoy.
    final Scheduled s = await l.addScheduled(Scheduled(id: 's', name: 'Internet', kind: TxKind.expense, amountMinor: 100, accountId: 'a_cash', nextDate: DateTime(2026, 10, 31), autoPost: false));
    final Tx posted = await l.postScheduled(s);
    expect(posted.date, d(2026, 10, 16));
    expect(oct.contains(posted.date), isTrue);
    expect(l.balanceMinor('a_cash'), 100000 - 100);
    expect(s.nextDate.isAfter(DateTime(2026, 10, 31)), isTrue);
  });

  test('G17: las categorías de fábrica siguen el idioma; las renombradas se respetan', () async {
    expect(l.category('c_food')!.name, 'Alimentación');
    l.category('c_transport')!.name = 'Buses';
    l.applyLanguage(false);
    expect(l.category('c_food')!.name, 'Food');
    expect(l.category('c_food_groceries')!.name, 'Groceries');
    expect(l.category('c_transport')!.name, 'Buses');
    expect(l.account('a_cash')!.name, 'Cash');
    l.applyLanguage(true);
    expect(l.category('c_food')!.name, 'Alimentación');
    expect(l.account('a_cash')!.name, 'Efectivo');
    // Un libro nuevo en inglés nace en inglés.
    final Directory other = await Directory.systemTemp.createTemp('plata_en');
    final Ledger en = Ledger(EncryptedStore(JsonStore(root: other), await CryptoBox.fromKeyStore(MemoryKeyStore())), spanish: false, clock: () => d(2026, 10, 16));
    await en.load();
    expect(en.category('c_food')!.name, 'Food');
    expect(en.account('a_cash')!.name, 'Cash');
    en.dispose();
    await other.delete(recursive: true);
  });

  test('M19: la aritmética de días es de calendario', () {
    // Sumar días con Duration correría la medianoche con horario de verano;
    // addDays y daysBetween cuentan días de calendario.
    expect(addDays(DateTime(2026, 3, 7, 0, 30), 1), DateTime(2026, 3, 8, 0, 30));
    expect(addDays(DateTime(2026, 10, 31), 1), DateTime(2026, 11, 1));
    expect(daysBetween(DateTime(2026, 3, 1, 23), DateTime(2026, 3, 31, 1)), 30);
    expect(daysBetween(DateTime(2026, 11, 1), DateTime(2026, 10, 31)), -1);
    final Budget weekly = Budget(id: 'w', name: 'w', amountMinor: 1, period: BudgetPeriod.week, startDate: DateTime(2026, 3, 2));
    final Period p = BudgetPeriods.containing(weekly, DateTime(2026, 3, 9, 1));
    expect(p.start, DateTime(2026, 3, 9));
    expect(p.end, DateTime(2026, 3, 16));
  });
}
