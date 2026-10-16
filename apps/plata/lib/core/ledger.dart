import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;

import '../model/models.dart';
import '../model/money.dart';
import 'crypto_store.dart';
import 'defaults.dart';
import 'periods.dart';

/// Filtro de búsqueda de movimientos.
class TxFilter {
  const TxFilter({
    this.text = '',
    this.accountIds = const <String>{},
    this.categoryIds = const <String>{},
    this.kinds = const <TxKind>{},
    this.from,
    this.to,
    this.minMinor,
    this.maxMinor,
    this.tags = const <String>{},
    this.onlyWithAttachment = false,
    this.onlyUncategorized = false,
    this.onlyUnreconciled = false,
  });

  final String text;
  final Set<String> accountIds;
  final Set<String> categoryIds;
  final Set<TxKind> kinds;
  final DateTime? from;
  final DateTime? to;
  final int? minMinor;
  final int? maxMinor;
  final Set<String> tags;
  final bool onlyWithAttachment;
  final bool onlyUncategorized;
  final bool onlyUnreconciled;

  bool get isEmpty => text.isEmpty && accountIds.isEmpty && categoryIds.isEmpty && kinds.isEmpty && from == null && to == null && minMinor == null && maxMinor == null && tags.isEmpty && !onlyWithAttachment && !onlyUncategorized && !onlyUnreconciled;

  TxFilter copyWith({String? text, Set<String>? accountIds, Set<String>? categoryIds, Set<TxKind>? kinds, DateTime? from, DateTime? to, int? minMinor, int? maxMinor, Set<String>? tags, bool? onlyWithAttachment, bool? onlyUncategorized, bool? onlyUnreconciled, bool clearDates = false, bool clearAmounts = false, bool clearMin = false, bool clearMax = false}) => TxFilter(
        text: text ?? this.text,
        accountIds: accountIds ?? this.accountIds,
        categoryIds: categoryIds ?? this.categoryIds,
        kinds: kinds ?? this.kinds,
        from: clearDates ? null : (from ?? this.from),
        to: clearDates ? null : (to ?? this.to),
        minMinor: clearAmounts || clearMin ? null : (minMinor ?? this.minMinor),
        maxMinor: clearAmounts || clearMax ? null : (maxMinor ?? this.maxMinor),
        tags: tags ?? this.tags,
        onlyWithAttachment: onlyWithAttachment ?? this.onlyWithAttachment,
        onlyUncategorized: onlyUncategorized ?? this.onlyUncategorized,
        onlyUnreconciled: onlyUnreconciled ?? this.onlyUnreconciled,
      );
}

/// Sugerencia de autocompletado a partir del historial.
class Suggestion {
  const Suggestion({required this.description, this.categoryId, this.accountId, this.payee = '', this.amountMinor, this.count = 1});

  final String description;
  final String? categoryId;
  final String? accountId;
  final String payee;
  final int? amountMinor;
  final int count;
}

/// Avance de un presupuesto en su periodo actual.
class BudgetProgress {
  const BudgetProgress({required this.budget, required this.period, required this.spentMinor, required this.carryMinor});

  final Budget budget;
  final Period period;
  final int spentMinor;

  /// Sobrante (+) o déficit (−) arrastrado de periodos anteriores.
  final int carryMinor;

  int get limitMinor => budget.amountMinor + carryMinor;
  int get availableMinor => limitMinor - spentMinor;
  double get fraction => limitMinor <= 0 ? (spentMinor > 0 ? 1 : 0) : (spentMinor / limitMinor).clamp(0.0, 1.0);
  bool get over => spentMinor > limitMinor;
}

/// Estado de cuenta de una tarjeta para un ciclo.
class CardStatement {
  const CardStatement({required this.cycle, required this.purchasesMinor, required this.installmentsMinor, required this.paymentsMinor});

  final CardCycle cycle;

  /// Compras de pago único del ciclo.
  final int purchasesMinor;

  /// Cuotas de compras diferidas que vencen en este ciclo.
  final int installmentsMinor;
  final int paymentsMinor;

  int get dueMinor => purchasesMinor + installmentsMinor - paymentsMinor;
}

/// Todo el libro: cuentas, categorías, movimientos, programados, presupuestos,
/// plantillas, avisos y tasas, con sus cálculos. Se guarda cifrado.
class Ledger extends ChangeNotifier {
  Ledger(this.store, {this.spanish = true, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final EncryptedStore store;
  final bool spanish;
  final DateTime Function() _clock;

  final List<Account> accounts = <Account>[];
  final List<Category> categories = <Category>[];
  final List<Tx> txs = <Tx>[];
  final List<Scheduled> scheduled = <Scheduled>[];
  final List<Budget> budgets = <Budget>[];
  final List<TxTemplate> templates = <TxTemplate>[];
  final List<InboxItem> inbox = <InboxItem>[];
  RateTable rates = RateTable();
  String baseCurrency = 'COP';
  PeriodSpec periodSpec = const PeriodSpec();
  bool loaded = false;
  Timer? _saveTimer;
  Future<void>? _saving;
  bool _dirty = false;

  static const String _file = 'ledger.json';

  // ------------------------------------------------------------------ carga

  /// Verdadero si el archivo existe pero no se pudo descifrar: la app no
  /// escribe nada hasta que el usuario restaure una copia (ver [replaceWith]).
  bool readOnly = false;

  Future<void> load() async {
    Map<String, dynamic>? j;
    try {
      j = await store.readJson(_file);
      readOnly = false;
    } on DecryptException catch (e) {
      debugPrint('$e');
      readOnly = true;
    }
    accounts.clear();
    categories.clear();
    txs.clear();
    scheduled.clear();
    budgets.clear();
    templates.clear();
    inbox.clear();
    if (j != null) {
      accounts.addAll(((j['accounts'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>().map(Account.fromJson));
      categories.addAll(((j['categories'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>().map(Category.fromJson));
      txs.addAll(((j['txs'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>().map(Tx.fromJson));
      scheduled.addAll(((j['scheduled'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>().map(Scheduled.fromJson));
      budgets.addAll(((j['budgets'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>().map(Budget.fromJson));
      templates.addAll(((j['templates'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>().map(TxTemplate.fromJson));
      inbox.addAll(((j['inbox'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>().map(InboxItem.fromJson));
      rates = RateTable.fromJson(j['rates'] as Map<String, dynamic>?);
      baseCurrency = j['baseCurrency'] as String? ?? 'COP';
      periodSpec = PeriodSpec(mode: j['periodMode'] == 'quincena' ? PeriodMode.quincena : PeriodMode.month, startDay: ((j['periodStartDay'] as num?)?.toInt() ?? 1).clamp(1, 28));
    }
    if (categories.isEmpty) {
      categories.addAll(Defaults.categories(spanish: spanish));
    }
    if (accounts.isEmpty) {
      accounts.addAll(Defaults.accounts(spanish: spanish));
    }
    _sortTxs();
    loaded = true;
    notifyListeners();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'exportedAt': _clock().toIso8601String(),
        'baseCurrency': baseCurrency,
        'periodMode': periodSpec.mode.name,
        'periodStartDay': periodSpec.startDay,
        'accounts': accounts.map((Account a) => a.toJson()).toList(),
        'categories': categories.map((Category c) => c.toJson()).toList(),
        'txs': txs.map((Tx t) => t.toJson()).toList(),
        'scheduled': scheduled.map((Scheduled s) => s.toJson()).toList(),
        'budgets': budgets.map((Budget b) => b.toJson()).toList(),
        'templates': templates.map((TxTemplate t) => t.toJson()).toList(),
        'inbox': inbox.map((InboxItem i) => i.toJson()).toList(),
        'rates': rates.toJson(),
      };

  /// Reemplaza todo el libro con un respaldo.
  Future<void> replaceWith(Map<String, dynamic> j) async {
    await store.writeJson(_file, j);
    await load();
  }

  /// Guarda con un pequeño retraso para agrupar cambios seguidos.
  void save() {
    if (readOnly) {
      notifyListeners();
      return;
    }
    _dirty = true;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () => unawaited(flush()));
  }

  /// Escribe de inmediato si hay cambios pendientes.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_dirty) {
      return _saving ?? Future<void>.value();
    }
    _dirty = false;
    final Future<void> f = store.writeJson(_file, toJson());
    _saving = f;
    try {
      await f;
    } finally {
      if (identical(_saving, f)) {
        _saving = null;
      }
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  void _sortTxs() => txs.sort((Tx a, Tx b) {
        final int c = b.date.compareTo(a.date);
        return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
      });

  // --------------------------------------------------------------- consultas

  Account? account(String? id) {
    if (id == null) {
      return null;
    }
    for (final Account a in accounts) {
      if (a.id == id) {
        return a;
      }
    }
    return null;
  }

  Category? category(String? id) {
    if (id == null) {
      return null;
    }
    for (final Category c in categories) {
      if (c.id == id) {
        return c;
      }
    }
    return null;
  }

  Tx? tx(String id) {
    for (final Tx t in txs) {
      if (t.id == id) {
        return t;
      }
    }
    return null;
  }

  List<Account> get activeAccounts => accounts.where((Account a) => !a.archived).toList()..sort((Account a, Account b) => a.order.compareTo(b.order));

  /// Subcategorías directas.
  List<Category> children(String parentId) => categories.where((Category c) => c.parentId == parentId && !c.archived).toList()..sort((Category a, Category b) => a.order.compareTo(b.order));

  List<Category> roots(CategoryKind kind) => categories.where((Category c) => c.parentId == null && c.kind == kind && !c.archived).toList()..sort((Category a, Category b) => a.order.compareTo(b.order));

  /// Una categoría y todas sus descendientes.
  Set<String> categoryTree(String id) {
    final Set<String> out = <String>{id};
    bool grew = true;
    while (grew) {
      grew = false;
      for (final Category c in categories) {
        if (c.parentId != null && out.contains(c.parentId) && out.add(c.id)) {
          grew = true;
        }
      }
    }
    return out;
  }

  String categoryPath(String? id) {
    final Category? c = category(id);
    if (c == null) {
      return '';
    }
    final Category? p = category(c.parentId);
    return p == null ? c.name : '${p.name} › ${c.name}';
  }

  /// Cuenta cuyo saldo mueve realmente una tarjeta débito.
  String effectiveAccountId(String id) {
    final Account? a = account(id);
    if (a != null && a.isDebit && a.linkedAccountId != null && account(a.linkedAccountId) != null) {
      return a.linkedAccountId!;
    }
    return id;
  }

  /// Tasa de una moneda a la base (1 unidad = r base), o null si no se conoce.
  double? rateToBase(String currency) => rates.rateFor(currency, baseCurrency);

  /// Convierte centavos de [currency] a la moneda base (si no hay tasa, devuelve el monto).
  int toBase(int minor, String currency, {double? rate}) {
    if (currency == baseCurrency) {
      return minor;
    }
    final double? r = rate ?? rateToBase(currency);
    return r == null ? minor : (minor * r).round();
  }

  // ------------------------------------------------------------------ saldos

  /// Saldo de una cuenta en su moneda (hasta [until] inclusive). Los bolsillos
  /// no se suman a la madre aquí; ver [balanceWithPockets].
  int balanceMinor(String accountId, {DateTime? until, bool includeDebitCards = true}) {
    int total = account(accountId)?.initialMinor ?? 0;
    for (final Tx t in txs) {
      if (until != null && t.date.isAfter(until)) {
        continue;
      }
      final String from = includeDebitCards ? effectiveAccountId(t.accountId) : t.accountId;
      final String? to = t.toAccountId == null ? null : (includeDebitCards ? effectiveAccountId(t.toAccountId!) : t.toAccountId);
      if (from == accountId) {
        total += t.signedMinor;
      }
      if (t.kind == TxKind.transfer && to == accountId) {
        total += t.toAmountMinor ?? t.amountMinor;
      }
    }
    return total;
  }

  int balanceWithPockets(String accountId, {DateTime? until}) {
    int total = balanceMinor(accountId, until: until);
    for (final Account a in accounts) {
      if (a.isPocket && a.parentId == accountId && !a.archived) {
        total += balanceMinor(a.id, until: until);
      }
    }
    return total;
  }

  /// Patrimonio neto en moneda base: activos menos deudas de las cuentas incluidas.
  int netWorthMinor({DateTime? until}) {
    int total = 0;
    for (final Account a in accounts) {
      if (a.archived || !a.includeInTotal || a.isDebit) {
        continue;
      }
      total += toBase(balanceMinor(a.id, until: until), a.currency);
    }
    return total;
  }

  /// Deuda total de tarjetas y préstamos (positiva) en moneda base.
  int debtMinor() {
    int total = 0;
    for (final Account a in accounts) {
      if (a.archived || !(a.isCredit || a.type == AccountType.loan)) {
        continue;
      }
      final int b = toBase(balanceMinor(a.id), a.currency);
      if (b < 0) {
        total += -b;
      }
    }
    return total;
  }

  // ------------------------------------------------------------- movimientos

  Future<Tx> addTx(Tx t) async {
    _normalize(t);
    txs.add(t);
    _sortTxs();
    save();
    return t;
  }

  void updateTx(Tx t) {
    _normalize(t);
    _sortTxs();
    save();
  }

  Future<void> deleteTx(String id) async {
    txs.removeWhere((Tx t) => t.id == id);
    save();
  }

  void _normalize(Tx t) {
    final Account? a = account(t.accountId);
    if (a != null) {
      t.currency = a.currency;
      t.rateToBase ??= rateToBase(a.currency);
    }
    if (t.kind != TxKind.transfer) {
      t.toAccountId = null;
      t.toAmountMinor = null;
    } else {
      t.categoryId = null;
      t.splits.clear();
      final Account? to = account(t.toAccountId);
      if (to != null && a != null && to.currency == a.currency) {
        t.toAmountMinor = null;
      }
    }
    if (t.splits.isNotEmpty) {
      t.amountMinor = t.splits.fold<int>(0, (int s, TxSplit p) => s + p.amountMinor);
      t.categoryId = null;
    }
    if (t.installments < 1) {
      t.installments = 1;
    }
  }

  /// Movimientos que cumplen el filtro, ordenados del más reciente al más antiguo.
  List<Tx> search(TxFilter f) {
    final String q = f.text.trim().toLowerCase();
    return txs.where((Tx t) {
      if (f.kinds.isNotEmpty && !f.kinds.contains(t.kind)) {
        return false;
      }
      if (f.accountIds.isNotEmpty && !f.accountIds.contains(t.accountId) && !(t.toAccountId != null && f.accountIds.contains(t.toAccountId))) {
        return false;
      }
      if (f.categoryIds.isNotEmpty) {
        final bool inCat = (t.categoryId != null && f.categoryIds.contains(t.categoryId)) || t.splits.any((TxSplit s) => f.categoryIds.contains(s.categoryId));
        if (!inCat) {
          return false;
        }
      }
      if (f.from != null && t.date.isBefore(dateOnly(f.from!))) {
        return false;
      }
      if (f.to != null && !t.date.isBefore(dateOnly(f.to!).add(const Duration(days: 1)))) {
        return false;
      }
      if (f.minMinor != null && t.amountMinor < f.minMinor!) {
        return false;
      }
      if (f.maxMinor != null && t.amountMinor > f.maxMinor!) {
        return false;
      }
      if (f.tags.isNotEmpty && !f.tags.any(t.tags.contains)) {
        return false;
      }
      if (f.onlyWithAttachment && t.attachments.isEmpty) {
        return false;
      }
      if (f.onlyUncategorized && !(t.kind != TxKind.transfer && t.categoryId == null && t.splits.isEmpty)) {
        return false;
      }
      if (f.onlyUnreconciled && t.reconciled) {
        return false;
      }
      if (q.isNotEmpty) {
        final String hay = '${t.description} ${t.payee} ${t.notes} ${t.tags.join(' ')} ${categoryPath(t.categoryId)} ${account(t.accountId)?.name ?? ''} ${t.checkNumber} ${Money.format(t.amountMinor, t.currency, withSymbol: false)}'.toLowerCase();
        if (!hay.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  List<Tx> inPeriod(Period p, {String? accountId}) => txs.where((Tx t) => p.contains(t.date) && (accountId == null || effectiveAccountId(t.accountId) == accountId || t.toAccountId == accountId)).toList();

  /// Totales de un periodo en moneda base: ingresos, gastos (positivos) y neto.
  /// Las transferencias no cuentan.
  PeriodTotals totals(Period p, {String? accountId}) {
    int income = 0;
    int expense = 0;
    for (final Tx t in inPeriod(p, accountId: accountId)) {
      if (t.kind == TxKind.income) {
        income += toBase(t.amountMinor, t.currency, rate: t.rateToBase);
      } else if (t.kind == TxKind.expense) {
        expense += toBase(t.amountMinor, t.currency, rate: t.rateToBase);
      }
    }
    return PeriodTotals(period: p, incomeMinor: income, expenseMinor: expense);
  }

  /// Gasto (o ingreso) por categoría raíz en un periodo, en moneda base, de mayor a menor.
  List<CategoryTotal> byCategory(Period p, {CategoryKind kind = CategoryKind.expense, String? accountId, bool roots = true}) {
    final Map<String, int> sums = <String, int>{};
    final TxKind txKind = kind == CategoryKind.expense ? TxKind.expense : TxKind.income;
    for (final Tx t in inPeriod(p, accountId: accountId)) {
      if (t.kind != txKind) {
        continue;
      }
      if (t.splits.isNotEmpty) {
        for (final TxSplit s in t.splits) {
          final String key = roots ? _rootOf(s.categoryId) : s.categoryId;
          sums[key] = (sums[key] ?? 0) + toBase(s.amountMinor, t.currency, rate: t.rateToBase);
        }
      } else {
        final String key = t.categoryId == null ? '' : (roots ? _rootOf(t.categoryId!) : t.categoryId!);
        sums[key] = (sums[key] ?? 0) + toBase(t.amountMinor, t.currency, rate: t.rateToBase);
      }
    }
    final List<CategoryTotal> out = sums.entries.map((MapEntry<String, int> e) => CategoryTotal(categoryId: e.key.isEmpty ? null : e.key, amountMinor: e.value)).toList();
    out.sort((CategoryTotal a, CategoryTotal b) => b.amountMinor.compareTo(a.amountMinor));
    return out;
  }

  String _rootOf(String categoryId) {
    Category? c = category(categoryId);
    int guard = 0;
    while (c != null && c.parentId != null && guard++ < 10) {
      final Category? p = category(c.parentId);
      if (p == null) {
        break;
      }
      c = p;
    }
    return c?.id ?? categoryId;
  }

  /// Totales de los últimos [n] periodos (orden cronológico).
  List<PeriodTotals> trend(int n, {DateTime? now, String? accountId}) => periodSpec.lastN(now ?? _clock(), n).map((Period p) => totals(p, accountId: accountId)).toList();

  /// Flujo por cuenta en un periodo: entradas y salidas incluyendo transferencias.
  List<AccountFlow> cashFlow(Period p) {
    final Map<String, List<int>> m = <String, List<int>>{};
    void add(String id, int inMinor, int outMinor) {
      final List<int> v = m.putIfAbsent(id, () => <int>[0, 0]);
      v[0] += inMinor;
      v[1] += outMinor;
    }

    for (final Tx t in inPeriod(p)) {
      final String from = effectiveAccountId(t.accountId);
      switch (t.kind) {
        case TxKind.income:
          add(from, t.amountMinor, 0);
          break;
        case TxKind.expense:
          add(from, 0, t.amountMinor);
          break;
        case TxKind.transfer:
          add(from, 0, t.amountMinor);
          if (t.toAccountId != null) {
            add(effectiveAccountId(t.toAccountId!), t.toAmountMinor ?? t.amountMinor, 0);
          }
          break;
      }
    }
    final List<AccountFlow> out = <AccountFlow>[];
    for (final Account a in activeAccounts) {
      final List<int>? v = m[a.id];
      if (v != null) {
        out.add(AccountFlow(account: a, inMinor: v[0], outMinor: v[1]));
      }
    }
    return out;
  }

  // ----------------------------------------------------------- autocompletar

  /// Descripciones usadas antes que empiezan por (o contienen) [prefix], con la
  /// categoría, cuenta, beneficiario y monto más recientes.
  List<Suggestion> suggest(String prefix, {TxKind? kind, int limit = 6}) {
    final String q = prefix.trim().toLowerCase();
    if (q.isEmpty) {
      return <Suggestion>[];
    }
    final Map<String, List<Tx>> groups = <String, List<Tx>>{};
    for (final Tx t in txs) {
      if (kind != null && t.kind != kind) {
        continue;
      }
      final String d = t.description.trim();
      if (d.isEmpty) {
        continue;
      }
      final String key = d.toLowerCase();
      if (key.startsWith(q) || key.contains(q)) {
        groups.putIfAbsent(key, () => <Tx>[]).add(t);
      }
    }
    final List<Suggestion> out = groups.values.map((List<Tx> g) {
      final Tx last = g.first; // txs está ordenado del más reciente al más antiguo
      return Suggestion(description: last.description.trim(), categoryId: last.categoryId, accountId: last.accountId, payee: last.payee, amountMinor: last.amountMinor, count: g.length);
    }).toList();
    out.sort((Suggestion a, Suggestion b) {
      final bool sa = a.description.toLowerCase().startsWith(q);
      final bool sb = b.description.toLowerCase().startsWith(q);
      if (sa != sb) {
        return sa ? -1 : 1;
      }
      return b.count.compareTo(a.count);
    });
    return out.take(limit).toList();
  }

  Set<String> get allTags {
    final Set<String> s = <String>{};
    for (final Tx t in txs) {
      s.addAll(t.tags);
    }
    return s;
  }

  Set<String> get allPayees => txs.map((Tx t) => t.payee.trim()).where((String p) => p.isNotEmpty).toSet();

  // ------------------------------------------------------------ presupuestos

  /// Gasto de un presupuesto en un periodo dado (moneda base).
  int budgetSpent(Budget b, Period p) {
    final Set<String> cats = <String>{};
    for (final String id in b.categoryIds) {
      cats.addAll(categoryTree(id));
    }
    int spent = 0;
    for (final Tx t in txs) {
      if (!p.contains(t.date)) {
        continue;
      }
      if (b.accountId != null && effectiveAccountId(t.accountId) != b.accountId) {
        continue;
      }
      if (t.kind == TxKind.expense) {
        if (cats.isEmpty) {
          spent += toBase(t.amountMinor, t.currency, rate: t.rateToBase);
        } else if (t.splits.isNotEmpty) {
          for (final TxSplit s in t.splits) {
            if (cats.contains(s.categoryId)) {
              spent += toBase(s.amountMinor, t.currency, rate: t.rateToBase);
            }
          }
        } else if (t.categoryId != null && cats.contains(t.categoryId)) {
          spent += toBase(t.amountMinor, t.currency, rate: t.rateToBase);
        }
      } else if (t.kind == TxKind.income && cats.isNotEmpty && t.categoryId != null && cats.contains(t.categoryId)) {
        // Reembolso anotado en una categoría de gasto: descuenta.
        spent -= toBase(t.amountMinor, t.currency, rate: t.rateToBase);
      }
    }
    return spent;
  }

  BudgetProgress progress(Budget b, {DateTime? now}) {
    final Period current = BudgetPeriods.containing(b, now ?? _clock());
    int carry = 0;
    if (b.rollover) {
      Period p = BudgetPeriods.previous(b, current);
      int guard = 0;
      final DateTime start = dateOnly(b.startDate);
      while (!p.end.isBefore(start.add(const Duration(days: 1))) && guard++ < 120) {
        carry += b.amountMinor - budgetSpent(b, p);
        if (!p.start.isAfter(start)) {
          break;
        }
        p = BudgetPeriods.previous(b, p);
      }
    }
    return BudgetProgress(budget: b, period: current, spentMinor: budgetSpent(b, current), carryMinor: carry);
  }

  // ------------------------------------------------------------- programados

  /// Anota los programados vencidos (si son automáticos) y avanza sus fechas.
  /// Devuelve los movimientos creados.
  List<Tx> processScheduled({DateTime? now}) {
    final DateTime today = dateOnly(now ?? _clock());
    final List<Tx> created = <Tx>[];
    bool changed = false;
    for (final Scheduled s in scheduled) {
      if (!s.enabled) {
        continue;
      }
      int guard = 0;
      while (!dateOnly(s.nextDate).isAfter(today) && guard++ < 400) {
        if (s.endDate != null && dateOnly(s.nextDate).isAfter(dateOnly(s.endDate!))) {
          s.enabled = false;
          changed = true;
          break;
        }
        if (!s.autoPost) {
          // Los manuales quedan vencidos hasta que el usuario los anote o salte.
          break;
        }
        {
          final Tx t = Tx(
            id: newId(),
            kind: s.kind,
            amountMinor: s.amountMinor,
            accountId: s.accountId,
            toAccountId: s.toAccountId,
            categoryId: s.categoryId,
            date: dateOnly(s.nextDate).add(const Duration(hours: 12)),
            description: s.description.isNotEmpty ? s.description : s.name,
            payee: s.payee,
            tags: List<String>.from(s.tags),
            scheduledId: s.id,
            source: 'scheduled',
          );
          _normalize(t);
          txs.add(t);
          created.add(t);
          s.lastPosted = t.date;
        }
        s.nextDate = s.frequency.next(dateOnly(s.nextDate), anchor: s.anchorDate);
        changed = true;
      }
    }
    if (changed) {
      _sortTxs();
      save();
    }
    return created;
  }

  /// Programados que vencen en los próximos [days] días (incluye los vencidos no automáticos).
  List<Scheduled> upcoming({int days = 7, DateTime? now}) {
    final DateTime today = dateOnly(now ?? _clock());
    final DateTime limit = today.add(Duration(days: days));
    final List<Scheduled> out = scheduled.where((Scheduled s) => s.enabled && dateOnly(s.nextDate).isBefore(limit.add(const Duration(days: 1)))).toList();
    out.sort((Scheduled a, Scheduled b) => a.nextDate.compareTo(b.nextDate));
    return out;
  }

  // ---------------------------------------------------------------- tarjetas

  /// Estado de cuenta de una tarjeta para el ciclo que contiene [date].
  ///
  /// Compras y cuotas: por fecha dentro del ciclo (corte anterior, corte].
  /// Pagos: los abonos hechos entre la fecha de pago del ciclo anterior y la
  /// fecha de pago de este, que es como el banco los aplica.
  CardStatement statement(Account card, {DateTime? date}) {
    final CardCycle cycle = CardCycle.current(card, date ?? _clock());
    final DateTime prevPay = cycle.previous(card).payDate;
    int purchases = 0;
    int installments = 0;
    int payments = 0;
    for (final Tx t in txs) {
      final bool from = effectiveAccountId(t.accountId) == card.id;
      final bool to = t.toAccountId == card.id;
      if (t.kind == TxKind.expense && from) {
        if (t.installments <= 1) {
          if (cycle.period.contains(t.date)) {
            purchases += t.amountMinor;
          }
        } else {
          // Cuota k (1..n) cae en el ciclo k-ésimo después del de la compra.
          final CardCycle purchaseCycle = CardCycle.current(card, t.date);
          final int k = _cyclesBetween(purchaseCycle.cut, cycle.cut);
          if (k >= 1 && k <= t.installments) {
            installments += (t.amountMinor / t.installments).round();
          }
        }
      } else if (t.kind == TxKind.income && from && cycle.period.contains(t.date)) {
        // Reembolso en la tarjeta: descuenta de las compras del ciclo.
        purchases -= t.amountMinor;
      } else if (t.kind == TxKind.transfer && to) {
        final DateTime d = dateOnly(t.date);
        if (d.isAfter(prevPay) && !d.isAfter(cycle.payDate)) {
          payments += t.toAmountMinor ?? t.amountMinor;
        }
      }
    }
    return CardStatement(cycle: cycle, purchasesMinor: purchases, installmentsMinor: installments, paymentsMinor: payments);
  }

  /// Estado de cuenta cuyo pago es el próximo: el del ciclo ya cerrado si su
  /// fecha de pago no ha pasado y aún debe algo; si no, el del ciclo en curso.
  CardStatement nextPayment(Account card, {DateTime? now}) {
    final DateTime today = dateOnly(now ?? _clock());
    final CardCycle current = CardCycle.current(card, today);
    final CardCycle prev = current.previous(card);
    if (!prev.payDate.isBefore(today)) {
      final CardStatement closed = statement(card, date: prev.cut);
      if (closed.dueMinor > 0) {
        return closed;
      }
    }
    return statement(card, date: today);
  }

  static int _cyclesBetween(DateTime cutA, DateTime cutB) => (cutB.year - cutA.year) * 12 + (cutB.month - cutA.month);

  /// Cuotas de una compra diferida que aún no se han facturado al terminar el
  /// ciclo que contiene [now] (la primera cuota se factura en el ciclo
  /// siguiente al de la compra).
  int remainingInstallments(Tx t, {DateTime? now}) {
    final Account? card = account(t.accountId);
    if (card == null || t.installments <= 1) {
      return 0;
    }
    final int k = _cyclesBetween(CardCycle.current(card, t.date).cut, CardCycle.current(card, now ?? _clock()).cut);
    return (t.installments - k).clamp(0, t.installments);
  }

  // -------------------------------------------------------- otras entidades

  Future<Account> addAccount(Account a) async {
    a.order = accounts.isEmpty ? 0 : accounts.map((Account x) => x.order).reduce((int x, int y) => x > y ? x : y) + 1;
    accounts.add(a);
    save();
    return a;
  }

  void deleteAccount(String id) {
    if (txs.any((Tx t) => t.accountId == id || t.toAccountId == id)) {
      final Account? a = account(id);
      if (a != null) {
        a.archived = true;
      }
    } else {
      accounts.removeWhere((Account a) => a.id == id);
    }
    save();
  }

  Future<Category> addCategory(Category c) async {
    c.order = categories.length;
    categories.add(c);
    save();
    return c;
  }

  void deleteCategory(String id) {
    final Set<String> tree = categoryTree(id);
    final bool used = txs.any((Tx t) => tree.contains(t.categoryId) || t.splits.any((TxSplit s) => tree.contains(s.categoryId)));
    for (final Category c in categories) {
      if (tree.contains(c.id)) {
        c.archived = true;
      }
    }
    if (!used) {
      categories.removeWhere((Category c) => tree.contains(c.id));
    }
    save();
  }

  Future<TxTemplate> addTemplate(TxTemplate t) async {
    templates.add(t);
    save();
    return t;
  }

  /// Anota una plantilla de un toque (si tiene monto y cuenta).
  Future<Tx?> applyTemplate(TxTemplate tpl, {DateTime? date}) async {
    if (tpl.amountMinor == null || tpl.accountId == null) {
      return null;
    }
    tpl.uses += 1;
    return addTx(Tx(
      id: newId(),
      kind: tpl.kind,
      amountMinor: tpl.amountMinor!,
      accountId: tpl.accountId!,
      toAccountId: tpl.toAccountId,
      categoryId: tpl.categoryId,
      date: date ?? _clock(),
      description: tpl.description.isNotEmpty ? tpl.description : tpl.name,
      payee: tpl.payee,
      tags: List<String>.from(tpl.tags),
      source: 'template',
    ));
  }

  Future<Scheduled> addScheduled(Scheduled s) async {
    scheduled.add(s);
    save();
    return s;
  }

  Future<Budget> addBudget(Budget b) async {
    budgets.add(b);
    save();
    return b;
  }

  void deleteBudget(String id) {
    budgets.removeWhere((Budget b) => b.id == id);
    save();
  }

  void deleteScheduled(String id) {
    scheduled.removeWhere((Scheduled s) => s.id == id);
    save();
  }

  void deleteTemplate(String id) {
    templates.removeWhere((TxTemplate t) => t.id == id);
    save();
  }

  /// Anota ahora un programado (aunque no sea automático) y avanza su fecha.
  Future<Tx> postScheduled(Scheduled s, {DateTime? date}) async {
    final DateTime when = date ?? dateOnly(s.nextDate);
    final Tx created = await addTx(Tx(
      id: newId(),
      kind: s.kind,
      amountMinor: s.amountMinor,
      accountId: s.accountId,
      toAccountId: s.toAccountId,
      categoryId: s.categoryId,
      date: when,
      description: s.description.isNotEmpty ? s.description : s.name,
      payee: s.payee,
      tags: List<String>.from(s.tags),
      scheduledId: s.id,
      source: 'scheduled',
    ));
    s.lastPosted = when;
    s.nextDate = s.frequency.next(dateOnly(s.nextDate), anchor: s.anchorDate);
    if (s.endDate != null && s.nextDate.isAfter(s.endDate!)) {
      s.enabled = false;
    }
    save();
    return created;
  }

  /// Salta la próxima ocurrencia de un programado.
  void skipScheduled(Scheduled s) {
    s.nextDate = s.frequency.next(dateOnly(s.nextDate), anchor: s.anchorDate);
    if (s.endDate != null && s.nextDate.isAfter(s.endDate!)) {
      s.enabled = false;
    }
    save();
  }

  // ------------------------------------------------------------------ avisos

  Future<InboxItem> addInbox(InboxItem item) async {
    // Evita duplicados del mismo aviso (mismo banco, monto y minuto).
    for (final InboxItem i in inbox) {
      if (i.bank == item.bank && i.amountMinor == item.amountMinor && i.kind == item.kind && i.receivedAt.difference(item.receivedAt).abs() < const Duration(minutes: 2) && i.rawText == item.rawText) {
        return i;
      }
    }
    item.accountId ??= guessAccountForNotice(item)?.id;
    inbox.insert(0, item);
    if (inbox.length > 200) {
      inbox.removeRange(200, inbox.length);
    }
    save();
    return item;
  }

  /// Cuenta que mejor casa con un aviso: por últimos dígitos y luego por banco.
  Account? guessAccountForNotice(InboxItem item) {
    final List<Account> candidates = activeAccounts.where((Account a) => a.bank == item.bank).toList();
    if (item.last4.isNotEmpty) {
      for (final Account a in candidates) {
        if (a.last4 == item.last4) {
          return a;
        }
      }
    }
    if (candidates.length == 1) {
      return candidates.first;
    }
    for (final Account a in candidates) {
      if (item.kind == TxKind.expense && a.isCredit) {
        return a;
      }
    }
    return candidates.isEmpty ? null : candidates.first;
  }

  Future<Tx?> acceptInbox(InboxItem item, {String? accountId, String? categoryId, String? description}) async {
    final String? acc = accountId ?? item.accountId;
    if (acc == null) {
      return null;
    }
    item.status = 'accepted';
    item.accountId = acc;
    return addTx(Tx(
      id: newId(),
      kind: item.kind == TxKind.transfer ? TxKind.expense : item.kind,
      amountMinor: item.amountMinor,
      accountId: acc,
      categoryId: categoryId,
      date: item.receivedAt,
      description: description ?? (item.merchant.isNotEmpty ? item.merchant : item.rawTitle),
      notes: item.rawText,
      source: 'notice',
    ));
  }

  void dismissInbox(InboxItem item) {
    item.status = 'dismissed';
    save();
  }

  List<InboxItem> get pendingInbox => inbox.where((InboxItem i) => i.status == 'pending').toList();
}

class PeriodTotals {
  const PeriodTotals({required this.period, required this.incomeMinor, required this.expenseMinor});

  final Period period;
  final int incomeMinor;
  final int expenseMinor;

  int get netMinor => incomeMinor - expenseMinor;
}

class CategoryTotal {
  const CategoryTotal({required this.categoryId, required this.amountMinor});

  final String? categoryId;
  final int amountMinor;
}

class AccountFlow {
  const AccountFlow({required this.account, required this.inMinor, required this.outMinor});

  final Account account;
  final int inMinor;
  final int outMinor;

  int get netMinor => inMinor - outMinor;
}
