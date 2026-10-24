/// Modelo de datos de Plata. Todo se guarda como JSON cifrado; los montos
/// son enteros en centavos (`...Minor`).
library;

import 'dart:math';

import 'package:clock/clock.dart';

int _idCounter = 0;
final Random _idRandom = Random();

/// Identificador único: microsegundos reales + contador + azar (dos llamadas
/// en el mismo microsegundo no chocan).
String newId() {
  _idCounter = (_idCounter + 1) % 1679616; // 36^4
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_idCounter.toRadixString(36).padLeft(4, '0')}${_idRandom.nextInt(46656).toRadixString(36)}';
}

String _dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _parseDate(dynamic v, {DateTime? fallback}) {
  if (v is String && v.isNotEmpty) {
    final DateTime? d = DateTime.tryParse(v);
    if (d != null) {
      return d;
    }
  }
  return fallback ?? clock.now();
}

/// Tipos de cuenta. `wallet` es Nequi/Daviplata/etc.; `pocket` es un
/// bolsillo que cuelga de otra cuenta; `debit` es una tarjeta débito
/// vinculada a una cuenta bancaria (comparte su saldo).
enum AccountType { cash, bank, debit, credit, wallet, pocket, savings, loan, investment, other }

class Account {
  Account({
    required this.id,
    required this.name,
    this.type = AccountType.cash,
    this.currency = 'COP',
    this.initialMinor = 0,
    this.color = 0xFF2E7D32,
    this.icon = 'wallet',
    this.archived = false,
    this.includeInTotal = true,
    this.parentId,
    this.linkedAccountId,
    this.creditLimitMinor,
    this.cutDay,
    this.payDay,
    this.bank = '',
    this.last4 = '',
    this.notes = '',
    this.order = 0,
    this.statementDueMinor,
    this.statementCut,
    Map<String, int>? statementMinimums,
    List<String>? paidStatements,
    Map<String, String>? paidOn,
    Map<String, String>? minimumsOn,
    List<OutsidePayment>? outsidePayments,
    List<String>? markedOnly,
    this.statementNotedOn,
  })  : statementMinimums = statementMinimums ?? <String, int>{},
        paidStatements = paidStatements ?? <String>[],
        paidOn = paidOn ?? <String, String>{},
        minimumsOn = minimumsOn ?? <String, String>{},
        outsidePayments = outsidePayments ?? <OutsidePayment>[],
        markedOnly = markedOnly ?? <String>[];

  final String id;
  String name;
  AccountType type;
  String currency;
  int initialMinor;
  int color;
  String icon;
  bool archived;
  bool includeInTotal;

  /// Cuenta madre de un bolsillo.
  String? parentId;

  /// Cuenta cuyo saldo mueve una tarjeta débito.
  String? linkedAccountId;
  int? creditLimitMinor;

  /// Día de corte y día de pago de una tarjeta de crédito (1–31).
  int? cutDay;
  int? payDay;

  /// Banco (clave de reglas de avisos: 'bancolombia', 'nequi', 'daviplata'…).
  String bank;

  /// Últimos dígitos de la tarjeta/cuenta para casar avisos.
  String last4;
  String notes;
  int order;

  /// Tarjeta de crédito: el pago mínimo del último extracto del banco (no el
  /// pago total, que es toda la deuda) cuando se anotó la deuda inicial, y el
  /// corte de ese extracto. Pagarlo deja la tarjeta al día. Es la parte de la deuda inicial que vence en ese pago; el resto
  /// (cuotas viejas, por ejemplo) es deuda de antes de Plata que el banco irá
  /// facturando y que Plata muestra aparte (ver Ledger.statement).
  int? statementDueMinor;
  DateTime? statementCut;

  /// Pagos mínimos que la persona anotó de sus extractos, por fecha de corte
  /// (`dayKey`). Solo contra un mínimo conocido se declara un pago vencido.
  final Map<String, int> statementMinimums;

  /// Día en que se anotó cada mínimo de [statementMinimums] (`dayKey` del
  /// corte → `dayKey` del día). Sirve para llevarlo al extracto correcto si
  /// cambia el día de corte. Los anotados antes de guardarse el día no lo
  /// traen.
  final Map<String, String> minimumsOn;

  /// Día en que se anotó el pago mínimo del último extracto al crear la
  /// tarjeta ([statementDueMinor], [statementCut]); null en los de antes.
  String? statementNotedOn;

  /// Extractos marcados «Ya lo pagué» sin un pago que anotar (`dayKey` del
  /// corte): los de antes de que la tarjeta empezara en Plata (la deuda
  /// inicial ya los refleja), los que ya estaban cubiertos por lo anotado y
  /// los que conservan la marca después de reemplazar su pago de fuera por
  /// uno de verdad. Los pagos hechos fuera de Plata son movimientos
  /// ([Tx.isOutsidePayment]).
  final List<String> markedOnly;

  /// Pagos hechos fuera de Plata de la versión 1.0.0 (ronda 10), guardados
  /// aparte. Al abrir el libro se convierten una sola vez en movimientos y
  /// quedan vacíos.
  final List<OutsidePayment> outsidePayments;

  /// Marcas de las versiones anteriores («Ya lo pagué» sin monto guardado).
  /// Al abrir el libro se convierten una sola vez en movimientos «Pago hecho
  /// fuera de Plata» (o en [markedOnly]) y quedan vacías.
  final List<String> paidStatements;

  /// Día de cada marca de [paidStatements] (versión anterior).
  final Map<String, String> paidOn;

  bool get isCredit => type == AccountType.credit;
  bool get isPocket => type == AccountType.pocket;
  bool get isDebit => type == AccountType.debit;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'type': type.name,
        'currency': currency,
        'initialMinor': initialMinor,
        'color': color,
        'icon': icon,
        'archived': archived,
        'includeInTotal': includeInTotal,
        'parentId': parentId,
        'linkedAccountId': linkedAccountId,
        'creditLimitMinor': creditLimitMinor,
        'cutDay': cutDay,
        'payDay': payDay,
        'bank': bank,
        'last4': last4,
        'notes': notes,
        'order': order,
        'statementDueMinor': statementDueMinor,
        'statementCut': statementCut?.toIso8601String(),
        'statementMinimums': statementMinimums,
        'paidStatements': paidStatements,
        'paidOn': paidOn,
        'minimumsOn': minimumsOn,
        'statementNotedOn': statementNotedOn,
        'outsidePayments': outsidePayments.map((OutsidePayment p) => p.toJson()).toList(),
        'markedOnly': markedOnly,
      };

  static Account fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String? ?? newId(),
        name: j['name'] as String? ?? '',
        type: AccountType.values.firstWhere((AccountType t) => t.name == j['type'], orElse: () => AccountType.cash),
        currency: j['currency'] as String? ?? 'COP',
        initialMinor: (j['initialMinor'] as num?)?.toInt() ?? 0,
        color: (j['color'] as num?)?.toInt() ?? 0xFF2E7D32,
        icon: j['icon'] as String? ?? 'wallet',
        archived: j['archived'] as bool? ?? false,
        includeInTotal: j['includeInTotal'] as bool? ?? true,
        parentId: j['parentId'] as String?,
        linkedAccountId: j['linkedAccountId'] as String?,
        creditLimitMinor: (j['creditLimitMinor'] as num?)?.toInt(),
        cutDay: (j['cutDay'] as num?)?.toInt(),
        payDay: (j['payDay'] as num?)?.toInt(),
        bank: j['bank'] as String? ?? '',
        last4: j['last4'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        order: (j['order'] as num?)?.toInt() ?? 0,
        statementDueMinor: (j['statementDueMinor'] as num?)?.toInt(),
        statementCut: j['statementCut'] == null ? null : DateTime.tryParse(j['statementCut'].toString()),
        statementMinimums: <String, int>{
          for (final MapEntry<String, dynamic> e in ((j['statementMinimums'] as Map<String, dynamic>?) ?? <String, dynamic>{}).entries)
            if (e.value is num) e.key: (e.value as num).toInt(),
        },
        paidStatements: <String>[for (final dynamic x in (j['paidStatements'] as List<dynamic>?) ?? <dynamic>[]) x.toString()],
        paidOn: <String, String>{
          for (final MapEntry<String, dynamic> e in ((j['paidOn'] as Map<String, dynamic>?) ?? <String, dynamic>{}).entries)
            if (e.value is String) e.key: e.value as String,
        },
        minimumsOn: <String, String>{
          for (final MapEntry<String, dynamic> e in ((j['minimumsOn'] as Map<String, dynamic>?) ?? <String, dynamic>{}).entries)
            if (e.value is String) e.key: e.value as String,
        },
        statementNotedOn: j['statementNotedOn'] as String?,
        markedOnly: <String>[for (final dynamic x in (j['markedOnly'] as List<dynamic>?) ?? <dynamic>[]) x.toString()],
        outsidePayments: <OutsidePayment>[
          for (final dynamic x in (j['outsidePayments'] as List<dynamic>?) ?? <dynamic>[])
            if (x is Map<String, dynamic>) OutsidePayment.fromJson(x),
        ],
      );
}

/// Pago de una tarjeta hecho fuera de Plata («Ya lo pagué»).
class OutsidePayment {
  OutsidePayment({required this.statement, required this.amountMinor, required this.on});

  /// Corte del extracto que pagó (`dayKey`).
  String statement;

  /// Lo que faltaba del mínimo cuando se marcó (o lo que la persona escribió
  /// después). No se recalcula.
  int amountMinor;

  /// Día en que se marcó (`dayKey`).
  String on;

  Map<String, dynamic> toJson() => <String, dynamic>{'statement': statement, 'amountMinor': amountMinor, 'on': on};

  static OutsidePayment fromJson(Map<String, dynamic> j) => OutsidePayment(statement: j['statement'] as String? ?? '', amountMinor: (j['amountMinor'] as num?)?.toInt() ?? 0, on: j['on'] as String? ?? '');
}

enum CategoryKind { expense, income }

class Category {
  Category({required this.id, required this.name, this.kind = CategoryKind.expense, this.icon = 'label', this.color = 0xFF607D8B, this.parentId, this.archived = false, this.order = 0});

  final String id;
  String name;
  CategoryKind kind;
  String icon;
  int color;
  String? parentId;
  bool archived;
  int order;

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'name': name, 'kind': kind.name, 'icon': icon, 'color': color, 'parentId': parentId, 'archived': archived, 'order': order};

  static Category fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] as String? ?? newId(),
        name: j['name'] as String? ?? '',
        kind: j['kind'] == 'income' ? CategoryKind.income : CategoryKind.expense,
        icon: j['icon'] as String? ?? 'label',
        color: (j['color'] as num?)?.toInt() ?? 0xFF607D8B,
        parentId: j['parentId'] as String?,
        archived: j['archived'] as bool? ?? false,
        order: (j['order'] as num?)?.toInt() ?? 0,
      );
}

enum TxKind { expense, income, transfer }

/// Parte de una transacción dividida entre categorías.
class TxSplit {
  const TxSplit({required this.categoryId, required this.amountMinor, this.note = ''});

  final String categoryId;
  final int amountMinor;
  final String note;

  Map<String, dynamic> toJson() => <String, dynamic>{'categoryId': categoryId, 'amountMinor': amountMinor, 'note': note};

  static TxSplit fromJson(Map<String, dynamic> j) => TxSplit(categoryId: j['categoryId'] as String? ?? '', amountMinor: (j['amountMinor'] as num?)?.toInt() ?? 0, note: j['note'] as String? ?? '');
}

class Tx {
  Tx({
    required this.id,
    required this.kind,
    required this.amountMinor,
    required this.accountId,
    required this.date,
    this.currency = 'COP',
    this.toAccountId,
    this.toAmountMinor,
    this.toAmountAuto = false,
    this.categoryId,
    this.description = '',
    this.payee = '',
    this.notes = '',
    List<String>? tags,
    List<TxSplit>? splits,
    List<String>? attachments,
    this.checkNumber = '',
    this.installments = 1,
    this.scheduledId,
    this.reconciled = false,
    this.source = 'manual',
    this.rateToBase,
    this.statementOf,
    this.apartFrom,
    DateTime? createdAt,
  })  : tags = tags ?? <String>[],
        splits = splits ?? <TxSplit>[],
        attachments = attachments ?? <String>[],
        createdAt = createdAt ?? clock.now();

  final String id;
  TxKind kind;

  /// Monto en centavos de la moneda de la cuenta de origen (siempre positivo).
  int amountMinor;
  String currency;
  String accountId;

  /// Destino de una transferencia.
  String? toAccountId;

  /// Monto recibido cuando la transferencia cambia de moneda.
  int? toAmountMinor;

  /// Verdadero si [toAmountMinor] lo calculó la app con las tasas guardadas
  /// (falso si lo escribió el usuario).
  bool toAmountAuto;
  String? categoryId;
  DateTime date;
  String description;
  String payee;
  String notes;
  final List<String> tags;
  final List<TxSplit> splits;

  /// Rutas relativas de fotos de recibos.
  final List<String> attachments;
  String checkNumber;

  /// Compra de tarjeta de crédito diferida a cuotas (1 = pago único).
  int installments;
  String? scheduledId;
  bool reconciled;

  /// manual | notice | scheduled | import | template | adjustment
  String source;

  /// Tasa a la moneda base en el momento del registro (1 unidad = rate base).
  double? rateToBase;

  /// Pago de tarjeta registrado desde la fila de un extracto («Registrar el
  /// pago de este extracto»): la fecha del corte de ese extracto
  /// (`aaaa-mm-dd`). Cuenta para ese extracto sea cual sea su fecha y
  /// reemplaza el pago que Plata daba por hecho al marcarlo «Ya lo pagué».
  /// Null en los demás movimientos (y en las copias anteriores).
  String? statementOf;

  /// Abono sin vínculo que la persona dijo que **no** es el pago del extracto
  /// marcado «Ya lo pagué» que cortó ese día (`dayKey`): ya no se pregunta.
  String? apartFrom;
  final DateTime createdAt;

  bool get isSplit => splits.isNotEmpty;

  /// Ajuste de saldo: corrige el saldo de una cuenta, pero no es gasto ni
  /// ingreso en informes ni presupuestos.
  bool get isAdjustment => source == 'adjustment';

  /// Pago de una tarjeta hecho fuera de Plata («Ya lo pagué»): un abono a la
  /// tarjeta que no sale de ninguna cuenta de Plata, vinculado a su extracto.
  bool get isOutsidePayment => source == 'outside';

  /// No es gasto ni ingreso en informes ni presupuestos: los ajustes de saldo
  /// y los pagos hechos fuera de Plata.
  bool get isNeutral => isAdjustment || isOutsidePayment;

  /// Monto con signo desde el punto de vista de la cuenta de origen.
  int get signedMinor => kind == TxKind.income ? amountMinor : -amountMinor;

  String get dayKey => _dateKey(date);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind.name,
        'amountMinor': amountMinor,
        'currency': currency,
        'accountId': accountId,
        'toAccountId': toAccountId,
        'toAmountMinor': toAmountMinor,
        'toAmountAuto': toAmountAuto,
        'categoryId': categoryId,
        'date': date.toIso8601String(),
        'description': description,
        'payee': payee,
        'notes': notes,
        'tags': tags,
        'splits': splits.map((TxSplit s) => s.toJson()).toList(),
        'attachments': attachments,
        'checkNumber': checkNumber,
        'installments': installments,
        'scheduledId': scheduledId,
        'reconciled': reconciled,
        'source': source,
        'rateToBase': rateToBase,
        if (statementOf != null) 'statementOf': statementOf,
        if (apartFrom != null) 'apartFrom': apartFrom,
        'createdAt': createdAt.toIso8601String(),
      };

  static Tx fromJson(Map<String, dynamic> j) => Tx(
        id: j['id'] as String? ?? newId(),
        kind: TxKind.values.firstWhere((TxKind k) => k.name == j['kind'], orElse: () => TxKind.expense),
        amountMinor: (j['amountMinor'] as num?)?.toInt() ?? 0,
        currency: j['currency'] as String? ?? 'COP',
        accountId: j['accountId'] as String? ?? '',
        toAccountId: j['toAccountId'] as String?,
        toAmountMinor: (j['toAmountMinor'] as num?)?.toInt(),
        toAmountAuto: j['toAmountAuto'] as bool? ?? false,
        categoryId: j['categoryId'] as String?,
        date: _parseDate(j['date']),
        description: j['description'] as String? ?? '',
        payee: j['payee'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        tags: ((j['tags'] as List<dynamic>?) ?? <dynamic>[]).map((dynamic e) => e.toString()).toList(),
        splits: ((j['splits'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>().map(TxSplit.fromJson).toList(),
        attachments: ((j['attachments'] as List<dynamic>?) ?? <dynamic>[]).map((dynamic e) => e.toString()).toList(),
        checkNumber: j['checkNumber'] as String? ?? '',
        installments: (j['installments'] as num?)?.toInt() ?? 1,
        scheduledId: j['scheduledId'] as String?,
        reconciled: j['reconciled'] as bool? ?? false,
        source: j['source'] as String? ?? 'manual',
        rateToBase: (j['rateToBase'] as num?)?.toDouble(),
        statementOf: j['statementOf'] as String?,
        apartFrom: j['apartFrom'] as String?,
        createdAt: _parseDate(j['createdAt']),
      );

  Tx copy({String? id, DateTime? date}) => Tx.fromJson(toJson()..['id'] = id ?? this.id..['date'] = (date ?? this.date).toIso8601String()..['createdAt'] = clock.now().toIso8601String());
}

/// Frecuencia de un movimiento programado.
enum FrequencyUnit { day, week, month, year, quincena }

class Frequency {
  const Frequency({this.unit = FrequencyUnit.month, this.every = 1});

  final FrequencyUnit unit;
  final int every;

  Map<String, dynamic> toJson() => <String, dynamic>{'unit': unit.name, 'every': every};

  static Frequency fromJson(Map<String, dynamic>? j) => j == null
      ? const Frequency()
      : Frequency(unit: FrequencyUnit.values.firstWhere((FrequencyUnit u) => u.name == j['unit'], orElse: () => FrequencyUnit.month), every: ((j['every'] as num?)?.toInt() ?? 1).clamp(1, 365));

  /// Siguiente fecha después de [from], manteniendo el día de [anchor] cuando
  /// se puede (meses cortos se recortan). La quincena cae el 15 y el último día.
  DateTime next(DateTime from, {DateTime? anchor}) {
    final DateTime a = anchor ?? from;
    switch (unit) {
      case FrequencyUnit.day:
        return DateTime(from.year, from.month, from.day + every);
      case FrequencyUnit.week:
        return DateTime(from.year, from.month, from.day + 7 * every);
      case FrequencyUnit.month:
        return _addMonths(from, every, a.day);
      case FrequencyUnit.year:
        return _clampDay(from.year + every, from.month, a.day);
      case FrequencyUnit.quincena:
        if (from.day < 15) {
          return DateTime(from.year, from.month, 15);
        }
        final int last = DateTime(from.year, from.month + 1, 0).day;
        if (from.day < last) {
          return DateTime(from.year, from.month, last);
        }
        return DateTime(from.year, from.month + 1, 15);
    }
  }

  static DateTime _addMonths(DateTime from, int months, int day) {
    int y = from.year;
    int m = from.month + months;
    while (m > 12) {
      m -= 12;
      y += 1;
    }
    return _clampDay(y, m, day);
  }

  static DateTime _clampDay(int y, int m, int day) {
    final int last = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, day > last ? last : day);
  }
}

class Scheduled {
  Scheduled({
    required this.id,
    required this.name,
    required this.kind,
    required this.amountMinor,
    required this.accountId,
    required this.nextDate,
    this.toAccountId,
    this.toAmountMinor,
    this.categoryId,
    this.description = '',
    this.payee = '',
    List<String>? tags,
    this.frequency = const Frequency(),
    DateTime? anchorDate,
    this.endDate,
    this.autoPost = true,
    this.remindDaysBefore = 1,
    this.enabled = true,
    this.lastPosted,
  })  : tags = tags ?? <String>[],
        anchorDate = anchorDate ?? nextDate;

  final String id;
  String name;
  TxKind kind;
  int amountMinor;
  String accountId;
  String? toAccountId;

  /// Monto fijo que llega a la cuenta de destino si cambia de moneda; vacío =
  /// se calcula con la tasa del día en que se anota.
  int? toAmountMinor;
  String? categoryId;
  String description;
  String payee;
  final List<String> tags;
  Frequency frequency;

  /// Fecha de referencia para el día del mes.
  DateTime anchorDate;
  DateTime nextDate;
  DateTime? endDate;

  /// Verdadero: se anota solo al vencer; falso: solo recuerda.
  bool autoPost;
  int remindDaysBefore;
  bool enabled;
  DateTime? lastPosted;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'kind': kind.name,
        'amountMinor': amountMinor,
        'accountId': accountId,
        'toAccountId': toAccountId,
        'toAmountMinor': toAmountMinor,
        'categoryId': categoryId,
        'description': description,
        'payee': payee,
        'tags': tags,
        'frequency': frequency.toJson(),
        'anchorDate': anchorDate.toIso8601String(),
        'nextDate': nextDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'autoPost': autoPost,
        'remindDaysBefore': remindDaysBefore,
        'enabled': enabled,
        'lastPosted': lastPosted?.toIso8601String(),
      };

  static Scheduled fromJson(Map<String, dynamic> j) => Scheduled(
        id: j['id'] as String? ?? newId(),
        name: j['name'] as String? ?? '',
        kind: TxKind.values.firstWhere((TxKind k) => k.name == j['kind'], orElse: () => TxKind.expense),
        amountMinor: (j['amountMinor'] as num?)?.toInt() ?? 0,
        accountId: j['accountId'] as String? ?? '',
        toAccountId: j['toAccountId'] as String?,
        toAmountMinor: (j['toAmountMinor'] as num?)?.toInt(),
        categoryId: j['categoryId'] as String?,
        description: j['description'] as String? ?? '',
        payee: j['payee'] as String? ?? '',
        tags: ((j['tags'] as List<dynamic>?) ?? <dynamic>[]).map((dynamic e) => e.toString()).toList(),
        frequency: Frequency.fromJson(j['frequency'] as Map<String, dynamic>?),
        anchorDate: _parseDate(j['anchorDate'], fallback: _parseDate(j['nextDate'])),
        nextDate: _parseDate(j['nextDate']),
        endDate: j['endDate'] == null ? null : _parseDate(j['endDate']),
        autoPost: j['autoPost'] as bool? ?? true,
        remindDaysBefore: (j['remindDaysBefore'] as num?)?.toInt() ?? 1,
        enabled: j['enabled'] as bool? ?? true,
        lastPosted: j['lastPosted'] == null ? null : _parseDate(j['lastPosted']),
      );
}

enum BudgetPeriod { week, quincena, month, year, custom }

class Budget {
  Budget({
    required this.id,
    required this.name,
    required this.amountMinor,
    List<String>? categoryIds,
    this.accountId,
    this.period = BudgetPeriod.month,
    this.customDays = 30,
    DateTime? startDate,
    this.rollover = false,
    this.notes = '',
    List<BudgetAmountChange>? amountHistory,
  })  : categoryIds = categoryIds ?? <String>[],
        amountHistory = amountHistory ?? <BudgetAmountChange>[],
        startDate = startDate ?? DateTime(clock.now().year, clock.now().month);

  final String id;
  String name;

  /// Tope vigente (el del periodo en curso y los que vienen).
  int amountMinor;

  /// Topes anteriores: cada cambio guarda el tope viejo y desde qué periodo
  /// dejó de valer. El arrastre de periodos pasados usa el tope de cada uno,
  /// así que subir el tope hoy no suma de golpe lo de los meses anteriores.
  final List<BudgetAmountChange> amountHistory;

  /// Tope del periodo que empieza en [periodStart].
  int amountFor(DateTime periodStart) {
    for (final BudgetAmountChange c in amountHistory) {
      if (periodStart.isBefore(c.until)) {
        return c.amountMinor;
      }
    }
    return amountMinor;
  }

  /// Cambia el tope desde el periodo que empieza en [from]; los periodos
  /// anteriores conservan el que tenían.
  void changeAmount(int newAmountMinor, {required DateTime from}) {
    if (newAmountMinor == amountMinor) {
      return;
    }
    // Dos cambios en el mismo periodo: vale el último, y los periodos
    // anteriores siguen con el tope que tenían antes del primero.
    if (!amountHistory.any((BudgetAmountChange c) => c.until == from)) {
      amountHistory.add(BudgetAmountChange(until: from, amountMinor: amountMinor));
      amountHistory.sort((BudgetAmountChange a, BudgetAmountChange b) => a.until.compareTo(b.until));
    }
    amountMinor = newAmountMinor;
  }

  /// Vacío = todos los gastos.
  final List<String> categoryIds;

  /// Presupuesto por tarjeta o cuenta (solo sus movimientos).
  String? accountId;
  BudgetPeriod period;
  int customDays;
  DateTime startDate;
  bool rollover;
  String notes;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'amountMinor': amountMinor,
        'categoryIds': categoryIds,
        'accountId': accountId,
        'period': period.name,
        'customDays': customDays,
        'startDate': startDate.toIso8601String(),
        'rollover': rollover,
        'notes': notes,
        'amountHistory': amountHistory.map((BudgetAmountChange c) => c.toJson()).toList(),
      };

  static Budget fromJson(Map<String, dynamic> j) => Budget(
        id: j['id'] as String? ?? newId(),
        name: j['name'] as String? ?? '',
        amountMinor: (j['amountMinor'] as num?)?.toInt() ?? 0,
        categoryIds: ((j['categoryIds'] as List<dynamic>?) ?? <dynamic>[]).map((dynamic e) => e.toString()).toList(),
        accountId: j['accountId'] as String?,
        period: BudgetPeriod.values.firstWhere((BudgetPeriod p) => p.name == j['period'], orElse: () => BudgetPeriod.month),
        customDays: (j['customDays'] as num?)?.toInt() ?? 30,
        startDate: _parseDate(j['startDate']),
        rollover: j['rollover'] as bool? ?? false,
        notes: j['notes'] as String? ?? '',
        amountHistory: ((j['amountHistory'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>().map(BudgetAmountChange.fromJson).toList()..sort((BudgetAmountChange a, BudgetAmountChange b) => a.until.compareTo(b.until)),
      );
}

/// Un tope anterior de un presupuesto: valió en los periodos que empiezan
/// antes de [until].
class BudgetAmountChange {
  const BudgetAmountChange({required this.until, required this.amountMinor});

  final DateTime until;
  final int amountMinor;

  Map<String, dynamic> toJson() => <String, dynamic>{'until': until.toIso8601String(), 'amountMinor': amountMinor};

  static BudgetAmountChange fromJson(Map<String, dynamic> j) => BudgetAmountChange(until: _parseDate(j['until']), amountMinor: (j['amountMinor'] as num?)?.toInt() ?? 0);
}

/// Plantilla / favorito: un movimiento frecuente que se anota con un toque.
class TxTemplate {
  TxTemplate({
    required this.id,
    required this.name,
    this.kind = TxKind.expense,
    this.amountMinor,
    this.accountId,
    this.toAccountId,
    this.toAmountMinor,
    this.categoryId,
    this.description = '',
    this.payee = '',
    List<String>? tags,
    this.icon = 'star',
    this.color = 0xFFFB8C00,
    this.uses = 0,
  }) : tags = tags ?? <String>[];

  final String id;
  String name;
  TxKind kind;
  int? amountMinor;
  String? accountId;
  String? toAccountId;

  /// Monto fijo recibido en una transferencia entre monedas; vacío = con la
  /// tasa del día.
  int? toAmountMinor;
  String? categoryId;
  String description;
  String payee;
  final List<String> tags;
  String icon;
  int color;
  int uses;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'kind': kind.name,
        'amountMinor': amountMinor,
        'accountId': accountId,
        'toAccountId': toAccountId,
        'toAmountMinor': toAmountMinor,
        'categoryId': categoryId,
        'description': description,
        'payee': payee,
        'tags': tags,
        'icon': icon,
        'color': color,
        'uses': uses,
      };

  static TxTemplate fromJson(Map<String, dynamic> j) => TxTemplate(
        id: j['id'] as String? ?? newId(),
        name: j['name'] as String? ?? '',
        kind: TxKind.values.firstWhere((TxKind k) => k.name == j['kind'], orElse: () => TxKind.expense),
        amountMinor: (j['amountMinor'] as num?)?.toInt(),
        accountId: j['accountId'] as String?,
        toAccountId: j['toAccountId'] as String?,
        toAmountMinor: (j['toAmountMinor'] as num?)?.toInt(),
        categoryId: j['categoryId'] as String?,
        description: j['description'] as String? ?? '',
        payee: j['payee'] as String? ?? '',
        tags: ((j['tags'] as List<dynamic>?) ?? <dynamic>[]).map((dynamic e) => e.toString()).toList(),
        icon: j['icon'] as String? ?? 'star',
        color: (j['color'] as num?)?.toInt() ?? 0xFFFB8C00,
        uses: (j['uses'] as num?)?.toInt() ?? 0,
      );
}

/// Qué clase de movimiento describe un aviso bancario.
class NoticeFlow {
  NoticeFlow._();

  /// Compra, pago a un tercero, consignación recibida…: gasto o ingreso.
  static const String normal = '';

  /// Pago de una tarjeta de crédito (transferencia hacia la tarjeta).
  static const String cardPayment = 'card_payment';

  /// Plata que sale hacia otra cuenta propia o un bolsillo.
  static const String transferOut = 'transfer_out';

  /// Plata que llega desde otra cuenta propia o un bolsillo.
  static const String transferIn = 'transfer_in';

  /// Retiro de efectivo (transferencia hacia la cuenta de efectivo).
  static const String withdrawal = 'withdrawal';

  /// Reverso o devolución de una compra: un ingreso que siempre se revisa
  /// (nunca se anota solo), porque la compra pudo no haberse anotado.
  static const String refund = 'refund';
}

/// Aviso bancario leído (Android) pendiente de confirmar.
class InboxItem {
  InboxItem({
    required this.id,
    required this.bank,
    required this.kind,
    required this.amountMinor,
    required this.receivedAt,
    this.currency = 'COP',
    this.merchant = '',
    this.last4 = '',
    this.toLast4 = '',
    this.flow = NoticeFlow.normal,
    this.rawTitle = '',
    this.rawText = '',
    this.accountId,
    this.status = 'pending',
    this.duplicateOf,
  });

  final String id;
  final String bank;

  /// Gasto, ingreso o transferencia (pagos de tarjeta, retiros y movimientos
  /// entre cuentas propias, que no son gasto ni ingreso).
  final TxKind kind;
  final int amountMinor;
  final String currency;
  final String merchant;

  /// Últimos dígitos de la cuenta o tarjeta del aviso (la de origen en una
  /// transferencia).
  final String last4;

  /// Últimos dígitos del destino de una transferencia (la tarjeta que se paga).
  final String toLast4;

  /// Ver [NoticeFlow].
  final String flow;
  final DateTime receivedAt;
  final String rawTitle;
  final String rawText;
  String? accountId;

  /// pending | accepted | dismissed
  String status;

  /// Movimiento ya anotado que parece ser el mismo (misma cuenta y monto,
  /// fechas cercanas), o `programado:<id>` si es la próxima ocurrencia de un
  /// programado: el aviso queda para revisar en lugar de anotarse solo.
  String? duplicateOf;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'bank': bank,
        'kind': kind.name,
        'amountMinor': amountMinor,
        'currency': currency,
        'merchant': merchant,
        'last4': last4,
        'toLast4': toLast4,
        'flow': flow,
        'receivedAt': receivedAt.toIso8601String(),
        'rawTitle': rawTitle,
        'rawText': rawText,
        'accountId': accountId,
        'status': status,
        'duplicateOf': duplicateOf,
      };

  static InboxItem fromJson(Map<String, dynamic> j) => InboxItem(
        id: j['id'] as String? ?? newId(),
        bank: j['bank'] as String? ?? '',
        kind: TxKind.values.firstWhere((TxKind k) => k.name == j['kind'], orElse: () => TxKind.expense),
        amountMinor: (j['amountMinor'] as num?)?.toInt() ?? 0,
        currency: j['currency'] as String? ?? 'COP',
        merchant: j['merchant'] as String? ?? '',
        last4: j['last4'] as String? ?? '',
        toLast4: j['toLast4'] as String? ?? '',
        flow: j['flow'] as String? ?? NoticeFlow.normal,
        receivedAt: _parseDate(j['receivedAt']),
        rawTitle: j['rawTitle'] as String? ?? '',
        rawText: j['rawText'] as String? ?? '',
        accountId: j['accountId'] as String?,
        status: j['status'] as String? ?? 'pending',
        duplicateOf: j['duplicateOf'] as String?,
      );
}

/// Fuentes de las tasas automáticas (ver [RateTable.origins]).
class RateOrigin {
  RateOrigin._();

  /// Tasa Representativa del Mercado (datos.gov.co).
  static const String trm = 'trm';

  /// Banco Central Europeo, a través de Frankfurter.
  static const String ecb = 'ecb';

  /// ExchangeRate-API (open.er-api.com).
  static const String erApi = 'erapi';
}

/// Tasas: 1 unidad de la moneda = [rate] unidades de la moneda base.
class RateTable {
  RateTable({Map<String, double>? rates, this.updatedAt, this.source = '', Map<String, double>? manual, Map<String, String>? origins})
      : rates = rates ?? <String, double>{},
        manual = manual ?? <String, double>{},
        origins = origins ?? <String, String>{};

  final Map<String, double> rates;
  final Map<String, double> manual;

  /// De dónde salió cada tasa automática ([RateOrigin]).
  final Map<String, String> origins;
  DateTime? updatedAt;
  String source;

  double? rateFor(String currency, String base) {
    if (currency == base) {
      return 1;
    }
    return manual[currency] ?? rates[currency];
  }

  Map<String, dynamic> toJson() => <String, dynamic>{'rates': rates, 'manual': manual, 'origins': origins, 'updatedAt': updatedAt?.toIso8601String(), 'source': source};

  static RateTable fromJson(Map<String, dynamic>? j) => j == null
      ? RateTable()
      : RateTable(
          rates: ((j['rates'] as Map<String, dynamic>?) ?? <String, dynamic>{}).map((String k, dynamic v) => MapEntry<String, double>(k, (v as num).toDouble())),
          manual: ((j['manual'] as Map<String, dynamic>?) ?? <String, dynamic>{}).map((String k, dynamic v) => MapEntry<String, double>(k, (v as num).toDouble())),
          origins: ((j['origins'] as Map<String, dynamic>?) ?? <String, dynamic>{}).map((String k, dynamic v) => MapEntry<String, String>(k, v as String)),
          updatedAt: j['updatedAt'] == null ? null : _parseDate(j['updatedAt']),
          source: j['source'] as String? ?? '',
        );
}

/// Formato de fecha sencillo (dd, MM, yyyy, HH, mm, EEE, MMM).
String formatDate(DateTime d, String pattern, {bool spanish = true}) {
  const List<String> diasEs = <String>['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  const List<String> diasEn = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const List<String> mesesEs = <String>['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  const List<String> mesesEn = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String two(int v) => v.toString().padLeft(2, '0');
  return pattern
      .replaceAll('yyyy', d.year.toString())
      .replaceAll('MMM', (spanish ? mesesEs : mesesEn)[d.month - 1])
      .replaceAll('MM', two(d.month))
      .replaceAll('dd', two(d.day))
      .replaceAll('HH', two(d.hour))
      .replaceAll('mm', two(d.minute))
      .replaceAll('EEE', (spanish ? diasEs : diasEn)[d.weekday - 1]);
}

/// Nombre largo del mes ("octubre de 2026").
String monthName(DateTime d, {bool spanish = true}) {
  const List<String> es = <String>['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
  const List<String> en = <String>['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return spanish ? '${es[d.month - 1]} de ${d.year}' : '${en[d.month - 1]} ${d.year}';
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Suma días de calendario (no horas): con horario de verano un día puede
/// durar 23 o 25 horas, y `Duration(days: 1)` correría la medianoche.
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days, d.hour, d.minute, d.second, d.millisecond, d.microsecond);

/// Días de calendario entre dos fechas (negativo si [to] es anterior).
int daysBetween(DateTime from, DateTime to) => DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

String dayKey(DateTime d) => _dateKey(d);
