/// Dinero en unidades mínimas (centavos) con formato colombiano.
///
/// Todos los montos se guardan como enteros de centavos, sin importar la
/// moneda, para evitar errores de coma flotante. El peso colombiano se
/// muestra sin centavos salvo que el usuario lo pida.
class Money {
  Money._();

  /// Monedas conocidas: símbolo y decimales habituales al mostrar.
  static const Map<String, CurrencyInfo> currencies = <String, CurrencyInfo>{
    'COP': CurrencyInfo('COP', r'$', 0, 'Peso colombiano'),
    'USD': CurrencyInfo('USD', r'US$', 2, 'Dólar estadounidense'),
    'EUR': CurrencyInfo('EUR', '€', 2, 'Euro'),
    'MXN': CurrencyInfo('MXN', r'MX$', 2, 'Peso mexicano'),
    'BRL': CurrencyInfo('BRL', r'R$', 2, 'Real brasileño'),
    'PEN': CurrencyInfo('PEN', 'S/', 2, 'Sol peruano'),
    'CLP': CurrencyInfo('CLP', r'CLP$', 0, 'Peso chileno'),
    'ARS': CurrencyInfo('ARS', r'AR$', 2, 'Peso argentino'),
    'GBP': CurrencyInfo('GBP', '£', 2, 'Libra esterlina'),
    'CAD': CurrencyInfo('CAD', r'CA$', 2, 'Dólar canadiense'),
    'CHF': CurrencyInfo('CHF', 'CHF', 2, 'Franco suizo'),
    'JPY': CurrencyInfo('JPY', '¥', 0, 'Yen japonés'),
    'CNY': CurrencyInfo('CNY', 'CN¥', 2, 'Yuan chino'),
    'PAB': CurrencyInfo('PAB', 'B/.', 2, 'Balboa panameño'),
    'CRC': CurrencyInfo('CRC', '₡', 0, 'Colón costarricense'),
    'DOP': CurrencyInfo('DOP', r'RD$', 2, 'Peso dominicano'),
    'UYU': CurrencyInfo('UYU', r'$U', 2, 'Peso uruguayo'),
    'VES': CurrencyInfo('VES', 'Bs.', 2, 'Bolívar'),
  };

  static CurrencyInfo info(String code) => currencies[code] ?? CurrencyInfo(code, code, 2, code);

  /// Formatea centavos como "$ 1.234.567" (COP) o "US$ 1.234,50".
  ///
  /// Las monedas con decimales muestran siempre dos; el peso colombiano solo
  /// si [showCents] es verdadero (si no, se redondea al peso).
  static String format(int minor, String currency, {bool showCents = false, bool withSymbol = true, bool compact = false}) {
    final CurrencyInfo c = info(currency);
    final bool neg = minor < 0;
    final int abs = minor.abs();
    final bool wantCents = c.decimals > 0 || showCents;
    final int units = wantCents ? abs ~/ 100 : (abs + 50) ~/ 100;
    final int cents = abs % 100;
    String body;
    if (compact && units >= 1000000) {
      body = '${_trimZeros((units / 1000000).toStringAsFixed(units >= 10000000 ? 1 : 2))} M';
    } else if (compact && units >= 10000) {
      body = '${_trimZeros((units / 1000).toStringAsFixed(1))} mil';
    } else {
      body = groupThousands(units);
      if (wantCents) {
        body = '$body,${cents.toString().padLeft(2, '0')}';
      }
    }
    final String sym = withSymbol ? '${c.symbol} ' : '';
    return '${neg ? '−' : ''}$sym$body';
  }

  static String _trimZeros(String s) {
    String t = s;
    if (t.contains('.')) {
      t = t.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return t.replaceAll('.', ',');
  }

  /// "1234567" → "1.234.567".
  static String groupThousands(int units) {
    final String s = units.toString();
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) {
        b.write('.');
      }
      b.write(s[i]);
    }
    return b.toString();
  }

  /// Interpreta "1.234.567,50", "1234567.5", "$ 45.000" o "45000" como centavos.
  static int? parse(String text, {String currency = 'COP'}) {
    String s = text.trim().replaceAll(RegExp(r'[^0-9,.\-]'), '');
    if (s.isEmpty) {
      return null;
    }
    final bool neg = s.startsWith('-');
    s = s.replaceAll('-', '');
    // Separador decimal: el último de ',' o '.' si va seguido de 1 o 2 dígitos
    // y no es un separador de miles (3 dígitos).
    String intPart = s;
    String decPart = '';
    final int lastComma = s.lastIndexOf(',');
    final int lastDot = s.lastIndexOf('.');
    final int sep = lastComma > lastDot ? lastComma : lastDot;
    if (sep >= 0) {
      final String after = s.substring(sep + 1);
      final bool looksDecimal = after.length <= 2 || (sep == lastDot && lastComma < 0 && after.length != 3);
      if (looksDecimal && after.length <= 2) {
        intPart = s.substring(0, sep);
        decPart = after;
      }
    }
    intPart = intPart.replaceAll(RegExp(r'[^0-9]'), '');
    if (intPart.isEmpty && decPart.isEmpty) {
      return null;
    }
    final int units = intPart.isEmpty ? 0 : int.parse(intPart);
    final int cents = decPart.isEmpty ? 0 : int.parse(decPart.padRight(2, '0').substring(0, 2));
    final int minor = units * 100 + cents;
    return neg ? -minor : minor;
  }

  /// Convierte centavos entre monedas con tasas "1 unidad = tasa en moneda base".
  static int convert(int minor, {required double fromRate, required double toRate}) {
    if (fromRate <= 0 || toRate <= 0) {
      return minor;
    }
    return (minor * fromRate / toRate).round();
  }
}

class CurrencyInfo {
  const CurrencyInfo(this.code, this.symbol, this.decimals, this.name);

  final String code;
  final String symbol;
  final int decimals;
  final String name;
}
