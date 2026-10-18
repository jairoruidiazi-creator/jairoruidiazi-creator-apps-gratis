import '../model/models.dart';
import '../model/money.dart';

/// Movimiento deducido de un aviso bancario.
class BankSuggestion {
  const BankSuggestion({required this.bank, required this.kind, required this.amountMinor, this.currency = 'COP', this.merchant = '', this.last4 = '', this.toLast4 = '', this.flow = NoticeFlow.normal});

  final String bank;

  /// Gasto, ingreso o transferencia (pago de tarjeta, retiro o movimiento entre
  /// cuentas propias: no son gasto ni ingreso).
  final TxKind kind;
  final int amountMinor;
  final String currency;
  final String merchant;

  /// Últimos dígitos de la cuenta o tarjeta de origen.
  final String last4;

  /// Últimos dígitos del destino (la tarjeta que se paga).
  final String toLast4;

  /// Ver [NoticeFlow].
  final String flow;
}

/// Reglas para leer los avisos de los bancos colombianos (notificaciones de
/// sus apps en Android). Son solo texto: no se usan SMS ni claves.
class BankRules {
  BankRules._();

  /// Fecha en que se revisó [packages] en Google Play.
  static const String packagesCheckedOn = '2026-10-18';

  /// Paquete de Android → banco. Cada paquete se comprobó en su ficha de
  /// Google Play el [packagesCheckedOn] (ver docs/DECISIONES.md). La misma
  /// lista vive en native/android/BankNoticeListener.kt, el servicio que lee
  /// las notificaciones; test/notices_test.dart verifica que coincidan.
  static const Map<String, String> packages = <String, String>{
    'co.com.bancolombia.personas.superapp': 'bancolombia',
    'com.nequi.MobileApp': 'nequi',
    'com.davivienda.daviplataapp': 'daviplata',
    'com.davivienda.daviviendaapp': 'davivienda',
    'co.com.bbva.mb': 'bbva',
    'com.bancodebogota.bancamovil': 'bogota',
    'com.grupoavaloc1.bancamovil': 'occidente',
    'eu.netinfo.colpatria.system': 'davibank',
    'co.com.lulobank.production': 'lulo',
    'com.nu.production': 'nu',
    'com.movilred.subscriber': 'movii',
  };

  static const Map<String, String> bankNames = <String, String>{
    'bancolombia': 'Bancolombia',
    'nequi': 'Nequi',
    'daviplata': 'Daviplata',
    'davivienda': 'Davivienda',
    'bbva': 'BBVA',
    'bogota': 'Banco de Bogotá',
    'occidente': 'Banco de Occidente',
    'davibank': 'DAVIbank (antes Scotiabank Colpatria)',
    'lulo': 'Lulo Bank',
    'nu': 'Nu',
    'movii': 'MOVii',
  };

  /// Otros nombres con que alguien pudo escribir el banco de una cuenta.
  static const Map<String, String> _aliases = <String, String>{
    'mi bancolombia': 'bancolombia',
    'banco de bogota': 'bogota',
    'bogota': 'bogota',
    'banco de occidente': 'occidente',
    'occidente': 'occidente',
    'davibank': 'davibank',
    'scotiabank colpatria': 'davibank',
    'scotiabank': 'davibank',
    'colpatria': 'davibank',
    'lulo': 'lulo',
    'lulo bank': 'lulo',
    'nubank': 'nu',
    'nu colombia': 'nu',
    'bbva colombia': 'bbva',
  };

  /// Nombre para mostrar de un banco a partir de su clave interna.
  static String displayName(String key, {bool spanish = true}) {
    final String name = bankNames[key] ?? key;
    return spanish ? name : name.replaceFirst('(antes ', '(formerly ');
  }

  /// Los bancos cuyos avisos se leen, en una frase ("A, B y C"). La guía, la
  /// pantalla de avisos y el selector de banco salen de [bankNames], así que
  /// no pueden prometer un banco que la app no lee.
  static String namesList({required bool spanish}) {
    final List<String> names = bankNames.keys.map((String k) => displayName(k, spanish: spanish)).toList();
    final String last = names.removeLast();
    return '${names.join(', ')} ${spanish ? 'y' : 'and'} $last';
  }

  /// Clave interna del banco de una cuenta, aunque se haya guardado con su
  /// nombre ("Bancolombia", "Banco de Bogotá"). Vacío si no es un banco de la
  /// lista.
  static String keyFor(String value) {
    final String v = _plain(value);
    if (v.isEmpty) {
      return '';
    }
    if (bankNames.containsKey(v)) {
      return v;
    }
    for (final MapEntry<String, String> e in bankNames.entries) {
      if (_plain(e.value) == v) {
        return e.key;
      }
    }
    return _aliases[v] ?? '';
  }

  static String _plain(String s) => s.trim().toLowerCase().replaceAll('á', 'a').replaceAll('é', 'e').replaceAll('í', 'i').replaceAll('ó', 'o').replaceAll('ú', 'u').replaceAll(RegExp(r'\s+'), ' ');

  static bool isBankPackage(String? packageName) => packageName != null && packages.containsKey(packageName);

  /// Banco a partir del paquete. Si el paquete no es de la lista, no es un
  /// aviso bancario. Sin paquete (pruebas o texto pegado) se busca el nombre
  /// del banco como palabra completa.
  static String? detectBank({String? packageName, String title = '', String text = ''}) {
    if (packageName != null) {
      return packages[packageName];
    }
    final String all = _plain('$title $text');
    for (final MapEntry<String, String> e in bankNames.entries) {
      final String name = _plain(e.value.split(' (').first);
      if (RegExp('(^|[^a-z0-9])${RegExp.escape(name)}([^a-z0-9]|\$)').hasMatch(all)) {
        return e.key;
      }
    }
    return null;
  }

  /// Monto tras "$", "COP", "USD" o "US$". La captura termina en una cifra:
  /// el punto o la coma con que cierra la frase ("$500.000,00.") no es parte
  /// del número (si lo fuera, Money.parse lo tomaría como decimal y
  /// multiplicaría por cien).
  static final RegExp _amount = RegExp(r'(?:COP|USD|US\$|\$)\s?([0-9](?:[0-9.,]*[0-9])?)', caseSensitive: false);
  static final RegExp _amountWord = RegExp(r'por\s+(?:valor\s+de\s+)?([0-9](?:[0-9.,]*[0-9])?)\s*(?:pesos|cop)', caseSensitive: false);
  static final RegExp _digits = RegExp(r'(?:\*+|terminad[ao]\s+en\s+|terminaci[oó]n\s+|tarjeta\s+(?:de\s+cr[eé]dito\s+|d[eé]bito\s+)?\*?|t\.?\s?(?:cred|deb)\w*\.?\s*\*?|cta\.?\s*\*?|cuenta\s+(?:de\s+ahorros\s+|corriente\s+)?\*?)(\d{4})\b', caseSensitive: false);

  /// Nunca son movimientos, aunque mencionen una compra o un pago.
  static const List<String> _hardIgnore = <String>['clave dinámica', 'clave dinamica', 'contraseña', 'intento de inicio', 'inicio de sesión', 'inicio de sesion', 'rechazad', 'declinad', 'no fue posible', 'no aprobad', 'fallid', 'anulad'];

  /// "OTP" como palabra suelta (un código de un solo uso), no dentro de un
  /// nombre como "HOTPOT".
  static final RegExp _otp = RegExp(r'(?<![a-záéíóúñ0-9])otp(?![a-záéíóúñ0-9])', caseSensitive: false);

  /// Publicidad y códigos. Un aviso con estas palabras solo cuenta si además
  /// trae un verbo de movimiento ya hecho ([_done]): "compra" o "pago" sueltos
  /// aparecen también en los anuncios. Las palabras se buscan completas (las
  /// letras con tilde no cuentan como letra para `\b` en Dart, de ahí los
  /// límites explícitos).
  static final RegExp _promo = RegExp(r'(?<![a-záéíóúñ])(?:c[oó]digo|ofertas?|promoci[oó]n|promo|descuentos?|aprovecha|cup[oó]n|sorteo|participa|gana|premios?|pre-?\s?aprobad[ao]s?|beneficios?|cashback|tasa especial)(?![a-záéíóúñ])|\d\s?%', caseSensitive: false);

  /// "Aprobado" cuenta como hecho ("Compra aprobada"), pero no en
  /// "pre-aprobado" o "pre aprobado", que es publicidad.
  static final RegExp _done = RegExp(r'(?<![a-záéíóúñ])(?:compraste|pagaste|recibiste|te lleg[oó]|te llegaron|retiraste|sacaste|transferiste|enviaste|pasaste|realizaste|se realiz[oó]|te enviaron|te envi[oó]|te pagaron|consignaron|abonaron|se debit[oó]|se acredit[oó]|le informa|exitos[ao]|(?<!pre-)(?<!pre\s)aprobad[ao])(?![a-záéíóúñ])', caseSensitive: false);

  /// Verbos de un movimiento que ya pasó (sin "le informa" ni "aprobado", que
  /// también encabezan recordatorios).
  static final RegExp _moved = RegExp(r'(?<![a-záéíóúñ])(?:compraste|pagaste|recibiste|te lleg[oó]|te llegaron|retiraste|sacaste|transferiste|enviaste|pasaste|realizaste|se realiz[oó]|te enviaron|te envi[oó]|te pagaron|consignaron|abonaron|se debit[oó]|se acredit[oó]|devolvimos|te devolv[ií][a-záéíóúñ]*|reversamos)(?![a-záéíóúñ])', caseSensitive: false);

  /// Recordatorios y anuncios de algo que todavía no pasa ("Mañana
  /// debitaremos…", "tu pago mínimo vence…", "te está cobrando…"). Sin un
  /// verbo de movimiento hecho ([_moved]) no son movimientos.
  static final RegExp _future = RegExp(r'(?<![a-záéíóúñ])(?:debitaremos|cobraremos|descontaremos|se debitar[aá]|se cobrar[aá]|se descontar[aá]|recuerda|recordatorio|vence|vencer[aá]|vencimiento|pago m[ií]nimo|fecha l[ií]mite|pr[oó]ximo pago|te est[aá]n? cobrando|solicitud de pago|te solicita|programad[oa] para|ma[ñn]ana)(?![a-záéíóúñ])', caseSensitive: false);

  /// Reverso o devolución de una compra: plata que vuelve. Se sugiere como
  /// ingreso (un reembolso) y siempre se revisa.
  static final RegExp _refund = RegExp(r'(?<![a-záéíóúñ])(?:revers|devolvimos|te devolv|devoluci[oó]n|reembols|reintegr)', caseSensitive: false);

  static const List<String> _income = <String>['recibiste', 'te llegó', 'te llego', 'te llegaron', 'abono', 'consignaci', 'consignaron', 'depósito', 'deposito', 'ingreso de', 'recepción', 'recepcion', 'transferencia recibida', 'nómina', 'nomina', 'devolución', 'devolucion', 'reembolso', 'pago recibido', 'te pagaron', 'recibió', 'recibio', 'recibido', 'te envió', 'te envio', 'te enviaron', 'se acreditó', 'se acredito'];
  static const List<String> _expense = <String>['compra', 'pago', 'pagaste', 'retiro', 'retiraste', 'sacaste', 'enviaste', 'pasaste', 'transferiste', 'transferencia', 'débito', 'debito', 'cuota', 'cobro', 'avance', 'giro', 'recarga', 'cargo'];

  /// Pago de una tarjeta de crédito: "Pagaste … a tu tarjeta", "Pago de
  /// tarjeta de crédito", "Abono a tu T.Crédito". "Pago con tu tarjeta" y
  /// "pago … con cargo a tu tarjeta" son compras, no pagos de la tarjeta.
  /// Entre el verbo y la tarjeta puede ir el monto ("$500.000"): se admite un
  /// punto solo si le sigue una cifra.
  static final RegExp _cardPayment = RegExp(r'\b(?:pag\w*|abon\w*)\b(?:[^.;]|\.(?=\d))*?(?<!cargo\s)\b(?:a|de|para)\s+(?:tu\s+|la\s+|su\s+)?(?:tarjeta|t\.?\s?cr[eé]d\w*)', caseSensitive: false);

  /// Plata que sale hacia una cuenta o un bolsillo propios.
  static final RegExp _ownOut = RegExp(r'\b(?:a|hacia)\s+(?:tu|tus)\s+(?:bolsillos?|colch[oó]n|metas?|cuentas?|otra\s+cuenta)\b|\bentre\s+(?:tus\s+)?cuentas\b|\bcuentas?\s+propias?\b', caseSensitive: false);

  /// Plata que llega desde una cuenta o un bolsillo propios.
  static final RegExp _ownIn = RegExp(r'\b(?:de|desde)\s+(?:tu|tus)\s+(?:bolsillos?|colch[oó]n|metas?|cuentas?|otra\s+cuenta)\b|\bentre\s+(?:tus\s+)?cuentas\b|\bcuentas?\s+propias?\b', caseSensitive: false);
  static final RegExp _withdrawal = RegExp(r'\b(?:retir\w*|sacaste)\b', caseSensitive: false);

  /// Interpreta un aviso. Devuelve null si no parece un movimiento.
  static BankSuggestion? parse({String? packageName, String title = '', String text = ''}) {
    final String? bank = detectBank(packageName: packageName, title: title, text: text);
    if (bank == null) {
      return null;
    }
    final String all = '$title. $text'.replaceAll('\n', ' ').trim();
    final String lower = all.toLowerCase();
    for (final String w in _hardIgnore) {
      if (lower.contains(w)) {
        return null;
      }
    }
    if (_otp.hasMatch(all)) {
      return null;
    }
    if (_promo.hasMatch(all) && !_done.hasMatch(all)) {
      return null;
    }
    if (_future.hasMatch(all) && !_moved.hasMatch(all)) {
      return null;
    }
    final RegExpMatch? m = _amount.firstMatch(all) ?? _amountWord.firstMatch(all);
    if (m == null) {
      return null;
    }
    final int? minor = Money.parse(m.group(1)!);
    if (minor == null || minor <= 0) {
      return null;
    }
    final String currency = m.group(0)!.toUpperCase().contains('US') ? 'USD' : 'COP';
    final int incomeIdx = _firstIndex(lower, _income);
    final int expenseIdx = _firstIndex(lower, _expense);
    final bool refund = _refund.hasMatch(all);
    TxKind kind;
    if (refund || (incomeIdx >= 0 && (expenseIdx < 0 || incomeIdx <= expenseIdx))) {
      kind = TxKind.income;
    } else if (expenseIdx >= 0) {
      kind = TxKind.expense;
    } else {
      return null;
    }
    final List<String> digits = _digits.allMatches(all).map((RegExpMatch d) => d.group(1)!).toList();
    String flow = NoticeFlow.normal;
    String last4 = digits.isEmpty ? '' : digits.first;
    String toLast4 = '';
    if (refund) {
      flow = NoticeFlow.refund;
    } else if (_cardPayment.hasMatch(all)) {
      flow = NoticeFlow.cardPayment;
      // Los dígitos que siguen a "tarjeta" son los de la tarjeta que se paga;
      // los de "desde tu cuenta", los de origen.
      final RegExpMatch? card = RegExp(r'(?:tarjeta|t\.?\s?cr[eé]d\w*)[^0-9*]{0,24}\**(\d{4})\b', caseSensitive: false).firstMatch(all);
      final RegExpMatch? source = RegExp(r'(?:desde|de)\s+(?:tu\s+)?(?:cuenta|cta\.?)[^0-9*]{0,24}\**(\d{4})\b', caseSensitive: false).firstMatch(all);
      toLast4 = card?.group(1) ?? '';
      last4 = source?.group(1) ?? '';
    } else if (kind == TxKind.expense && _withdrawal.hasMatch(all)) {
      flow = NoticeFlow.withdrawal;
    } else if (kind == TxKind.expense && _ownOut.hasMatch(all)) {
      flow = NoticeFlow.transferOut;
    } else if (kind == TxKind.income && _ownIn.hasMatch(all)) {
      flow = NoticeFlow.transferIn;
    }
    if (flow != NoticeFlow.normal && flow != NoticeFlow.refund) {
      kind = TxKind.transfer;
    }
    return BankSuggestion(bank: bank, kind: kind, amountMinor: minor, currency: currency, merchant: kind == TxKind.transfer ? '' : _merchant(all, kind), last4: last4, toLast4: toLast4, flow: flow);
  }

  static int _firstIndex(String lower, List<String> words) {
    int best = -1;
    for (final String w in words) {
      final int i = lower.indexOf(w);
      if (i >= 0 && (best < 0 || i < best)) {
        best = i;
      }
    }
    return best;
  }

  /// Comercio o persona: lo que sigue a " en ", " a " o " de ".
  static String _merchant(String all, TxKind kind) {
    final List<RegExp> patterns = kind == TxKind.income
        ? <RegExp>[RegExp(r'\bde\s+([A-ZÁÉÍÓÚÑa-záéíóúñ0-9][^.,;]*?)(?=\s+(?:en|a|por|con|el|la|desde)\b|[.,;]|$)', caseSensitive: false)]
        : <RegExp>[
            RegExp(r'\ben\s+([A-ZÁÉÍÓÚÑ0-9][A-ZÁÉÍÓÚÑ0-9 .*&\-]*?)(?=\s+(?:con|el|a las|desde|por|hora|fecha)\b|[,;]|\.\s|\.$|\s+\d{1,2}[:/]|$)'),
            RegExp(r'\ben\s+([A-Za-zÁÉÍÓÚÑáéíóúñ0-9][^.,;]*?)(?=\s+(?:con|el|a las|desde|por|hora|fecha)\b|[.,;]|$)', caseSensitive: false),
            RegExp(r'\ba\s+([A-ZÁÉÍÓÚÑa-záéíóúñ][^.,;]*?)(?=\s+(?:desde|por|con|el|la|hoy)\b|[.,;]|$)', caseSensitive: false),
          ];
    for (final RegExp r in patterns) {
      final RegExpMatch? m = r.firstMatch(all);
      if (m != null) {
        String s = m.group(1)!.trim();
        s = s.replaceAll(RegExp(r'\s+'), ' ');
        if (s.length > 2 && !RegExp(r'^\d').hasMatch(s) && !s.toLowerCase().startsWith('tu ') && !s.toLowerCase().startsWith('su ')) {
          return s.length > 60 ? s.substring(0, 60) : s;
        }
      }
    }
    return '';
  }
}
