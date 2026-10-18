import 'dart:async';

import 'package:clock/clock.dart' as clk;
import 'package:flutter/foundation.dart' hide Category;

import '../model/models.dart';
import '../model/money.dart';
import 'bank_rules.dart';
import 'crypto_store.dart';
import 'defaults.dart';
import 'key_setup.dart';
import 'periods.dart';
import 'storage.dart';

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

/// Estado de cuenta estimado de una tarjeta de crédito para un ciclo.
///
/// Es el **capital** que según lo anotado en Plata vence en la fecha de pago:
/// no incluye intereses, cuota de manejo ni seguros, que solo conoce el banco.
class CardStatement {
  const CardStatement({required this.cycle, required this.previousMinor, required this.purchasesMinor, required this.advancesMinor, required this.installmentsMinor, required this.paymentsMinor});

  final CardCycle cycle;

  /// Saldo anterior: lo facturado en ciclos anteriores (y la deuda inicial de
  /// la tarjeta) menos los abonos hechos hasta la fecha de pago anterior.
  /// Negativo = saldo a favor que se descuenta de este estado.
  final int previousMinor;

  /// Compras de una cuota del ciclo.
  final int purchasesMinor;

  /// Avances y transferencias que salieron de la tarjeta en el ciclo.
  final int advancesMinor;

  /// Cuotas de compras diferidas que se facturan en este ciclo.
  final int installmentsMinor;

  /// Abonos (pagos y devoluciones) hechos entre la fecha de pago anterior y la
  /// de este estado.
  final int paymentsMinor;

  /// Lo nuevo que se factura en el ciclo.
  int get chargesMinor => purchasesMinor + advancesMinor + installmentsMinor;

  /// Capital estimado pendiente del estado (negativo = saldo a favor).
  int get balanceMinor => previousMinor + chargesMinor - paymentsMinor;

  /// Lo que falta por pagar (nunca negativo).
  int get dueMinor => balanceMinor > 0 ? balanceMinor : 0;

  /// Saldo a favor (nunca negativo).
  int get creditMinor => balanceMinor < 0 ? -balanceMinor : 0;
}

/// Por qué un movimiento no se puede guardar.
enum TxProblem {
  /// Monto vacío, cero o negativo.
  amount,

  /// La cuenta de origen no existe.
  account,

  /// Transferencia sin cuenta de destino válida.
  destination,

  /// Transferencia hacia la misma cuenta.
  sameAccount,

  /// Transferencia entre monedas sin monto recibido y sin tasa para calcularlo.
  missingRate,
}

/// Un movimiento que el libro no acepta (ver [TxProblem]).
class TxRejected implements Exception {
  const TxRejected(this.problem, {this.currency});

  final TxProblem problem;

  /// Moneda sin tasa, para [TxProblem.missingRate].
  final String? currency;

  @override
  String toString() => 'TxRejected(${problem.name}${currency == null ? '' : ', $currency'})';
}

/// Por qué el libro está en modo de recuperación (solo lectura).
enum RecoveryReason {
  /// El archivo existe pero no se pudo descifrar (otra llave o archivo dañado).
  unreadable,

  /// Se descifró, pero su contenido no tiene la forma esperada o es de una
  /// versión más nueva de Plata.
  invalid,

  /// El archivo desapareció y quedan copias automáticas para restaurar.
  missing,
}

/// Lo que suman al mes los programados (ver [Ledger.monthlyCommitments]).
class MonthlyCommitments {
  const MonthlyCommitments({required this.outMinor, required this.inMinor});

  final int outMinor;
  final int inMinor;
}

/// Cuenta que corresponde a un aviso bancario.
class NoticeMatch {
  const NoticeMatch(this.account, {required this.certain});

  final Account? account;

  /// Verdadero si la cuenta se identificó sin dudas: por sus últimos 4 dígitos,
  /// o porque es la única de ese banco, no tiene dígitos registrados y el aviso
  /// no trae ninguno. Solo así se anota sin preguntar.
  final bool certain;
}

/// Contenido del libro leído de un archivo o de una copia, ya validado. Se
/// arma completo antes de tocar nada: si algo no cuadra, lanza
/// [FormatException] y el libro actual queda intacto.
class LedgerSnapshot {
  LedgerSnapshot({
    required this.accounts,
    required this.categories,
    required this.txs,
    required this.scheduled,
    required this.budgets,
    required this.templates,
    required this.inbox,
    required this.rates,
    required this.baseCurrency,
    required this.periodSpec,
  });

  /// Versión del formato que escribe esta app.
  static const int currentVersion = 1;

  final List<Account> accounts;
  final List<Category> categories;
  final List<Tx> txs;
  final List<Scheduled> scheduled;
  final List<Budget> budgets;
  final List<TxTemplate> templates;
  final List<InboxItem> inbox;
  final RateTable rates;
  final String baseCurrency;
  final PeriodSpec periodSpec;

  static LedgerSnapshot parse(Map<String, dynamic> j) {
    final Object? v = j['version'];
    if (v != null && (v is! num || v.toInt() > currentVersion)) {
      throw const FormatException('Los datos son de una versión más nueva de Plata');
    }
    try {
      final Object? base = j['baseCurrency'];
      if (base != null && (base is! String || base.isEmpty)) {
        throw const FormatException('Moneda base inválida');
      }
      return LedgerSnapshot(
        accounts: _list(j['accounts'], Account.fromJson),
        categories: _list(j['categories'], Category.fromJson),
        txs: _list(j['txs'], Tx.fromJson),
        scheduled: _list(j['scheduled'], Scheduled.fromJson),
        budgets: _list(j['budgets'], Budget.fromJson),
        templates: _list(j['templates'], TxTemplate.fromJson),
        inbox: _list(j['inbox'], InboxItem.fromJson),
        rates: RateTable.fromJson(j['rates'] as Map<String, dynamic>?),
        baseCurrency: base as String? ?? 'COP',
        periodSpec: PeriodSpec(mode: j['periodMode'] == 'quincena' ? PeriodMode.quincena : PeriodMode.month, startDay: ((j['periodStartDay'] as num?)?.toInt() ?? 1).clamp(1, 28)),
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      // Un campo con otro tipo (un JSON editado a mano) lanza TypeError.
      throw FormatException('Los datos no tienen el formato de Plata: $e');
    }
  }

  static List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) read) {
    final List<T> out = <T>[];
    if (raw == null) {
      return out;
    }
    if (raw is! List) {
      throw const FormatException('Se esperaba una lista');
    }
    for (final Object? e in raw) {
      if (e is! Map<String, dynamic>) {
        throw const FormatException('Elemento con un formato inesperado');
      }
      out.add(read(e));
    }
    return out;
  }
}

/// Todo el libro: cuentas, categorías, movimientos, programados, presupuestos,
/// plantillas, avisos y tasas, con sus cálculos. Se guarda cifrado.
class Ledger extends ChangeNotifier {
  Ledger(this.store, {this.spanish = true, DateTime Function()? clock}) : _clock = clock ?? _systemNow;

  final EncryptedStore store;

  /// Idioma de los nombres de fábrica (ver [applyLanguage]).
  bool spanish;
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
  Future<void>? _writing;
  bool _dirty = false;
  int _revision = 0;
  final Map<String, int> _spentCache = <String, int>{};

  static const String _file = kLedgerFile;

  /// Cambia con cada modificación (sirve para invalidar cálculos guardados).
  int get revision => _revision;

  @override
  void notifyListeners() {
    _revision += 1;
    _spentCache.clear();
    super.notifyListeners();
  }

  // ------------------------------------------------------------------ carga

  /// Verdadero mientras los datos guardados no se pueden abrir: la app no
  /// escribe nada y muestra la pantalla de recuperación hasta que el usuario
  /// restaure una copia o empiece de cero (ver [replaceWith] y [startFresh]).
  final ValueNotifier<bool> readOnlyState = ValueNotifier<bool>(false);
  bool get readOnly => readOnlyState.value;
  set readOnly(bool v) => readOnlyState.value = v;

  /// Motivo del modo de recuperación (null si el libro se abrió bien).
  RecoveryReason? recoveryReason;

  Future<void> load() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    _dirty = false;
    await _waitWrites();
    Map<String, dynamic>? j;
    RecoveryReason? reason;
    bool fileExisted = false;
    try {
      j = await store.readJson(_file);
      fileExisted = j != null;
      if (j == null) {
        // Sin libro (o vacío): quizá quedó el temporal de una escritura cortada.
        j = await _recoverTemp();
        fileExisted = j != null;
        if (j == null && (await store.store.list('backups', extension: '.json.enc')).isNotEmpty) {
          // Había datos (quedan copias) y el libro no está: no se empieza vacío
          // en silencio; se ofrece restaurar.
          reason = RecoveryReason.missing;
        }
      }
    } on DecryptException catch (e) {
      debugPrint('$e');
      reason = RecoveryReason.unreadable;
    }
    LedgerSnapshot? snap;
    if (j != null) {
      try {
        snap = LedgerSnapshot.parse(j);
      } on FormatException catch (e) {
        debugPrint('Libro inválido: $e');
        reason = RecoveryReason.invalid;
      }
    }
    _apply(snap);
    recoveryReason = reason;
    readOnly = reason != null;
    loaded = true;
    if (!readOnly) {
      await _clearStaleTemps();
      if (!fileExisted) {
        // Primer arranque: el libro de fábrica se escribe de una vez, para que
        // un libro ausente siempre signifique pérdida y no "aún no se guardó".
        _dirty = true;
        await flush();
      }
    }
    notifyListeners();
  }

  /// Pone en memoria el contenido de [snap] (o el libro de fábrica).
  void _apply(LedgerSnapshot? snap) {
    accounts.clear();
    categories.clear();
    txs.clear();
    scheduled.clear();
    budgets.clear();
    templates.clear();
    inbox.clear();
    rates = RateTable();
    baseCurrency = 'COP';
    periodSpec = const PeriodSpec();
    if (snap != null) {
      accounts.addAll(snap.accounts);
      categories.addAll(snap.categories);
      txs.addAll(snap.txs);
      scheduled.addAll(snap.scheduled);
      budgets.addAll(snap.budgets);
      templates.addAll(snap.templates);
      inbox.addAll(snap.inbox);
      rates = snap.rates;
      baseCurrency = snap.baseCurrency;
      periodSpec = snap.periodSpec;
    }
    if (categories.isEmpty) {
      categories.addAll(Defaults.categories(spanish: spanish));
    }
    if (accounts.isEmpty) {
      accounts.addAll(Defaults.accounts(spanish: spanish));
    }
    _sortTxs();
  }

  /// Si el libro falta pero quedó el temporal completo de una escritura que se
  /// cortó antes del renombrado, se recupera el más reciente que se pueda leer.
  Future<Map<String, dynamic>?> _recoverTemp() async {
    final List<String> temps = await store.store.list('', prefix: '$_file.', extension: JsonStore.tmpSuffix);
    final List<MapEntry<String, DateTime>> dated = <MapEntry<String, DateTime>>[];
    for (final String rel in temps) {
      dated.add(MapEntry<String, DateTime>(rel, await store.store.modified(rel) ?? DateTime(2000)));
    }
    dated.sort((MapEntry<String, DateTime> a, MapEntry<String, DateTime> b) => b.value.compareTo(a.value));
    for (final MapEntry<String, DateTime> e in dated) {
      try {
        final Map<String, dynamic>? j = await store.readJson(e.key);
        if (j != null) {
          LedgerSnapshot.parse(j);
          await store.store.move(e.key, _file);
          debugPrint('Libro recuperado de ${e.key}');
          return j;
        }
      } catch (err) {
        debugPrint('Temporal ${e.key} ilegible: $err');
      }
    }
    return null;
  }

  Future<void> _clearStaleTemps() async {
    try {
      for (final String rel in await store.store.list('', prefix: '$_file.', extension: JsonStore.tmpSuffix)) {
        await store.store.delete(rel);
      }
    } catch (e) {
      debugPrint('Temporales: $e');
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': LedgerSnapshot.currentVersion,
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

  /// Reemplaza todo el libro con un respaldo. Primero lo valida completo (si
  /// no sirve, lanza [FormatException] sin tocar nada); si el libro actual no
  /// se podía abrir, lo aparta en recovery/ antes de escribir.
  Future<void> replaceWith(Map<String, dynamic> j) async {
    final LedgerSnapshot snap = LedgerSnapshot.parse(j);
    _saveTimer?.cancel();
    _saveTimer = null;
    _dirty = false;
    await _waitWrites();
    if (readOnly) {
      await _keepUnreadableCopy();
    }
    _apply(snap);
    _renameFactoryItems(spanish);
    recoveryReason = null;
    readOnly = false;
    _dirty = true;
    await flush();
    notifyListeners();
    await pruneAttachments();
  }

  /// Empieza con un libro de fábrica (borrar todo, o salir del modo de
  /// recuperación sin copia). Lo que no se pudo abrir queda en recovery/.
  Future<void> startFresh() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    _dirty = false;
    await _waitWrites();
    if (readOnly) {
      await _keepUnreadableCopy();
    }
    _apply(null);
    recoveryReason = null;
    readOnly = false;
    loaded = true;
    _dirty = true;
    await flush();
    notifyListeners();
  }

  /// Cancela el guardado pendiente y espera la escritura en curso (antes de
  /// borrar todo).
  Future<void> discardPendingWrites() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    _dirty = false;
    await _waitWrites();
  }

  Future<void> _keepUnreadableCopy() async {
    try {
      final Uint8List? raw = await store.store.readBytes(_file);
      if (raw != null && raw.isNotEmpty) {
        final String stamp = _clock().toIso8601String().replaceAll(':', '-');
        await store.store.writeBytes('recovery/ledger-$stamp.json.enc', raw);
        final List<String> kept = await store.store.list('recovery', prefix: 'ledger-');
        for (final String old in kept.take(kept.length > 3 ? kept.length - 3 : 0)) {
          await store.store.delete(old);
        }
      }
    } catch (e) {
      debugPrint('Copia del libro ilegible: $e');
    }
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
    _saveTimer = Timer(const Duration(milliseconds: 400), () => unawaited(_flushQuietly()));
  }

  Future<void> _flushQuietly() async {
    try {
      await flush();
    } catch (e) {
      debugPrint('No se pudo guardar el libro: $e');
    }
  }

  /// Hay cambios sin escribir o una escritura en curso.
  bool get busy => _dirty || _writing != null;

  Future<void> _waitWrites() async {
    final Future<void>? w = _writing;
    if (w != null) {
      await w;
    }
  }

  /// Escribe de inmediato si hay cambios pendientes. Las escrituras van en
  /// fila: cada una espera a la anterior y lleva el libro tal como estaba al
  /// pedirla. Si falla, los cambios quedan pendientes para el siguiente guardado.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_dirty) {
      await _waitWrites();
      return;
    }
    if (readOnly) {
      _dirty = false;
      return;
    }
    _dirty = false;
    final Map<String, dynamic> data = toJson();
    final Future<void>? previous = _writing;
    final Completer<void> done = Completer<void>();
    final Future<void> mine = done.future;
    _writing = mine;
    try {
      if (previous != null) {
        await previous;
      }
      await store.writeJson(_file, data);
    } catch (e) {
      _dirty = true;
      rethrow;
    } finally {
      // El futuro de la fila nunca falla: los que esperan solo necesitan saber
      // que esta escritura terminó.
      done.complete();
      if (identical(_writing, mine)) {
        _writing = null;
      }
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    readOnlyState.dispose();
    super.dispose();
  }

  void _sortTxs() => txs.sort((Tx a, Tx b) {
        final int c = b.date.compareTo(a.date);
        return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
      });

  // ------------------------------------------------------------------ idioma

  /// Cambia de idioma los nombres de fábrica (categorías y la cuenta de
  /// efectivo) que el usuario no renombró. Los demás se respetan.
  void applyLanguage(bool toSpanish) {
    spanish = toSpanish;
    if (_renameFactoryItems(toSpanish)) {
      save();
    } else {
      notifyListeners();
    }
  }

  bool _renameFactoryItems(bool toSpanish) {
    bool changed = false;
    String? rename(String current, List<String>? names) {
      if (names == null) {
        return null;
      }
      final String target = toSpanish ? names[0] : names[1];
      return current != target && (current == names[0] || current == names[1]) ? target : null;
    }

    final Map<String, List<String>> catNames = Defaults.categoryNames();
    for (final Category c in categories) {
      final String? n = rename(c.name, catNames[c.id]);
      if (n != null) {
        c.name = n;
        changed = true;
      }
    }
    for (final Account a in accounts) {
      final String? n = rename(a.name, Defaults.accountNames[a.id]);
      if (n != null) {
        a.name = n;
        changed = true;
      }
    }
    return changed;
  }

  // --------------------------------------------------------------- consultas

  DateTime get _today => dateOnly(_clock());

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

  /// Si el movimiento sale de (o se carga a) la cuenta [accountId]. Una
  /// tarjeta débito ve solo lo que se pagó con ella; su cuenta bancaria ve
  /// además lo de todas sus tarjetas débito, igual que su saldo.
  bool chargesAccount(Tx t, String accountId) {
    final Account? a = account(accountId);
    if (a != null && a.isDebit) {
      return t.accountId == accountId;
    }
    return effectiveAccountId(t.accountId) == accountId;
  }

  /// Si el movimiento toca la cuenta, como origen o como destino (ver
  /// [chargesAccount]). Es el criterio de la lista de una cuenta, de los
  /// informes por cuenta y de los presupuestos.
  bool touchesAccount(Tx t, String accountId) {
    if (chargesAccount(t, accountId)) {
      return true;
    }
    final String? to = t.toAccountId;
    if (to == null) {
      return false;
    }
    final Account? a = account(accountId);
    if (a != null && a.isDebit) {
      return to == accountId;
    }
    return effectiveAccountId(to) == accountId;
  }

  /// Un ingreso en una categoría de gasto es un reembolso: en totales,
  /// informes y presupuestos descuenta del gasto en vez de sumar ingresos.
  bool isRefundCategory(String? categoryId) => categoryId != null && category(categoryId)?.kind == CategoryKind.expense;

  // ----------------------------------------------------------------- monedas

  /// Si el libro tiene algo que depende de la moneda base (movimientos,
  /// presupuestos o saldos iniciales).
  bool get hasMoneyData => txs.isNotEmpty || budgets.isNotEmpty || accounts.any((Account a) => a.initialMinor != 0);

  /// Cambia la moneda base. Las tasas (automáticas y manuales), la tasa
  /// guardada en cada movimiento y los topes de los presupuestos se recalculan
  /// con la tasa actual entre las dos monedas, así que nada se suma 1:1. Si esa
  /// tasa no se conoce y hay datos que convertir, lanza [TxRejected] con
  /// [TxProblem.missingRate] y no cambia nada.
  void changeBaseCurrency(String currency) {
    if (currency == baseCurrency) {
      return;
    }
    final double? r = rateToBase(currency); // 1 [currency] = r [base actual]
    if (r == null || r <= 0) {
      if (hasMoneyData) {
        throw TxRejected(TxProblem.missingRate, currency: currency);
      }
      baseCurrency = currency;
      rates.rates.clear();
      rates.manual.clear();
      rates.origins.clear();
      rates.updatedAt = null;
      save();
      return;
    }
    final String old = baseCurrency;
    Map<String, double> rebase(Map<String, double> m) {
      final Map<String, double> out = <String, double>{};
      m.forEach((String c, double v) {
        if (c != currency && v > 0) {
          out[c] = v / r;
        }
      });
      return out;
    }

    final Map<String, double> auto = rebase(rates.rates)..[old] = 1 / r;
    final Map<String, double> manual = rebase(rates.manual);
    final String? newBaseOrigin = rates.origins[currency];
    rates.rates
      ..clear()
      ..addAll(auto);
    rates.manual
      ..clear()
      ..addAll(manual);
    rates.origins.remove(currency);
    if (newBaseOrigin != null) {
      rates.origins[old] = newBaseOrigin;
    }
    for (final Tx t in txs) {
      final double? tr = t.rateToBase;
      if (tr != null) {
        t.rateToBase = tr / r;
      }
    }
    for (final Budget b in budgets) {
      b.amountMinor = (b.amountMinor / r).round();
    }
    baseCurrency = currency;
    save();
  }

  /// Tasa de una moneda a la base (1 unidad = r base), o null si no se conoce.
  double? rateToBase(String currency) => rates.rateFor(currency, baseCurrency);

  /// Monedas de las cuentas activas que no tienen tasa a la base: sus saldos
  /// se suman 1:1 hasta que se actualicen las tasas o se ponga una a mano.
  List<String> currenciesWithoutRate() {
    final Set<String> out = <String>{};
    for (final Account a in accounts) {
      if (!a.archived && a.currency != baseCurrency && rateToBase(a.currency) == null) {
        out.add(a.currency);
      }
    }
    return out.toList()..sort();
  }

  /// Convierte centavos de [currency] a la moneda base (si no hay tasa, devuelve el monto).
  int toBase(int minor, String currency, {double? rate}) {
    if (currency == baseCurrency) {
      return minor;
    }
    final double? r = rate ?? rateToBase(currency);
    return r == null ? minor : (minor * r).round();
  }

  /// Convierte centavos entre dos monedas con las tasas guardadas, o null si
  /// falta alguna tasa.
  int? convert(int minor, String from, String to) {
    if (from == to) {
      return minor;
    }
    final double? rf = rateToBase(from);
    final double? rt = rateToBase(to);
    if (rf == null || rt == null || rf <= 0 || rt <= 0) {
      return null;
    }
    return (minor * rf / rt).round();
  }

  /// La moneda que falta para convertir entre [from] y [to].
  String missingRateFor(String from, String to) => rateToBase(from) == null ? from : to;

  /// Lo que llega a la cuenta de destino de una transferencia, en su moneda.
  int receivedMinor(Tx t) {
    final int? stored = t.toAmountMinor;
    if (stored != null) {
      return stored;
    }
    final Account? to = account(t.toAccountId);
    if (to == null || to.currency == t.currency) {
      return t.amountMinor;
    }
    // Datos viejos sin monto recibido: se estima con las tasas de hoy.
    return convert(t.amountMinor, t.currency, to.currency) ?? t.amountMinor;
  }

  // ------------------------------------------------------------------ saldos

  /// Saldo de una cuenta en su moneda con los movimientos anteriores a
  /// [before] (por defecto, hasta el final de hoy: un movimiento con fecha
  /// futura no cuenta todavía). Los bolsillos no se suman a la madre aquí; ver
  /// [balanceWithPockets].
  int balanceMinor(String accountId, {DateTime? before, bool includeDebitCards = true}) {
    final DateTime limit = before ?? addDays(_today, 1);
    int total = account(accountId)?.initialMinor ?? 0;
    for (final Tx t in txs) {
      if (!t.date.isBefore(limit)) {
        continue;
      }
      final String from = includeDebitCards ? effectiveAccountId(t.accountId) : t.accountId;
      final String? to = t.toAccountId == null ? null : (includeDebitCards ? effectiveAccountId(t.toAccountId!) : t.toAccountId);
      if (from == accountId) {
        total += t.signedMinor;
      }
      if (t.kind == TxKind.transfer && to == accountId) {
        total += receivedMinor(t);
      }
    }
    return total;
  }

  int balanceWithPockets(String accountId, {DateTime? before}) {
    int total = balanceMinor(accountId, before: before);
    for (final Account a in accounts) {
      if (a.isPocket && a.parentId == accountId && !a.archived) {
        total += balanceMinor(a.id, before: before);
      }
    }
    return total;
  }

  /// Patrimonio neto en moneda base: activos menos deudas de las cuentas incluidas.
  int netWorthMinor({DateTime? before}) {
    int total = 0;
    for (final Account a in accounts) {
      if (a.archived || !a.includeInTotal || a.isDebit) {
        continue;
      }
      total += toBase(balanceMinor(a.id, before: before), a.currency);
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

  /// Cupo libre de una tarjeta de crédito: el cupo menos lo que se debe (un
  /// saldo a favor lo aumenta). Null si la tarjeta no tiene cupo.
  int? availableCreditMinor(Account card) {
    final int? limit = card.creditLimitMinor;
    if (limit == null) {
      return null;
    }
    return limit + balanceMinor(card.id);
  }

  // ------------------------------------------------------------- movimientos

  /// Revisa un movimiento sin guardarlo (lanza [TxRejected] si no sirve). Puede
  /// completar campos: la tasa del día, el monto recibido entre monedas.
  void validate(Tx t) => _normalize(t);

  Future<Tx> addTx(Tx t) async {
    _normalize(t);
    txs.add(t);
    _sortTxs();
    save();
    return t;
  }

  /// Guarda los cambios de un movimiento existente. [draft] trae los datos
  /// nuevos y el mismo id: si no pasa la revisión, el original queda intacto.
  void updateTx(Tx draft) {
    _normalize(draft);
    final int i = txs.indexWhere((Tx x) => x.id == draft.id);
    if (i < 0) {
      txs.add(draft);
    } else {
      txs[i] = draft;
    }
    _sortTxs();
    save();
  }

  Future<void> deleteTx(String id) async {
    final List<String> files = <String>[for (final Tx t in txs.where((Tx t) => t.id == id)) ...t.attachments];
    txs.removeWhere((Tx t) => t.id == id);
    save();
    await deleteAttachmentFiles(files);
  }

  /// Copia un movimiento con fecha de hoy, como uno nuevo: con la tasa del
  /// día, sin conciliar, sin fotos y sin el vínculo a su programado.
  Future<Tx> duplicateTx(Tx source, {DateTime? date}) {
    final Tx c = source.copy(id: newId(), date: date ?? _clock());
    c.rateToBase = null;
    if (c.toAmountAuto) {
      c.toAmountMinor = null;
      c.toAmountAuto = false;
    }
    c.reconciled = false;
    c.scheduledId = null;
    c.source = 'manual';
    c.attachments.clear();
    return addTx(c);
  }

  /// Ajusta el saldo de una cuenta al real con un movimiento de ajuste: corrige
  /// el saldo, pero no cuenta como gasto ni ingreso. Devuelve null si ya
  /// coincidía.
  Future<Tx?> adjustBalance(Account a, int realBalanceMinor, {String description = ''}) async {
    final int diff = realBalanceMinor - balanceMinor(a.id);
    if (diff == 0) {
      return null;
    }
    return addTx(Tx(
      id: newId(),
      kind: diff > 0 ? TxKind.income : TxKind.expense,
      amountMinor: diff.abs(),
      accountId: a.id,
      date: _clock(),
      description: description,
      source: 'adjustment',
    ));
  }

  /// Borra fotos de recibos que ya no usa ningún movimiento.
  Future<void> deleteAttachmentFiles(Iterable<String> files) async {
    final Set<String> used = <String>{for (final Tx t in txs) ...t.attachments};
    for (final String f in files) {
      if (!used.contains(f)) {
        try {
          await store.store.delete(f);
        } catch (e) {
          debugPrint('Adjunto $f: $e');
        }
      }
    }
  }

  /// Ordena la carpeta de fotos de recibos: borra los archivos que ningún
  /// movimiento usa (por ejemplo, de un movimiento que no se llegó a guardar) y
  /// quita las referencias a fotos que no están en este teléfono (al restaurar
  /// una copia hecha en otro: las copias guardan los datos, no las fotos). Solo
  /// corre si el libro se leyó bien, para no tocar nada si no se pudo descifrar.
  Future<void> pruneAttachments() async {
    if (readOnly || !loaded) {
      return;
    }
    final List<String> files = await store.store.list('attachments');
    final Set<String> present = files.where((String f) => !f.endsWith(JsonStore.tmpSuffix)).toSet();
    bool changed = false;
    for (final Tx t in txs) {
      final int before = t.attachments.length;
      t.attachments.removeWhere((String a) => !present.contains(a));
      changed = changed || t.attachments.length != before;
    }
    await deleteAttachmentFiles(files);
    if (changed) {
      save();
    }
  }

  void _normalize(Tx t) {
    final Account? a = account(t.accountId);
    if (a == null) {
      throw const TxRejected(TxProblem.account);
    }
    if (t.splits.isNotEmpty) {
      t.amountMinor = t.splits.fold<int>(0, (int s, TxSplit p) => s + p.amountMinor);
      t.categoryId = null;
    }
    if (t.amountMinor <= 0) {
      throw const TxRejected(TxProblem.amount);
    }
    if (t.currency != a.currency || t.rateToBase == null) {
      // Moneda nueva (o movimiento sin tasa): vale la tasa de hoy. Si la
      // moneda no cambia, se conserva la tasa histórica.
      t.rateToBase = rateToBase(a.currency);
    }
    t.currency = a.currency;
    if (t.kind != TxKind.transfer) {
      t.toAccountId = null;
      t.toAmountMinor = null;
      t.toAmountAuto = false;
    } else {
      t.categoryId = null;
      t.splits.clear();
      final Account? to = account(t.toAccountId);
      if (to == null) {
        throw const TxRejected(TxProblem.destination);
      }
      if (to.id == a.id || effectiveAccountId(to.id) == effectiveAccountId(a.id)) {
        throw const TxRejected(TxProblem.sameAccount);
      }
      if (to.currency == a.currency) {
        t.toAmountMinor = null;
        t.toAmountAuto = false;
      } else if (t.toAmountMinor == null || t.toAmountMinor! <= 0) {
        final int? received = convert(t.amountMinor, a.currency, to.currency);
        if (received == null) {
          throw TxRejected(TxProblem.missingRate, currency: missingRateFor(a.currency, to.currency));
        }
        t.toAmountMinor = received;
        t.toAmountAuto = true;
      }
    }
    if (t.installments < 1 || !(a.isCredit && t.kind == TxKind.expense)) {
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
      if (f.accountIds.isNotEmpty && !f.accountIds.any((String id) => touchesAccount(t, id))) {
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
      if (f.to != null && !t.date.isBefore(addDays(dateOnly(f.to!), 1))) {
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
      if (f.onlyUncategorized && !(t.kind != TxKind.transfer && !t.isAdjustment && t.categoryId == null && t.splits.isEmpty)) {
        return false;
      }
      if (f.onlyUnreconciled && t.reconciled) {
        return false;
      }
      if (q.isNotEmpty) {
        final String hay = '${t.description} ${t.payee} ${t.notes} ${t.tags.join(' ')} ${categoryPath(t.categoryId)} ${account(t.accountId)?.name ?? ''} ${t.checkNumber} ${Money.format(t.amountMinor, t.currency, withSymbol: false)} ${Money.format(t.amountMinor, t.currency, withSymbol: false, spanish: false)}'.toLowerCase();
        if (!hay.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  List<Tx> inPeriod(Period p, {String? accountId}) => txs.where((Tx t) => p.contains(t.date) && (accountId == null || touchesAccount(t, accountId))).toList();

  /// Partes de un movimiento con su categoría (una por división, o una sola).
  List<TxSplit> _parts(Tx t) => t.splits.isNotEmpty ? t.splits : <TxSplit>[TxSplit(categoryId: t.categoryId ?? '', amountMinor: t.amountMinor)];

  /// Totales de un periodo en moneda base: ingresos, gastos (positivos) y neto.
  /// Las transferencias y los ajustes de saldo no cuentan; los reembolsos
  /// (ingresos en una categoría de gasto) descuentan del gasto.
  PeriodTotals totals(Period p, {String? accountId}) {
    int income = 0;
    int expense = 0;
    for (final Tx t in inPeriod(p, accountId: accountId)) {
      if (t.isAdjustment || t.kind == TxKind.transfer) {
        continue;
      }
      if (accountId != null && !chargesAccount(t, accountId)) {
        continue;
      }
      for (final TxSplit part in _parts(t)) {
        final int v = toBase(part.amountMinor, t.currency, rate: t.rateToBase);
        if (t.kind == TxKind.expense) {
          expense += v;
        } else if (isRefundCategory(part.categoryId)) {
          expense -= v;
        } else {
          income += v;
        }
      }
    }
    return PeriodTotals(period: p, incomeMinor: income, expenseMinor: expense);
  }

  /// Gasto (o ingreso) por categoría raíz en un periodo, en moneda base, de
  /// mayor a menor. Los reembolsos descuentan de su categoría de gasto.
  List<CategoryTotal> byCategory(Period p, {CategoryKind kind = CategoryKind.expense, String? accountId, bool roots = true}) {
    final Map<String, int> sums = <String, int>{};
    for (final Tx t in inPeriod(p, accountId: accountId)) {
      if (t.isAdjustment || t.kind == TxKind.transfer) {
        continue;
      }
      if (accountId != null && !chargesAccount(t, accountId)) {
        continue;
      }
      for (final TxSplit part in _parts(t)) {
        final bool refund = t.kind == TxKind.income && isRefundCategory(part.categoryId);
        int sign;
        if (kind == CategoryKind.expense) {
          sign = t.kind == TxKind.expense ? 1 : (refund ? -1 : 0);
        } else {
          sign = t.kind == TxKind.income && !refund ? 1 : 0;
        }
        if (sign == 0) {
          continue;
        }
        final String key = part.categoryId.isEmpty ? '' : (roots ? _rootOf(part.categoryId) : part.categoryId);
        sums[key] = (sums[key] ?? 0) + sign * toBase(part.amountMinor, t.currency, rate: t.rateToBase);
      }
    }
    final List<CategoryTotal> out = sums.entries.where((MapEntry<String, int> e) => e.value != 0).map((MapEntry<String, int> e) => CategoryTotal(categoryId: e.key.isEmpty ? null : e.key, amountMinor: e.value)).toList();
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
            add(effectiveAccountId(t.toAccountId!), receivedMinor(t), 0);
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
      if ((kind != null && t.kind != kind) || t.isAdjustment) {
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

  /// Categorías que cubre un presupuesto (con sus subcategorías); vacío =
  /// todos los gastos.
  Set<String> budgetCategories(Budget b) {
    final Set<String> cats = <String>{};
    for (final String id in b.categoryIds) {
      cats.addAll(categoryTree(id));
    }
    return cats;
  }

  /// Lo que [t] suma al gasto de [b], en moneda base: positivo si es un gasto
  /// en sus categorías, negativo si es un reembolso (ingreso en una categoría
  /// de gasto) y cero si no cuenta. Los ajustes de saldo y las transferencias
  /// no cuentan. Es la misma regla de los totales de Informes.
  int budgetShare(Budget b, Tx t, {Set<String>? cats}) {
    if (t.isAdjustment || t.kind == TxKind.transfer) {
      return 0;
    }
    if (b.accountId != null && !chargesAccount(t, b.accountId!)) {
      return 0;
    }
    final Set<String> c = cats ?? budgetCategories(b);
    int share = 0;
    for (final TxSplit part in _parts(t)) {
      if (c.isNotEmpty && !c.contains(part.categoryId)) {
        continue;
      }
      final int v = toBase(part.amountMinor, t.currency, rate: t.rateToBase);
      if (t.kind == TxKind.expense) {
        share += v;
      } else if (isRefundCategory(part.categoryId)) {
        share -= v;
      }
    }
    return share;
  }

  /// Movimientos que cuentan en [b] durante [p] (los de "Ver movimientos"),
  /// del más reciente al más antiguo. Su suma es [budgetSpent].
  List<Tx> budgetTxs(Budget b, Period p) {
    final Set<String> cats = budgetCategories(b);
    return txs.where((Tx t) => p.contains(t.date) && budgetShare(b, t, cats: cats) != 0).toList();
  }

  /// Gasto de un presupuesto en un periodo dado (moneda base).
  int budgetSpent(Budget b, Period p) {
    final String key = '${b.id}|${b.accountId}|${b.categoryIds.join(',')}|${p.start.toIso8601String()}|${p.end.toIso8601String()}';
    final int? cached = _spentCache[key];
    if (cached != null) {
      return cached;
    }
    final Set<String> cats = budgetCategories(b);
    int spent = 0;
    for (final Tx t in txs) {
      if (p.contains(t.date)) {
        spent += budgetShare(b, t, cats: cats);
      }
    }
    _spentCache[key] = spent;
    return spent;
  }

  BudgetProgress progress(Budget b, {DateTime? now}) {
    final Period current = BudgetPeriods.containing(b, now ?? _clock());
    int carry = 0;
    if (b.rollover) {
      Period p = BudgetPeriods.previous(b, current);
      int guard = 0;
      final DateTime start = dateOnly(b.startDate);
      while (!p.end.isBefore(addDays(start, 1)) && guard++ < 120) {
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

  Tx _txFromScheduled(Scheduled s, DateTime date) => Tx(
        id: newId(),
        kind: s.kind,
        amountMinor: s.amountMinor,
        accountId: s.accountId,
        toAccountId: s.toAccountId,
        toAmountMinor: s.kind == TxKind.transfer ? s.toAmountMinor : null,
        categoryId: s.categoryId,
        date: date,
        description: s.description.isNotEmpty ? s.description : s.name,
        payee: s.payee,
        tags: List<String>.from(s.tags),
        scheduledId: s.id,
        source: 'scheduled',
      );

  /// Mediodía del día (no cae en el día anterior por zona horaria ni por
  /// horario de verano).
  static DateTime _noon(DateTime d) => DateTime(d.year, d.month, d.day, 12);

  /// Anota los programados vencidos (si son automáticos) y avanza sus fechas.
  /// Uno que no se puede anotar (falta la tasa de una transferencia entre
  /// monedas) queda vencido hasta que el usuario lo resuelva; uno cuya cuenta
  /// ya no existe se pausa. Devuelve los movimientos creados.
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
        final Tx t = _txFromScheduled(s, _noon(s.nextDate));
        try {
          _normalize(t);
        } on TxRejected catch (e) {
          if (e.problem == TxProblem.account || e.problem == TxProblem.destination) {
            s.enabled = false;
            changed = true;
          }
          break;
        }
        txs.add(t);
        created.add(t);
        s.lastPosted = t.date;
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

  /// Lo que un programado mueve en un mes promedio, en la moneda de su cuenta.
  static int perMonthMinor(Scheduled s) {
    final int every = s.frequency.every < 1 ? 1 : s.frequency.every;
    switch (s.frequency.unit) {
      case FrequencyUnit.day:
        return (s.amountMinor * 30 / every).round();
      case FrequencyUnit.week:
        return (s.amountMinor * 52 / 12 / every).round();
      case FrequencyUnit.month:
        return (s.amountMinor / every).round();
      case FrequencyUnit.year:
        return (s.amountMinor / 12 / every).round();
      case FrequencyUnit.quincena:
        return s.amountMinor * 2;
    }
  }

  /// Compromisos fijos al mes de los programados activos, en moneda base:
  /// cada uno está en la moneda de su cuenta y se convierte antes de sumar.
  /// Las transferencias no son gasto ni ingreso y no cuentan.
  MonthlyCommitments monthlyCommitments() {
    int out = 0;
    int incoming = 0;
    for (final Scheduled s in scheduled) {
      if (!s.enabled || s.kind == TxKind.transfer) {
        continue;
      }
      final int v = toBase(perMonthMinor(s), account(s.accountId)?.currency ?? baseCurrency);
      if (s.kind == TxKind.expense) {
        out += v;
      } else {
        incoming += v;
      }
    }
    return MonthlyCommitments(outMinor: out, inMinor: incoming);
  }

  /// Programados que vencen en los próximos [days] días (incluye los vencidos no automáticos).
  List<Scheduled> upcoming({int days = 7, DateTime? now}) {
    final DateTime limit = addDays(dateOnly(now ?? _clock()), days + 1);
    final List<Scheduled> out = scheduled.where((Scheduled s) => s.enabled && dateOnly(s.nextDate).isBefore(limit)).toList();
    out.sort((Scheduled a, Scheduled b) => a.nextDate.compareTo(b.nextDate));
    return out;
  }

  // ---------------------------------------------------------------- tarjetas

  /// Valor de la cuota [k] (1..[n]) de una compra de [total]: todas iguales y
  /// la última con lo que sobra, para que las cuotas sumen exactamente el total.
  static int installmentAmount(int total, int n, int k) {
    if (n <= 1) {
      return total;
    }
    final int base = total ~/ n;
    return k == n ? total - base * (n - 1) : base;
  }

  /// Corte del ciclo en que cae una fecha.
  DateTime _cutOf(Account card, DateTime d) => CardCycle.current(card, d).cut;

  /// Estado de cuenta estimado de una tarjeta para el ciclo que contiene [date].
  ///
  /// - Compras de una cuota, avances (transferencias que salen de la tarjeta)
  ///   y ajustes: en el ciclo de su fecha, (corte anterior, corte].
  /// - Cuota k de una compra diferida: en el k-ésimo corte desde la compra; la
  ///   primera cuota se factura en el primer corte después de la compra, como
  ///   en los bancos colombianos (ver docs/DECISIONES.md).
  /// - Abonos (pagos a la tarjeta y devoluciones): en la ventana entre la fecha
  ///   de pago anterior y la de este estado, que es como el banco los aplica.
  /// - Lo facturado antes y no pagado, y la deuda inicial, llegan como saldo
  ///   anterior; un abono de más llega como saldo a favor.
  ///
  /// Es solo capital: Plata no calcula intereses ni cuota de manejo.
  CardStatement statement(Account card, {DateTime? date}) {
    final CardCycle cycle = CardCycle.current(card, date ?? _clock());
    final DateTime cut = cycle.cut;
    final DateTime prevPay = cycle.previous(card).payDate;
    final DateTime payDate = cycle.payDate;
    int previous = -card.initialMinor;
    int purchases = 0;
    int advances = 0;
    int installments = 0;
    int payments = 0;
    void charge(DateTime d, int amount, bool advance) {
      final DateTime c = _cutOf(card, d);
      if (c == cut) {
        if (advance) {
          advances += amount;
        } else {
          purchases += amount;
        }
      } else if (c.isBefore(cut)) {
        previous += amount;
      }
    }

    void credit(DateTime d, int amount) {
      if (!d.isAfter(prevPay)) {
        previous -= amount;
      } else if (!d.isAfter(payDate)) {
        payments += amount;
      }
    }

    for (final Tx t in txs) {
      final DateTime d = dateOnly(t.date);
      final bool from = effectiveAccountId(t.accountId) == card.id;
      if (from && t.kind == TxKind.expense) {
        if (t.installments <= 1) {
          charge(d, t.amountMinor, false);
        } else {
          final int n = t.installments;
          // Cortes desde el de la compra hasta el de este ciclo: la cuota
          // m + 1 es la de este estado y las m anteriores ya se facturaron.
          final int m = CardCycle.cyclesBetween(_cutOf(card, d), cut);
          for (int k = 1; k <= n && k <= m; k++) {
            previous += installmentAmount(t.amountMinor, n, k);
          }
          if (m >= 0 && m < n) {
            installments += installmentAmount(t.amountMinor, n, m + 1);
          }
        }
      } else if (from && t.kind == TxKind.transfer) {
        charge(d, t.amountMinor, true);
      } else if (from && t.kind == TxKind.income) {
        credit(d, t.amountMinor);
      }
      if (t.kind == TxKind.transfer && t.toAccountId != null && effectiveAccountId(t.toAccountId!) == card.id) {
        credit(d, receivedMinor(t));
      }
    }
    return CardStatement(cycle: cycle, previousMinor: previous, purchasesMinor: purchases, advancesMinor: advances, installmentsMinor: installments, paymentsMinor: payments);
  }

  /// Estado de cuenta cuyo pago es el próximo: el del ciclo ya cerrado si su
  /// fecha de pago no ha pasado y aún debe algo; si no, el del ciclo en curso
  /// (que ya trae como saldo anterior lo que no se pagó).
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

  /// Cuotas de una compra diferida que aún no se han facturado al terminar el
  /// ciclo que contiene [now] (la primera cuota se factura en el primer corte
  /// después de la compra).
  int remainingInstallments(Tx t, {DateTime? now}) {
    final Account? card = account(t.accountId);
    if (card == null || t.installments <= 1) {
      return 0;
    }
    final int billed = CardCycle.cyclesBetween(_cutOf(card, t.date), _cutOf(card, now ?? _clock())) + 1;
    return (t.installments - billed).clamp(0, t.installments);
  }

  /// Capital de las cuotas que faltan por facturar de una compra diferida.
  int remainingInstallmentsMinor(Tx t, {DateTime? now}) {
    final int left = remainingInstallments(t, now: now);
    int sum = 0;
    for (int k = t.installments - left + 1; k <= t.installments; k++) {
      sum += installmentAmount(t.amountMinor, t.installments, k);
    }
    return sum;
  }

  /// Cuenta desde la que conviene pagar una tarjeta: una de su misma moneda
  /// (la preferida, si sirve). Null si no hay ninguna: entonces el pago es una
  /// transferencia entre monedas y el editor pide el monto.
  Account? paymentSourceFor(Account card, {String? preferredId}) {
    bool ok(Account a) =>
        !a.archived &&
        a.id != card.id &&
        a.currency == card.currency &&
        (a.type == AccountType.bank || a.type == AccountType.savings || a.type == AccountType.cash || a.type == AccountType.wallet || a.type == AccountType.other);
    final Account? pref = account(preferredId);
    if (pref != null && ok(pref)) {
      return pref;
    }
    for (final Account a in activeAccounts) {
      if (ok(a)) {
        return a;
      }
    }
    return null;
  }

  // -------------------------------------------------------- otras entidades

  Future<Account> addAccount(Account a) async {
    a.order = accounts.isEmpty ? 0 : accounts.map((Account x) => x.order).reduce((int x, int y) => x > y ? x : y) + 1;
    accounts.add(a);
    save();
    return a;
  }

  /// Si la cuenta tiene movimientos (como origen o destino).
  bool accountInUse(String id) => txs.any((Tx t) => t.accountId == id || t.toAccountId == id);

  /// Archiva o desarchiva una cuenta. Al archivarla se pausan sus programados
  /// y las plantillas dejan de apuntar a ella (piden la cuenta al usarlas).
  void setArchived(Account a, bool archived) {
    a.archived = archived;
    if (archived) {
      _releaseAccount(a.id);
    }
    save();
  }

  void _releaseAccount(String id) {
    for (final Scheduled s in scheduled) {
      if (s.accountId == id || s.toAccountId == id) {
        s.enabled = false;
      }
    }
    for (final TxTemplate t in templates) {
      if (t.accountId == id) {
        t.accountId = null;
      }
      if (t.toAccountId == id) {
        t.toAccountId = null;
      }
    }
  }

  void deleteAccount(String id) {
    _releaseAccount(id);
    if (accountInUse(id)) {
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

  /// Movimiento que anotaría una plantilla hoy (sin guardarlo).
  Tx draftFromTemplate(TxTemplate tpl, {DateTime? date}) => Tx(
        id: newId(),
        kind: tpl.kind,
        amountMinor: tpl.amountMinor ?? 0,
        accountId: tpl.accountId ?? '',
        toAccountId: tpl.kind == TxKind.transfer ? tpl.toAccountId : null,
        toAmountMinor: tpl.kind == TxKind.transfer ? tpl.toAmountMinor : null,
        categoryId: tpl.categoryId,
        date: date ?? _clock(),
        description: tpl.description.isNotEmpty ? tpl.description : tpl.name,
        payee: tpl.payee,
        tags: List<String>.from(tpl.tags),
        source: 'template',
      );

  /// Anota una plantilla de un toque. Devuelve null (y no anota nada) si le
  /// falta algo para quedar bien (monto, cuenta, destino de una transferencia
  /// o la tasa de una transferencia entre monedas): entonces se abre el editor.
  Future<Tx?> applyTemplate(TxTemplate tpl, {DateTime? date}) async {
    if (tpl.amountMinor == null || tpl.accountId == null) {
      return null;
    }
    final Tx t = draftFromTemplate(tpl, date: date);
    try {
      _normalize(t);
    } on TxRejected {
      return null;
    }
    tpl.uses += 1;
    txs.add(t);
    _sortTxs();
    save();
    return t;
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
  /// Lanza [TxRejected] si no se puede (por ejemplo, falta la tasa).
  Future<Tx> postScheduled(Scheduled s, {DateTime? date}) async {
    final Tx t = _txFromScheduled(s, date ?? _noon(s.nextDate));
    final Tx created = await addTx(t);
    s.lastPosted = created.date;
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
    // Evita duplicados del mismo aviso (mismo banco, monto, texto y minutos).
    for (final InboxItem i in inbox) {
      if (i.bank == item.bank && i.amountMinor == item.amountMinor && i.kind == item.kind && i.receivedAt.difference(item.receivedAt).abs() < const Duration(minutes: 2) && i.rawText == item.rawText) {
        return i;
      }
    }
    item.accountId ??= matchNotice(item).account?.id;
    inbox.insert(0, item);
    if (inbox.length > 200) {
      inbox.removeRange(200, inbox.length);
    }
    save();
    return item;
  }

  /// Cuenta de un aviso: por sus últimos 4 dígitos entre las cuentas de ese
  /// banco o, si el aviso no trae dígitos, la única cuenta de ese banco. Si el
  /// aviso trae dígitos que no son de ninguna cuenta, o hay varias posibles,
  /// no se adivina.
  NoticeMatch matchNotice(InboxItem item) {
    List<Account> candidates = activeAccounts.where((Account a) => BankRules.keyFor(a.bank) == item.bank && !a.isPocket).toList();
    if (item.kind == TxKind.transfer) {
      // En pagos de tarjeta, retiros y movimientos propios la cuenta del aviso
      // es la de origen (o la que recibe), nunca la tarjeta que se paga.
      candidates = candidates.where((Account a) => !(item.flow == NoticeFlow.cardPayment && a.isCredit)).toList();
    }
    if (item.last4.isNotEmpty) {
      for (final Account a in candidates) {
        if (a.last4 == item.last4) {
          return NoticeMatch(a, certain: true);
        }
      }
      return const NoticeMatch(null, certain: false);
    }
    if (candidates.length == 1) {
      return NoticeMatch(candidates.single, certain: candidates.single.last4.isEmpty);
    }
    return const NoticeMatch(null, certain: false);
  }

  /// Tarjeta de crédito que se paga en un aviso (por los dígitos de destino o,
  /// si no los trae, la única tarjeta de ese banco).
  Account? noticeCard(InboxItem item) {
    final List<Account> cards = activeAccounts.where((Account a) => a.isCredit).toList();
    if (item.toLast4.isNotEmpty) {
      for (final Account a in cards) {
        if (a.last4 == item.toLast4) {
          return a;
        }
      }
      return null;
    }
    final List<Account> ofBank = cards.where((Account a) => BankRules.keyFor(a.bank) == item.bank).toList();
    return ofBank.length == 1 ? ofBank.single : null;
  }

  /// Anota un aviso de gasto o ingreso en su cuenta, convirtiendo el monto si
  /// el aviso viene en otra moneda. Las transferencias (pagos de tarjeta,
  /// retiros, movimientos propios) siempre pasan por el editor: devuelve null.
  Future<Tx?> acceptInbox(InboxItem item, {String? accountId, String? categoryId, String? description}) async {
    final Account? a = account(accountId ?? item.accountId);
    if (a == null || item.kind == TxKind.transfer) {
      return null;
    }
    final int? amount = convert(item.amountMinor, item.currency, a.currency);
    if (amount == null) {
      return null;
    }
    final Tx t = Tx(
      id: newId(),
      kind: item.kind,
      amountMinor: amount,
      accountId: a.id,
      categoryId: categoryId,
      date: item.receivedAt,
      description: description ?? (item.merchant.isNotEmpty ? item.merchant : item.rawTitle),
      notes: item.rawText,
      source: 'notice',
    );
    try {
      await addTx(t);
    } on TxRejected {
      return null;
    }
    item.status = 'accepted';
    item.accountId = a.id;
    save();
    return t;
  }

  void dismissInbox(InboxItem item) {
    item.status = 'dismissed';
    save();
  }

  List<InboxItem> get pendingInbox => inbox.where((InboxItem i) => i.status == 'pending').toList();

  /// Los últimos avisos ya anotados o descartados, del más reciente al más
  /// antiguo (la bandeja guarda primero los nuevos).
  List<InboxItem> noticeHistory({int limit = 30}) => inbox.where((InboxItem i) => i.status != 'pending').take(limit).toList();
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

/// Hora del reloj inyectable (package:clock), fijo en las pruebas.
DateTime _systemNow() => clk.clock.now();
