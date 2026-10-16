import '../model/models.dart';
import '../model/money.dart';

/// Movimiento deducido de un aviso bancario.
class BankSuggestion {
  const BankSuggestion({required this.bank, required this.kind, required this.amountMinor, this.currency = 'COP', this.merchant = '', this.last4 = ''});

  final String bank;
  final TxKind kind;
  final int amountMinor;
  final String currency;
  final String merchant;
  final String last4;
}

/// Reglas para leer los avisos de los bancos colombianos (notificaciones de
/// sus apps en Android). Son solo texto: no se usan SMS ni claves.
class BankRules {
  BankRules._();

  /// Paquete de Android → banco.
  static const Map<String, String> packages = <String, String>{
    'com.bancolombia.personas': 'bancolombia',
    'com.bancolombia.app.personas': 'bancolombia',
    'com.nequi.MobileApp': 'nequi',
    'com.nequi.mobileapp': 'nequi',
    'com.davivienda.daviplataapp': 'daviplata',
    'com.davivienda.daviviendaapp': 'davivienda',
    'co.com.bbva.mb': 'bbva',
    'com.bancodebogota.bancamovil': 'bogota',
    'co.com.bancodeoccidente.bancamovil': 'occidente',
    'com.scotiabankcolpatria.mobile': 'colpatria',
    'com.lulobank.app': 'lulo',
    'co.com.rappi.pay': 'rappipay',
    'com.nu.production': 'nu',
    'co.uala.app': 'uala',
    'com.movii.movii': 'movii',
  };

  static const Map<String, String> bankNames = <String, String>{
    'bancolombia': 'Bancolombia',
    'nequi': 'Nequi',
    'daviplata': 'Daviplata',
    'davivienda': 'Davivienda',
    'bbva': 'BBVA',
    'bogota': 'Banco de Bogotá',
    'occidente': 'Banco de Occidente',
    'colpatria': 'Scotiabank Colpatria',
    'lulo': 'Lulo Bank',
    'rappipay': 'RappiPay',
    'nu': 'Nu',
    'uala': 'Ualá',
    'movii': 'Movii',
  };

  static bool isBankPackage(String? packageName) => packageName != null && packages.containsKey(packageName);

  /// Banco a partir del paquete o del propio texto.
  static String? detectBank({String? packageName, String title = '', String text = ''}) {
    if (packageName != null && packages.containsKey(packageName)) {
      return packages[packageName];
    }
    final String all = '$title $text'.toLowerCase();
    for (final MapEntry<String, String> e in bankNames.entries) {
      if (all.contains(e.value.toLowerCase())) {
        return e.key;
      }
    }
    return null;
  }

  static final RegExp _amount = RegExp(r'(?:COP|USD|US\$|\$)\s?([0-9][0-9.,]*)', caseSensitive: false);
  static final RegExp _amountWord = RegExp(r'por\s+(?:valor\s+de\s+)?([0-9][0-9.,]*)\s*(?:pesos|cop)', caseSensitive: false);
  static final RegExp _last4 = RegExp(r'(?:\*+|terminad[ao]\s+en\s+|terminaci[oó]n\s+|tarjeta\s+|cta\.?\s*\*?|cuenta\s+\*?)(\d{4})\b', caseSensitive: false);

  /// Nunca son movimientos, aunque mencionen una compra o un pago.
  static const List<String> _hardIgnore = <String>['clave dinámica', 'clave dinamica', 'otp', 'contraseña', 'intento de inicio', 'inicio de sesión', 'inicio de sesion', 'rechazad', 'declinad', 'no fue posible', 'no aprobad', 'fallid', 'anulad', 'reversad'];

  /// Publicidad y códigos, salvo que el texto hable de una compra o un pago.
  static const List<String> _ignore = <String>['código', 'codigo', 'oferta', 'promoción', 'promocion', 'descuento'];
  static const List<String> _income = <String>['recibiste', 'te llegó', 'te llego', 'te llegaron', 'abono', 'consignaci', 'consignaron', 'depósito', 'deposito', 'ingreso de', 'recepción', 'recepcion', 'transferencia recibida', 'nómina', 'nomina', 'devolución', 'devolucion', 'reembolso', 'pago recibido', 'te pagaron', 'recibió', 'recibio', 'recibido'];
  static const List<String> _expense = <String>['compra', 'pago', 'pagaste', 'retiro', 'retiraste', 'sacaste', 'enviaste', 'pasaste', 'transferiste', 'transferencia', 'débito', 'debito', 'cuota', 'cobro', 'avance', 'giro', 'recarga', 'cargo'];

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
    for (final String w in _ignore) {
      if (lower.contains(w) && !lower.contains('compra') && !lower.contains('pago')) {
        return null;
      }
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
    TxKind kind;
    if (incomeIdx >= 0 && (expenseIdx < 0 || incomeIdx <= expenseIdx)) {
      kind = TxKind.income;
    } else if (expenseIdx >= 0) {
      kind = TxKind.expense;
    } else {
      return null;
    }
    final String? last4 = _last4.firstMatch(all)?.group(1);
    return BankSuggestion(bank: bank, kind: kind, amountMinor: minor, currency: currency, merchant: _merchant(all, kind), last4: last4 ?? '');
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
            RegExp(r'\ben\s+([A-ZÁÉÍÓÚÑ0-9][A-ZÁÉÍÓÚÑ0-9 .*&\-]*?)(?=\s+(?:con|el|a las|desde|por|hora|fecha)\b|[,;]|\s+\d{1,2}[:/]|$)'),
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
