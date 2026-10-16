import 'package:flutter/material.dart';

import '../../content/vocab.dart';
import '../../core/rng.dart';
import '../../core/theme.dart';
import '../../model/age_band.dart';
import '../choice/choice_round.dart';
import '../choice/option_builders.dart';
import '../shell/math_shapes.dart';
import '../shell/widgets.dart';

/// Cocina de medidas: lleno y vacío, tazas y pesos (5-6), fracciones de
/// pizza y de taza (7-8), fracciones equivalentes y sumas (9-11).
class CocinaGenerator implements ChoiceGenerator {
  @override
  ChoiceRound next(Rng rng, AgeBand band, int level) {
    switch (band) {
      case AgeBand.b3a4:
      case AgeBand.b5a6:
        if (level == 1) {
          return _masLleno(rng);
        }
        if (level == 2) {
          return _medioVacio(rng);
        }
        if (level == 3) {
          return _cuantasTazas(rng);
        }
        return _balanza(rng);
      case AgeBand.b7a8:
        if (level == 1) {
          return _queFraccion(rng, <int>[2, 4]);
        }
        if (level == 2) {
          return _cualMuestra(rng, <int>[2, 3, 4]);
        }
        if (level == 3) {
          return _cualEsMas(rng);
        }
        return _receta(rng);
      case AgeBand.b9a11:
        if (level == 1) {
          return _equivalente(rng);
        }
        if (level == 2) {
          return _sumaFracciones(rng);
        }
        if (level == 3) {
          return _fraccionDeReceta(rng);
        }
        return _compararDistintoDen(rng);
    }
  }

  static const List<Color> _jugos = <Color>[PilasColors.naranja, PilasColors.rosa, PilasColors.morado, PilasColors.verde];

  ChoiceOption _vaso(String id, double nivel, Color c, String label) {
    return ChoiceOption(id: id, label: label, build: (BuildContext context, double size) => GlassFill(level: nivel, size: size, color: c));
  }

  ChoiceRound _masLleno(Rng rng) {
    final bool mas = rng.chance(0.5);
    final List<double> niveles = rng.sample(<double>[0.15, 0.4, 0.65, 0.95], 3);
    final Color c = rng.pick(_jugos);
    niveles.sort();
    final double objetivo = mas ? niveles.last : niveles.first;
    final List<ChoiceOption> options = <ChoiceOption>[];
    for (int i = 0; i < niveles.length; i++) {
      options.add(_vaso('v$i', niveles[i], c, _nombreNivel(niveles[i])));
    }
    rng.shuffle(options);
    final String correctId = options.firstWhere((ChoiceOption o) => o.label == _nombreNivel(objetivo)).id;
    return ChoiceRound(
      instruction: mas ? '¿Cuál vaso tiene más jugo?' : '¿Cuál vaso tiene menos jugo?',
      options: options,
      correctId: correctId,
      hint: mas ? 'Mira hasta dónde llega el jugo: el que llega más arriba tiene más.' : 'El que tiene el jugo más abajito es el que tiene menos.',
      explain: mas ? 'Este es el que tiene más: el jugo llega más arriba.' : 'Este es el que tiene menos: el jugo llega más abajo.',
    );
  }

  String _nombreNivel(double n) {
    if (n < 0.2) {
      return 'casi vacío';
    }
    if (n < 0.5) {
      return 'menos de la mitad';
    }
    if (n < 0.8) {
      return 'más de la mitad';
    }
    return 'lleno';
  }

  ChoiceRound _medioVacio(Rng rng) {
    final int tipo = rng.nextInt(3); // 0 lleno, 1 medio, 2 vacío
    final Color c = rng.pick(_jugos);
    final List<ChoiceOption> options = <ChoiceOption>[
      _vaso('lleno', 0.95, c, 'lleno'),
      _vaso('medio', 0.5, c, 'por la mitad'),
      _vaso('vacio', 0.0, c, 'vacío'),
    ];
    rng.shuffle(options);
    final String id = <String>['lleno', 'medio', 'vacio'][tipo];
    final String nombre = <String>['lleno', 'por la mitad', 'vacío'][tipo];
    return ChoiceRound(
      instruction: '¿Cuál vaso está $nombre?',
      options: options,
      correctId: id,
      hint: tipo == 1 ? 'Por la mitad es cuando el jugo llega justo al medio del vaso.' : (tipo == 0 ? 'Lleno es cuando el jugo llega hasta arriba.' : 'Vacío es cuando no tiene nada.'),
      explain: 'Este vaso está $nombre.',
    );
  }

  ChoiceRound _cuantasTazas(Rng rng) {
    final int n = rng.range(2, 5);
    final List<int> opciones = <int>{n, n - 1, n + 1}.toList();
    final List<ChoiceOption> options = <ChoiceOption>[for (final int o in opciones) Opt.number(o)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿Cuántas tazas de harina se echaron al tazón?',
      prompt: (BuildContext context) => BigPrompt(
        child: Wrap(spacing: 6, alignment: WrapAlignment.center, children: <Widget>[for (int i = 0; i < n; i++) const EmojiImage('1f375', size: 44), const SizedBox(width: 12), const EmojiImage('1f963', size: 56)]),
      ),
      options: options,
      correctId: 'n$n',
      hint: 'Cuenta las tazas una por una tocándolas con el dedo.',
      explain: 'Se echaron $n tazas.',
      readOptionsAloud: true,
    );
  }

  ChoiceRound _balanza(Rng rng) {
    final List<VocabItem> pesados = <VocabItem>[...Vocab.withTag('grande'), ...Vocab.withTag('vehiculo')];
    final List<VocabItem> livianos = Vocab.withTag('fruta');
    final VocabItem a = rng.pick(pesados);
    final VocabItem b = rng.pick(livianos);
    final bool izqPesado = rng.chance(0.5);
    final VocabItem izq = izqPesado ? a : b;
    final VocabItem der = izqPesado ? b : a;
    final bool preguntaPesado = rng.chance(0.5);
    final String correcto = preguntaPesado ? (izqPesado ? 'izq' : 'der') : (izqPesado ? 'der' : 'izq');
    return ChoiceRound(
      instruction: preguntaPesado ? '¿Cuál pesa más?' : '¿Cuál pesa menos?',
      prompt: (BuildContext context) => BigPrompt(
        child: Balance(
          heavier: izqPesado ? -1 : 1,
          left: EmojiImage(izq.emoji, size: 40),
          right: EmojiImage(der.emoji, size: 40),
        ),
      ),
      options: <ChoiceOption>[
        ChoiceOption(id: 'izq', label: izq.nombre, build: (BuildContext context, double size) => EmojiImage(izq.emoji, size: size, semanticsLabel: izq.nombre)),
        ChoiceOption(id: 'der', label: der.nombre, build: (BuildContext context, double size) => EmojiImage(der.emoji, size: size, semanticsLabel: der.nombre)),
      ],
      correctId: correcto,
      hint: 'En la balanza, el platillo que baja es el que pesa más.',
      explain: preguntaPesado ? '${_cap(a.conArticulo)} pesa más que ${b.conArticulo}.' : '${_cap(b.conArticulo)} pesa menos que ${a.conArticulo}.',
      readOptionsAloud: true,
    );
  }

  String _cap(String t) => t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);

  static String nombreFraccion(int num, int den) {
    const Map<int, String> dens = <int, String>{2: 'medio', 3: 'tercio', 4: 'cuarto', 5: 'quinto', 6: 'sexto', 8: 'octavo', 10: 'décimo'};
    final String d = dens[den] ?? 'parte de $den';
    if (num == 1) {
      return den == 2 ? 'un medio' : 'un $d';
    }
    final String plural = den == 2 ? 'medios' : '${d}s';
    return '$num $plural';
  }

  ChoiceOption _pie(String id, int num, int den, {Color color = PilasColors.naranja}) {
    return ChoiceOption(id: id, label: nombreFraccion(num, den), build: (BuildContext context, double size) => FractionPie(num: num, den: den, size: size, color: color));
  }

  ChoiceOption _frac(String id, int num, int den) => Opt.text(id, '$num/$den', fontSize: 34, label: nombreFraccion(num, den));

  /// Se muestra una pizza con porciones comidas; se elige la fracción escrita.
  ChoiceRound _queFraccion(Rng rng, List<int> dens) {
    final int den = rng.pick(dens);
    final int num = rng.range(1, den - 1);
    final Set<String> ids = <String>{'$num/$den'};
    final List<ChoiceOption> options = <ChoiceOption>[_frac('$num/$den', num, den)];
    int guard = 0;
    while (options.length < 3 && guard < 30) {
      guard += 1;
      final int d2 = rng.pick(<int>[2, 3, 4, 6, 8]);
      final int n2 = rng.range(1, d2 - 1);
      if (ids.add('$n2/$d2') && (n2 * den != num * d2)) {
        options.add(_frac('$n2/$d2', n2, d2));
      }
    }
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿Qué fracción de la pizza se comieron?',
      prompt: (BuildContext context) => BigPrompt(child: FractionPie(num: num, den: den, size: 120), caption: 'Las porciones de color ya se comieron'),
      options: options,
      correctId: '$num/$den',
      hint: 'El número de abajo es en cuántas porciones iguales está partida la pizza; el de arriba, cuántas se comieron.',
      explain: 'La pizza está en $den porciones y se comieron $num: ${nombreFraccion(num, den)}, $num/$den.',
    );
  }

  /// Se da la fracción y se elige el dibujo.
  ChoiceRound _cualMuestra(Rng rng, List<int> dens) {
    final int den = rng.pick(dens);
    final int num = rng.range(1, den - 1);
    final List<ChoiceOption> options = <ChoiceOption>[_pie('ok', num, den)];
    final Set<String> usados = <String>{'$num/$den'};
    int guard = 0;
    while (options.length < 3 && guard < 30) {
      guard += 1;
      final int d2 = rng.chance(0.5) ? den : rng.pick(<int>[2, 3, 4, 6]);
      final int n2 = rng.range(1, d2 - 1);
      if (n2 * den == num * d2 || !usados.add('$n2/$d2')) {
        continue;
      }
      options.add(_pie('d${options.length}', n2, d2));
    }
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿Cuál dibujo muestra $num/$den (${nombreFraccion(num, den)})?',
      options: options,
      correctId: 'ok',
      hint: 'Cuenta primero en cuántas partes iguales está partido cada círculo: deben ser $den.',
      explain: 'Este círculo está en $den partes y tiene $num de color: $num/$den.',
      optionSize: 100,
    );
  }

  ChoiceRound _cualEsMas(Rng rng) {
    // Mismo numerador, distinto denominador: 1/2 vs 1/4; o mismo denominador.
    final bool mismoNum = rng.chance(0.5);
    int n1;
    int d1;
    int n2;
    int d2;
    if (mismoNum) {
      n1 = 1;
      n2 = 1;
      final List<int> ds = rng.sample(<int>[2, 3, 4, 6, 8], 2);
      d1 = ds[0];
      d2 = ds[1];
    } else {
      d1 = rng.pick(<int>[4, 6, 8]);
      d2 = d1;
      final List<int> ns = rng.sample(<int>[for (int i = 1; i < d1; i++) i], 2);
      n1 = ns[0];
      n2 = ns[1];
    }
    final bool primeraMayor = n1 * d2 > n2 * d1;
    final bool preguntaMayor = rng.chance(0.6);
    final String correcto = preguntaMayor == primeraMayor ? 'a' : 'b';
    return ChoiceRound(
      instruction: preguntaMayor ? '¿Qué cantidad de taza es más: $n1/$d1 o $n2/$d2?' : '¿Qué cantidad de taza es menos: $n1/$d1 o $n2/$d2?',
      options: <ChoiceOption>[
        ChoiceOption(id: 'a', label: nombreFraccion(n1, d1), build: (BuildContext context, double size) => _pieConTexto(n1, d1, size)),
        ChoiceOption(id: 'b', label: nombreFraccion(n2, d2), build: (BuildContext context, double size) => _pieConTexto(n2, d2, size)),
      ],
      correctId: correcto,
      hint: mismoNum ? 'Entre más partes se parte la taza, más pequeña es cada parte.' : 'Las dos tazas están partidas igual: gana la que tiene más partes de color.',
      explain: primeraMayor ? '$n1/$d1 es más que $n2/$d2.' : '$n2/$d2 es más que $n1/$d1.',
      optionSize: 110,
    );
  }

  Widget _pieConTexto(int n, int d, double size) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        FractionPie(num: n, den: d, size: size * 0.72),
        const SizedBox(height: 4),
        Text('$n/$d', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      ],
    );
  }

  ChoiceRound _receta(Rng rng) {
    final List<List<dynamic>> ingredientes = <List<dynamic>>[
      <dynamic>['tazas de harina', '1f35e'],
      <dynamic>['huevos', '1f95a'],
      <dynamic>['cucharadas de azúcar', '1f944'],
      <dynamic>['tazas de leche', '1f95b'],
    ];
    final List<dynamic> ing = rng.pick(ingredientes);
    final int base = rng.range(1, 4);
    final int personas = rng.pick(<int>[2, 4]);
    final int factor = rng.pick(<int>[2, 3]);
    final int r = base * factor;
    final Set<int> valores = <int>{r, base + factor, r + personas, r + 1};
    final List<ChoiceOption> options = <ChoiceOption>[for (final int v in valores.take(3)) Opt.number(v)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: 'La receta para $personas personas lleva $base ${ing[0]}. ¿Cuánto necesitas para ${personas * factor} personas?',
      prompt: (BuildContext context) => BigPrompt(child: EmojiImage(ing[1] as String, size: 72), caption: '$base para $personas → ? para ${personas * factor}'),
      options: options,
      correctId: 'n$r',
      hint: '${personas * factor} es $factor veces $personas, así que necesitas $factor veces más de todo.',
      explain: 'Como son $factor veces más personas, se multiplica: $base × $factor = $r.',
    );
  }

  ChoiceRound _equivalente(Rng rng) {
    final List<List<int>> bases = <List<int>>[
      <int>[1, 2],
      <int>[1, 3],
      <int>[1, 4],
      <int>[2, 3],
      <int>[3, 4],
    ];
    final List<int> b = rng.pick(bases);
    final int k = rng.pick(<int>[2, 3]);
    final int num = b[0] * k;
    final int den = b[1] * k;
    final List<ChoiceOption> options = <ChoiceOption>[_pie('ok', num, den, color: PilasColors.azul)];
    final Set<String> usados = <String>{'$num/$den'};
    int guard = 0;
    while (options.length < 3 && guard < 40) {
      guard += 1;
      final int d2 = rng.pick(<int>[4, 6, 8, 9]);
      final int n2 = rng.range(1, d2 - 1);
      if (n2 * b[1] == b[0] * d2 || !usados.add('$n2/$d2')) {
        continue;
      }
      options.add(_pie('d${options.length}', n2, d2, color: PilasColors.azul));
    }
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿Cuál dibujo muestra una fracción equivalente a ${b[0]}/${b[1]}?',
      prompt: (BuildContext context) => BigPrompt(child: FractionPie(num: b[0], den: b[1], size: 100), caption: '${b[0]}/${b[1]}'),
      options: options,
      correctId: 'ok',
      hint: 'Equivalente quiere decir que cubre la misma cantidad del círculo, aunque esté partido en más pedazos.',
      explain: '$num/$den cubre lo mismo que ${b[0]}/${b[1]}: se multiplicaron arriba y abajo por $k.',
      optionSize: 100,
    );
  }

  ChoiceRound _sumaFracciones(Rng rng) {
    final int den = rng.pick(<int>[4, 5, 6, 8]);
    final int a = rng.range(1, den - 2);
    final int b = rng.range(1, den - a - 1);
    final int r = a + b;
    final List<ChoiceOption> options = <ChoiceOption>[_frac('ok', r, den), _frac('d1', r, den * 2), _frac('d2', a * b == r ? r + 1 : (a * b >= den ? r - 1 : a * b), den)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: 'Pilo comió $a/$den de chocolatina en la mañana y $b/$den en la tarde. ¿Cuánto comió en total?',
      prompt: (BuildContext context) => BigPrompt(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FractionBar(num: a, den: den),
            const SizedBox(height: 6),
            const Icon(Icons.add_rounded, color: PilasColors.tinta),
            const SizedBox(height: 6),
            FractionBar(num: b, den: den, color: PilasColors.rosa),
          ],
        ),
      ),
      options: options,
      correctId: 'ok',
      hint: 'Los pedazos son del mismo tamaño ($den partes): solo se suman los de arriba; el de abajo no cambia.',
      explain: '$a/$den + $b/$den = $r/$den. El denominador se queda igual porque los pedazos son iguales.',
    );
  }

  ChoiceRound _fraccionDeReceta(Rng rng) {
    final List<List<int>> fr = <List<int>>[
      <int>[1, 2],
      <int>[1, 4],
      <int>[3, 4],
      <int>[2, 3],
      <int>[1, 3],
    ];
    final List<int> f = rng.pick(fr);
    final int unidad = rng.range(2, 6);
    final int total = unidad * f[1];
    final int r = unidad * f[0];
    final List<ChoiceOption> options = <ChoiceOption>[Opt.number(r), Opt.number(total - r == r ? r + unidad : total - r), Opt.number(unidad == r ? r + 1 : unidad)];
    final Set<String> ids = options.map((ChoiceOption o) => o.id).toSet();
    if (ids.length < 3) {
      options.removeLast();
      options.add(Opt.number(total + 1));
    }
    rng.shuffle(options);
    return ChoiceRound(
      instruction: 'La receta lleva $total cucharadas de azúcar, pero solo quieres hacer ${f[0]}/${f[1]} de la receta. ¿Cuántas cucharadas usas?',
      prompt: (BuildContext context) => BigPrompt(child: FractionPie(num: f[0], den: f[1], size: 96, color: PilasColors.verde), caption: '${f[0]}/${f[1]} de $total'),
      options: options,
      correctId: 'n$r',
      hint: 'Divide $total entre ${f[1]} para saber cuánto vale una parte ($unidad) y multiplica por ${f[0]}.',
      explain: '$total ÷ ${f[1]} = $unidad, y $unidad × ${f[0]} = $r cucharadas.',
    );
  }

  ChoiceRound _compararDistintoDen(Rng rng) {
    final List<List<int>> pares = <List<int>>[
      <int>[2, 3, 3, 5],
      <int>[3, 4, 2, 3],
      <int>[1, 2, 2, 5],
      <int>[5, 8, 1, 2],
      <int>[3, 5, 1, 2],
      <int>[2, 6, 1, 4],
      <int>[2, 4, 1, 2],
      <int>[3, 6, 2, 4],
    ];
    final List<int> p = rng.pick(pares);
    final bool invertir = rng.chance(0.5);
    final int n1 = invertir ? p[2] : p[0];
    final int d1 = invertir ? p[3] : p[1];
    final int n2 = invertir ? p[0] : p[2];
    final int d2 = invertir ? p[1] : p[3];
    final bool primeraMayor = n1 * d2 > n2 * d1;
    final bool iguales = n1 * d2 == n2 * d1;
    return ChoiceRound(
      instruction: '¿Qué cantidad es mayor: $n1/$d1 o $n2/$d2?',
      options: <ChoiceOption>[
        ChoiceOption(id: 'a', label: nombreFraccion(n1, d1), build: (BuildContext context, double size) => _pieConTexto(n1, d1, size)),
        ChoiceOption(id: 'b', label: nombreFraccion(n2, d2), build: (BuildContext context, double size) => _pieConTexto(n2, d2, size)),
        Opt.text('igual', 'Son iguales', fontSize: 20),
      ],
      correctId: iguales ? 'igual' : (primeraMayor ? 'a' : 'b'),
      hint: 'Compara los dibujos: ¿cuál tiene más círculo de color? También puedes pensar cuánto le falta a cada una para llegar a 1.',
      explain: iguales ? '$n1/$d1 y $n2/$d2 cubren lo mismo.' : (primeraMayor ? '$n1/$d1 es mayor que $n2/$d2.' : '$n2/$d2 es mayor que $n1/$d1.'),
      optionSize: 100,
    );
  }
}
