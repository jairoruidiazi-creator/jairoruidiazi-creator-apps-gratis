import 'package:flutter/material.dart';

import '../../core/rng.dart';
import '../../core/theme.dart';
import '../../model/age_band.dart';
import '../choice/choice_round.dart';
import '../choice/option_builders.dart';
import '../shell/math_shapes.dart';
import '../shell/widgets.dart';

/// Constructor de figuras: reconocer formas (3-4), lados y esquinas (5-6),
/// perímetro (7-8) y área (9-11), con figuras dibujadas sobre cuadrícula.
class FigurasGenerator implements ChoiceGenerator {
  static const List<ShapeKind> _basicas = <ShapeKind>[ShapeKind.circle, ShapeKind.square, ShapeKind.triangle, ShapeKind.rectangle, ShapeKind.star, ShapeKind.heart, ShapeKind.oval, ShapeKind.hexagon];

  static int lados(ShapeKind k) {
    switch (k) {
      case ShapeKind.triangle:
        return 3;
      case ShapeKind.square:
      case ShapeKind.rectangle:
        return 4;
      case ShapeKind.hexagon:
        return 6;
      case ShapeKind.star:
        return 10;
      case ShapeKind.circle:
      case ShapeKind.oval:
      case ShapeKind.heart:
        return 0;
    }
  }

  /// Objetos cotidianos con su forma.
  static const List<List<String>> _objetos = <List<String>>[
    <String>['26bd', 'la pelota', 'circle'],
    <String>['1f355', 'la porción de pizza', 'triangle'],
    <String>['1f4d5', 'el libro', 'rectangle'],
    <String>['1f3b2', 'el dado', 'square'],
    <String>['1f95a', 'el huevo', 'oval'],
    <String>['1f6d1', 'la señal de pare', 'hexagon'],
    <String>['1f319', 'la luna llena', 'circle'],
    <String>['1f4f1', 'el celular', 'rectangle'],
    <String>['1f6a9', 'la banderita', 'triangle'],
    <String>['1f4b3', 'la tarjeta', 'rectangle'],
  ];

  static ShapeKind _kindFrom(String s) {
    for (final ShapeKind k in ShapeKind.values) {
      if (k.name == s) {
        return k;
      }
    }
    return ShapeKind.circle;
  }

  @override
  ChoiceRound next(Rng rng, AgeBand band, int level) {
    switch (band) {
      case AgeBand.b3a4:
        if (level <= 2) {
          return _cualEs(rng, level == 1 ? 3 : 4);
        }
        if (level == 3) {
          return _formaDelObjeto(rng);
        }
        return _cuantosLados(rng, <ShapeKind>[ShapeKind.triangle, ShapeKind.square]);
      case AgeBand.b5a6:
        if (level == 1) {
          return _cuantosLados(rng, <ShapeKind>[ShapeKind.triangle, ShapeKind.square, ShapeKind.rectangle, ShapeKind.hexagon]);
        }
        if (level == 2) {
          return _masLados(rng);
        }
        if (level == 3) {
          return _masLargo(rng);
        }
        return _cuantosCuadritos(rng, 2, 3);
      case AgeBand.b7a8:
        if (level == 1) {
          return _cuantosCuadritos(rng, 3, 5);
        }
        if (level == 2) {
          return _perimetroCuadricula(rng, 2, 4);
        }
        if (level == 3) {
          return _perimetroMedidas(rng, 2, 9);
        }
        return _perimetroL(rng);
      case AgeBand.b9a11:
        if (level == 1) {
          return _areaCuadricula(rng, 2, 5);
        }
        if (level == 2) {
          return _areaMedidas(rng);
        }
        if (level == 3) {
          return _areaL(rng);
        }
        return _mismoPerimetro(rng);
    }
  }

  ChoiceOption _shapeOpt(String id, ShapeKind k, NamedColor c) => Opt.shape(id, k, c.color, nombreForma(k));

  ChoiceRound _cualEs(Rng rng, int n) {
    final List<ShapeKind> ks = rng.sample(_basicas.sublist(0, 6), n);
    final ShapeKind objetivo = rng.pick(ks);
    final NamedColor c = rng.pick(NamedColor.basicos);
    final List<ChoiceOption> options = <ChoiceOption>[for (final ShapeKind k in ks) _shapeOpt(k.name, k, c)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿Cuál es el ${nombreForma(objetivo)}?',
      options: options,
      correctId: objetivo.name,
      hint: _pistaForma(objetivo),
      explain: 'Este es el ${nombreForma(objetivo)}. ${_pistaForma(objetivo)}',
      readOptionsAloud: false,
    );
  }

  String _pistaForma(ShapeKind k) {
    switch (k) {
      case ShapeKind.circle:
        return 'El círculo es redondo, como una pelota: no tiene esquinas.';
      case ShapeKind.square:
        return 'El cuadrado tiene cuatro lados iguales y cuatro esquinas.';
      case ShapeKind.triangle:
        return 'El triángulo tiene tres lados y tres puntas.';
      case ShapeKind.rectangle:
        return 'El rectángulo tiene cuatro lados: dos largos y dos cortos.';
      case ShapeKind.star:
        return 'La estrella tiene muchas puntas.';
      case ShapeKind.heart:
        return 'El corazón tiene dos curvas arriba y una punta abajo.';
      case ShapeKind.oval:
        return 'El óvalo es como un círculo estirado, como un huevo.';
      case ShapeKind.hexagon:
        return 'El hexágono tiene seis lados, como una celda de panal.';
    }
  }

  ChoiceRound _formaDelObjeto(Rng rng) {
    final List<String> obj = rng.pick(_objetos);
    final ShapeKind k = _kindFrom(obj[2]);
    final List<ShapeKind> otros = rng.sample(_basicas.where((ShapeKind x) => x != k && !(k == ShapeKind.circle && x == ShapeKind.oval) && !(k == ShapeKind.oval && x == ShapeKind.circle) && !(k == ShapeKind.square && x == ShapeKind.rectangle) && !(k == ShapeKind.rectangle && x == ShapeKind.square)).toList(), 2);
    final NamedColor c = rng.pick(NamedColor.basicos);
    final List<ChoiceOption> options = <ChoiceOption>[_shapeOpt(k.name, k, c), for (final ShapeKind o in otros) _shapeOpt(o.name, o, c)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿Qué forma tiene ${obj[1]}?',
      prompt: (BuildContext context) => BigPrompt(child: EmojiImage(obj[0], size: 90), caption: obj[1]),
      options: options,
      correctId: k.name,
      hint: 'Mira el contorno de ${obj[1]}: ${_pistaForma(k)}',
      explain: '${_cap(obj[1])} tiene forma de ${nombreForma(k)}.',
    );
  }

  String _cap(String t) => t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);

  ChoiceRound _cuantosLados(Rng rng, List<ShapeKind> ks) {
    final ShapeKind k = rng.pick(ks);
    final int n = lados(k);
    final NamedColor c = rng.pick(NamedColor.basicos);
    final Set<int> vals = <int>{n, n - 1, n + 1}..remove(n == 3 ? 2 : -1);
    final List<int> lista = vals.toList();
    if (lista.length < 3) {
      lista.add(n + 2);
    }
    final List<ChoiceOption> options = <ChoiceOption>[for (final int v in lista) Opt.number(v)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿Cuántos lados tiene el ${nombreForma(k)}?',
      prompt: (BuildContext context) => BigPrompt(child: ShapeIcon(kind: k, color: c.color, size: 110)),
      options: options,
      correctId: 'n$n',
      hint: 'Recorre el borde con el dedo y cuenta cada línea recta.',
      explain: 'El ${nombreForma(k)} tiene $n lados.',
      readOptionsAloud: true,
    );
  }

  ChoiceRound _masLados(Rng rng) {
    final List<ShapeKind> ks = rng.sample(<ShapeKind>[ShapeKind.triangle, ShapeKind.square, ShapeKind.hexagon, ShapeKind.rectangle], 2);
    final bool mas = rng.chance(0.5);
    final ShapeKind objetivo = mas ? (lados(ks[0]) >= lados(ks[1]) ? ks[0] : ks[1]) : (lados(ks[0]) <= lados(ks[1]) ? ks[0] : ks[1]);
    if (lados(ks[0]) == lados(ks[1])) {
      return _cuantosLados(rng, ks);
    }
    final NamedColor c = rng.pick(NamedColor.basicos);
    final List<ChoiceOption> options = <ChoiceOption>[for (final ShapeKind k in ks) _shapeOpt(k.name, k, c)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: mas ? '¿Cuál figura tiene más lados?' : '¿Cuál figura tiene menos lados?',
      options: options,
      correctId: objetivo.name,
      hint: 'Cuenta los lados de cada una: ${nombreForma(ks[0])} tiene ${lados(ks[0])} y ${nombreForma(ks[1])} tiene ${lados(ks[1])}.',
      explain: 'El ${nombreForma(objetivo)} tiene ${lados(objetivo)} lados: ${mas ? 'más' : 'menos'} que la otra figura.',
      optionSize: 110,
    );
  }

  ChoiceRound _masLargo(Rng rng) {
    final int a = rng.range(2, 7);
    int b = rng.range(2, 7);
    while (b == a) {
      b = rng.range(2, 7);
    }
    final bool largo = rng.chance(0.5);
    final String correcto = largo ? (a > b ? 'a' : 'b') : (a < b ? 'a' : 'b');
    Widget barra(int n, Color c) => Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            GridFigure(cells: <Offset>[for (int i = 0; i < n; i++) Offset(i.toDouble(), 0)], cols: 7, rows: 1, size: 154, color: c),
          ],
        );
    return ChoiceRound(
      instruction: largo ? '¿Cuál cinta es más larga?' : '¿Cuál cinta es más corta?',
      options: <ChoiceOption>[
        ChoiceOption(id: 'a', label: 'cinta de $a cuadros', build: (BuildContext context, double size) => barra(a, PilasColors.azul)),
        ChoiceOption(id: 'b', label: 'cinta de $b cuadros', build: (BuildContext context, double size) => barra(b, PilasColors.rosa)),
      ],
      columns: 1,
      correctId: correcto,
      hint: 'Cuenta los cuadros de cada cinta: la que tiene más cuadros es más larga.',
      explain: largo ? 'La cinta de ${a > b ? a : b} cuadros es más larga que la de ${a > b ? b : a}.' : 'La cinta de ${a < b ? a : b} cuadros es más corta que la de ${a < b ? b : a}.',
    );
  }

  List<Offset> _rect(int w, int h, {int x = 0, int y = 0}) => <Offset>[
        for (int i = 0; i < w; i++)
          for (int j = 0; j < h; j++) Offset((x + i).toDouble(), (y + j).toDouble()),
      ];

  ChoiceRound _cuantosCuadritos(Rng rng, int min, int max) {
    final int w = rng.range(min, max);
    final int h = rng.range(min, max);
    final int n = w * h;
    final Set<int> vals = <int>{n, n + w, n - h > 0 ? n - h : n + 1, n + 1};
    final List<ChoiceOption> options = <ChoiceOption>[for (final int v in vals.take(3)) Opt.number(v)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿Cuántos cuadritos tiene la figura?',
      prompt: (BuildContext context) => BigPrompt(child: GridFigure(cells: _rect(w, h, x: 1, y: 0), cols: max + 2, rows: max, size: 200, color: PilasColors.naranja)),
      options: options,
      correctId: 'n$n',
      hint: 'Cuenta una fila: tiene $w cuadritos. Hay $h filas iguales.',
      explain: '$h filas de $w cuadritos: $w × $h = $n.',
    );
  }

  ChoiceRound _perimetroCuadricula(Rng rng, int min, int max) {
    final int w = rng.range(min, max);
    final int h = rng.range(min, max);
    final int p = 2 * (w + h);
    final Set<int> vals = <int>{p, w * h == p ? p + 2 : w * h, p - 2, p + 2};
    final List<ChoiceOption> options = <ChoiceOption>[for (final int v in vals.take(3)) Opt.number(v)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: 'Cada lado de cuadrito mide 1 metro. ¿Cuántos metros de cerca necesita el jardín?',
      prompt: (BuildContext context) => BigPrompt(child: GridFigure(cells: _rect(w, h, x: 1, y: 1), cols: max + 3, rows: max + 2, size: 220, color: PilasColors.verde), caption: 'Perímetro: todo el borde'),
      options: options,
      correctId: 'n$p',
      hint: 'El perímetro es la suma de los cuatro lados: $w + $h + $w + $h.',
      explain: 'Perímetro = $w + $h + $w + $h = $p metros.',
    );
  }

  ChoiceRound _perimetroMedidas(Rng rng, int min, int max) {
    final int w = rng.range(min, max);
    final int h = rng.range(min, max);
    final int p = 2 * (w + h);
    final Set<int> vals = <int>{p, w + h, w * h == p || w * h == w + h ? p + 3 : w * h, p + 2};
    final List<ChoiceOption> options = <ChoiceOption>[for (final int v in vals.take(3)) Opt.number(v)];
    rng.shuffle(options);
    final int sw = (w * 5 / max).round().clamp(1, 5).toInt();
    final int sh = (h * 4 / max).round().clamp(1, 4).toInt();
    return ChoiceRound(
      instruction: w == h ? 'Un cuadrado tiene lados de $w cm. ¿Cuánto mide su perímetro?' : 'Un rectángulo mide $w cm de largo y $h cm de ancho. ¿Cuánto mide su perímetro?',
      prompt: (BuildContext context) => BigPrompt(child: GridFigure(cells: _rect(sw, sh, x: 1, y: 1), cols: 7, rows: 6, size: 230, color: PilasColors.azul, showGrid: false, labels: <String, String>{'top': '$w cm', 'left': '$h cm'})),
      options: options,
      correctId: 'n$p',
      hint: w == h ? 'Los cuatro lados miden igual: $w × 4.' : 'Suma los dos largos y los dos anchos: $w + $w + $h + $h.',
      explain: w == h ? '$w × 4 = $p cm.' : '$w + $w + $h + $h = $p cm.',
    );
  }

  ChoiceRound _perimetroL(Rng rng) {
    final int w = rng.range(3, 5);
    final int h = rng.range(3, 5);
    final int cw = rng.range(1, w - 1);
    final int ch = rng.range(1, h - 1);
    final List<Offset> cells = _rect(w, h, x: 1, y: 1).where((Offset c) => !(c.dx >= 1 + w - cw && c.dy < 1 + ch)).toList();
    final int p = 2 * (w + h); // una L tiene el mismo perímetro que su rectángulo envolvente
    final int area = w * h - cw * ch;
    final Set<int> vals = <int>{p, area == p ? p + 2 : area, p - 2, p + 4};
    final List<ChoiceOption> options = <ChoiceOption>[for (final int v in vals.take(3)) Opt.number(v)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: 'Cada lado de cuadrito mide 1 m. ¿Cuánto mide el perímetro de esta figura en L?',
      prompt: (BuildContext context) => BigPrompt(child: GridFigure(cells: cells, cols: 8, rows: 7, size: 220, color: PilasColors.morado)),
      options: options,
      correctId: 'n$p',
      hint: 'Recorre el borde contando cada lado de cuadrito, incluidos los dos lados de la esquina que entra.',
      explain: 'Si empujas la esquina hacia afuera, la L se vuelve un rectángulo de $w por $h con el mismo borde: 2 × ($w + $h) = $p m.',
    );
  }

  ChoiceRound _areaCuadricula(Rng rng, int min, int max) {
    final int w = rng.range(min, max);
    final int h = rng.range(min, max);
    final int a = w * h;
    final int p = 2 * (w + h);
    final Set<int> vals = <int>{a, p == a ? a + 2 : p, a + w, a - 1};
    final List<ChoiceOption> options = <ChoiceOption>[for (final int v in vals.take(3)) Opt.number(v)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: 'Cada cuadrito es 1 m². ¿Cuál es el área del piso?',
      prompt: (BuildContext context) => BigPrompt(child: GridFigure(cells: _rect(w, h, x: 1, y: 1), cols: max + 3, rows: max + 2, size: 220, color: PilasColors.naranja), caption: 'Área: cuántos cuadritos cubre'),
      options: options,
      correctId: 'n$a',
      hint: 'El área es cuántos cuadritos hay adentro: $w en cada fila por $h filas.',
      explain: 'Área = $w × $h = $a m². (El perímetro, el borde, sería $p m: no lo confundas.)',
    );
  }

  ChoiceRound _areaMedidas(Rng rng) {
    final int w = rng.range(3, 12);
    final int h = rng.range(2, 9);
    final int a = w * h;
    final int p = 2 * (w + h);
    final Set<int> vals = <int>{a, p == a ? a + 3 : p, a + h, w + h == a || w + h == p ? a - 2 : w + h};
    final List<ChoiceOption> options = <ChoiceOption>[for (final int v in vals.take(3)) Opt.number(v)];
    rng.shuffle(options);
    final int sw = (w * 5 / 12).round().clamp(1, 5).toInt();
    final int sh = (h * 4 / 9).round().clamp(1, 4).toInt();
    return ChoiceRound(
      instruction: 'Una cancha mide $w m de largo y $h m de ancho. ¿Cuál es su área en metros cuadrados?',
      prompt: (BuildContext context) => BigPrompt(child: GridFigure(cells: _rect(sw, sh, x: 1, y: 1), cols: 7, rows: 6, size: 230, color: PilasColors.verde, showGrid: false, labels: <String, String>{'top': '$w m', 'left': '$h m'})),
      options: options,
      correctId: 'n$a',
      hint: 'Área del rectángulo: largo por ancho.',
      explain: '$w × $h = $a m².',
    );
  }

  ChoiceRound _areaL(Rng rng) {
    final int w = rng.range(4, 6);
    final int h = rng.range(3, 5);
    final int cw = rng.range(1, w - 2);
    final int ch = rng.range(1, h - 1);
    final List<Offset> cells = _rect(w, h, x: 1, y: 1).where((Offset c) => !(c.dx >= 1 + w - cw && c.dy < 1 + ch)).toList();
    final int a = w * h - cw * ch;
    final Set<int> vals = <int>{a, w * h, a - cw, a + ch};
    final List<ChoiceOption> options = <ChoiceOption>[for (final int v in vals.take(3)) Opt.number(v)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: 'Cada cuadrito es 1 m². ¿Cuál es el área de esta figura?',
      prompt: (BuildContext context) => BigPrompt(child: GridFigure(cells: cells, cols: 9, rows: 7, size: 230, color: PilasColors.rosa)),
      options: options,
      correctId: 'n$a',
      hint: 'Parte la figura en dos rectángulos y suma sus áreas, o toma el rectángulo completo ($w × $h) y resta la esquina que falta ($cw × $ch).',
      explain: '$w × $h = ${w * h}, menos la esquina $cw × $ch = ${cw * ch}: $a m².',
    );
  }

  ChoiceRound _mismoPerimetro(Rng rng) {
    // Dos rectángulos con el mismo perímetro y distinta área: el más cuadrado gana.
    final int semi = rng.range(6, 10); // w + h
    final int w1 = rng.range(1, 2);
    final int h1 = semi - w1;
    final int w2 = semi ~/ 2;
    final int h2 = semi - w2;
    final bool preguntaMayor = rng.chance(0.6);
    final String correcto = preguntaMayor ? 'b' : 'a';
    Widget fig(int w, int h, Color c) => GridFigure(cells: _rect(w > 9 ? 9 : w, h > 5 ? 5 : h), cols: 10, rows: 5, size: 170, color: c, labels: <String, String>{'top': '$w', 'left': '$h'});
    return ChoiceRound(
      instruction: 'Las dos cercas usan la misma cantidad de malla (${2 * semi} m). ¿Cuál corral tiene ${preguntaMayor ? 'más' : 'menos'} espacio adentro?',
      options: <ChoiceOption>[
        ChoiceOption(id: 'a', label: 'corral de $w1 por $h1', build: (BuildContext context, double size) => fig(w1, h1, PilasColors.azul)),
        ChoiceOption(id: 'b', label: 'corral de $w2 por $h2', build: (BuildContext context, double size) => fig(w2, h2, PilasColors.verde)),
      ],
      columns: 1,
      correctId: correcto,
      hint: 'Calcula el área de cada uno: $w1 × $h1 y $w2 × $h2. El perímetro igual no quiere decir área igual.',
      explain: 'Áreas: $w1 × $h1 = ${w1 * h1} y $w2 × $h2 = ${w2 * h2}. Con el mismo perímetro, el más parecido a un cuadrado tiene más área.',
    );
  }
}
