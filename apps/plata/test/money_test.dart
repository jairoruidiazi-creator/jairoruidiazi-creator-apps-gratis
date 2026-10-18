// Dinero, tasas y calculadora: los hallazgos B3, G3 y M1 del informe de
// auditoría (ver docs/DECISIONES.md).

import 'package:flutter_test/flutter_test.dart';
import 'package:plata/model/money.dart';
import 'package:plata/ui/widgets/amount_keypad.dart';

void press(Calc c, String keys) {
  for (final String k in keys.split(' ')) {
    if (k.isEmpty) {
      continue;
    }
    if (RegExp(r'^\d+$').hasMatch(k)) {
      for (final String d in k.split('')) {
        c.press(d);
      }
    } else {
      c.press(k);
    }
  }
}

void main() {
  group('B3: la calculadora vale lo que se ve aunque no se pulse "="', () {
    test('una suma a medias se guarda completa', () {
      final Calc c = Calc();
      press(c, '50000 + 20000');
      expect(c.hasPendingOp, isTrue);
      expect(c.valueMinor, 7000000);
    });

    test('resta, multiplicación y división a medias', () {
      final Calc minus = Calc();
      press(minus, '120000 − 20000');
      expect(minus.valueMinor, 10000000);
      final Calc times = Calc();
      press(times, '15000 × 3');
      expect(times.valueMinor, 4500000);
      final Calc divide = Calc();
      press(divide, '120000 ÷ 3');
      expect(divide.valueMinor, 4000000);
    });

    test('con el operador recién puesto vale el primer número', () {
      final Calc c = Calc();
      press(c, '50000 +');
      expect(c.valueMinor, 5000000);
    });

    test('evaluate resuelve la operación como "="', () {
      final Calc c = Calc();
      press(c, '50000 + 20000 + 5000');
      expect(c.valueMinor, 7500000);
      c.evaluate();
      expect(c.hasPendingOp, isFalse);
      expect(c.valueMinor, 7500000);
      expect(c.expression, '75.000');
    });

    test('la expresión usa los separadores del idioma', () {
      final Calc c = Calc(spanish: false);
      press(c, '12000 + 3000');
      expect(c.expression, '12,000 + 3,000');
    });
  });

  group('G3: tasas escritas a mano con todos sus decimales', () {
    test('lee tasas grandes, pequeñas y con muchos decimales', () {
      expect(Money.parseRate('4.123,45'), closeTo(4123.45, 1e-9));
      expect(Money.parseRate('4123,4567'), closeTo(4123.4567, 1e-9));
      expect(Money.parseRate('0,00025'), closeTo(0.00025, 1e-12));
      expect(Money.parseRate('0,000243'), closeTo(0.000243, 1e-12));
      expect(Money.parseRate('1,0856'), closeTo(1.0856, 1e-12));
      expect(Money.parseRate('4.123'), closeTo(4123, 1e-9)); // en español el punto agrupa miles
      expect(Money.parseRate('1.234.567'), closeTo(1234567, 1e-9));
    });

    test('en inglés el punto es decimal', () {
      expect(Money.parseRate('4.123', spanish: false), closeTo(4.123, 1e-12));
      expect(Money.parseRate('4,123.45', spanish: false), closeTo(4123.45, 1e-9));
      expect(Money.parseRate('0.00025', spanish: false), closeTo(0.00025, 1e-12));
    });

    test('rechaza lo que no es una tasa positiva', () {
      expect(Money.parseRate(''), isNull);
      expect(Money.parseRate('abc'), isNull);
      expect(Money.parseRate('0'), isNull);
      expect(Money.parseRate('0,000'), isNull);
      expect(Money.parseRate('1,2.3,4'), isNull); // dos comas decimales
    });

    test('se muestra con las cifras que hacen falta y vuelve igual', () {
      expect(Money.formatRate(4123.45), '4.123,45');
      expect(Money.formatRate(1.0856), '1,0856');
      expect(Money.formatRate(0.000243), '0,000243');
      expect(Money.formatRate(0.000243, spanish: false), '0.000243');
      for (final double r in <double>[4123.45, 1.0856, 0.000243, 0.00025, 18.25]) {
        expect(Money.parseRate(Money.formatRate(r)), closeTo(r, r * 1e-6));
        expect(Money.parseRate(Money.formatRate(r, spanish: false), spanish: false), closeTo(r, r * 1e-6));
      }
    });

    test('convertir con una tasa pequeña no la redondea a cero', () {
      // Con el dólar de moneda base, 1 COP = 0,000243 USD: 100.000 pesos son
      // 24,30 dólares (con la tasa recortada a 0,00 serían cero).
      expect(Money.convert(10000000, fromRate: 0.000243, toRate: 1), 2430);
    });
  });

  group('M1: formatos en inglés', () {
    test('montos con separadores ingleses', () {
      expect(Money.format(123456700, 'COP', spanish: false), r'$ 1,234,567');
      expect(Money.format(123450, 'USD', spanish: false), r'US$ 1,234.50');
    });

    test('compacto: "mil" y "M" en español, "k" y "M" en inglés', () {
      expect(Money.format(150000000, 'COP', compact: true), r'$ 1,5 M');
      expect(Money.format(150000000, 'COP', compact: true, spanish: false), r'$ 1.5M');
      expect(Money.format(35000000, 'COP', compact: true), r'$ 350 mil');
      expect(Money.format(35000000, 'COP', compact: true, spanish: false), r'$ 350k');
      // Justo antes del millón no queda "1.000 mil".
      expect(Money.format(99999900, 'COP', compact: true), r'$ 1 M');
    });

    test('rótulos de ejes de gráficas', () {
      expect(Money.compactNumber(1500000), '1,5 M');
      expect(Money.compactNumber(1500000, spanish: false), '1.5M');
      expect(Money.compactNumber(350000), '350 mil');
      expect(Money.compactNumber(350000, spanish: false), '350k');
      expect(Money.compactNumber(999999), '1 M');
      expect(Money.compactNumber(950), '950');
    });

    test('nombres de monedas en los dos idiomas', () {
      expect(Money.info('USD').nameFor(spanish: true), 'Dólar estadounidense');
      expect(Money.info('USD').nameFor(spanish: false), 'US dollar');
      for (final CurrencyInfo c in Money.currencies.values) {
        expect(c.nameEn, isNotEmpty, reason: c.code);
      }
    });
  });
}
