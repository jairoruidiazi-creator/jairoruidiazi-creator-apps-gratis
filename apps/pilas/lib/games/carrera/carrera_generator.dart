import 'package:flutter/material.dart';

import '../../core/es.dart';
import '../../core/rng.dart';
import '../../core/theme.dart';
import '../../model/age_band.dart';
import '../choice/choice_round.dart';
import '../choice/option_builders.dart';

/// Carrera de cálculo: operaciones con estrategia explicada al fallar.
/// Sin reloj: el niño compite contra su propia marca de aciertos, nunca
/// contra otros ni contra el tiempo.
class CarreraGenerator implements ChoiceGenerator {
  @override
  ChoiceRound next(Rng rng, AgeBand band, int level) {
    switch (band) {
      case AgeBand.b3a4:
      case AgeBand.b5a6:
        return _sumasRestas(rng, level <= 2 ? 10 : 20, level >= 3);
      case AgeBand.b7a8:
        if (level == 1) {
          return _sumasRestas(rng, 100, true);
        }
        if (level == 2) {
          return _tablas(rng, <int>[2, 3, 4, 5, 10]);
        }
        if (level == 3) {
          return rng.chance(0.5) ? _tablas(rng, <int>[6, 7, 8, 9]) : _division(rng, <int>[2, 3, 4, 5]);
        }
        return rng.chance(0.5) ? _division(rng, <int>[6, 7, 8, 9]) : _sumasRestas(rng, 100, true, llevadas: true);
      case AgeBand.b9a11:
        if (level == 1) {
          return rng.chance(0.5) ? _tablas(rng, <int>[6, 7, 8, 9, 12]) : _division(rng, <int>[6, 7, 8, 9]);
        }
        if (level == 2) {
          return _multiplicacionDosCifras(rng);
        }
        if (level == 3) {
          return rng.chance(0.5) ? _decimales(rng) : _divisionConResto(rng);
        }
        return rng.chance(0.5) ? _fraccionDeCantidad(rng) : _multiplicacionDosCifras(rng, max: 99);
    }
  }

  ChoiceRound _opts(Rng rng, String titulo, String expresion, int correcto, String hint, String explain, {int spread = 3, String? spoken}) {
    final Set<int> opciones = <int>{correcto};
    int guard = 0;
    while (opciones.length < 3 && guard < 60) {
      guard += 1;
      final int d = correcto + rng.range(-spread, spread);
      if (d >= 0 && d != correcto) {
        opciones.add(d);
      }
    }
    while (opciones.length < 3) {
      opciones.add(correcto + opciones.length);
    }
    final List<ChoiceOption> options = <ChoiceOption>[for (final int o in opciones) Opt.number(o)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: titulo,
      spoken: spoken,
      prompt: (BuildContext context) => BigPrompt(
        child: Text(expresion, style: TextStyle(fontSize: 46, fontWeight: FontWeight.w800, color: PilasPalette.of(context).tinta)),
      ),
      options: options,
      correctId: 'n$correcto',
      hint: hint,
      explain: explain,
    );
  }

  ChoiceRound _sumasRestas(Rng rng, int max, bool conResta, {bool llevadas = false}) {
    final bool suma = !conResta || rng.chance(0.55);
    int a;
    int b;
    if (llevadas && suma) {
      // Suma con llevada: las unidades pasan de 10 y el total no pasa de 99.
      a = rng.range(15, 84);
      if (a % 10 == 0) {
        a += 1;
      }
      final int ub = rng.range(10 - a % 10, 9);
      final int db = rng.range(0, (99 - a - ub) ~/ 10);
      b = db * 10 + ub;
    } else if (llevadas) {
      // Resta con préstamo: la unidad del sustraendo es mayor que la del minuendo.
      a = rng.range(30, 99);
      if (a % 10 == 9) {
        a -= 1;
      }
      final int ub = rng.range(a % 10 + 1, 9);
      final int db = rng.range(1, (a - ub - 1) ~/ 10);
      b = db * 10 + ub;
    } else {
      a = rng.range(1, max - 1);
      b = suma ? rng.range(1, max - a) : rng.range(1, a);
    }
    final int r = suma ? a + b : a - b;
    final String expr = suma ? '$a + $b' : '$a − $b';
    String estrategia;
    if (max <= 20) {
      estrategia = suma ? 'Empieza en $a y cuenta $b más con los dedos: ${_contar(a, b, true)}.' : 'Empieza en $a y cuenta $b hacia atrás: ${_contar(a, b, false)}.';
    } else {
      final int decenasB = (b ~/ 10) * 10;
      final int unidadesB = b % 10;
      estrategia = suma
          ? 'Suma primero las decenas y luego las unidades: $a + $decenasB = ${a + decenasB}, y ${a + decenasB} + $unidadesB = $r.'
          : 'Resta primero las decenas y luego las unidades: $a − $decenasB = ${a - decenasB}, y ${a - decenasB} − $unidadesB = $r.';
    }
    return _opts(rng, '¿Cuánto es $expr?', '$expr = ?', r, estrategia, '$expr es $r. $estrategia', spread: max <= 20 ? 2 : 10);
  }

  String _contar(int a, int b, bool arriba) {
    final List<int> pasos = <int>[];
    for (int i = 1; i <= b && i <= 5; i++) {
      pasos.add(arriba ? a + i : a - i);
    }
    return '${pasos.join(', ')}${b > 5 ? '...' : ''}';
  }

  ChoiceRound _tablas(Rng rng, List<int> tablas) {
    final int t = rng.pick(tablas);
    final int n = rng.range(2, 10);
    final int r = t * n;
    final String truco = t == 10
        ? 'Multiplicar por 10 es agregar un cero.'
        : (t == 5 ? 'La tabla del 5 va de 5 en 5: termina en 0 o en 5.' : (t == 2 ? 'Multiplicar por 2 es sumar el número consigo mismo.' : 'Puedes sumar $t veces $n, o usar $t × ${n - 1} = ${t * (n - 1)} y agregar $t.'));
    return _opts(rng, '¿Cuánto es $t por $n?', '$t × $n = ?', r, truco, '$t × $n es $r. $truco', spread: t);
  }

  ChoiceRound _division(Rng rng, List<int> divisores) {
    final int d = rng.pick(divisores);
    final int q = rng.range(2, 10);
    final int total = d * q;
    return _opts(rng, '¿Cuánto es $total dividido entre $d?', '$total ÷ $d = ?', q, 'Piensa qué número por $d da $total: busca en la tabla del $d.', '$total ÷ $d es $q, porque $d × $q = $total.', spread: 2);
  }

  ChoiceRound _multiplicacionDosCifras(Rng rng, {int max = 30}) {
    final int a = rng.range(11, max);
    final int b = rng.range(2, 9);
    final int r = a * b;
    final int dec = (a ~/ 10) * 10;
    final int uni = a % 10;
    final String estrategia = 'Separa $a en $dec + $uni: $dec × $b = ${dec * b} y $uni × $b = ${uni * b}; suma ${dec * b} + ${uni * b} = $r.';
    return _opts(rng, '¿Cuánto es $a por $b?', '$a × $b = ?', r, estrategia, '$a × $b es $r. $estrategia', spread: 12);
  }

  ChoiceRound _divisionConResto(Rng rng) {
    final int d = rng.range(3, 9);
    final int q = rng.range(3, 12);
    final int resto = rng.range(1, d - 1);
    final int total = d * q + resto;
    return _opts(rng, '$total dividido entre $d, ¿cuánto sobra?', '$total ÷ $d  →  resto ?', resto, 'Busca el múltiplo de $d más cercano sin pasarte: $d × $q = ${d * q}. Lo que falta hasta $total es el resto.', '$d × $q = ${d * q} y $total − ${d * q} = $resto. Sobran $resto.', spread: 2);
  }

  /// Décimos con coma, sin ",0": 35 → "3,5"; 40 → "4".
  static String decimos(int v) => v % 10 == 0 ? '${v ~/ 10}' : '${v ~/ 10},${v % 10}';

  ChoiceRound _decimales(Rng rng) {
    // Dos cantidades con décimos (1,5 + 2,3), como precios en miles de pesos.
    int a;
    int b;
    do {
      a = rng.range(11, 89);
      b = rng.range(11, 89);
    } while (a % 10 == 0 || b % 10 == 0);
    final int r = a + b;
    return _opts(rng, '¿Cuánto es ${decimos(a)} más ${decimos(b)}?', '${decimos(a)} + ${decimos(b)} = ?', r,
        'Suma primero los enteros y luego los décimos; si los décimos pasan de diez, llevas uno al entero.',
        '${decimos(a)} + ${decimos(b)} = ${decimos(r)}.',
        spread: 5).copyWithNumbersAsDecimals();
  }

  ChoiceRound _fraccionDeCantidad(Rng rng) {
    final int den = rng.pick(<int>[2, 3, 4, 5]);
    final int num = rng.range(1, den - 1);
    final int unidad = rng.range(2, 12);
    final int total = unidad * den;
    final int r = unidad * num;
    return _opts(rng, '¿Cuánto es $num/$den de $total?', '$num/$den de $total = ?', r, 'Divide $total entre $den para saber cuánto vale una parte. Luego multiplica por $num.', '$total ÷ $den = $unidad y $unidad × $num = $r.', spread: unidad, spoken: '¿Cuánto es ${Es.fraccion(num, den)} de $total?');
  }
}

extension on ChoiceRound {
  /// Las opciones numéricas de la ronda de decimales se muestran con coma.
  ChoiceRound copyWithNumbersAsDecimals() {
    final List<ChoiceOption> opts = options.map((ChoiceOption o) {
      final int? n = int.tryParse(o.id.substring(1));
      if (n == null) {
        return o;
      }
      final String txt = CarreraGenerator.decimos(n);
      return Opt.text(o.id, txt, label: txt.replaceAll(',', ' coma '));
    }).toList();
    return ChoiceRound(
      instruction: instruction,
      spoken: spoken,
      options: opts,
      correctId: correctId,
      hint: hint,
      explain: explain,
      prompt: prompt,
      praise: praise,
      columns: columns,
      readOptionsAloud: readOptionsAloud,
      optionSize: optionSize,
      optionAspect: optionAspect,
    );
  }
}
