/// Dinero en unidades mínimas (centavos) con formato colombiano o inglés.
///
/// Todos los montos se guardan como enteros de centavos, sin importar la
/// moneda, para evitar errores de coma flotante. El peso colombiano se
/// muestra sin centavos salvo que el usuario lo pida.
class Money {
  Money._();

  /// Monedas conocidas: símbolo, decimales habituales al mostrar y nombre en
  /// español e inglés.
  static const Map<String, CurrencyInfo> currencies = <String, CurrencyInfo>{
    'COP': CurrencyInfo('COP', r'$', 0, 'Peso colombiano', 'Colombian peso'),
    'USD': CurrencyInfo('USD', r'US$', 2, 'Dólar estadounidense', 'US dollar'),
    'EUR': CurrencyInfo('EUR', '€', 2, 'Euro', 'Euro'),
    'MXN': CurrencyInfo('MXN', r'MX$', 2, 'Peso mexicano', 'Mexican peso'),
    'BRL': CurrencyInfo('BRL', r'R$', 2, 'Real brasileño', 'Brazilian real'),
    'PEN': CurrencyInfo('PEN', 'S/', 2, 'Sol peruano', 'Peruvian sol'),
    'CLP': CurrencyInfo('CLP', r'CLP$', 0, 'Peso chileno', 'Chilean peso'),
    'ARS': CurrencyInfo('ARS', r'AR$', 2, 'Peso argentino', 'Argentine peso'),
    'GBP': CurrencyInfo('GBP', '£', 2, 'Libra esterlina', 'Pound sterling'),
    'CAD': CurrencyInfo('CAD', r'CA$', 2, 'Dólar canadiense', 'Canadian dollar'),
    'CHF': CurrencyInfo('CHF', 'CHF', 2, 'Franco suizo', 'Swiss franc'),
    'JPY': CurrencyInfo('JPY', '¥', 0, 'Yen japonés', 'Japanese yen'),
    'CNY': CurrencyInfo('CNY', 'CN¥', 2, 'Yuan chino', 'Chinese yuan'),
    'PAB': CurrencyInfo('PAB', 'B/.', 2, 'Balboa panameño', 'Panamanian balboa'),
    'CRC': CurrencyInfo('CRC', '₡', 0, 'Colón costarricense', 'Costa Rican colón'),
    'DOP': CurrencyInfo('DOP', r'RD$', 2, 'Peso dominicano', 'Dominican peso'),
    'UYU': CurrencyInfo('UYU', r'$U', 2, 'Peso uruguayo', 'Uruguayan peso'),
    'VES': CurrencyInfo('VES', 'Bs.', 2, 'Bolívar', 'Venezuelan bolívar'),
  };

  static CurrencyInfo info(String code) => currencies[code] ?? CurrencyInfo(code, code, 2, code, code);

  /// Formatea centavos: "$ 1.234.567" (COP) o "US$ 1.234,50" en español y
  /// "$ 1,234,567" o "US$ 1,234.50" en inglés.
  ///
  /// Las monedas con decimales muestran siempre dos; el peso colombiano solo
  /// si [showCents] es verdadero (si no, se redondea al peso). El formato
  /// compacto usa "1,5 M" y "350 mil" en español, "1.5M" y "350k" en inglés.
  static String format(int minor, String currency, {bool showCents = false, bool withSymbol = true, bool compact = false, bool spanish = true}) {
    final CurrencyInfo c = info(currency);
    final bool neg = minor < 0;
    final int abs = minor.abs();
    final bool wantCents = c.decimals > 0 || showCents;
    final int units = wantCents ? abs ~/ 100 : (abs + 50) ~/ 100;
    final int cents = abs % 100;
    final String decimalSep = spanish ? ',' : '.';
    String body;
    // Desde 999.950 se redondearía a "1.000 mil": se muestra en millones.
    if (compact && units >= 999950) {
      final String n = _trimZeros((units / 1000000).toStringAsFixed(units >= 10000000 ? 1 : 2), spanish: spanish);
      body = spanish ? '$n M' : '${n}M';
    } else if (compact && units >= 10000) {
      final String n = _trimZeros((units / 1000).toStringAsFixed(1), spanish: spanish);
      body = spanish ? '$n mil' : '${n}k';
    } else {
      body = groupThousands(units, separator: spanish ? '.' : ',');
      if (wantCents) {
        body = '$body$decimalSep${cents.toString().padLeft(2, '0')}';
      }
    }
    final String sym = withSymbol ? '${c.symbol} ' : '';
    return '${neg ? '−' : ''}$sym$body';
  }

  /// Número compacto sin moneda para ejes de gráficas: "1,5 M"/"350 mil" o
  /// "1.5M"/"350k".
  static String compactNumber(double value, {bool spanish = true}) {
    final double v = value.abs();
    final String sign = value < 0 ? '−' : '';
    if (v >= 999500) {
      final String n = _trimZeros((v / 1000000).toStringAsFixed(1), spanish: spanish);
      return spanish ? '$sign$n M' : '$sign${n}M';
    }
    if (v >= 1000) {
      final String n = _trimZeros((v / 1000).toStringAsFixed(0), spanish: spanish);
      return spanish ? '$sign$n mil' : '$sign${n}k';
    }
    return '$sign${v.toStringAsFixed(0)}';
  }

  static String _trimZeros(String s, {required bool spanish}) {
    String t = s;
    if (t.contains('.')) {
      t = t.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return spanish ? t.replaceAll('.', ',') : t;
  }

  /// "1234567" → "1.234.567" (o "1,234,567" con [separator] = ',').
  static String groupThousands(int units, {String separator = '.'}) {
    final String s = units.toString();
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) {
        b.write(separator);
      }
      b.write(s[i]);
    }
    return b.toString();
  }

  /// Interpreta "1.234.567,50", "1,234,567.50", "1234567.5", "$ 45.000" o
  /// "45000" como centavos.
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
      if (after.length <= 2) {
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

  /// Lee una tasa de cambio escrita a mano: "4.123,45", "4123.45", "0,00025",
  /// "1.0856" o "1.234.567". Con un solo separador seguido de exactamente tres
  /// cifras ("4.123") decide el idioma: en español el punto agrupa miles y la
  /// coma es decimal; en inglés, al revés. Devuelve null si no es un número
  /// mayor que cero.
  static double? parseRate(String text, {bool spanish = true}) {
    final String s = text.replaceAll(RegExp(r'[^0-9,.]'), '');
    if (!RegExp(r'[0-9]').hasMatch(s)) {
      return null;
    }
    final int commas = ','.allMatches(s).length;
    final int dots = '.'.allMatches(s).length;
    String normalized;
    if (commas > 0 && dots > 0) {
      final String dec = s.lastIndexOf(',') > s.lastIndexOf('.') ? ',' : '.';
      final String group = dec == ',' ? '.' : ',';
      if ((dec == ',' ? commas : dots) > 1) {
        return null;
      }
      normalized = s.replaceAll(group, '').replaceAll(dec, '.');
    } else if (commas + dots == 0) {
      normalized = s;
    } else {
      final String sep = commas > 0 ? ',' : '.';
      if (commas + dots > 1) {
        // Varios separadores iguales: agrupan miles ("1.234.567").
        normalized = s.replaceAll(sep, '');
      } else {
        final int i = s.indexOf(sep);
        final String before = s.substring(0, i);
        final String after = s.substring(i + 1);
        final bool looksGrouped = after.length == 3 && before.isNotEmpty && before.length <= 3 && before != '0';
        final bool groups = looksGrouped && (spanish ? sep == '.' : sep == ',');
        if (groups) {
          normalized = '$before$after';
        } else if (after.isEmpty) {
          normalized = before;
        } else {
          normalized = '${before.isEmpty ? '0' : before}.$after';
        }
      }
    }
    final double? v = double.tryParse(normalized);
    if (v == null || !v.isFinite || v <= 0) {
      return null;
    }
    return v;
  }

  /// Tasa legible con las cifras que hacen falta: "4.123,45", "1,0856" o
  /// "0,000243" (con punto decimal en inglés).
  static String formatRate(double rate, {bool spanish = true}) {
    final double r = rate.abs();
    int decimals;
    if (r >= 1000) {
      decimals = 2;
    } else if (r >= 1) {
      decimals = 4;
    } else {
      // Tres cifras significativas para tasas pequeñas (1 COP = 0,000243 USD).
      decimals = 3;
      double x = r;
      while (x > 0 && x < 0.1 && decimals < 12) {
        x *= 10;
        decimals += 1;
      }
    }
    String fixed = r.toStringAsFixed(decimals);
    if (fixed.contains('.')) {
      fixed = fixed.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    final List<String> parts = fixed.split('.');
    final String intPart = groupThousands(int.parse(parts.first), separator: spanish ? '.' : ',');
    return parts.length > 1 ? '$intPart${spanish ? ',' : '.'}${parts[1]}' : intPart;
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
  const CurrencyInfo(this.code, this.symbol, this.decimals, this.name, [this.nameEn = '']);

  final String code;
  final String symbol;
  final int decimals;

  /// Nombre en español.
  final String name;

  /// Nombre en inglés.
  final String nameEn;

  String nameFor({required bool spanish}) => spanish || nameEn.isEmpty ? name : nameEn;
}
