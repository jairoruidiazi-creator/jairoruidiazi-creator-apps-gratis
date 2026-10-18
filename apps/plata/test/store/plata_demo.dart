// Datos de ejemplo de las capturas de tienda: seis meses de una persona en
// Bogotá con sueldo quincenal. Son ficticios y sin marcas comerciales; las
// cifras siguen precios típicos de 2026 en Colombia.

import 'package:plata/core/ledger.dart';
import 'package:plata/model/models.dart';

/// "Hoy" en las capturas: sábado 31 de octubre de 2026, 9:41 a. m., recién
/// llegada la segunda quincena del mes.
final DateTime demoNow = DateTime(2026, 10, 31, 9, 41);

int cop(int pesos) => pesos * 100;

class _Desc {
  const _Desc(this.es, this.en);

  final String es;
  final String en;
  String of(bool spanish) => spanish ? es : en;
}

Future<void> seedDemo(Ledger l, {required bool spanish, bool withNotices = true}) async {
  String tr(String es, String en) => spanish ? es : en;

  // ------------------------------------------------------------- cuentas
  final Account cash = l.account('a_cash')!..initialMinor = cop(85000);
  await l.addAccount(Account(id: 'ahorros', name: tr('Cuenta de ahorros', 'Savings account'), type: AccountType.bank, icon: 'bank', color: 0xFF1565C0, initialMinor: cop(3420000), bank: 'bancolombia', last4: '7310'));
  await l.addAccount(Account(id: 'billetera', name: tr('Billetera digital', 'Digital wallet'), type: AccountType.wallet, icon: 'wallet', color: 0xFF6A1B9A, initialMinor: cop(240000), bank: 'nequi'));
  await l.addAccount(Account(id: 'tarjeta', name: tr('Tarjeta de crédito', 'Credit card'), type: AccountType.credit, icon: 'card', color: 0xFF37474F, cutDay: 15, payDay: 5, creditLimitMinor: cop(6500000), bank: 'bancolombia', last4: '4821'));
  await l.addAccount(Account(id: 'viaje', name: tr('Viaje de diciembre', 'December trip'), type: AccountType.pocket, icon: 'savings', color: 0xFF00897B, parentId: 'ahorros', initialMinor: cop(600000)));
  await l.addAccount(Account(id: 'cdt', name: tr('CDT a 6 meses', '6-month CD'), type: AccountType.investment, icon: 'trending', color: 0xFF00695C, initialMinor: cop(5000000)));
  cash.order = 10;

  Future<void> tx(DateTime d, TxKind k, int pesos, String account, String? category, _Desc desc, {String? to, int installments = 1}) async {
    await l.addTx(Tx(
      id: newId(),
      kind: k,
      amountMinor: cop(pesos),
      accountId: account,
      toAccountId: to,
      categoryId: category,
      date: d,
      description: desc.of(spanish),
      installments: installments,
      createdAt: d,
    ));
  }

  const _Desc salary = _Desc('Quincena', 'Paycheck');
  const _Desc rent = _Desc('Arriendo apartamento', 'Apartment rent');
  const _Desc hoa = _Desc('Administración', 'Building fees');
  const _Desc power = _Desc('Energía', 'Electricity');
  const _Desc water = _Desc('Agua y alcantarillado', 'Water');
  const _Desc gas = _Desc('Gas natural', 'Natural gas');
  const _Desc internet = _Desc('Internet y TV', 'Internet & TV');
  const _Desc phone = _Desc('Plan celular', 'Mobile plan');
  const _Desc groceries = _Desc('Mercado de la semana', 'Weekly groceries');
  const _Desc lunch = _Desc('Almuerzo ejecutivo', 'Set lunch');
  const _Desc coffee = _Desc('Tinto y pandebono', 'Coffee and cheese bread');
  const _Desc delivery = _Desc('Domicilio de pizza', 'Pizza delivery');
  const _Desc transit = _Desc('Recarga tarjeta de transporte', 'Transit card top-up');
  const _Desc taxi = _Desc('Taxi', 'Taxi');
  const _Desc pharmacy = _Desc('Farmacia', 'Pharmacy');
  const _Desc movies = _Desc('Cine', 'Movies');
  const _Desc streaming = _Desc('Series en línea', 'Streaming service');
  const _Desc music = _Desc('Música en línea', 'Music streaming');
  const _Desc haircut = _Desc('Peluquería', 'Haircut');
  const _Desc clothes = _Desc('Ropa', 'Clothes');
  const _Desc cardPayment = _Desc('Pago tarjeta de crédito', 'Credit card payment');
  const _Desc saving = _Desc('Ahorro para el viaje', 'Saving for the trip');

  // Seis meses: de mayo a octubre de 2026. Las cifras varían de forma fija
  // (sin azar) para que las capturas salgan siempre iguales.
  for (int m = 5; m <= 10; m++) {
    final int v = m - 5; // 0..5
    DateTime day(int d, [int h = 12]) => DateTime(2026, m, d, h, (v * 7 + d) % 60);
    bool past(DateTime d) => !d.isAfter(demoNow);
    Future<void> add(int d, TxKind k, int pesos, String account, String? cat, _Desc desc, {String? to, int installments = 1, int hour = 12}) async {
      final DateTime when = day(d, hour);
      if (past(when)) {
        await tx(when, k, pesos, account, cat, desc, to: to, installments: installments);
      }
    }

    await add(15, TxKind.income, 2150000, 'ahorros', 'c_salary_paycheck', salary, hour: 7);
    await add(DateTime(2026, m + 1, 0).day, TxKind.income, 2150000, 'ahorros', 'c_salary_paycheck', salary, hour: 7);
    await add(5, TxKind.expense, 1450000, 'ahorros', 'c_housing_rent', rent, hour: 9);
    await add(5, TxKind.expense, 210000, 'ahorros', 'c_housing_hoa_fees', hoa, hour: 9);
    await add(12, TxKind.expense, 98000 + v * 3700, 'ahorros', 'c_housing_electricity', power, hour: 18);
    if (m.isEven) {
      await add(14, TxKind.expense, 126400 + v * 1800, 'ahorros', 'c_housing_water', water, hour: 18);
    }
    await add(16, TxKind.expense, 27800 + v * 600, 'ahorros', 'c_housing_gas', gas, hour: 18);
    await add(18, TxKind.expense, 98900, 'tarjeta', 'c_housing_internet_tv', internet, hour: 8);
    await add(20, TxKind.expense, 55000, 'billetera', 'c_housing_mobile_phone', phone, hour: 8);
    // Mercado semanal
    for (final int d in <int>[3, 10, 17, 24]) {
      await add(d, TxKind.expense, 186000 + ((d * 13 + v * 29) % 7) * 9800, d == 17 ? 'tarjeta' : 'ahorros', 'c_food_groceries', groceries, hour: 17);
    }
    // Almuerzos y tintos entre semana
    for (final int d in <int>[2, 6, 8, 9, 13, 16, 21, 22, 23, 27]) {
      await add(d, TxKind.expense, 18000 + ((d + v) % 4) * 1500, 'billetera', 'c_food_restaurants', lunch, hour: 13);
    }
    for (final int d in <int>[6, 9, 14, 20, 26]) {
      await add(d, TxKind.expense, 4500 + ((d + v) % 3) * 1500, 'a_cash', 'c_food_coffee_snacks', coffee, hour: 8);
    }
    for (final int d in <int>[7, 19, 25]) {
      await add(d, TxKind.expense, 38000 + ((d * 3 + v) % 5) * 5200, 'tarjeta', 'c_food_delivery', delivery, hour: 20);
    }
    // Transporte
    for (final int d in <int>[1, 8, 15, 22]) {
      await add(d, TxKind.expense, 45000, 'billetera', 'c_transport_public_transit', transit, hour: 7);
    }
    for (final int d in <int>[11, 24]) {
      await add(d, TxKind.expense, 14500 + ((d + v) % 4) * 3100, 'billetera', 'c_transport_taxi_ride_apps', taxi, hour: 22);
    }
    // Salud, entretenimiento y personal
    await add(9, TxKind.expense, 32000 + v * 4400, 'billetera', 'c_health_medicines', pharmacy, hour: 19);
    await add(3, TxKind.expense, 26900, 'tarjeta', 'c_entertainment_subscriptions', streaming, hour: 6);
    await add(4, TxKind.expense, 16900, 'tarjeta', 'c_entertainment_subscriptions', music, hour: 6);
    if (m != 8) {
      await add(18, TxKind.expense, 68000, 'tarjeta', 'c_entertainment_going_out', movies, hour: 21);
    }
    if (m.isOdd) {
      await add(23, TxKind.expense, 35000, 'a_cash', 'c_personal_hair_care', haircut, hour: 11);
    }
    if (m == 6 || m == 9) {
      await add(26, TxKind.expense, m == 6 ? 189000 : 254000, 'tarjeta', 'c_personal_clothing_shoes', clothes, hour: 16);
    }
    // Ahorro al bolsillo y pago de la tarjeta
    await add(16, TxKind.transfer, 300000, 'ahorros', null, saving, to: 'viaje', hour: 8);
    await add(5, TxKind.transfer, 980000 + v * 45000, 'ahorros', null, cardPayment, to: 'tarjeta', hour: 10);
    // Retiro de efectivo
    await add(2, TxKind.transfer, 100000, 'ahorros', null, const _Desc('Retiro en cajero', 'ATM withdrawal'), to: 'a_cash', hour: 18);
  }
  // Compras a cuotas en la tarjeta
  await tx(DateTime(2026, 6, 10, 15, 20), TxKind.expense, 1689000, 'tarjeta', 'c_personal', const _Desc('Celular nuevo', 'New phone'), installments: 6);
  await tx(DateTime(2026, 8, 22, 11, 5), TxKind.expense, 2399900, 'tarjeta', 'c_household_furniture_appliances', const _Desc('Nevera', 'Refrigerator'), installments: 12);

  // ------------------------------------------------------- presupuestos
  final DateTime june = DateTime(2026, 6);
  await l.addBudget(Budget(id: 'b_mercado', name: tr('Mercado', 'Groceries'), amountMinor: cop(950000), categoryIds: <String>['c_food_groceries'], startDate: june));
  await l.addBudget(Budget(id: 'b_comer', name: tr('Comer fuera', 'Eating out'), amountMinor: cop(420000), categoryIds: <String>['c_food_restaurants', 'c_food_delivery', 'c_food_coffee_snacks'], startDate: june));
  await l.addBudget(Budget(id: 'b_transporte', name: tr('Transporte', 'Transport'), amountMinor: cop(320000), categoryIds: <String>['c_transport'], startDate: june));
  await l.addBudget(Budget(id: 'b_ocio', name: tr('Entretenimiento', 'Entertainment'), amountMinor: cop(160000), categoryIds: <String>['c_entertainment'], startDate: june, rollover: true));

  // --------------------------------------------------------- programados
  await l.addScheduled(Scheduled(id: 's_quincena', name: tr('Quincena', 'Paycheck'), kind: TxKind.income, amountMinor: cop(2150000), accountId: 'ahorros', categoryId: 'c_salary_paycheck', nextDate: DateTime(2026, 11, 15), anchorDate: DateTime(2026, 5, 15), lastPosted: DateTime(2026, 10, 31, 7), frequency: const Frequency(unit: FrequencyUnit.quincena)));
  await l.addScheduled(Scheduled(id: 's_arriendo', name: tr('Arriendo', 'Rent'), kind: TxKind.expense, amountMinor: cop(1450000), accountId: 'ahorros', categoryId: 'c_housing_rent', nextDate: DateTime(2026, 11, 5)));
  await l.addScheduled(Scheduled(id: 's_admin', name: tr('Administración', 'Building fees'), kind: TxKind.expense, amountMinor: cop(210000), accountId: 'ahorros', categoryId: 'c_housing_hoa_fees', nextDate: DateTime(2026, 11, 5)));
  await l.addScheduled(Scheduled(id: 's_internet', name: tr('Internet y TV', 'Internet & TV'), kind: TxKind.expense, amountMinor: cop(98900), accountId: 'tarjeta', categoryId: 'c_housing_internet_tv', nextDate: DateTime(2026, 11, 18)));
  await l.addScheduled(Scheduled(id: 's_celular', name: tr('Plan celular', 'Mobile plan'), kind: TxKind.expense, amountMinor: cop(55000), accountId: 'billetera', categoryId: 'c_housing_mobile_phone', nextDate: DateTime(2026, 11, 20), autoPost: false));

  // ------------------------------------------------- favoritos de un toque
  await l.addTemplate(TxTemplate(id: 't_tinto', name: tr('Tinto', 'Coffee'), amountMinor: cop(4500), accountId: 'a_cash', categoryId: 'c_food_coffee_snacks', icon: 'coffee', color: 0xFF795548, uses: 42));
  await l.addTemplate(TxTemplate(id: 't_almuerzo', name: tr('Almuerzo', 'Lunch'), amountMinor: cop(20000), accountId: 'billetera', categoryId: 'c_food_restaurants', icon: 'restaurant', color: 0xFFEF6C00, uses: 37));
  await l.addTemplate(TxTemplate(id: 't_transporte', name: tr('Recarga transporte', 'Transit top-up'), amountMinor: cop(45000), accountId: 'billetera', categoryId: 'c_transport_public_transit', icon: 'bus', color: 0xFF1976D2, uses: 21));
  await l.addTemplate(TxTemplate(id: 't_mercado', name: tr('Mercado', 'Groceries'), accountId: 'ahorros', categoryId: 'c_food_groceries', icon: 'cart', color: 0xFF2E7D32, uses: 18));

  // ------------------------------------------------- avisos por confirmar
  if (!withNotices) {
    return;
  }
  await l.addInbox(InboxItem(id: 'i_1', bank: 'bancolombia', kind: TxKind.expense, amountMinor: cop(62400), receivedAt: DateTime(2026, 10, 30, 20, 14), merchant: tr('RESTAURANTE EL FOGÓN', 'RESTAURANTE EL FOGÓN'), last4: '4821', rawTitle: 'Bancolombia', rawText: tr('Compraste \$62.400 en RESTAURANTE EL FOGÓN con tu tarjeta *4821.', 'Compraste \$62.400 en RESTAURANTE EL FOGÓN con tu tarjeta *4821.')));
  await l.addInbox(InboxItem(id: 'i_2', bank: 'nequi', kind: TxKind.income, amountMinor: cop(150000), receivedAt: DateTime(2026, 10, 31, 8, 52), merchant: 'Laura Gómez', rawTitle: 'Nequi', rawText: 'Laura Gómez te envió \$150.000.'));
}
