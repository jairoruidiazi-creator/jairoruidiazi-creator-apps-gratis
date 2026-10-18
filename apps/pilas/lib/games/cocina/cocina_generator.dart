import 'package:flutter/material.dart';

import '../../content/vocab.dart';
import '../../core/es.dart';
import '../../core/rng.dart';
import '../../core/theme.dart';
import '../../model/age_band.dart';
import '../choice/choice_round.dart';
import '../choice/option_builders.dart';
import '../shell/math_shapes.dart';
import '../shell/widgets.dart';

/// Un ingrediente de receta con su forma en singular y en plural.
class Ingrediente {
  const Ingrediente(this.singular, this.plural, this.genero, this.emoji);

  final String singular;
  final String plural;
  final String genero;
  final String emoji;

  String cantidad(int n) => Es.cantidadEnPalabras(n, singular, genero: genero, pluralForm: plural);
}

/// Cocina de medidas: lleno y vacío, contar huevos y balanza (3-6),
/// fracciones de pizza y de círculos (7-8), fracciones equivalentes y sumas (9-11).
class CocinaGenerator implements ChoiceGenerator {
  /// Peso aproximado en gramos de lo que sale en la balanza. Solo se comparan
  /// cosas que pesan claramente distinto (cuatro veces o más) o casi igual.
  static const Map<String, int> pesos = <String, int>{
    'sandia': 6000, 'pina': 1500, 'melon': 1500, 'coco': 1000, 'mango': 300,
    'manzana': 200, 'naranja': 200, 'pera': 180, 'banano': 150, 'durazno': 150,
    'kiwi': 70, 'limon': 60, 'huevo': 60, 'fresa': 15, 'cereza': 8,
    'balon': 450, 'libro': 350, 'lapiz': 6, 'llave': 15, 'dado': 5, 'cuchara': 30,
    'silla': 4000, 'olla': 1200, 'bicicleta': 12000, 'guitarra': 2500,
    'gato': 4000, 'perro': 15000, 'conejo': 2000, 'raton': 25, 'pajaro': 30,
  };

  static const List<Ingrediente> ingredientes = <Ingrediente>[
    Ingrediente('taza de harina', 'tazas de harina', 'f', '1f33e'),
    Ingrediente('huevo', 'huevos', 'm', '1f95a'),
    Ingrediente('cucharada de azúcar', 'cucharadas de azúcar', 'f', '1f944'),
    Ingrediente('taza de leche', 'tazas de leche', 'f', '1f95b'),
  ];

  @override
  ChoiceRound next(Rng rng, AgeBand band, int level) {
    switch (band) {
      case AgeBand.b3a4:
      case AgeBand.b5a6:
        if (level == 1) {
          return masLleno(rng);
        }
        if (level == 2) {
          return medioVacio(rng);
        }
        if (level == 3) {
          return cuantosHuevos(rng);
        }
        return balanza(rng);
      case AgeBand.b7a8:
        if (level == 1) {
          return queFraccion(rng, <int>[2, 4]);
        }
        if (level == 2) {
          return cualMuestra(rng, <int>[2, 3, 4]);
        }
        if (level == 3) {
          return cualEsMas(rng);
        }
        return receta(rng);
      case AgeBand.b9a11:
        if (level == 1) {
          return equivalente(rng);
        }
        if (level == 2) {
          return sumaFracciones(rng);
        }
        if (level == 3) {
          return fraccionDeReceta(rng);
        }
        return compararDistintoDen(rng);
    }
  }

  static const List<Color> _jugos = <Color>[PilasColors.naranja, PilasColors.rosa, PilasColors.morado, PilasColors.verde];

  ChoiceOption _vaso(String id, double nivel, Color c, String label) {
    return ChoiceOption(id: id, label: label, build: (BuildContext context, double size) => GlassFill(level: nivel, size: size, color: c));
  }

  ChoiceRound masLleno(Rng rng) {
    final bool mas = rng.chance(0.5);
    final List<double> niveles = rng.sample(<double>[0.15, 0.4, 0.65, 0.95], 3)..sort();
    final Color c = rng.pick(_jugos);
    final double objetivo = mas ? niveles.last : niveles.first;
    final List<ChoiceOption> options = <ChoiceOption>[for (int i = 0; i < niveles.length; i++) _vaso('v${(niveles[i] * 100).round()}', niveles[i], c, nombreNivel(niveles[i]))];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: mas ? '¿Cuál vaso tiene más jugo?' : '¿Cuál vaso tiene menos jugo?',
      options: options,
      correctId: 'v${(objetivo * 100).round()}',
      hint: mas ? 'Mira hasta dónde llega el jugo: el que llega más arriba tiene más.' : 'El que tiene el jugo más abajo es el que tiene menos.',
      explain: mas ? 'Este es el que tiene más: el jugo llega más arriba.' : 'Este es el que tiene menos: el jugo llega más abajo.',
    );
  }

  static String nombreNivel(double n) {
    if (n < 0.2) {
      return 'casi vacío';
    }
    if (n < 0.5) {
      return 'con menos de la mitad';
    }
    if (n < 0.8) {
      return 'con más de la mitad';
    }
    return 'lleno';
  }

  ChoiceRound medioVacio(Rng rng) {
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
      hint: tipo == 1 ? 'Por la mitad es cuando el jugo llega justo a la rayita del medio.' : (tipo == 0 ? 'Lleno es cuando el jugo llega hasta arriba.' : 'Vacío es cuando no tiene nada.'),
      explain: 'Este vaso está $nombre.',
    );
  }

  /// Pictograma de lo que se cuenta en [cuantosHuevos]: un huevo entero (está
  /// en [Vocab.unObjeto]).
  static const String huevo = '1f95a';

  /// Cuántos huevos van al tazón de la receta (contar hasta cinco).
  ChoiceRound cuantosHuevos(Rng rng) {
    final int n = rng.range(2, 5);
    final List<ChoiceOption> options = <ChoiceOption>[for (final int o in <int>[n - 1, n, n + 1]) Opt.number(o)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿Cuántos huevos van al tazón?',
      prompt: (BuildContext context) => BigPrompt(
        child: Semantics(
          label: '${Es.cantidadEnPalabras(n, 'huevo', genero: 'm')} y un tazón',
          child: Wrap(spacing: 6, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[for (int i = 0; i < n; i++) const EmojiImage(huevo, size: 44), const SizedBox(width: 12), const EmojiImage('1f963', size: 56)]),
        ),
      ),
      options: options,
      correctId: 'n$n',
      hint: 'Cuenta los huevos uno por uno tocándolos con el dedo.',
      explain: 'Van ${Es.cantidadEnPalabras(n, 'huevo', genero: 'm')} al tazón.',
      readOptionsAloud: true,
    );
  }

  /// Balanza con dos cosas: el platillo que baja es el que pesa más; si
  /// queda derecha, pesan lo mismo. Tres opciones: izquierda, derecha o igual.
  ChoiceRound balanza(Rng rng) {
    final List<String> ids = pesos.keys.toList();
    VocabItem? a;
    VocabItem? b;
    int signo = 0;
    for (int intento = 0; intento < 200 && a == null; intento++) {
      final List<String> par = rng.sample(ids, 2);
      final int pa = pesos[par[0]]!;
      final int pb = pesos[par[1]]!;
      final double ratio = pa > pb ? pa / pb : pb / pa;
      if (ratio >= 4) {
        signo = pa > pb ? -1 : 1;
      } else if (ratio <= 1.2) {
        signo = 0;
      } else {
        continue;
      }
      a = Vocab.item(par[0]);
      b = Vocab.item(par[1]);
    }
    final VocabItem izq = a ?? Vocab.item('sandia');
    final VocabItem der = b ?? Vocab.item('fresa');
    if (a == null) {
      signo = -1;
    }
    final bool preguntaMas = rng.chance(0.5);
    String correcto;
    if (signo == 0) {
      correcto = 'igual';
    } else if (preguntaMas) {
      correcto = signo < 0 ? 'izq' : 'der';
    } else {
      correcto = signo < 0 ? 'der' : 'izq';
    }
    final VocabItem pesado = signo < 0 ? izq : der;
    final VocabItem liviano = signo < 0 ? der : izq;
    final String explicacion = signo == 0
        ? '${Es.cap(izq.conArticulo)} y ${der.conArticulo} pesan lo mismo: la balanza queda derecha.'
        : (preguntaMas
            ? '${Es.cap(pesado.conArticulo)} ${pesado.verbo('pesa', 'pesan')} más que ${liviano.conArticulo}: su platillo baja.'
            : '${Es.cap(liviano.conArticulo)} ${liviano.verbo('pesa', 'pesan')} menos que ${pesado.conArticulo}: su platillo sube.');
    return ChoiceRound(
      instruction: preguntaMas ? '¿Qué pesa más?' : '¿Qué pesa menos?',
      prompt: (BuildContext context) => BigPrompt(
        child: Semantics(
          label: 'Balanza con ${izq.conArticulo} a la izquierda y ${der.conArticulo} a la derecha',
          child: Balance(heavier: signo, left: EmojiImage(izq.emoji, size: 40), right: EmojiImage(der.emoji, size: 40)),
        ),
      ),
      options: <ChoiceOption>[
        ChoiceOption(id: 'izq', label: izq.nombre, build: (BuildContext context, double size) => EmojiImage(izq.emoji, size: size, semanticsLabel: izq.nombre)),
        ChoiceOption(id: 'der', label: der.nombre, build: (BuildContext context, double size) => EmojiImage(der.emoji, size: size, semanticsLabel: der.nombre)),
        Opt.textWithEmoji('igual', 'Pesan lo mismo', '2696'),
      ],
      correctId: correcto,
      hint: 'En la balanza, el platillo que baja es el que pesa más. Si queda derecha, pesan lo mismo.',
      explain: explicacion,
      readOptionsAloud: true,
    );
  }

  ChoiceOption _pie(String id, int num, int den, {Color color = PilasColors.naranja}) {
    return ChoiceOption(id: id, label: Es.fraccion(num, den), build: (BuildContext context, double size) => FractionPie(num: num, den: den, size: size, color: color));
  }

  ChoiceOption _frac(String id, int num, int den) => Opt.text(id, '$num/$den', fontSize: 34, label: Es.fraccion(num, den));

  /// Se muestra una pizza con porciones comidas; se elige la fracción escrita.
  ChoiceRound queFraccion(Rng rng, List<int> dens) {
    final int den = rng.pick(dens);
    final int num = rng.range(1, den - 1);
    final Set<String> ids = <String>{'$num/$den'};
    final List<ChoiceOption> options = <ChoiceOption>[_frac('$num/$den', num, den)];
    int guard = 0;
    while (options.length < 3 && guard < 60) {
      guard += 1;
      final int d2 = rng.pick(<int>[2, 3, 4, 6, 8]);
      final int n2 = rng.range(1, d2 - 1);
      if (n2 * den != num * d2 && ids.add('$n2/$d2')) {
        options.add(_frac('$n2/$d2', n2, d2));
      }
    }
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿Qué fracción de la pizza se comieron?',
      prompt: (BuildContext context) => BigPrompt(child: FractionPie(num: num, den: den, size: 120), caption: 'Las porciones de color ya se comieron'),
      options: options,
      correctId: '$num/$den',
      hint: 'El número de abajo dice en cuántas porciones iguales está partida la pizza; el de arriba, cuántas se comieron.',
      explain: 'La pizza está en ${Es.cantidadEnPalabras(den, 'porción', genero: 'f')} y se comieron ${Es.numero(num, femenino: true)}: ${Es.fraccion(num, den)}, $num/$den.',
    );
  }

  /// Se da la fracción y se elige el dibujo.
  ChoiceRound cualMuestra(Rng rng, List<int> dens) {
    final int den = rng.pick(dens);
    final int num = rng.range(1, den - 1);
    final List<ChoiceOption> options = <ChoiceOption>[_pie('ok', num, den)];
    final Set<String> usados = <String>{'$num/$den'};
    int guard = 0;
    while (options.length < 3 && guard < 60) {
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
      instruction: '¿Cuál dibujo muestra $num/$den?',
      spoken: '¿Cuál dibujo muestra ${Es.fraccion(num, den)}?',
      options: options,
      correctId: 'ok',
      hint: 'Cuenta primero en cuántas partes iguales está partido cada círculo.',
      explain: 'Este círculo está partido en ${Es.cantidadEnPalabras(den, 'parte', genero: 'f')} y tiene ${Es.numero(num, femenino: true)} de color: $num/$den.',
      optionSize: 100,
    );
  }

  Widget _pieConTexto(BuildContext context, int n, int d, double size) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        FractionPie(num: n, den: d, size: size * 0.72),
        const SizedBox(height: 4),
        Text('$n/$d', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: PilasPalette.of(context).tinta)),
      ],
    );
  }

  /// Tres fracciones con el mismo numerador o el mismo denominador: ¿cuál es
  /// la más grande (o la más pequeña)?
  ChoiceRound cualEsMas(Rng rng) {
    final bool mismoNum = rng.chance(0.5);
    final List<List<int>> fr;
    if (mismoNum) {
      final List<int> ds = rng.sample(<int>[2, 3, 4, 6, 8], 3);
      fr = <List<int>>[for (final int d in ds) <int>[1, d]];
    } else {
      final int d = rng.pick(<int>[4, 6, 8]);
      final List<int> ns = rng.sample(<int>[for (int i = 1; i < d; i++) i], 3);
      fr = <List<int>>[for (final int n in ns) <int>[n, d]];
    }
    final bool mayor = rng.chance(0.6);
    final List<List<int>> orden = List<List<int>>.from(fr)..sort((List<int> x, List<int> y) => (x[0] * y[1]).compareTo(y[0] * x[1]));
    final List<int> objetivo = mayor ? orden.last : orden.first;
    final List<ChoiceOption> options = <ChoiceOption>[
      for (final List<int> f in fr) ChoiceOption(id: '${f[0]}/${f[1]}', label: Es.fraccion(f[0], f[1]), build: (BuildContext context, double size) => _pieConTexto(context, f[0], f[1], size)),
    ];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: mayor ? '¿Qué fracción es la más grande?' : '¿Qué fracción es la más pequeña?',
      options: options,
      correctId: '${objetivo[0]}/${objetivo[1]}',
      hint: mismoNum ? 'Todas tienen una sola parte de color: entre más partes tenga el círculo, más pequeña es cada parte.' : 'Los tres círculos están partidos igual: mira cuántas partes de color tiene cada uno.',
      explain: '${objetivo[0]}/${objetivo[1]} es la ${mayor ? 'más grande' : 'más pequeña'}.',
      optionSize: 110,
    );
  }

  ChoiceRound receta(Rng rng) {
    final Ingrediente ing = rng.pick(ingredientes);
    final int base = rng.range(1, 4);
    final int personas = rng.pick(<int>[2, 4]);
    final int factor = rng.pick(<int>[2, 3]);
    final int r = base * factor;
    final List<int> valores = <int>{r, base + factor, r + personas, r + 1}.where((int v) => v > 0).take(3).toList();
    final List<ChoiceOption> options = <ChoiceOption>[for (final int v in valores) Opt.number(v)];
    rng.shuffle(options);
    final String gente = Es.cantidadEnPalabras(personas * factor, 'persona', genero: 'f');
    return ChoiceRound(
      instruction: 'La receta para ${Es.cantidadEnPalabras(personas, 'persona', genero: 'f')} lleva ${ing.cantidad(base)}. ¿${ing.genero == 'f' ? 'Cuántas' : 'Cuántos'} ${ing.plural} necesitas para $gente?',
      prompt: (BuildContext context) => BigPrompt(child: EmojiImage(ing.emoji, size: 72), caption: '$base para $personas → ? para ${personas * factor}'),
      options: options,
      correctId: 'n$r',
      hint: 'Piensa cuántas veces cabe el grupo de ${Es.numero(personas, femenino: true)} personas en el grupo nuevo, y multiplica.',
      explain: 'Son ${Es.numero(factor, femenino: true)} veces más personas: ${Es.numero(base)} por ${Es.numero(factor)} es ${Es.numero(r)}.',
    );
  }

  ChoiceRound equivalente(Rng rng) {
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
    while (options.length < 3 && guard < 60) {
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
      spoken: '¿Cuál dibujo muestra una fracción equivalente a ${Es.fraccion(b[0], b[1])}?',
      prompt: (BuildContext context) => BigPrompt(child: FractionPie(num: b[0], den: b[1], size: 100), caption: '${b[0]}/${b[1]}'),
      options: options,
      correctId: 'ok',
      hint: 'Equivalente quiere decir que cubre la misma cantidad del círculo, aunque esté partido en más pedazos.',
      explain: '$num/$den cubre lo mismo que ${b[0]}/${b[1]}: se multiplicaron por ${Es.numero(k)} el número de arriba y el de abajo.',
      optionSize: 100,
    );
  }

  ChoiceRound sumaFracciones(Rng rng) {
    final int den = rng.pick(<int>[4, 5, 6, 8]);
    final int a = rng.range(1, den - 2);
    final int b = rng.range(1, den - a - 1);
    final int r = a + b;
    final int tercero = a != b ? (a - b).abs() : (r + 1 < den ? r + 1 : r - 1);
    final List<ChoiceOption> options = <ChoiceOption>[_frac('ok', r, den), _frac('d1', r, den * 2), _frac('d2', tercero, den)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: 'Pilo comió $a/$den de una chocolatina en la mañana y $b/$den en la tarde. ¿Cuánto comió en total?',
      spoken: 'Pilo comió ${Es.fraccion(a, den)} de una chocolatina en la mañana y ${Es.fraccion(b, den)} en la tarde. ¿Cuánto comió en total?',
      prompt: (BuildContext context) => BigPrompt(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FractionBar(num: a, den: den),
            const SizedBox(height: 6),
            Icon(Icons.add_rounded, color: PilasPalette.of(context).tinta),
            const SizedBox(height: 6),
            FractionBar(num: b, den: den, color: PilasColors.rosa),
          ],
        ),
      ),
      options: options,
      correctId: 'ok',
      hint: 'Los pedazos son del mismo tamaño: solo se suman los de arriba; el número de abajo no cambia.',
      explain: '$a/$den + $b/$den = $r/$den. El denominador se queda igual porque los pedazos son iguales.',
    );
  }

  ChoiceRound fraccionDeReceta(Rng rng) {
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
    final List<int> valores = <int>[r];
    for (final int v in <int>[total - r, unidad, total, r + unidad, r + 1]) {
      if (valores.length < 3 && v > 0 && !valores.contains(v)) {
        valores.add(v);
      }
    }
    final List<ChoiceOption> options = <ChoiceOption>[for (final int v in valores) Opt.number(v)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: 'La receta lleva $total cucharadas de azúcar, pero solo quieres hacer ${f[0]}/${f[1]} de la receta. ¿Cuántas cucharadas usas?',
      spoken: 'La receta lleva $total cucharadas de azúcar, pero solo quieres hacer ${f[0] == 1 && f[1] == 2 ? 'la mitad' : Es.fraccion(f[0], f[1])} de la receta. ¿Cuántas cucharadas usas?',
      prompt: (BuildContext context) => BigPrompt(child: FractionPie(num: f[0], den: f[1], size: 96, color: PilasColors.verde), caption: '${f[0]}/${f[1]} de $total'),
      options: options,
      correctId: 'n$r',
      hint: 'Divide $total entre ${f[1]} para saber cuánto vale una parte, y multiplica por ${f[0]}.',
      explain: '$total ÷ ${f[1]} = $unidad, y $unidad × ${f[0]} = $r cucharadas.',
    );
  }

  ChoiceRound compararDistintoDen(Rng rng) {
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
    final List<ChoiceOption> options = <ChoiceOption>[
      ChoiceOption(id: 'a', label: Es.fraccion(n1, d1), build: (BuildContext context, double size) => _pieConTexto(context, n1, d1, size)),
      ChoiceOption(id: 'b', label: Es.fraccion(n2, d2), build: (BuildContext context, double size) => _pieConTexto(context, n2, d2, size)),
      Opt.text('igual', 'Son iguales', fontSize: 22),
    ];
    return ChoiceRound(
      instruction: '¿Qué cantidad es mayor: $n1/$d1 o $n2/$d2?',
      spoken: '¿Qué cantidad es mayor: ${Es.fraccion(n1, d1)} ${Es.o(Es.fraccion(n2, d2))} ${Es.fraccion(n2, d2)}?',
      options: options,
      correctId: iguales ? 'igual' : (primeraMayor ? 'a' : 'b'),
      hint: 'Compara los dibujos: ¿cuál tiene más círculo de color? También puedes pensar cuánto le falta a cada una para llegar a uno.',
      explain: iguales ? '$n1/$d1 y $n2/$d2 cubren lo mismo.' : (primeraMayor ? '$n1/$d1 es mayor que $n2/$d2.' : '$n2/$d2 es mayor que $n1/$d1.'),
      optionSize: 100,
    );
  }
}
