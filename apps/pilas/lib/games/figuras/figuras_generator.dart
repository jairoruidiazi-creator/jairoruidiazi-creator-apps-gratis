import 'package:flutter/material.dart';

import '../../core/es.dart';
import '../../core/rng.dart';
import '../../core/theme.dart';
import '../../model/age_band.dart';
import '../choice/choice_round.dart';
import '../choice/option_builders.dart';
import '../shell/math_shapes.dart';
import '../shell/widgets.dart';

/// Un objeto cotidiano y la forma que tiene (vista de frente en su pictograma).
class ObjetoForma {
  const ObjetoForma(this.emoji, this.nombre, this.genero, this.forma);

  final String emoji;
  final String nombre;
  final String genero;
  final ShapeKind forma;

  String get conArticulo => '${Es.articulo(genero)} $nombre';
}

/// Figuras y medidas: reconocer formas (3-4), lados y longitudes (5-6),
/// perímetro (7-8) y área (9-11), con figuras dibujadas sobre cuadrícula.
class FigurasGenerator implements ChoiceGenerator {
  static const List<ShapeKind> _basicas = <ShapeKind>[ShapeKind.circle, ShapeKind.square, ShapeKind.triangle, ShapeKind.rectangle, ShapeKind.star, ShapeKind.heart];

  /// Figuras con lados rectos, para contarlos.
  static const List<ShapeKind> _poligonos = <ShapeKind>[ShapeKind.triangle, ShapeKind.square, ShapeKind.pentagon, ShapeKind.hexagon, ShapeKind.octagon];

  static int lados(ShapeKind k) {
    switch (k) {
      case ShapeKind.triangle:
        return 3;
      case ShapeKind.square:
      case ShapeKind.rectangle:
        return 4;
      case ShapeKind.pentagon:
        return 5;
      case ShapeKind.hexagon:
        return 6;
      case ShapeKind.octagon:
        return 8;
      case ShapeKind.star:
        return 10;
      case ShapeKind.circle:
      case ShapeKind.oval:
      case ShapeKind.heart:
        return 0;
    }
  }

  /// Objetos cotidianos con su forma (revisados uno por uno contra su
  /// pictograma: la señal de pare es un octágono; la luna llena, un círculo).
  static const List<ObjetoForma> objetos = <ObjetoForma>[
    ObjetoForma('26bd', 'pelota', 'f', ShapeKind.circle),
    ObjetoForma('1fa99', 'moneda', 'f', ShapeKind.circle),
    ObjetoForma('1f315', 'luna llena', 'f', ShapeKind.circle),
    ObjetoForma('1f36a', 'galleta', 'f', ShapeKind.circle),
    ObjetoForma('1f355', 'porción de pizza', 'f', ShapeKind.triangle),
    ObjetoForma('1f6a9', 'banderita', 'f', ShapeKind.triangle),
    ObjetoForma('26a0', 'señal de cuidado', 'f', ShapeKind.triangle),
    ObjetoForma('1f4c5', 'hoja del calendario', 'f', ShapeKind.square),
    ObjetoForma('1f381', 'caja de regalo', 'f', ShapeKind.square),
    ObjetoForma('1f4f1', 'celular', 'm', ShapeKind.rectangle),
    ObjetoForma('1f6aa', 'puerta', 'f', ShapeKind.rectangle),
    ObjetoForma('1f4b3', 'tarjeta', 'f', ShapeKind.rectangle),
    ObjetoForma('1f95a', 'huevo', 'm', ShapeKind.oval),
    ObjetoForma('1f6d1', 'señal de pare', 'f', ShapeKind.octagon),
  ];

  @override
  ChoiceRound next(Rng rng, AgeBand band, int level) {
    switch (band) {
      case AgeBand.b3a4:
        if (level <= 2) {
          return cualEs(rng, level == 1 ? 3 : 4);
        }
        if (level == 3) {
          return formaDelObjeto(rng);
        }
        return cuantosLados(rng, <ShapeKind>[ShapeKind.triangle, ShapeKind.square]);
      case AgeBand.b5a6:
        if (level == 1) {
          return cuantosLados(rng, _poligonos);
        }
        if (level == 2) {
          return masLados(rng);
        }
        if (level == 3) {
          return masLarga(rng);
        }
        return cuantosCuadritos(rng, 2, 3);
      case AgeBand.b7a8:
        if (level == 1) {
          return cuantosCuadritos(rng, 3, 5);
        }
        if (level == 2) {
          return perimetroCuadricula(rng, 2, 4);
        }
        if (level == 3) {
          return perimetroMedidas(rng, 2, 9);
        }
        return perimetroL(rng);
      case AgeBand.b9a11:
        if (level == 1) {
          return areaCuadricula(rng, 2, 5);
        }
        if (level == 2) {
          return areaMedidas(rng);
        }
        if (level == 3) {
          return areaL(rng);
        }
        return mismoPerimetro(rng);
    }
  }

  ChoiceOption _shapeOpt(ShapeKind k, NamedColor c) => Opt.shape(k.name, k, c, nombreForma(k));

  static String elNombre(ShapeKind k) => '${Es.articulo(generoForma(k))} ${nombreForma(k)}';

  static String unNombre(ShapeKind k) => '${Es.articulo(generoForma(k), definido: false)} ${nombreForma(k)}';

  ChoiceRound cualEs(Rng rng, int n) {
    final List<ShapeKind> ks = rng.sample(_basicas, n);
    final ShapeKind objetivo = rng.pick(ks);
    final NamedColor c = rng.pick(NamedColor.basicos);
    final List<ChoiceOption> options = <ChoiceOption>[for (final ShapeKind k in ks) _shapeOpt(k, c)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿Cuál es ${elNombre(objetivo)}?',
      options: options,
      correctId: objetivo.name,
      hint: pistaForma(objetivo),
      explain: 'Este es ${elNombre(objetivo)}. ${pistaForma(objetivo)}',
      praise: Es.cap('${elNombre(objetivo)}.'),
    );
  }

  static String pistaForma(ShapeKind k) {
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
        return 'La estrella tiene cinco puntas.';
      case ShapeKind.heart:
        return 'El corazón tiene dos curvas arriba y una punta abajo.';
      case ShapeKind.oval:
        return 'El óvalo es como un círculo estirado, como un huevo.';
      case ShapeKind.pentagon:
        return 'El pentágono tiene cinco lados.';
      case ShapeKind.hexagon:
        return 'El hexágono tiene seis lados, como una celda de un panal.';
      case ShapeKind.octagon:
        return 'El octágono tiene ocho lados, como la señal de pare.';
    }
  }

  ChoiceRound formaDelObjeto(Rng rng) {
    final ObjetoForma obj = rng.pick(objetos);
    final ShapeKind k = obj.forma;
    bool parecida(ShapeKind x) {
      // Formas que se confunden con la correcta no salen como distractor.
      const List<List<ShapeKind>> pares = <List<ShapeKind>>[
        <ShapeKind>[ShapeKind.circle, ShapeKind.oval],
        <ShapeKind>[ShapeKind.square, ShapeKind.rectangle],
        <ShapeKind>[ShapeKind.octagon, ShapeKind.circle],
        <ShapeKind>[ShapeKind.octagon, ShapeKind.hexagon],
        <ShapeKind>[ShapeKind.octagon, ShapeKind.pentagon],
      ];
      return pares.any((List<ShapeKind> p) => p.contains(k) && p.contains(x));
    }

    final List<ShapeKind> candidatos = <ShapeKind>[..._basicas, ShapeKind.oval].where((ShapeKind x) => x != k && !parecida(x)).toList();
    final List<ShapeKind> otros = rng.sample(candidatos, 2);
    final NamedColor c = rng.pick(NamedColor.basicos);
    final List<ChoiceOption> options = <ChoiceOption>[_shapeOpt(k, c), for (final ShapeKind o in otros) _shapeOpt(o, c)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿Qué forma tiene ${obj.conArticulo}?',
      prompt: (BuildContext context) => BigPrompt(child: EmojiImage(obj.emoji, size: 90, semanticsLabel: obj.nombre), caption: obj.nombre),
      options: options,
      correctId: k.name,
      hint: 'Mira el borde ${Es.deEl(obj.genero, obj.nombre)} y pásale el dedo alrededor.',
      explain: '${Es.cap(obj.conArticulo)} tiene forma de ${nombreForma(k)}. ${pistaForma(k)}',
      praise: '${Es.cap(obj.conArticulo)} tiene forma de ${nombreForma(k)}.',
    );
  }

  ChoiceRound cuantosLados(Rng rng, List<ShapeKind> ks) {
    final ShapeKind k = rng.pick(ks);
    final int n = lados(k);
    final NamedColor c = rng.pick(NamedColor.basicos);
    final List<int> lista = <int>[n - 1, n, n + 1];
    final List<ChoiceOption> options = <ChoiceOption>[for (final int v in lista) Opt.number(v)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿Cuántos lados tiene ${elNombre(k)}?',
      prompt: (BuildContext context) => BigPrompt(child: ShapeIcon(kind: k, color: c.color, size: 110, mark: c.mark)),
      options: options,
      correctId: 'n$n',
      hint: 'Recorre el borde con el dedo y cuenta cada línea recta.',
      explain: '${Es.cap(elNombre(k))} tiene ${Es.cantidadEnPalabras(n, 'lado', genero: 'm')}.',
      praise: Es.cap('${Es.cantidadEnPalabras(n, 'lado', genero: 'm')}.'),
      readOptionsAloud: true,
    );
  }

  /// Tres figuras con distinto número de lados: la que tiene más (o menos).
  ChoiceRound masLados(Rng rng) {
    final List<ShapeKind> ks = rng.sample(_poligonos, 3);
    final bool mas = rng.chance(0.5);
    final List<ShapeKind> orden = List<ShapeKind>.from(ks)..sort((ShapeKind a, ShapeKind b) => lados(a).compareTo(lados(b)));
    final ShapeKind objetivo = mas ? orden.last : orden.first;
    final NamedColor c = rng.pick(NamedColor.basicos);
    final List<ChoiceOption> options = <ChoiceOption>[for (final ShapeKind k in ks) _shapeOpt(k, c)];
    rng.shuffle(options);
    final String cuenta = Es.listaY(<String>[for (final ShapeKind k in orden) '${elNombre(k)} tiene ${lados(k)}']);
    return ChoiceRound(
      instruction: mas ? '¿Cuál figura tiene más lados?' : '¿Cuál figura tiene menos lados?',
      options: options,
      correctId: objetivo.name,
      hint: 'Cuenta los lados de cada figura con el dedo.',
      explain: 'Contando los lados: ${Es.contraer(cuenta)}. ${Es.cap(elNombre(objetivo))} tiene ${mas ? 'más' : 'menos'}.',
      praise: '${Es.cap(elNombre(objetivo))} tiene ${Es.cantidadEnPalabras(lados(objetivo), 'lado', genero: 'm')}.',
      optionSize: 110,
    );
  }

  /// Tres cintas de distinto largo: la más larga (o la más corta).
  ChoiceRound masLarga(Rng rng) {
    final List<int> largos = rng.sample(<int>[2, 3, 4, 5, 6, 7], 3);
    final bool larga = rng.chance(0.5);
    final List<int> orden = List<int>.from(largos)..sort();
    final int objetivo = larga ? orden.last : orden.first;
    const List<Color> colores = <Color>[PilasColors.azul, PilasColors.rosa, PilasColors.verde];
    Widget barra(int n, Color c, double size) => SizedBox(
          width: size * 1.8,
          child: GridFigure(cells: <Offset>[for (int i = 0; i < n; i++) Offset(i.toDouble(), 0)], cols: 7, rows: 1, size: size * 1.8, color: c),
        );
    final List<ChoiceOption> options = <ChoiceOption>[
      for (int i = 0; i < 3; i++)
        ChoiceOption(
          id: 'c${largos[i]}',
          label: 'cinta de ${Es.cantidadEnPalabras(largos[i], 'cuadro', genero: 'm')}',
          build: (BuildContext context, double size) => barra(largos[i], colores[i], size),
        ),
    ];
    rng.shuffle(options);
    final String de = Es.cantidadEnPalabras(objetivo, 'cuadro', genero: 'm');
    return ChoiceRound(
      instruction: larga ? '¿Cuál cinta es la más larga?' : '¿Cuál cinta es la más corta?',
      options: options,
      columns: 1,
      optionAspect: 3.0,
      correctId: 'c$objetivo',
      hint: 'Cuenta los cuadros de cada cinta: la que tiene más cuadros es más larga.',
      explain: larga ? 'La cinta de $de es la más larga.' : 'La cinta de $de es la más corta.',
    );
  }

  List<Offset> _rect(int w, int h, {int x = 0, int y = 0}) => <Offset>[
        for (int i = 0; i < w; i++)
          for (int j = 0; j < h; j++) Offset((x + i).toDouble(), (y + j).toDouble()),
      ];

  /// Tres valores distintos y positivos alrededor del correcto.
  static List<int> tresOpciones(Rng rng, int correcto, List<int> errores) {
    final List<int> out = <int>[correcto];
    for (final int e in errores) {
      if (out.length == 3) {
        break;
      }
      if (e > 0 && !out.contains(e)) {
        out.add(e);
      }
    }
    int k = 1;
    while (out.length < 3) {
      final int v = correcto + k;
      if (!out.contains(v)) {
        out.add(v);
      }
      k = k > 0 ? -k : -k + 1;
    }
    return out;
  }

  ChoiceRound cuantosCuadritos(Rng rng, int min, int max) {
    final int w = rng.range(min, max);
    final int h = rng.range(min, max);
    final int n = w * h;
    final List<ChoiceOption> options = <ChoiceOption>[for (final int v in tresOpciones(rng, n, <int>[n + w, n - h, n + 1])) Opt.number(v)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿Cuántos cuadritos tiene la figura?',
      prompt: (BuildContext context) => BigPrompt(child: GridFigure(cells: _rect(w, h, x: 1, y: 0), cols: max + 2, rows: max, size: 200, color: PilasColors.naranja)),
      options: options,
      correctId: 'n$n',
      hint: 'Cuenta los cuadritos de una fila y cuántas filas hay.',
      explain: 'Hay ${Es.cantidadEnPalabras(h, 'fila', genero: 'f')} de ${Es.cantidadEnPalabras(w, 'cuadrito', genero: 'm')}: $n cuadritos.',
      readOptionsAloud: true,
    );
  }

  ChoiceRound perimetroCuadricula(Rng rng, int min, int max) {
    final int w = rng.range(min, max);
    final int h = rng.range(min, max);
    final int p = 2 * (w + h);
    final List<ChoiceOption> options = <ChoiceOption>[for (final int v in tresOpciones(rng, p, <int>[w * h, w + h, p + 2])) Opt.number(v)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: 'Cada lado de un cuadrito mide 1 metro. ¿Cuántos metros de cerca necesita el jardín?',
      prompt: (BuildContext context) => BigPrompt(child: GridFigure(cells: _rect(w, h, x: 1, y: 1), cols: max + 3, rows: max + 2, size: 220, color: PilasColors.verde), caption: 'Perímetro: todo el borde'),
      options: options,
      correctId: 'n$p',
      hint: 'El perímetro es la suma de los cuatro lados: cuenta los lados de cuadrito de todo el borde.',
      explain: 'Perímetro = $w + $h + $w + $h = $p metros.',
    );
  }

  ChoiceRound perimetroMedidas(Rng rng, int min, int max) {
    final int a = rng.range(min, max);
    final int b = rng.range(min, max);
    final int w = a >= b ? a : b;
    final int h = a >= b ? b : a;
    final int p = 2 * (w + h);
    final List<ChoiceOption> options = <ChoiceOption>[for (final int v in tresOpciones(rng, p, <int>[w + h, w * h, p + 2])) Opt.number(v)];
    rng.shuffle(options);
    final int sw = (w * 5 / max).round().clamp(1, 5).toInt();
    final int sh = (h * 4 / max).round().clamp(1, 4).toInt();
    return ChoiceRound(
      instruction: w == h ? 'Un cuadrado tiene lados de $w cm. ¿Cuánto mide su perímetro?' : 'Un rectángulo mide $w cm de largo y $h cm de ancho. ¿Cuánto mide su perímetro?',
      prompt: (BuildContext context) => BigPrompt(child: GridFigure(cells: _rect(sw, sh, x: 1, y: 1), cols: 7, rows: 6, size: 230, color: PilasColors.azul, showGrid: false, labels: <String, String>{'top': '$w cm', 'left': '$h cm'})),
      options: options,
      correctId: 'n$p',
      hint: w == h ? 'Los cuatro lados miden igual: suma cuatro veces $w.' : 'Suma los dos largos y los dos anchos.',
      explain: w == h ? '$w × 4 = $p cm.' : '$w + $w + $h + $h = $p cm.',
    );
  }

  ChoiceRound perimetroL(Rng rng) {
    final int w = rng.range(3, 5);
    final int h = rng.range(3, 5);
    final int cw = rng.range(1, w - 1);
    final int ch = rng.range(1, h - 1);
    final List<Offset> cells = _rect(w, h, x: 1, y: 1).where((Offset c) => !(c.dx >= 1 + w - cw && c.dy < 1 + ch)).toList();
    final int p = 2 * (w + h); // una L tiene el mismo perímetro que su rectángulo envolvente
    final int area = w * h - cw * ch;
    final List<ChoiceOption> options = <ChoiceOption>[for (final int v in tresOpciones(rng, p, <int>[area, p - 2, p + 4])) Opt.number(v)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: 'Cada lado de un cuadrito mide 1 m. ¿Cuánto mide el perímetro de esta figura en L?',
      prompt: (BuildContext context) => BigPrompt(child: GridFigure(cells: cells, cols: 8, rows: 7, size: 220, color: PilasColors.morado)),
      options: options,
      correctId: 'n$p',
      hint: 'Recorre el borde contando cada lado de cuadrito, también los dos lados de la esquina que entra.',
      explain: 'Si empujas la esquina hacia afuera, la L se vuelve un rectángulo de $w por $h con el mismo borde: 2 × ($w + $h) = $p m.',
    );
  }

  ChoiceRound areaCuadricula(Rng rng, int min, int max) {
    final int w = rng.range(min, max);
    final int h = rng.range(min, max);
    final int a = w * h;
    final int p = 2 * (w + h);
    final List<ChoiceOption> options = <ChoiceOption>[for (final int v in tresOpciones(rng, a, <int>[p, a + w, a - 1])) Opt.number(v)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: 'Cada cuadrito es 1 m². ¿Cuál es el área del piso?',
      prompt: (BuildContext context) => BigPrompt(child: GridFigure(cells: _rect(w, h, x: 1, y: 1), cols: max + 3, rows: max + 2, size: 220, color: PilasColors.naranja), caption: 'Área: cuántos cuadritos cubre'),
      options: options,
      correctId: 'n$a',
      hint: 'El área es cuántos cuadritos hay adentro: cuántos hay en cada fila por cuántas filas.',
      explain: 'Área = $w × $h = $a m². El perímetro, el borde, sería $p m: no son lo mismo.',
    );
  }

  ChoiceRound areaMedidas(Rng rng) {
    final int w = rng.range(4, 12);
    final int h = rng.range(2, w - 1);
    final int a = w * h;
    final int p = 2 * (w + h);
    final List<ChoiceOption> options = <ChoiceOption>[for (final int v in tresOpciones(rng, a, <int>[p, w + h, a + h])) Opt.number(v)];
    rng.shuffle(options);
    final int sw = (w * 5 / 12).round().clamp(1, 5).toInt();
    final int sh = (h * 4 / 12).round().clamp(1, 4).toInt();
    return ChoiceRound(
      instruction: 'Una cancha mide $w m de largo y $h m de ancho. ¿Cuál es su área en metros cuadrados?',
      prompt: (BuildContext context) => BigPrompt(child: GridFigure(cells: _rect(sw, sh, x: 1, y: 1), cols: 7, rows: 6, size: 230, color: PilasColors.verde, showGrid: false, labels: <String, String>{'top': '$w m', 'left': '$h m'})),
      options: options,
      correctId: 'n$a',
      hint: 'Área del rectángulo: largo por ancho.',
      explain: '$w × $h = $a m².',
    );
  }

  ChoiceRound areaL(Rng rng) {
    final int w = rng.range(4, 6);
    final int h = rng.range(3, 5);
    final int cw = rng.range(1, w - 2);
    final int ch = rng.range(1, h - 1);
    final List<Offset> cells = _rect(w, h, x: 1, y: 1).where((Offset c) => !(c.dx >= 1 + w - cw && c.dy < 1 + ch)).toList();
    final int a = w * h - cw * ch;
    final List<ChoiceOption> options = <ChoiceOption>[for (final int v in tresOpciones(rng, a, <int>[w * h, a - cw, a + ch])) Opt.number(v)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: 'Cada cuadrito es 1 m². ¿Cuál es el área de esta figura?',
      prompt: (BuildContext context) => BigPrompt(child: GridFigure(cells: cells, cols: 9, rows: 7, size: 230, color: PilasColors.rosa)),
      options: options,
      correctId: 'n$a',
      hint: 'Parte la figura en dos rectángulos y suma sus áreas, o toma el rectángulo completo y resta la esquina que falta.',
      explain: '$w × $h = ${w * h}, menos la esquina de $cw × $ch = ${cw * ch}: $a m².',
    );
  }

  /// Tres corrales con la misma cerca y distinta área.
  ChoiceRound mismoPerimetro(Rng rng) {
    final int semi = rng.range(7, 10); // largo + ancho
    final List<int> anchos = <int>[for (int i = 1; i <= semi ~/ 2; i++) i];
    final List<int> elegidos = rng.sample(anchos, 3)..sort();
    final bool preguntaMayor = rng.chance(0.6);
    final int objetivo = preguntaMayor ? elegidos.last : elegidos.first;
    const List<Color> colores = <Color>[PilasColors.azul, PilasColors.verde, PilasColors.morado];
    Widget fig(int w, int h, Color c, double size) => GridFigure(cells: _rect(w, h), cols: semi - 1, rows: semi ~/ 2, size: size * 1.6, color: c, labels: <String, String>{'top': '$w', 'left': '$h'});
    final List<ChoiceOption> options = <ChoiceOption>[
      for (int i = 0; i < 3; i++)
        ChoiceOption(
          id: 'c${elegidos[i]}',
          label: 'corral de ${semi - elegidos[i]} por ${elegidos[i]}',
          build: (BuildContext context, double size) => fig(semi - elegidos[i], elegidos[i], colores[i], size),
        ),
    ];
    rng.shuffle(options);
    final String areas = Es.listaY(<String>[for (final int e in elegidos) '${semi - e} × $e = ${(semi - e) * e}']);
    return ChoiceRound(
      instruction: 'Los tres corrales usan la misma cerca (${2 * semi} m). ¿Cuál tiene ${preguntaMayor ? 'más' : 'menos'} espacio adentro?',
      options: options,
      optionAspect: 1.6,
      correctId: 'c$objetivo',
      hint: 'Calcula el área de cada corral: largo por ancho. El mismo perímetro no quiere decir la misma área.',
      explain: 'Áreas: $areas. Con el mismo perímetro, el más parecido a un cuadrado tiene más área.',
    );
  }
}
