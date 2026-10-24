import 'dart:async';

import 'package:clock/clock.dart' as clk;
import 'package:flutter/foundation.dart' hide Category;

import '../model/models.dart';
import '../model/money.dart';
import 'bank_rules.dart';
import 'crypto_store.dart';
import 'defaults.dart';
import 'holidays.dart';
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

  /// Tope del periodo (el que tenía entonces, si cambió después) más el
  /// arrastre.
  int get limitMinor => budget.amountFor(period.start) + carryMinor;
  int get availableMinor => limitMinor - spentMinor;
  double get fraction => limitMinor <= 0 ? (spentMinor > 0 ? 1 : 0) : (spentMinor / limitMinor).clamp(0.0, 1.0);
  bool get over => spentMinor > limitMinor;
}

/// Estado de cuenta estimado de una tarjeta de crédito para un ciclo.
///
/// Es el **capital** que según lo anotado en Plata vence en la fecha de pago:
/// no incluye intereses, cuota de manejo ni seguros, que solo conoce el banco.
class CardStatement {
  const CardStatement({required this.cycle, required this.previousMinor, required this.purchasesMinor, required this.advancesMinor, required this.installmentsMinor, required this.paymentsMinor, this.toLegacyMinor = 0, this.legacyMinor = 0, this.fromBankStatement = false});

  final CardCycle cycle;

  /// Saldo anterior: lo facturado en ciclos anteriores (y el pago del último
  /// extracto anotado al crear la tarjeta) menos los abonos hechos hasta la
  /// fecha de pago anterior. Negativo = saldo a favor que se descuenta de este
  /// estado.
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

  /// Parte de los abonos que pasó de lo que pedía este estado y se descontó de
  /// la deuda de antes de Plata (cuotas viejas que el banco sigue cobrando).
  final int toLegacyMinor;

  /// Deuda de antes de Plata que queda después de este estado: no está en
  /// ningún estado de cuenta de Plata porque no se sabe cómo la reparte el
  /// banco; cuenta en la deuda total y en el cupo.
  final int legacyMinor;

  /// El saldo anterior de este estado es el pago mínimo del último extracto que se
  /// anotó al crear la tarjeta (es el primer ciclo que lleva Plata).
  final bool fromBankStatement;

  /// Lo nuevo que se factura en el ciclo.
  int get chargesMinor => purchasesMinor + advancesMinor + installmentsMinor;

  /// Capital estimado pendiente del estado (negativo = saldo a favor).
  int get balanceMinor => previousMinor + chargesMinor - paymentsMinor + toLegacyMinor;

  /// Lo que falta por pagar (nunca negativo).
  int get dueMinor => balanceMinor > 0 ? balanceMinor : 0;

  /// Saldo a favor (nunca negativo).
  int get creditMinor => balanceMinor < 0 ? -balanceMinor : 0;
}

/// Situación de pago de una tarjeta hoy: el próximo pago y, del último
/// extracto cuya fecha límite ya pasó, si quedó algo sin pagar.
///
/// «Vencido» ([overdue]) solo se declara contra un pago mínimo que se conoce
/// de verdad, porque lo anotó la persona: el del último extracto al crear la
/// tarjeta o el que anote para un extracto. El estado de cuenta de Plata es
/// un estimado (no conoce los plazos del banco, la cuota de manejo ni las
/// compras diferidas que llegaron a 1 cuota), así que si solo hay ese
/// cálculo, lo que falta se informa sin hablar de mora ([unconfirmedMinor]).
class CardDue {
  const CardDue({required this.next, this.overdueMinor = 0, this.overdueSince, this.unconfirmedMinor = 0, this.statementCut, this.statementPayDate});

  /// Estado cuyo pago es el próximo (ver [Ledger.nextPayment]).
  final CardStatement next;

  /// Lo que falta del pago mínimo conocido después de su fecha límite.
  final int overdueMinor;

  /// Fecha límite que pasó (null si no hay nada vencido).
  final DateTime? overdueSince;

  /// Sin mínimo conocido: lo que, según lo anotado, queda del último extracto
  /// cuya fecha límite pasó. Es informativo: no es mora.
  final int unconfirmedMinor;

  /// Corte y fecha límite del último extracto cuya fecha límite pasó.
  final DateTime? statementCut;
  final DateTime? statementPayDate;

  bool get overdue => overdueMinor > 0;

  bool get unconfirmed => !overdue && unconfirmedMinor > 0;
}

/// Lo que suma una tarjeta en un ciclo (ver [Ledger.statement]).
class _CycleSums {
  int purchases = 0;
  int advances = 0;
  int installments = 0;
  int payments = 0;

  /// Ajustes de saldo del ciclo: van a la deuda aparte, no al estado (+ sube
  /// la deuda, − la baja).
  int adjustments = 0;
}

/// Movimientos de una tarjeta repartidos por ciclo, desde el primer ciclo que
/// lleva Plata.
class _CardBook {
  _CardBook(this.firstCut);

  /// Corte del primer ciclo: el del último extracto anotado al crear la
  /// tarjeta o, si no se anotó, el del movimiento más antiguo.
  final DateTime firstCut;

  /// Saldo anterior del primer ciclo: el pago mínimo del último extracto (o un saldo
  /// a favor inicial), más lo facturado antes y menos lo abonado antes.
  int opening = 0;

  /// Deuda inicial que no estaba en el último extracto, más los ajustes de
  /// saldo anteriores al primer ciclo.
  int legacy = 0;

  /// Si algún ajuste de saldo cambió la deuda aparte.
  bool adjusted = false;
  final Map<DateTime, _CycleSums> sums = <DateTime, _CycleSums>{};

  /// Pagos vinculados a cada extracto (`Tx.statementOf`).
  final Map<DateTime, int> linked = <DateTime, int>{};

  _CycleSums at(DateTime cut) => sums.putIfAbsent(cut, _CycleSums.new);
}

/// Qué hace «Ya lo pagué» con un extracto (ver [Ledger.markKind]).
enum MarkKind {
  /// Guarda un movimiento «Pago hecho fuera de Plata».
  payment,

  /// Solo marca: Plata no tiene deuda de ese extracto.
  markOnly,

  /// Hay que preguntar si se pagó antes de crear la tarjeta en Plata.
  ask,
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

  /// Versión del formato que escribe esta app. 2: pagos hechos fuera de
  /// Plata como movimientos (ronda 11). 3: `Tx.apartFrom` es una lista y los
  /// abonos provisionales (`outsidePending`, `outsideTaken`, ronda 12): una
  /// app con la versión 2 no los leería bien, así que los rechaza entera.
  static const int currentVersion = 3;

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
  Ledger(this.store, {this.spanish = true, DateTime Function()? clock, this.defaultCurrency = 'COP'}) : _clock = clock ?? _systemNow;

  final EncryptedStore store;

  /// Moneda base de un libro nuevo (la del país del teléfono, ver
  /// Defaults.currencyForLocales).
  final String defaultCurrency;

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
  final Map<String, _CardBook> _cardCache = <String, _CardBook>{};

  static const String _file = kLedgerFile;

  /// Cambia con cada modificación (sirve para invalidar cálculos guardados).
  int get revision => _revision;

  @override
  void notifyListeners() {
    _revision += 1;
    _spentCache.clear();
    _cardCache.clear();
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
    baseCurrency = defaultCurrency;
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
      accounts.addAll(Defaults.accounts(spanish: spanish, currency: baseCurrency));
    }
    _sortTxs();
    _migrateOldMarks();
    // Los pagos de fuera de la ronda 11 guardaban su nombre como texto fijo:
    // ahora se genera al mostrarlo, en el idioma actual.
    for (final Tx t in txs) {
      if (t.isOutsidePayment && t.description.isNotEmpty && (t.description == outsideName(spanish: true) || t.description == outsideName(spanish: false))) {
        t.description = '';
        _dirty = true;
      }
    }
  }

  /// «Ya lo pagué» de las versiones anteriores, convertido una sola vez en
  /// movimientos al abrir el libro (o al restaurar una copia vieja):
  /// - las marcas sin monto (`paidStatements`, con o sin `paidOn`) toman el
  ///   monto que daba la regla de entonces: el mínimo menos lo vinculado y
  ///   menos los pagos sin vínculo (no las devoluciones) anotados después del
  ///   corte y hasta el día de la marca, o hasta la fecha límite real si la
  ///   marca no tenía día, sin pasar de la fecha límite del extracto
  ///   siguiente;
  /// - los pagos de fuera guardados aparte (`outsidePayments`, de la ronda
  ///   10) conservan su monto y su día.
  /// Cada uno pasa a ser un movimiento «Pago hecho fuera de Plata»
  /// ([Tx.isOutsidePayment]) o, si es de un extracto de antes de que la
  /// tarjeta empezara en Plata o quedó en cero, solo una marca
  /// ([Account.markedOnly]). Luego esos campos quedan vacíos: no se vuelve a
  /// migrar.
  void _migrateOldMarks() {
    bool changed = false;
    for (final Account card in accounts) {
      if (card.paidStatements.isEmpty && card.outsidePayments.isEmpty) {
        continue;
      }
      _cardCache.clear();
      final _CardBook book = _cardBook(card);
      if (card.paidStatements.isNotEmpty) {
        final List<Tx> candidates = txs.where((Tx t) => t.statementOf == null && _creditAmount(card, t) > 0 && !(t.kind == TxKind.income && _parts(t).every((TxSplit p) => isRefundCategory(p.categoryId)))).toList()
          ..sort((Tx a, Tx b) => a.date.compareTo(b.date));
        final Map<String, int> left = <String, int>{for (final Tx t in candidates) t.id: _creditAmount(card, t)};
        final Map<DateTime, String> keys = <DateTime, String>{
          for (final String key in card.paidStatements)
            if (DateTime.tryParse(key) != null) CardCycle.current(card, DateTime.parse(key)).cut: key,
        };
        final List<DateTime> marked = keys.keys.toList()..sort();
        for (final DateTime cut in marked) {
          final String key = keys[cut]!;
          final DateTime due = effectivePayDate(card, CardCycle.current(card, cut).payDate);
          final DateTime on = DateTime.tryParse(card.paidOn[key] ?? '') ?? (due.isAfter(_today) ? _today : due);
          int amount = 0;
          final int? minimum = statementMinimum(card, cut);
          if (minimum != null && !cut.isBefore(book.firstCut)) {
            int need = minimum - (book.linked[cut] ?? 0);
            final CardCycle next = CardCycle.current(card, DateTime(cut.year, cut.month, cut.day + 1));
            final DateTime cap = effectivePayDate(card, next.payDate);
            final DateTime end = on.isAfter(cap) ? cap : on;
            for (final Tx t in candidates) {
              if (need <= 0) {
                break;
              }
              final DateTime d = dateOnly(t.date);
              final int available = left[t.id] ?? 0;
              if (!d.isAfter(cut) || d.isAfter(end) || available <= 0) {
                continue;
              }
              final int take = available < need ? available : need;
              left[t.id] = available - take;
              need -= take;
            }
            amount = need > 0 ? need : 0;
          }
          card.outsidePayments.add(OutsidePayment(statement: dayKey(cut), amountMinor: amount, on: dayKey(on)));
        }
      }
      for (final OutsidePayment p in card.outsidePayments) {
        final DateTime? d = DateTime.tryParse(p.statement);
        if (d == null) {
          continue;
        }
        final DateTime cut = CardCycle.current(card, d).cut;
        if (p.amountMinor <= 0 || _beforeStart(card, cut, book)) {
          _addMarkOnly(card, cut);
        } else {
          txs.add(_outsideTx(card, cut, p.amountMinor, DateTime.tryParse(p.on) ?? _today));
        }
      }
      card.outsidePayments.clear();
      card.paidStatements.clear();
      card.paidOn.clear();
      changed = true;
    }
    if (changed) {
      _sortTxs();
      _dirty = true;
    }
    _cardCache.clear();
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
      // Los topes anteriores también: el arrastre y los periodos pasados los
      // usan, y en la moneda vieja serían miles de veces más grandes.
      final List<BudgetAmountChange> history = b.amountHistory.map((BudgetAmountChange c) => BudgetAmountChange(until: c.until, amountMinor: (c.amountMinor / r).round())).toList();
      b.amountHistory
        ..clear()
        ..addAll(history);
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

  /// Anota un movimiento. Todos los caminos (el editor, el favorito de un
  /// toque, «Anotar ahora», «Duplicar hoy», los programados automáticos y los
  /// avisos) pasan por aquí o por [_insertOutsideCheck]: un abono sin vínculo
  /// que puede ser el pago hecho fuera de Plata de un extracto marcado se
  /// toma provisionalmente por ese pago ([_matchOutside]) y queda la pregunta.
  Future<Tx> addTx(Tx t) async {
    _normalize(t);
    t.loggedOn ??= _today;
    txs.add(t);
    _sortTxs();
    _insertOutsideCheck(t);
    save();
    return t;
  }

  /// Lo que hace un movimiento nuevo con los pagos hechos fuera de Plata: si
  /// está vinculado a un extracto, los reemplaza; si no, puede ser uno de
  /// ellos ([_matchOutside]).
  void _insertOutsideCheck(Tx t) {
    if (t.statementOf == null) {
      _matchOutside(t);
    } else {
      _replaceOutside(null, t);
    }
  }

  /// Un abono que queda vinculado a un extracto con un pago hecho fuera de
  /// Plata («Ya lo pagué») es ese pago (o parte de él) anotado desde Plata:
  /// lo reemplaza. El pago de fuera baja en lo que el abono suma al extracto
  /// (al editarlo, solo en lo que subió); si queda en cero, se borra y el
  /// extracto sigue marcado. Un abono confirmado (no provisional) toma
  /// también lo que tenían provisionalmente otros abonos sin contestar de ese
  /// extracto. Lo reemplazado queda en [Tx.outsideTaken]. Nunca se cuenta
  /// dos veces.
  void _replaceOutside(Tx? before, Tx after) {
    if (after.statementOf == null || after.isOutsidePayment) {
      return;
    }
    for (final Account card in accounts) {
      if (!card.isCredit) {
        continue;
      }
      final DateTime? cut = _linkedCut(card, after);
      if (cut == null) {
        continue;
      }
      final int previous = before != null && _linkedCut(card, before) == cut ? _creditAmount(card, before) : 0;
      int delta = _creditAmount(card, after) - previous;
      int got = 0;
      for (final Tx o in txs.where((Tx x) => x.isOutsidePayment && _linkedCut(card, x) == cut).toList()) {
        if (delta <= 0) {
          break;
        }
        final int take = o.amountMinor < delta ? o.amountMinor : delta;
        o.amountMinor -= take;
        delta -= take;
        got += take;
        if (o.amountMinor <= 0) {
          txs.remove(o);
          _addMarkOnly(card, cut);
        }
      }
      if (delta > 0 && !after.outsidePending) {
        got += _takeFromPending(card, after, cut, delta);
      }
      if (got > 0) {
        after.outsideTaken = (after.outsideTaken ?? 0) + got;
      }
    }
  }

  /// Quita hasta [need] de lo que tomaron provisionalmente otros abonos sin
  /// contestar del extracto que cortó en [cut] (para dárselo a [t]).
  int _takeFromPending(Account card, Tx t, DateTime cut, int need) {
    int got = 0;
    for (final Tx o in txs) {
      if (need <= 0) {
        break;
      }
      final int held = o.outsideTaken ?? 0;
      if (identical(o, t) || o.id == t.id || !o.outsidePending || held <= 0 || _linkedCut(card, o) != cut) {
        continue;
      }
      final int x = held < need ? held : need;
      o.outsideTaken = held - x;
      need -= x;
      got += x;
    }
    return got;
  }

  /// Tarjeta y extracto al que está vinculado un abono, o null.
  _Link? _linkOf(Tx t) {
    for (final Account card in accounts) {
      final DateTime? cut = card.isCredit ? _linkedCut(card, t) : null;
      if (cut != null) {
        return _Link(card, cut);
      }
    }
    return null;
  }

  /// Deshace la suposición de que [t] era el pago hecho fuera de Plata de su
  /// extracto: lo que tomó pasa primero a otros abonos provisionales de ese
  /// extracto que tomaron menos de lo que abonan, y el resto vuelve a lo de
  /// fuera. [t] queda vinculado; quien llama decide qué hacer con él.
  /// Devuelve el corte del extracto.
  DateTime? _giveBack(Tx t) {
    final _Link? link = _linkOf(t);
    int amount = t.outsideTaken ?? 0;
    t.outsideTaken = null;
    t.outsidePending = false;
    if (link == null) {
      return null;
    }
    final Account card = link.card;
    final DateTime cut = link.cut;
    for (final Tx o in txs) {
      if (amount <= 0) {
        break;
      }
      final int? held = o.outsideTaken;
      if (identical(o, t) || o.id == t.id || !o.outsidePending || held == null || _linkedCut(card, o) != cut) {
        continue;
      }
      final int spare = _creditAmount(card, o) - held;
      if (spare > 0) {
        final int x = spare < amount ? spare : amount;
        o.outsideTaken = held + x;
        amount -= x;
      }
    }
    if (amount > 0) {
      final List<Tx> mine = outsidePayments(card, cut);
      if (mine.isNotEmpty) {
        mine.first.amountMinor += amount;
      } else {
        card.markedOnly.remove(dayKey(cut));
        final DateTime after = DateTime(cut.year, cut.month, cut.day + 1);
        txs.add(_outsideTx(card, cut, amount, _today.isAfter(after) ? _today : after));
        _sortTxs();
      }
    }
    return cut;
  }

  /// Si [t] (un abono sin vínculo) puede ser el pago hecho fuera de Plata de
  /// un extracto marcado ([outsideCandidate]), se toma provisionalmente por
  /// ese pago: queda vinculado, lo reemplaza y la pregunta «¿Es el pago del
  /// extracto…?» queda pendiente ([Tx.outsidePending]) hasta que se conteste
  /// ([answerOutsideMatch]). Así nunca cuenta dos veces mientras tanto.
  DateTime? _matchOutside(Tx t) {
    final DateTime? cut = outsideCandidate(t);
    if (cut == null) {
      return null;
    }
    t.statementOf = dayKey(cut);
    t.outsideTaken = 0;
    t.outsidePending = true;
    _replaceOutside(null, t);
    return cut;
  }

  /// Guarda los cambios de un movimiento existente. [draft] trae los datos
  /// nuevos y el mismo id: si no pasa la revisión, el original queda intacto.
  /// Un abono provisional (pregunta pendiente) que se edita sin cambiar su
  /// vínculo sigue provisional, con lo que toma recalculado; uno sin vínculo
  /// pasa otra vez por [_matchOutside].
  void updateTx(Tx draft) {
    _normalize(draft);
    final int i = txs.indexWhere((Tx x) => x.id == draft.id);
    Tx? before;
    if (i < 0) {
      txs.add(draft);
    } else {
      before = txs[i];
      txs[i] = draft;
    }
    _sortTxs();
    // Si se editó el mismo objeto, no se sabe cuánto cambió: no se toca lo de
    // fuera (el editor siempre manda una copia).
    if (before == null) {
      draft.loggedOn ??= _today;
      _insertOutsideCheck(draft);
    } else if (!identical(before, draft)) {
      if (before.outsidePending) {
        final String? was = before.statementOf;
        // Lo que tomó vuelve (a otros provisionales o a lo de fuera).
        _giveBack(before);
        final bool keep = draft.outsidePending && draft.statementOf != null && draft.statementOf == was;
        draft.outsideTaken = null;
        draft.outsidePending = false;
        if (keep && _linkOf(draft) != null) {
          draft.outsideTaken = 0;
          draft.outsidePending = true;
          _replaceOutside(null, draft);
        } else {
          if (keep) {
            draft.statementOf = null;
          }
          _insertOutsideCheck(draft);
        }
      } else if (draft.statementOf == null) {
        // Editar sin cambiar el monto, las cuentas ni la fecha no vuelve a
        // preguntar.
        final bool changed = draft.kind != before.kind || draft.amountMinor != before.amountMinor || draft.accountId != before.accountId || draft.toAccountId != before.toAccountId || draft.toAmountMinor != before.toAmountMinor || dateOnly(draft.date) != dateOnly(before.date);
        if (changed) {
          _matchOutside(draft);
        }
      } else {
        _replaceOutside(before, draft);
      }
    }
    // Un pago hecho fuera de Plata que se convierte en otra cosa (una
    // transferencia desde una cuenta, por ejemplo) deja la marca: la persona
    // dijo que ese extracto ya estaba pagado.
    if (before != null && before.isOutsidePayment && !draft.isOutsidePayment) {
      for (final Account card in accounts) {
        final DateTime? cut = card.isCredit ? _linkedCut(card, before) : null;
        if (cut != null && !isStatementPaid(card, cut)) {
          _addMarkOnly(card, cut);
        }
      }
    }
    save();
  }

  /// Borra un movimiento. Si era un abono provisional (pregunta pendiente),
  /// lo que tomó del pago hecho fuera de Plata vuelve; con [restoreOutside]
  /// («Deshacer» de lo que se acaba de anotar), también si ya se había
  /// confirmado. Si se borra el pago hecho fuera de Plata de un extracto, sus
  /// abonos provisionales quedan aparte (la persona dijo que no pagó fuera).
  Future<void> deleteTx(String id, {bool restoreOutside = false}) async {
    final List<String> files = <String>[for (final Tx t in txs.where((Tx t) => t.id == id)) ...t.attachments];
    for (final Tx t in txs.where((Tx t) => t.id == id && (t.outsidePending || (restoreOutside && (t.outsideTaken ?? 0) > 0))).toList()) {
      _giveBack(t);
    }
    final List<_Link> outsideOf = <_Link>[
      for (final Tx t in txs.where((Tx t) => t.id == id && t.isOutsidePayment))
        if (_linkOf(t) != null) _linkOf(t)!,
    ];
    txs.removeWhere((Tx t) => t.id == id);
    for (final _Link link in outsideOf) {
      if (outsidePayments(link.card, link.cut).isEmpty) {
        _releasePending(link.card, link.cut);
      }
    }
    save();
    await deleteAttachmentFiles(files);
  }

  /// Los abonos provisionales del extracto que cortó en [cut] quedan aparte:
  /// la persona quitó el pago hecho fuera de Plata («Desmarcar», «Cambiar
  /// monto» a cero o borrarlo). Lo que habían tomado no vuelve.
  void _releasePending(Account card, DateTime cut) {
    final String key = dayKey(dateOnly(cut));
    for (final Tx t in pendingOutsideMatches(card: card, cut: cut)) {
      t.outsidePending = false;
      t.outsideTaken = null;
      t.statementOf = null;
      if (!t.apartFrom.contains(key)) {
        t.apartFrom.add(key);
      }
    }
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
    // Una copia no es el pago de ese extracto (si puede serlo, se pregunta).
    c.statementOf = null;
    c.apartFrom.clear();
    c.outsideTaken = null;
    c.outsidePending = false;
    c.loggedOn = null;
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

  /// Registro de fotos de recibos que ningún movimiento usa, con la fecha en
  /// que quedaron así (ver [pruneAttachments]).
  static const String orphansFile = 'attachments-orphans.json';

  /// Cuánto se guarda una foto que ningún movimiento usa antes de borrarla.
  static const Duration orphanGrace = Duration(days: 30);

  /// Ordena la carpeta de fotos de recibos. Quita las referencias a fotos que
  /// no están en este teléfono (al restaurar una copia hecha en otro: las
  /// copias guardan los datos, no las fotos). Las fotos que ningún movimiento
  /// usa no se borran de una vez: pueden ser de los datos que reemplazó una
  /// restauración, y deshacerla (restaurar la copia automática previa) las
  /// vuelve a usar. Se borran cuando llevan [orphanGrace] sin uso. Solo corre
  /// si el libro se leyó bien, para no tocar nada si no se pudo descifrar.
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
    final Set<String> used = <String>{for (final Tx t in txs) ...t.attachments};
    Map<String, dynamic> orphans;
    try {
      orphans = await store.store.readJson(orphansFile) ?? <String, dynamic>{};
    } catch (_) {
      orphans = <String, dynamic>{};
    }
    final DateTime now = _clock();
    final Map<String, dynamic> keep = <String, dynamic>{};
    for (final String f in files) {
      if (used.contains(f)) {
        continue;
      }
      if (f.endsWith(JsonStore.tmpSuffix)) {
        // Escritura cortada de una foto: nunca llegó a usarse.
        await deleteAttachmentFiles(<String>[f]);
        continue;
      }
      final DateTime? since = DateTime.tryParse('${orphans[f] ?? ''}');
      if (since == null) {
        keep[f] = now.toIso8601String();
      } else if (now.difference(since) >= orphanGrace) {
        await deleteAttachmentFiles(<String>[f]);
      } else {
        keep[f] = orphans[f];
      }
    }
    try {
      if (keep.isEmpty) {
        await store.store.delete(orphansFile);
      } else {
        await store.store.writeJson(orphansFile, keep);
      }
    } catch (e) {
      debugPrint('Registro de fotos: $e');
    }
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
    // Cuotas: compras y avances (transferencias que salen) de una tarjeta de
    // crédito. Un ajuste de saldo nunca va a cuotas.
    if (t.installments < 1 || !(a.isCredit && (t.kind == TxKind.expense || t.kind == TxKind.transfer)) || t.isAdjustment) {
      t.installments = 1;
    }
  }

  /// Movimientos que cumplen el filtro, ordenados del más reciente al más antiguo.
  List<Tx> search(TxFilter f) {
    final String q = f.text.trim().toLowerCase();
    final String qDigits = RegExp(r'^[\s$]*\d[\d.,\s]*$').hasMatch(q) ? q.replaceAll(RegExp(r'[^0-9]'), '') : '';
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
      if (f.onlyUncategorized && !(t.kind != TxKind.transfer && !t.isNeutral && t.categoryId == null && t.splits.isEmpty)) {
        return false;
      }
      if (f.onlyUnreconciled && t.reconciled) {
        return false;
      }
      if (q.isNotEmpty) {
        final String hay = '${t.description}${t.isOutsidePayment ? ' ${outsideName(spanish: true)} ${outsideName(spanish: false)}' : ''} ${t.payee} ${t.notes} ${t.tags.join(' ')} ${categoryPath(t.categoryId)} ${account(t.accountId)?.name ?? ''} ${t.checkNumber} ${Money.format(t.amountMinor, t.currency, withSymbol: false)} ${Money.format(t.amountMinor, t.currency, withSymbol: false, spanish: false)}'.toLowerCase();
        // Un monto escrito sin separadores ("45000") encuentra $ 45.000.
        final bool sameAmount = qDigits.isNotEmpty && (t.amountMinor % 100 == 0 ? '${t.amountMinor ~/ 100}' == qDigits : '${t.amountMinor}' == qDigits);
        if (!sameAmount && !hay.contains(q)) {
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
  PeriodTotals totals(Period p, {String? accountId}) => totalsOf(p, inPeriod(p, accountId: accountId), accountId: accountId);

  /// Ingresos y gastos de [list] con la misma regla de [totals]: sirve para
  /// la cabecera de Movimientos, que suma lo que muestra la búsqueda.
  PeriodTotals totalsOf(Period p, Iterable<Tx> list, {String? accountId}) {
    int income = 0;
    int expense = 0;
    for (final Tx t in list) {
      if (t.isNeutral || t.kind == TxKind.transfer) {
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
      if (t.isNeutral || t.kind == TxKind.transfer) {
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
      if ((kind != null && t.kind != kind) || t.isNeutral) {
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
    if (t.isNeutral || t.kind == TxKind.transfer) {
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
    return BudgetProgress(budget: b, period: current, spentMinor: budgetSpent(b, current), carryMinor: b.rollover ? _carry(b, current) : 0);
  }

  /// Arrastre de un presupuesto hasta el periodo [current]: la suma, desde su
  /// primer periodo, del tope de cada periodo (el que tenía entonces, ver
  /// [Budget.amountFor]) menos lo gastado en él. Se recorre el libro una sola
  /// vez y se reparte cada movimiento en su periodo.
  int _carry(Budget b, Period current) {
    final String key = 'carry|${b.id}|${b.accountId}|${b.categoryIds.join(',')}|${b.period.name}|${b.customDays}|${dayKey(b.startDate)}|${dayKey(current.start)}|${b.amountMinor}|${b.amountHistory.map((BudgetAmountChange c) => '${dayKey(c.until)}:${c.amountMinor}').join(',')}';
    final int? cached = _spentCache[key];
    if (cached != null) {
      return cached;
    }
    final List<Period> periods = <Period>[];
    Period p = BudgetPeriods.containing(b, dateOnly(b.startDate));
    while (p.start.isBefore(current.start) && periods.length < 50000) {
      periods.add(p);
      p = BudgetPeriods.next(b, p);
    }
    int carry = 0;
    if (periods.isNotEmpty) {
      final List<int> spent = List<int>.filled(periods.length, 0);
      final Set<String> cats = budgetCategories(b);
      final DateTime from = periods.first.start;
      final DateTime to = periods.last.end;
      for (final Tx t in txs) {
        if (t.date.isBefore(from) || !t.date.isBefore(to)) {
          continue;
        }
        final int share = budgetShare(b, t, cats: cats);
        if (share == 0) {
          continue;
        }
        int lo = 0;
        int hi = periods.length - 1;
        while (lo < hi) {
          final int mid = (lo + hi + 1) >> 1;
          if (t.date.isBefore(periods[mid].start)) {
            hi = mid - 1;
          } else {
            lo = mid;
          }
        }
        if (periods[lo].contains(t.date)) {
          spent[lo] += share;
        }
      }
      for (int i = 0; i < periods.length; i++) {
        carry += b.amountFor(periods[i].start) - spent[i];
      }
    }
    _spentCache[key] = carry;
    return carry;
  }

  /// Si los avances de [list] se pueden sumar sin contar dos veces el mismo
  /// gasto: todos en el mismo periodo, ninguno de "todo el gasto" y sin
  /// categorías que se crucen (salvo que sean de cuentas distintas).
  bool canSumBudgets(List<BudgetProgress> list) {
    if (list.length < 2) {
      return false;
    }
    final Period period = list.first.period;
    final List<Set<String>> cats = <Set<String>>[];
    for (final BudgetProgress p in list) {
      if (p.period != period || p.budget.categoryIds.isEmpty) {
        return false;
      }
      cats.add(budgetCategories(p.budget));
    }
    for (int i = 0; i < list.length; i++) {
      for (int j = i + 1; j < list.length; j++) {
        final String? a = list[i].budget.accountId;
        final String? b = list[j].budget.accountId;
        final bool sameMoney = a == null || b == null || effectiveAccountId(a) == effectiveAccountId(b);
        if (sameMoney && cats[i].intersection(cats[j]).isNotEmpty) {
          return false;
        }
      }
    }
    return true;
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
        // Si un aviso del banco ya anotó este cargo (mismo monto y cuenta, dos
        // días o menos), no se anota otra vez: queda vencido para que el
        // usuario lo confirme o lo salte.
        final InboxItem? pendingNotice = pendingNoticeFor(s);
        if (noticeDuplicateFor(s) != null || pendingNotice != null) {
          // Un aviso que espera en la bandeja queda marcado como posible
          // duplicado: al confirmarlo, el programado ya no se anota solo.
          pendingNotice?.duplicateOf ??= 'programado:${s.id}';
          changed = changed || pendingNotice != null;
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
        t.loggedOn = today;
        txs.add(t);
        // Un pago automático a la tarjeta que puede ser el pago hecho fuera
        // de Plata de un extracto marcado: provisional y con la pregunta
        // pendiente en Inicio.
        _insertOutsideCheck(t);
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

  /// Aviso pendiente en la bandeja que parece ser esta ocurrencia de un
  /// programado: mismo tipo, misma cuenta, mismo monto (en la moneda de la
  /// cuenta) y dos días o menos de diferencia con su próxima fecha.
  InboxItem? pendingNoticeFor(Scheduled s) {
    final Account? a = account(s.accountId);
    if (a == null) {
      return null;
    }
    for (final InboxItem i in inbox) {
      if (i.status != 'pending' || i.kind != s.kind || daysBetween(i.receivedAt, s.nextDate).abs() > 2) {
        continue;
      }
      if (_noticeMayBeAccount(i, a) && convert(i.amountMinor, i.currency, a.currency) == s.amountMinor) {
        return i;
      }
    }
    return null;
  }

  /// Si un aviso puede ser de la cuenta [a]: la suya si se sabe; si no se
  /// sabe cuál (varias cuentas de ese banco), basta que [a] sea de ese banco.
  bool _noticeMayBeAccount(InboxItem i, Account a) {
    final String? known = i.accountId ?? matchNotice(i).account?.id;
    if (known != null) {
      return effectiveAccountId(known) == effectiveAccountId(a.id);
    }
    final Account? own = account(effectiveAccountId(a.id));
    return own != null && own.bank.isNotEmpty && BankRules.keyFor(own.bank) == i.bank;
  }

  /// Programado activo cuya próxima ocurrencia parece ser el cargo de un
  /// aviso (el aviso llegó antes de que el programado se anotara).
  Scheduled? scheduledDuplicateFor(InboxItem item) {
    for (final Scheduled s in scheduled) {
      final Account? a = account(s.accountId);
      if (a == null || !s.enabled || s.kind != item.kind || daysBetween(s.nextDate, item.receivedAt).abs() > 2) {
        continue;
      }
      if (_noticeMayBeAccount(item, a) && convert(item.amountMinor, item.currency, a.currency) == s.amountMinor) {
        return s;
      }
    }
    return null;
  }

  /// Movimiento ya anotado que se parece a [t] (otro, del mismo tipo, misma
  /// cuenta, mismo monto y dos días o menos): al confirmar un aviso se
  /// pregunta antes de contarlo dos veces.
  Tx? similarTx(Tx t) {
    for (final Tx o in txs) {
      if (o.id == t.id || o.kind != t.kind || o.isNeutral || o.amountMinor != t.amountMinor) {
        continue;
      }
      if (effectiveAccountId(o.accountId) != effectiveAccountId(t.accountId) || daysBetween(o.date, t.date).abs() > 2) {
        continue;
      }
      return o;
    }
    return null;
  }

  /// Movimiento anotado desde un aviso del banco que parece ser esta
  /// ocurrencia de un programado: mismo tipo, misma cuenta (o una débito
  /// suya), mismo monto y dos días o menos de diferencia con [date] (por
  /// defecto, la próxima fecha del programado).
  Tx? noticeDuplicateFor(Scheduled s, {DateTime? date}) {
    final DateTime d = date ?? s.nextDate;
    final String acc = effectiveAccountId(s.accountId);
    for (final Tx t in txs) {
      if (t.source != 'notice' || t.kind != s.kind || t.amountMinor != s.amountMinor || t.isNeutral) {
        continue;
      }
      if (effectiveAccountId(t.accountId) != acc || daysBetween(t.date, d).abs() > 2) {
        continue;
      }
      return t;
    }
    return null;
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

  /// Unidad más pequeña que se muestra de una moneda, en centavos: 100 si se
  /// muestra sin decimales (el peso colombiano), 1 si con dos.
  static int displayUnit(String currency) => Money.info(currency).decimals >= 2 ? 1 : 100;

  /// Valor de la cuota [k] (1..[n]) de una compra de [total]: todas iguales,
  /// redondeadas a la unidad que se muestra ([unit], ver [displayUnit]), y la
  /// última con lo que sobra, para que sumen exactamente el total y cada línea
  /// del estado de cuenta sea una cifra que se puede pagar.
  static int installmentAmount(int total, int n, int k, {int unit = 1}) {
    if (n <= 1) {
      return total;
    }
    final int u = unit < 1 ? 1 : unit;
    final int base = (total ~/ n) ~/ u * u;
    return k == n ? total - base * (n - 1) : base;
  }

  /// Corte del ciclo en que cae una fecha.
  DateTime _cutOf(Account card, DateTime d) => CardCycle.current(card, d).cut;

  /// Corte del estado al que se aplica un abono hecho el día [d]: el que tiene
  /// la primera fecha de pago en o después de [d].
  DateTime _paymentCut(Account card, DateTime d) {
    CardCycle c = CardCycle.current(card, d);
    for (int i = 0; i < 2; i++) {
      final CardCycle p = c.previous(card);
      // Con la fecha límite real (corrida al día hábil): un abono del domingo
      // o del lunes corrido es para el extracto que vence ese lunes.
      if (!d.isAfter(effectivePayDate(card, p.payDate))) {
        c = p;
      } else {
        break;
      }
    }
    return c.cut;
  }

  /// Corte del extracto al que se refiere «el pago mínimo del último extracto» de
  /// una tarjeta: el que quedó fijo al anotarlo o, si todavía no, el último
  /// que cerró antes del primer movimiento de la tarjeta (o antes de hoy, si
  /// no tiene ninguno). Así lo anotado en Plata nunca se cuenta dos veces.
  DateTime referenceStatementCut(Account card) {
    final DateTime? fixed = card.statementCut;
    if (fixed != null) {
      return CardCycle.current(card, fixed).cut;
    }
    DateTime? earliest;
    if (card.id.isNotEmpty) {
      for (final Tx t in txs) {
        final bool touches = effectiveAccountId(t.accountId) == card.id || (t.kind == TxKind.transfer && t.toAccountId != null && effectiveAccountId(t.toAccountId!) == card.id);
        if (touches && !t.isOutsidePayment && (earliest == null || t.date.isBefore(earliest))) {
          earliest = t.date;
        }
      }
    }
    return CardCycle.current(card, earliest ?? _clock()).previous(card).cut;
  }

  /// Movimientos de una tarjeta repartidos por ciclo (se calcula una vez por
  /// versión del libro).
  _CardBook _cardBook(Account card) {
    final String key = '${card.id}|${card.cutDay}|${card.payDay}|${card.initialMinor}|${card.statementDueMinor}|${card.statementCut?.toIso8601String()}|${card.currency}|${card.markedOnly.join(',')}|${card.statementMinimums}';
    final _CardBook? cached = _cardCache[key];
    if (cached != null) {
      return cached;
    }
    bool touches(Tx t) => effectiveAccountId(t.accountId) == card.id || (t.kind == TxKind.transfer && t.toAccountId != null && effectiveAccountId(t.toAccountId!) == card.id);
    DateTime? earliest;
    for (final Tx t in txs) {
      // Un pago hecho fuera de Plata no marca el comienzo de la tarjeta.
      if (touches(t) && !t.isOutsidePayment && (earliest == null || t.date.isBefore(earliest))) {
        earliest = t.date;
      }
    }
    final DateTime? statementCut = card.statementCut;
    final CardCycle first = statementCut != null
        ? CardCycle.current(card, statementCut)
        : (earliest != null ? CardCycle.current(card, earliest) : CardCycle.current(card, _clock()).previous(card));
    final _CardBook book = _CardBook(first.cut);
    final int debt = card.initialMinor < 0 ? -card.initialMinor : 0;
    final int lastStatement = (card.statementDueMinor ?? 0).clamp(0, debt);
    book.opening = card.initialMinor > 0 ? -card.initialMinor : lastStatement;
    book.legacy = debt - lastStatement;
    final int unit = displayUnit(card.currency);

    void charge(DateTime cut, int amount, bool advance) {
      if (cut.isBefore(book.firstCut)) {
        book.opening += amount;
      } else if (advance) {
        book.at(cut).advances += amount;
      } else {
        book.at(cut).purchases += amount;
      }
    }

    void creditTo(DateTime cut, int amount) {
      if (cut.isBefore(book.firstCut)) {
        book.opening -= amount;
      } else {
        book.at(cut).payments += amount;
      }
    }

    // Una sola regla decide a qué extracto va cada abono:
    // 1. el vinculado (`Tx.statementOf`), también el pago hecho fuera de
    //    Plata («Ya lo pagué»), a su extracto, con cualquier fecha;
    // 2. los demás, al extracto con la primera fecha límite real en o después
    //    del día del abono.
    void credit(DateTime d, int amount, Tx t) {
      final DateTime? linked = _linkedCut(card, t);
      if (linked != null) {
        book.linked[linked] = (book.linked[linked] ?? 0) + amount;
        creditTo(linked, amount);
        return;
      }
      creditTo(_paymentCut(card, d), amount);
    }

    for (final Tx t in txs) {
      final DateTime d = dateOnly(t.date);
      final bool from = effectiveAccountId(t.accountId) == card.id;
      if (from && t.isAdjustment) {
        // «Ajustar saldo real» corrige la deuda, pero no es algo que el banco
        // cobre en el próximo pago: va a la deuda aparte.
        final int delta = t.kind == TxKind.expense ? t.amountMinor : -t.amountMinor;
        final DateTime cut = _cutOf(card, d);
        book.adjusted = true;
        if (cut.isBefore(book.firstCut)) {
          book.legacy += delta;
        } else {
          book.at(cut).adjustments += delta;
        }
        continue;
      }
      if (from && (t.kind == TxKind.expense || t.kind == TxKind.transfer) && t.installments > 1) {
        // Compra o avance diferido: la cuota k se factura en el k-ésimo corte
        // desde la operación; la primera, en el primer corte después.
        final bool advance = t.kind == TxKind.transfer;
        final DateTime firstCut = _cutOf(card, d);
        for (int k = 1; k <= t.installments; k++) {
          final DateTime cut = CardCycle.cutAfter(card, firstCut, k - 1);
          final int amount = installmentAmount(t.amountMinor, t.installments, k, unit: unit);
          if (cut.isBefore(book.firstCut)) {
            book.opening += amount;
          } else if (advance) {
            book.at(cut).advances += amount;
          } else {
            book.at(cut).installments += amount;
          }
        }
      } else if (from && t.kind == TxKind.expense) {
        if (t.installments <= 1) {
          charge(_cutOf(card, d), t.amountMinor, false);
        } else {
          // La cuota k se factura en el k-ésimo corte desde la compra: la
          // primera, en el primer corte después de la compra.
          final DateTime firstCut = _cutOf(card, d);
          for (int k = 1; k <= t.installments; k++) {
            final DateTime cut = CardCycle.cutAfter(card, firstCut, k - 1);
            final int amount = installmentAmount(t.amountMinor, t.installments, k, unit: unit);
            if (cut.isBefore(book.firstCut)) {
              book.opening += amount;
            } else {
              book.at(cut).installments += amount;
            }
          }
        }
      } else if (from && t.kind == TxKind.transfer) {
        charge(_cutOf(card, d), t.amountMinor, true);
      } else if (from && t.kind == TxKind.income) {
        credit(d, t.amountMinor, t);
      }
      if (t.kind == TxKind.transfer && t.toAccountId != null && effectiveAccountId(t.toAccountId!) == card.id) {
        credit(d, receivedMinor(t), t);
      }
    }
    if (book.legacy < 0) {
      // Un ajuste hacia abajo antes del primer ciclo que pasa de la deuda
      // aparte baja el saldo anterior.
      book.opening += book.legacy;
      book.legacy = 0;
    }
    _cardCache[key] = book;
    return book;
  }

  /// Estado de cuenta estimado de una tarjeta para el ciclo que contiene [date].
  ///
  /// - Compras de una cuota, avances (transferencias que salen de la tarjeta)
  ///   y ajustes: en el ciclo de su fecha, (corte anterior, corte].
  /// - Cuota k de una compra diferida: en el k-ésimo corte desde la compra; la
  ///   primera cuota se factura en el primer corte después de la compra, como
  ///   en los bancos colombianos (ver docs/DECISIONES.md).
  /// - Abonos (pagos a la tarjeta y devoluciones): en la ventana entre la fecha
  ///   de pago anterior y la de este estado, que es como el banco los aplica.
  /// - Lo facturado antes y no pagado llega como saldo anterior; un abono de
  ///   más llega como saldo a favor.
  /// - La deuda inicial se reparte así: el pago mínimo del último extracto (si se
  ///   anotó al crear la tarjeta) vence en ese extracto; el resto es deuda de
  ///   antes de Plata, que el banco factura a su manera (cuotas viejas): no se
  ///   suma a ningún estado y se muestra aparte. Lo que se abone de más sobre
  ///   un estado se descuenta primero de esa deuda vieja.
  ///
  /// Es solo capital: Plata no calcula intereses ni cuota de manejo.
  CardStatement statement(Account card, {DateTime? date}) {
    final CardCycle cycle = CardCycle.current(card, date ?? _clock());
    final _CardBook book = _cardBook(card);
    if (cycle.cut.isBefore(book.firstCut)) {
      return CardStatement(cycle: cycle, previousMinor: 0, purchasesMinor: 0, advancesMinor: 0, installmentsMinor: 0, paymentsMinor: 0, legacyMinor: book.legacy);
    }
    int carry = book.opening;
    int legacy = book.legacy;
    final _CycleSums empty = _CycleSums();
    for (int i = 0; i < 1200; i++) {
      final DateTime cut = CardCycle.cutAfter(card, book.firstCut, i);
      final _CycleSums s = book.sums[cut] ?? empty;
      legacy += s.adjustments;
      // Un ajuste hacia abajo mayor que la deuda aparte se descuenta del
      // estado, como un abono (y se muestra junto con los abonos).
      int adjustCredit = 0;
      if (legacy < 0) {
        adjustCredit = -legacy;
        legacy = 0;
      }
      final int payments = s.payments + adjustCredit;
      int balance = carry + s.purchases + s.advances + s.installments - payments;
      int toLegacy = 0;
      if (balance < 0 && legacy > 0) {
        toLegacy = legacy < -balance ? legacy : -balance;
        legacy -= toLegacy;
        balance += toLegacy;
      }
      if (cut == cycle.cut || cut.isAfter(cycle.cut)) {
        return CardStatement(cycle: cycle, previousMinor: carry, purchasesMinor: s.purchases, advancesMinor: s.advances, installmentsMinor: s.installments, paymentsMinor: payments, toLegacyMinor: toLegacy, legacyMinor: legacy, fromBankStatement: i == 0 && card.statementCut != null && (card.statementDueMinor ?? 0) > 0);
      }
      carry = balance;
    }
    return CardStatement(cycle: cycle, previousMinor: carry, purchasesMinor: 0, advancesMinor: 0, installmentsMinor: 0, paymentsMinor: 0, legacyMinor: legacy);
  }

  /// Abonos sin vínculo a una tarjeta hechos después de [after] y hasta el
  /// final de [until].
  int _creditsBetween(Account card, DateTime after, DateTime until) {
    final DateTime a = dateOnly(after);
    final DateTime u = dateOnly(until);
    int sum = 0;
    for (final Tx t in txs) {
      final int amount = _creditAmount(card, t);
      if (amount == 0 || _linkedCut(card, t) != null) {
        continue;
      }
      final DateTime d = dateOnly(t.date);
      if (d.isAfter(a) && !d.isAfter(u)) {
        sum += amount;
      }
    }
    return sum;
  }

  /// Lo que un movimiento abona a una tarjeta (0 si no le abona; los ajustes
  /// de saldo no son abonos).
  int _creditAmount(Account card, Tx t) {
    if (t.isAdjustment) {
      return 0;
    }
    if (t.kind == TxKind.income && effectiveAccountId(t.accountId) == card.id) {
      return t.amountMinor;
    }
    if (t.kind == TxKind.transfer && t.toAccountId != null && effectiveAccountId(t.toAccountId!) == card.id) {
      return receivedMinor(t);
    }
    return 0;
  }

  /// Lo que falta del mínimo conocido del extracto que cortó en [cut], según
  /// lo anotado hasta [now]. Es la cifra del aviso rojo, de la notificación y
  /// de la fila del extracto, y lo que guarda «Ya lo pagué». Null si no se
  /// conoce el mínimo. Ver [_minimumsLeft].
  int? statementMissing(Account card, DateTime cut, {DateTime? now}) {
    if (statementMinimum(card, cut) == null) {
      return null;
    }
    return _minimumsLeft(card, dateOnly(now ?? _clock()))[dateOnly(cut)] ?? 0;
  }

  /// Lo que falta de cada mínimo conocido, con una sola regla para que ningún
  /// abono cuente para dos mínimos: a cada extracto le cuentan primero los
  /// pagos vinculados a él y lo pagado fuera de Plata para él; después, los
  /// abonos sin vínculo (devoluciones incluidas) hechos después de su corte y
  /// hasta [now], del más antiguo al más reciente, y del extracto más antiguo
  /// al más reciente (como el banco, que aplica primero a lo más viejo). Un
  /// abono que ya completó un mínimo no cuenta otra vez para el siguiente.
  Map<DateTime, int> _minimumsLeft(Account card, DateTime now, {Tx? exclude}) {
    final _CardBook book = _cardBook(card);
    // Un abono provisional (pregunta sin contestar) cuenta para el mínimo de
    // su extracto natural, por fecha, como si no estuviera vinculado; lo que
    // tomó sigue contando como pago de fuera de su extracto. Así ningún
    // «Vencido» depende de una pregunta sin contestar.
    final Map<DateTime, int> pendingCredit = <DateTime, int>{};
    final Map<DateTime, int> pendingTaken = <DateTime, int>{};
    for (final Tx t in txs) {
      final DateTime? k = t.outsidePending ? _linkedCut(card, t) : null;
      if (k != null) {
        pendingCredit[k] = (pendingCredit[k] ?? 0) + _creditAmount(card, t);
        pendingTaken[k] = (pendingTaken[k] ?? 0) + (t.outsideTaken ?? 0);
      }
    }
    final Set<DateTime> cuts = <DateTime>{
      for (final String key in card.statementMinimums.keys)
        if (DateTime.tryParse(key) != null) CardCycle.current(card, DateTime.parse(key)).cut,
      if (card.statementCut != null && card.statementDueMinor != null) CardCycle.current(card, card.statementCut!).cut,
    };
    final List<DateTime> ordered = cuts.toList()..sort();
    final Map<DateTime, int> need = <DateTime, int>{};
    for (final DateTime c in ordered) {
      // Lo vinculado incluye lo pagado fuera de Plata.
      final int linked = (book.linked[c] ?? 0) - (pendingCredit[c] ?? 0) + (pendingTaken[c] ?? 0);
      final int left = (statementMinimum(card, c) ?? 0) - linked;
      need[c] = left > 0 ? left : 0;
    }
    final List<Tx> credits = txs.where((Tx t) => !identical(t, exclude) && (t.statementOf == null || t.outsidePending) && _creditAmount(card, t) > 0 && !dateOnly(t.date).isAfter(now)).toList()
      ..sort((Tx a, Tx b) => a.date.compareTo(b.date));
    final List<int> left = <int>[for (final Tx t in credits) _creditAmount(card, t)];
    for (final DateTime c in ordered) {
      int n = need[c]!;
      for (int i = 0; i < credits.length && n > 0; i++) {
        if (left[i] <= 0 || !dateOnly(credits[i].date).isAfter(c)) {
          continue;
        }
        final int take = left[i] < n ? left[i] : n;
        left[i] -= take;
        n -= take;
      }
      need[c] = n;
    }
    return need;
  }

  /// Situación de pago de una tarjeta hoy.
  ///
  /// - Próximo pago: el último estado cerrado mientras no pase su fecha
  ///   límite (si debe algo); si no, el del ciclo en curso.
  /// - Del último extracto cuya fecha límite ya pasó: si hay un pago mínimo
  ///   conocido ([statementMinimum]) y lo abonado después de su corte es
  ///   menor, la diferencia está **vencida** desde esa fecha, hasta que se
  ///   pague. Sin mínimo conocido, lo que el estimado de Plata diga que falta
  ///   se informa como [CardDue.unconfirmedMinor], sin declarar mora.
  CardDue cardDue(Account card, {DateTime? now}) {
    final DateTime today = dateOnly(now ?? _clock());
    final CardCycle current = CardCycle.current(card, today);
    final CardCycle prev = current.previous(card);
    CardStatement? next;
    // El próximo pago es el extracto cerrado más antiguo cuya fecha límite
    // real no ha pasado, si debe algo y no está marcado como pagado. La fecha
    // que cae en sábado, domingo o festivo se corre al siguiente día hábil:
    // hasta ese día el extracto sigue siendo el próximo. Con el día de pago
    // igual al corte o uno o dos días antes, la fecha corrida puede caer
    // después del corte siguiente: por eso se miran dos extractos.
    for (final CardCycle closed in <CardCycle>[prev.previous(card), prev]) {
      if (!effectivePayDate(card, closed.payDate).isBefore(today) && !isStatementPaid(card, closed.cut)) {
        final CardStatement st = statement(card, date: closed.cut);
        if (st.dueMinor > 0) {
          next = st;
          break;
        }
      }
    }
    next ??= statement(card, date: today);
    CardCycle passed = prev;
    for (int i = 0; i < 3 && !effectivePayDate(card, passed.payDate).isBefore(today); i++) {
      passed = passed.previous(card);
    }
    final DateTime due = effectivePayDate(card, passed.payDate);
    if (!due.isBefore(today) || passed.cut.isBefore(_cardBook(card).firstCut) || isStatementPaid(card, passed.cut)) {
      // Sin extracto vencido, de antes de Plata, o que la persona dijo que ya
      // pagó: no hay nada que avisar.
      return CardDue(next: next);
    }
    if (statementMinimum(card, passed.cut) != null) {
      final int late = statementMissing(card, passed.cut, now: today)!;
      return CardDue(next: next, overdueMinor: late > 0 ? late : 0, overdueSince: late > 0 ? due : null, statementCut: passed.cut, statementPayDate: due);
    }
    final int left = statement(card, date: passed.cut).dueMinor - _creditsBetween(card, due, today);
    return CardDue(next: next, unconfirmedMinor: left > 0 ? left : 0, statementCut: passed.cut, statementPayDate: due);
  }

  /// Fecha límite real de un pago: la nominal o, si cae en sábado, domingo o
  /// festivo de Colombia, el siguiente día hábil (art. 829 del Código de
  /// Comercio y práctica de los bancos). Se aplica a las tarjetas en pesos y
  /// a las de un libro en pesos; para las demás se deja la nominal.
  DateTime effectivePayDate(Account card, DateTime nominal) {
    if (card.currency != 'COP' && baseCurrency != 'COP') {
      return dateOnly(nominal);
    }
    return ColombianHolidays.nextBusinessDay(nominal);
  }

  /// Lo pagado fuera de Plata para el extracto que cortó en [cut] («Ya lo
  /// pagué»): la suma de sus movimientos «Pago hecho fuera de Plata».
  int outsidePayment(Account card, DateTime cut) => outsidePayments(card, cut).fold<int>(0, (int a, Tx t) => a + t.amountMinor);

  /// Movimientos «Pago hecho fuera de Plata» del extracto que cortó en [cut].
  List<Tx> outsidePayments(Account card, DateTime cut) {
    final DateTime c = dateOnly(cut);
    return txs.where((Tx t) => t.isOutsidePayment && _linkedCut(card, t) == c).toList();
  }

  /// Cambia lo pagado fuera de Plata para un extracto marcado («Cambiar
  /// monto» en la fila). En cero se borra el movimiento y queda la marca.
  void setOutsidePayment(Account card, DateTime cut, int amountMinor) {
    final DateTime c = dateOnly(cut);
    final List<Tx> mine = outsidePayments(card, c);
    final int value = amountMinor < 0 ? 0 : amountMinor;
    if (mine.isEmpty) {
      if (value > 0 && isStatementPaid(card, c)) {
        card.markedOnly.remove(dayKey(c));
        txs.add(_outsideTx(card, c, value, _today));
        _sortTxs();
        save();
      }
      return;
    }
    for (final Tx t in mine.skip(1)) {
      txs.remove(t);
    }
    if (value == 0) {
      txs.remove(mine.first);
      _addMarkOnly(card, c);
      _releasePending(card, c);
    } else {
      mine.first.amountMinor = value;
    }
    save();
  }

  /// Total de los pagos vinculados al extracto que cortó en [cut] anotados
  /// desde cuentas de Plata (sin los hechos fuera).
  int linkedPayments(Account card, DateTime cut) {
    final DateTime c = dateOnly(cut);
    int sum = 0;
    for (final Tx t in txs) {
      if (!t.isOutsidePayment && t.statementOf != null && _linkedCut(card, t) == c) {
        sum += _creditAmount(card, t);
      }
    }
    return sum;
  }

  /// Movimiento «Pago hecho fuera de Plata»: un abono a la tarjeta que no sale
  /// de ninguna cuenta, vinculado al extracto que cortó en [cut], con el día
  /// en que se marcó.
  Tx _outsideTx(Account card, DateTime cut, int amountMinor, DateTime on) => Tx(
        id: newId(),
        kind: TxKind.income,
        amountMinor: amountMinor,
        accountId: card.id,
        currency: card.currency,
        date: DateTime(on.year, on.month, on.day, 12),
        // El nombre se genera al mostrarlo, en el idioma de ese momento
        // ([outsideName]).
        source: 'outside',
        statementOf: dayKey(cut),
      );

  /// Nombre de un pago hecho fuera de Plata, en el idioma que se pide.
  static String outsideName({required bool spanish}) => spanish ? 'Pago hecho fuera de Plata' : 'Payment made outside Plata';

  /// Descripción que se muestra de un movimiento: la escrita o, en un pago
  /// hecho fuera de Plata sin descripción propia, su nombre en el idioma
  /// actual.
  static String shownDescription(Tx t, {required bool spanish}) {
    if (t.isOutsidePayment && (t.description.isEmpty || t.description == outsideName(spanish: true) || t.description == outsideName(spanish: false))) {
      return outsideName(spanish: spanish);
    }
    return t.description;
  }

  void _addMarkOnly(Account card, DateTime cut) {
    final String key = dayKey(cut);
    if (!card.markedOnly.contains(key)) {
      card.markedOnly.add(key);
      card.markedOnly.sort();
      while (card.markedOnly.length > 48) {
        card.markedOnly.removeAt(0);
      }
    }
  }

  /// Si el extracto que cortó en [cut] es de antes de que la tarjeta empezara
  /// en Plata: anterior a su primer ciclo, o el primer ciclo de una tarjeta
  /// con deuda inicial (salvo que su mínimo se anotara como pendiente al
  /// crearla). La deuda inicial ya refleja lo que se pagó antes.
  bool _beforeStart(Account card, DateTime cut, [_CardBook? known]) {
    final _CardBook book = known ?? _cardBook(card);
    final DateTime c = dateOnly(cut);
    if (c.isBefore(book.firstCut)) {
      return true;
    }
    if (c.isAfter(book.firstCut) || card.initialMinor >= 0) {
      return false;
    }
    final DateTime? ref = card.statementCut;
    final bool pendingAtStart = ref != null && CardCycle.current(card, ref).cut == c && (card.statementDueMinor ?? 0) > 0;
    return !pendingAtStart;
  }

  /// Qué hace «Ya lo pagué» con el extracto que cortó en [cut]:
  /// - [MarkKind.payment]: crea un movimiento «Pago hecho fuera de Plata»;
  /// - [MarkKind.markOnly]: solo marca (Plata no tiene deuda de ese extracto);
  /// - [MarkKind.ask]: es de antes de que la tarjeta empezara en Plata y hay
  ///   deuda inicial: hay que preguntar si se pagó antes de crearla (la deuda
  ///   inicial ya lo descuenta: solo marca) o después (es un pago).
  MarkKind markKind(Account card, DateTime cut) {
    if (!_beforeStart(card, cut)) {
      return MarkKind.payment;
    }
    return card.initialMinor < 0 ? MarkKind.ask : MarkKind.markOnly;
  }

  /// Si [t] (un abono sin vínculo a una tarjeta) puede ser el pago hecho
  /// fuera de Plata de un extracto marcado «Ya lo pagué», devuelve el corte
  /// de ese extracto; si no, null. Regla acotada y predecible (ronda 13):
  /// - un solo candidato: el extracto marcado más reciente que aún tiene pago
  ///   de fuera (contando lo que tienen provisionalmente otros abonos sin
  ///   contestar), si la persona no contestó ya «Es otro pago» por él
  ///   ([Tx.apartFrom]);
  /// - el abono se **anotó** ([Tx.loggedOn]; los de antes, su fecha) entre
  ///   el día de la marca y la fecha límite real del extracto siguiente;
  /// - su fecha es posterior a ese corte; con fecha después del corte
  ///   siguiente y más de lo pagado fuera (+1 %), es el pago de ese extracto
  ///   siguiente (caso N2): no;
  /// - si hay un extracto cerrado más nuevo, sin marcar, con un mínimo
  ///   conocido que aún falta, el abono es de ese: no se pregunta;
  /// - nunca las devoluciones, los ajustes ni los pagos de fuera.
  /// Quien anota un pago marcado después de la ventana lo vincula desde la
  /// fila del extracto («Ya lo anoté en Plata: elegir el movimiento»).
  DateTime? outsideCandidate(Tx t) {
    if (t.statementOf != null || t.isOutsidePayment || t.isAdjustment) {
      return null;
    }
    // Una devolución de una compra no es el pago del extracto.
    if (t.kind == TxKind.income && _parts(t).every((TxSplit p) => isRefundCategory(p.categoryId))) {
      return null;
    }
    final DateTime d = dateOnly(t.date);
    final DateTime logged = dateOnly(t.loggedOn ?? t.date);
    for (final Account card in accounts) {
      final int amount = card.isCredit ? _creditAmount(card, t) : 0;
      if (amount <= 0) {
        continue;
      }
      final Map<DateTime, int> outside = <DateTime, int>{};
      final Map<DateTime, DateTime> markedOn = <DateTime, DateTime>{};
      for (final Tx o in txs) {
        if (identical(o, t) || o.id == t.id) {
          continue;
        }
        final int held = o.isOutsidePayment ? o.amountMinor : (o.outsidePending ? (o.outsideTaken ?? 0) : 0);
        final DateTime? cut = held > 0 ? _linkedCut(card, o) : null;
        if (cut != null) {
          outside[cut] = (outside[cut] ?? 0) + held;
          final DateTime on = dateOnly(o.isOutsidePayment ? o.date : (o.loggedOn ?? o.date));
          final DateTime? was = markedOn[cut];
          markedOn[cut] = was == null || on.isBefore(was) ? on : was;
        }
      }
      if (outside.isEmpty) {
        continue;
      }
      final DateTime cut = outside.keys.reduce((DateTime a, DateTime b) => a.isAfter(b) ? a : b);
      if (t.apartFrom.contains(dayKey(cut))) {
        continue;
      }
      final CardCycle next = CardCycle.current(card, DateTime(cut.year, cut.month, cut.day + 1));
      if (logged.isBefore(markedOn[cut]!) || logged.isAfter(effectivePayDate(card, next.payDate))) {
        continue;
      }
      if (!d.isAfter(cut)) {
        continue;
      }
      final int out = outside[cut]!;
      if (d.isAfter(next.cut) && amount > out + out ~/ 100) {
        continue;
      }
      bool newerUnpaid = false;
      Map<DateTime, int>? left;
      for (DateTime k2 = next.cut; k2.isBefore(d) && !newerUnpaid; k2 = CardCycle.cutAfter(card, k2, 1)) {
        if (!isStatementPaid(card, k2) && statementMinimum(card, k2) != null) {
          left ??= _minimumsLeft(card, _today, exclude: t);
          newerUnpaid = (left[k2] ?? 0) > 0;
        }
      }
      if (newerUnpaid) {
        continue;
      }
      return cut;
    }
    return null;
  }

  /// Abonos sin vínculo a [card] con fecha después del corte [cut] (sin las
  /// devoluciones): los que se pueden elegir con «Ya lo anoté en Plata» en la
  /// fila de un extracto marcado, del más reciente al más antiguo.
  List<Tx> unlinkedCreditsAfter(Account card, DateTime cut) {
    final DateTime c = dateOnly(cut);
    return txs.where((Tx t) {
      if (t.statementOf != null || t.isOutsidePayment || t.isAdjustment || _creditAmount(card, t) <= 0) {
        return false;
      }
      if (t.kind == TxKind.income && _parts(t).every((TxSplit p) => isRefundCategory(p.categoryId))) {
        return false;
      }
      return dateOnly(t.date).isAfter(c);
    }).toList()
      ..sort((Tx a, Tx b) => b.date.compareTo(a.date));
  }

  /// «Ya lo anoté en Plata: elegir el movimiento»: [t] es el pago hecho
  /// fuera de Plata del extracto que cortó en [cut], anotado desde Plata
  /// (por ejemplo, después de la ventana de la pregunta). Queda vinculado y
  /// lo reemplaza, como un pago registrado desde la fila.
  void linkToStatement(Tx t, DateTime cut) {
    final Tx draft = Tx.fromJson(t.toJson())
      ..statementOf = dayKey(dateOnly(cut))
      ..outsidePending = false
      ..outsideTaken = null;
    draft.apartFrom.remove(dayKey(dateOnly(cut)));
    updateTx(draft);
  }

  /// Abonos que Plata tomó provisionalmente por un pago hecho fuera de Plata
  /// y cuya pregunta «¿Es el pago del extracto…?» nadie ha contestado (de
  /// [card], y del extracto que cortó en [cut], si se dan). Se muestran en
  /// Inicio y en Tarjetas hasta que se contesten.
  List<Tx> pendingOutsideMatches({Account? card, DateTime? cut}) {
    final DateTime? c = cut == null ? null : dateOnly(cut);
    return txs.where((Tx t) {
      if (!t.outsidePending) {
        return false;
      }
      final _Link? link = _linkOf(t);
      return link != null && (card == null || link.card.id == card.id) && (c == null || link.cut == c);
    }).toList();
  }

  /// Extracto del que [t] es provisionalmente el pago hecho fuera de Plata
  /// (pregunta pendiente), o null.
  DateTime? pendingOutsideCut(Tx t) => t.outsidePending ? _linkOf(t)?.cut : null;

  /// Tarjeta a la que abona [t] y que tiene su pregunta pendiente, o null.
  Account? pendingOutsideCard(Tx t) => t.outsidePending ? _linkOf(t)?.card : null;

  /// La persona contesta la pregunta de un abono provisional ([t] o el que
  /// tiene su id). «Sí, es ese pago»: queda vinculado (y toma lo que tenían
  /// otros provisionales de ese extracto si abona más). «Es otro pago»: lo
  /// que tomó vuelve, queda sin vínculo y aparte de ese extracto. No se
  /// pregunta por otros extractos (sin cadena).
  void answerOutsideMatch(Tx t, {required bool same}) {
    final int i = txs.indexWhere((Tx x) => x.id == t.id);
    if (i < 0 || !txs[i].outsidePending) {
      return;
    }
    final Tx stored = txs[i];
    if (same) {
      stored.outsidePending = false;
      final _Link? link = _linkOf(stored);
      if (link != null) {
        final int spare = _creditAmount(link.card, stored) - (stored.outsideTaken ?? 0);
        if (spare > 0) {
          final int got = _takeFromPending(link.card, stored, link.cut, spare);
          if (got > 0) {
            stored.outsideTaken = (stored.outsideTaken ?? 0) + got;
          }
        }
      }
    } else {
      // Sin cadena: queda aparte y no se pregunta por otros extractos.
      final DateTime? cut = _giveBack(stored);
      stored.statementOf = null;
      if (cut != null && !stored.apartFrom.contains(dayKey(cut))) {
        stored.apartFrom.add(dayKey(cut));
      }
    }
    save();
  }

  /// Corte del extracto al que está vinculado un abono a [card], o null si
  /// no es un abono a esa tarjeta o no está vinculado.
  DateTime? _linkedCut(Account card, Tx t) {
    final String? key = t.statementOf;
    if (key == null) {
      return null;
    }
    final bool credits = (t.kind == TxKind.income && effectiveAccountId(t.accountId) == card.id) || (t.kind == TxKind.transfer && t.toAccountId != null && effectiveAccountId(t.toAccountId!) == card.id);
    if (!credits) {
      return null;
    }
    final DateTime? d = DateTime.tryParse(key);
    return d == null ? null : CardCycle.current(card, d).cut;
  }

  /// Pagos vinculados al extracto que cortó en [cut] (registrados desde su
  /// fila en Tarjetas), del más antiguo al más reciente.
  List<Tx> statementPayments(Account card, DateTime cut) {
    final DateTime c = dateOnly(cut);
    return txs.where((Tx t) => t.statementOf != null && _linkedCut(card, t) == c).toList()..sort((Tx a, Tx b) => a.date.compareTo(b.date));
  }

  /// Extracto al que pasa un dato del extracto que cortó en [old] cuando el
  /// día de corte cambia a [newCutDay], con [on] el día de referencia de ese
  /// extracto: el del mismo mes con el día nuevo si ya había cerrado ese día
  /// (su corte es anterior a [on]); si no, el anterior. Nunca uno que no
  /// había cerrado ese día, ni uno posterior a hoy.
  DateTime movedCut(int newCutDay, DateTime old, DateTime on) {
    final DateTime limit = on.isAfter(_today) ? _today : dateOnly(on);
    final Account probe = Account(id: '', name: '', type: AccountType.credit, cutDay: newCutDay);
    final DateTime same = CardCycle.cutAfter(probe, DateTime(old.year, old.month), 0);
    return same.isBefore(limit) ? same : CardCycle.cutAfter(probe, same, -1);
  }

  /// Día de las versiones anteriores, que no lo guardaban: la fecha límite
  /// real del extracto con el corte y el pago de entonces ([oldCutDay],
  /// [oldPayDay]), sin pasar de hoy.
  DateTime _legacyNotedOn(Account card, DateTime cut, int oldCutDay, int? oldPayDay) {
    final Account old = Account(id: card.id, name: '', type: AccountType.credit, cutDay: oldCutDay, payDay: oldPayDay ?? card.payDay, currency: card.currency);
    final DateTime due = effectivePayDate(old, CardCycle.current(old, cut).payDate);
    return due.isAfter(_today) ? _today : due;
  }

  /// Día de referencia de cada extracto con datos (`dayKey` del corte), para
  /// moverlos **juntos** al cambiar el día de corte: el más antiguo entre el
  /// día en que se anotó su mínimo, el de sus pagos hechos fuera, el de sus
  /// pagos vinculados (posteriores a su corte) y, si es el extracto de
  /// referencia de la deuda inicial, el día en que se anotó. Sin ninguno
  /// (datos de versiones anteriores), el de [_legacyNotedOn].
  Map<String, DateTime> _statementDays(Account card, int oldCutDay, int? oldPayDay) {
    final Map<String, DateTime?> days = <String, DateTime?>{};
    void consider(String key, DateTime? on) {
      final DateTime? cut = DateTime.tryParse(key);
      if (cut == null) {
        return;
      }
      days.putIfAbsent(key, () => null);
      if (on == null || !dateOnly(on).isAfter(cut)) {
        return;
      }
      final DateTime d = dateOnly(on);
      final DateTime? current = days[key];
      if (current == null || d.isBefore(current)) {
        days[key] = d;
      }
    }

    for (final String key in card.statementMinimums.keys) {
      consider(key, DateTime.tryParse(card.minimumsOn[key] ?? ''));
    }
    for (final String key in card.markedOnly) {
      consider(key, null);
    }
    final DateTime? ref = card.statementCut;
    if (ref != null) {
      consider(dayKey(ref), DateTime.tryParse(card.statementNotedOn ?? ''));
    }
    for (final Tx t in txs) {
      final String? key = t.statementOf;
      if (key != null && _creditAmount(card, t) > 0) {
        consider(key, t.date);
      }
    }
    return <String, DateTime>{for (final MapEntry<String, DateTime?> e in days.entries) e.key: e.value ?? _legacyNotedOn(card, DateTime.parse(e.key), oldCutDay, oldPayDay)};
  }

  /// A qué extracto nuevo pasa cada extracto viejo con datos (`dayKey` →
  /// `dayKey`): todos sus datos juntos, con su día de referencia.
  Map<String, String> _cutMoves(Account card, int oldCutDay, int? oldPayDay, int newCutDay) {
    final Map<String, DateTime> days = _statementDays(card, oldCutDay, oldPayDay);
    return <String, String>{
      for (final MapEntry<String, DateTime> e in days.entries) e.key: dayKey(movedCut(newCutDay, DateTime.parse(e.key), e.value)),
    };
  }

  /// A qué extracto pasaría cada extracto con datos si el día de corte
  /// cambiara a [newCutDay] (`dayKey` → `dayKey`), con todos sus datos juntos.
  Map<String, String> cutMoves(Account card, int newCutDay, {int? oldPayDay}) {
    final int? oldCutDay = card.cutDay;
    if (oldCutDay == null || oldCutDay == newCutDay) {
      return <String, String>{};
    }
    return _cutMoves(card, oldCutDay, oldPayDay ?? card.payDay, newCutDay);
  }

  /// Extracto de referencia de la deuda inicial con otro día de corte (lo que
  /// muestra el editor antes de guardar; ver [moveCardCut]).
  DateTime? movedReference(Account card, int newCutDay) {
    final DateTime? ref = card.statementCut;
    final int? oldCutDay = card.cutDay;
    if (ref == null || oldCutDay == null || oldCutDay == newCutDay) {
      return ref;
    }
    final String? to = _cutMoves(card, oldCutDay, card.payDay, newCutDay)[dayKey(ref)];
    return to == null ? ref : DateTime.parse(to);
  }

  /// Mínimos que, al cambiar el día de corte a [newCutDay], caerían en el
  /// mismo extracto: por cada extracto nuevo, los extractos viejos con
  /// mínimo que caerían en él, del más antiguo al más reciente. Los pagos
  /// (vinculados y hechos fuera de Plata) y las marcas no chocan: quedan
  /// todos en ese extracto.
  Map<DateTime, List<DateTime>> cutMoveConflicts(Account card, int newCutDay, {int? oldPayDay}) {
    final Map<DateTime, List<DateTime>> into = <DateTime, List<DateTime>>{};
    final int? oldCutDay = card.cutDay;
    if (oldCutDay == null || oldCutDay == newCutDay) {
      return into;
    }
    final Map<String, String> moves = _cutMoves(card, oldCutDay, oldPayDay ?? card.payDay, newCutDay);
    for (final String key in card.statementMinimums.keys) {
      final String? to = moves[key];
      if (to != null) {
        (into[DateTime.parse(to)] ??= <DateTime>[]).add(DateTime.parse(key));
      }
    }
    into.removeWhere((DateTime _, List<DateTime> from) => from.length < 2);
    for (final List<DateTime> from in into.values) {
      from.sort();
    }
    return into;
  }

  /// Al cambiar el día de corte de una tarjeta (de [oldCutDay], con el día de
  /// pago [oldPayDay], al que ya tiene), **todos los datos de cada extracto se
  /// mueven juntos** (mínimo, pagos hechos fuera, pagos vinculados, marcas y
  /// referencia de la deuda inicial) al extracto que había cerrado su día de
  /// referencia ([_statementDays], [movedCut]): nunca se separan. Si dos
  /// mínimos caen en el mismo extracto queda el que diga [keep] (extracto
  /// nuevo → extracto viejo elegido) o, si no lo dice, el del más reciente;
  /// los pagos y las marcas de los dos quedan en ese extracto.
  void moveCardCut(Account card, int? oldCutDay, {int? oldPayDay, Map<DateTime, DateTime>? keep}) {
    final int? newDay = card.cutDay;
    if (oldCutDay == null || newDay == null || oldCutDay == newDay) {
      return;
    }
    // Con los datos como estaban (las claves viejas).
    final Map<String, String> moves = _cutMoves(card, oldCutDay, oldPayDay, newDay);
    String to(String key) => moves[key] ?? key;
    final Map<String, List<String>> groups = <String, List<String>>{};
    for (final String key in card.statementMinimums.keys.toList()..sort()) {
      (groups[to(key)] ??= <String>[]).add(key);
    }
    final Map<String, int> minimums = <String, int>{};
    final Map<String, String> minimumsOn = <String, String>{};
    groups.forEach((String target, List<String> from) {
      final DateTime? chosen = keep?[DateTime.parse(target)];
      final String pick = chosen != null && from.contains(dayKey(chosen)) ? dayKey(chosen) : from.last;
      minimums[target] = card.statementMinimums[pick]!;
      final String? on = card.minimumsOn[pick];
      if (on != null) {
        minimumsOn[target] = on;
      }
    });
    final List<String> marks = <String>{for (final String key in card.markedOnly) to(key)}.toList()..sort();
    final DateTime? ref = card.statementCut;
    if (ref != null) {
      card.statementCut = DateTime.parse(to(dayKey(ref)));
    }
    for (final Tx t in txs) {
      if (_creditAmount(card, t) <= 0) {
        continue;
      }
      final String? key = t.statementOf;
      if (key != null) {
        t.statementOf = to(key);
      }
      if (t.apartFrom.isNotEmpty) {
        final List<String> moved = <String>{for (final String k in t.apartFrom) to(k)}.toList()..sort();
        t.apartFrom
          ..clear()
          ..addAll(moved);
      }
    }
    card.statementMinimums
      ..clear()
      ..addAll(minimums);
    card.minimumsOn
      ..clear()
      ..addAll(minimumsOn);
    card.markedOnly
      ..clear()
      ..addAll(marks);
    save();
  }

  /// Si la persona dijo que ya pagó el extracto que cortó en [cut] («Ya lo
  /// pagué»): tiene un pago hecho fuera de Plata o una marca.
  bool isStatementPaid(Account card, DateTime cut) {
    final DateTime c = dateOnly(cut);
    return card.markedOnly.contains(dayKey(c)) || txs.any((Tx t) => t.isOutsidePayment && _linkedCut(card, t) == c);
  }

  /// Marca como pagado el extracto que cortó en [cut] («Ya lo pagué»): crea
  /// un movimiento «Pago hecho fuera de Plata» por [amount] o, si no se da,
  /// por lo que faltaba ([statementMissing], la cifra del aviso), con fecha
  /// [on] (hoy si no se da). Con [payment] falso (o, sin decirlo, cuando
  /// [markKind] no es un pago), o si no faltaba nada, solo marca. Si ya estaba
  /// marcado no cambia nada. Con [paid] falso lo desmarca: borra sus pagos
  /// hechos fuera y la marca. Devuelve si cambió algo.
  bool markStatementPaid(Account card, DateTime cut, {bool paid = true, DateTime? on, int? amount, bool? payment}) {
    final DateTime c = dateOnly(cut);
    final String key = dayKey(c);
    if (!paid) {
      final int before = txs.length;
      txs.removeWhere((Tx t) => t.isOutsidePayment && _linkedCut(card, t) == c);
      final bool removed = card.markedOnly.remove(key);
      // Sin pago de fuera, los abonos provisionales de ese extracto son
      // abonos aparte.
      _releasePending(card, c);
      if (removed || txs.length != before) {
        save();
        return true;
      }
      return false;
    }
    if (isStatementPaid(card, c)) {
      return false;
    }
    final int value = amount ?? statementMissing(card, c, now: on) ?? 0;
    final bool asPayment = payment ?? markKind(card, c) == MarkKind.payment;
    if (value <= 0 || !asPayment) {
      _addMarkOnly(card, c);
    } else {
      // M1: los abonos sin vínculo que ya estaban anotados después del corte
      // contaron en lo que faltaba: no son este pago de fuera.
      for (final Tx t in txs) {
        if (t.statementOf == null && !t.isOutsidePayment && _creditAmount(card, t) > 0 && dateOnly(t.date).isAfter(c) && !t.apartFrom.contains(key)) {
          t.apartFrom.add(key);
        }
      }
      txs.add(_outsideTx(card, c, value, on ?? _today));
      _sortTxs();
    }
    save();
    return true;
  }

  /// Pago mínimo conocido del extracto que cortó en [cut]: el que se anotó
  /// al crear la tarjeta (para su extracto de referencia) o el que se anotó
  /// después para ese extracto. Null si no se conoce.
  int? statementMinimum(Account card, DateTime cut) {
    final String key = dayKey(cut);
    final int? noted = card.statementMinimums[key];
    if (noted != null) {
      return noted;
    }
    final DateTime? ref = card.statementCut;
    if (ref != null && card.statementDueMinor != null && dayKey(CardCycle.current(card, ref).cut) == key) {
      return card.statementDueMinor;
    }
    return null;
  }

  /// Anota (o borra, con null) el pago mínimo que pidió el banco en el
  /// extracto que cortó en [cut].
  void setStatementMinimum(Account card, DateTime cut, int? minor) {
    final String key = dayKey(cut);
    if (minor == null) {
      card.statementMinimums.remove(key);
      card.minimumsOn.remove(key);
    } else {
      card.statementMinimums[key] = minor < 0 ? 0 : minor;
      card.minimumsOn[key] = dayKey(_today);
    }
    // Solo se guardan los últimos: los viejos ya no deciden nada.
    while (card.statementMinimums.length > 24) {
      final List<String> keys = card.statementMinimums.keys.toList()..sort();
      card.statementMinimums.remove(keys.first);
      card.minimumsOn.remove(keys.first);
    }
    save();
  }

  /// Si algún ajuste de saldo cambió la deuda aparte de una tarjeta.
  bool cardHasAdjustments(Account card) => _cardBook(card).adjusted;

  /// Estado de cuenta cuyo pago es el próximo (ver [cardDue]).
  CardStatement nextPayment(Account card, {DateTime? now}) => cardDue(card, now: now).next;

  /// Deuda de antes de Plata que queda hoy en una tarjeta (ver [statement]).
  int legacyDebtMinor(Account card, {DateTime? now}) => statement(card, date: now ?? _clock()).legacyMinor;

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
    final int unit = displayUnit(account(t.accountId)?.currency ?? t.currency);
    int sum = 0;
    for (int k = t.installments - left + 1; k <= t.installments; k++) {
      sum += installmentAmount(t.amountMinor, t.installments, k, unit: unit);
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
    t.loggedOn = _today;
    txs.add(t);
    _sortTxs();
    _insertOutsideCheck(t);
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
  /// El movimiento lleva la fecha y la hora de hoy: es "anotar ahora", aunque
  /// el programado tocara otro día (si tocaba en el futuro, con su fecha no
  /// contaría en el saldo de hoy). Lanza [TxRejected] si no se puede (por
  /// ejemplo, falta la tasa).
  Future<Tx> postScheduled(Scheduled s, {DateTime? date}) async {
    final Tx t = _txFromScheduled(s, date ?? _clock());
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
    if (item.kind != TxKind.transfer) {
      final Scheduled? s = scheduledDuplicateFor(item);
      final String? tx = item.accountId == null ? null : likelyDuplicate(item, item.accountId!)?.id;
      item.duplicateOf = tx ?? (s == null ? null : 'programado:${s.id}');
    }
    inbox.insert(0, item);
    if (inbox.length > 200) {
      inbox.removeRange(200, inbox.length);
    }
    save();
    return item;
  }

  /// Movimiento ya anotado que parece ser el mismo de un aviso: de la misma
  /// cuenta (o de una tarjeta débito suya), del mismo tipo, por el mismo monto
  /// en la moneda de la cuenta y con dos días o menos de diferencia. Pasa con
  /// un programado que se anotó solo o un gasto que se anotó a mano antes de
  /// que llegara el aviso.
  Tx? likelyDuplicate(InboxItem item, String accountId) {
    final Account? a = account(accountId);
    if (a == null) {
      return null;
    }
    final int? amount = convert(item.amountMinor, item.currency, a.currency);
    if (amount == null) {
      return null;
    }
    for (final Tx t in txs) {
      if (t.kind != item.kind || t.isNeutral || t.amountMinor != amount) {
        continue;
      }
      if (effectiveAccountId(t.accountId) != effectiveAccountId(a.id)) {
        continue;
      }
      if (daysBetween(t.date, item.receivedAt).abs() > 2) {
        continue;
      }
      return t;
    }
    return null;
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
    linkNoticeToScheduled(item, t);
    save();
    return t;
  }

  /// Un aviso confirmado que es la ocurrencia de un programado (marcado
  /// `programado:<id>` al llegar, o con la misma cuenta, monto y fecha
  /// cercana): el movimiento queda como de ese programado y el programado
  /// pasa a su siguiente fecha, como si se hubiera anotado él. Así no queda
  /// retenido para siempre y los meses siguientes se anotan solos.
  Scheduled? linkNoticeToScheduled(InboxItem item, Tx t) {
    if (t.kind == TxKind.transfer) {
      return null;
    }
    Scheduled? s;
    final String? mark = item.duplicateOf;
    if (mark != null && mark.startsWith('programado:')) {
      final String id = mark.substring('programado:'.length);
      s = scheduled.where((Scheduled x) => x.id == id).firstOrNull;
    }
    s ??= scheduledDuplicateFor(item);
    if (s == null || !s.enabled || effectiveAccountId(s.accountId) != effectiveAccountId(t.accountId) || s.amountMinor != t.amountMinor || daysBetween(s.nextDate, t.date).abs() > 2) {
      return null;
    }
    t.scheduledId = s.id;
    s.lastPosted = t.date;
    s.nextDate = s.frequency.next(dateOnly(s.nextDate), anchor: s.anchorDate);
    if (s.endDate != null && s.nextDate.isAfter(s.endDate!)) {
      s.enabled = false;
    }
    return s;
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

/// Tarjeta y extracto al que está vinculado un abono.
class _Link {
  const _Link(this.card, this.cut);

  final Account card;
  final DateTime cut;
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
