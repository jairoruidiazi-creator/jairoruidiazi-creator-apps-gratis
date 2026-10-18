import 'package:flutter/material.dart';

import '../../content/vocab.dart';
import '../../core/rng.dart';
import '../../core/theme.dart';
import '../../model/age_band.dart';
import '../choice/choice_round.dart';
import '../choice/option_builders.dart';
import '../shell/widgets.dart';

/// ¿Qué sigue?: patrones y series. Los más pequeños ven figuras y colores;
/// desde los 7 años, series de números con una regla que se nombra al acertar.
class PatronesGenerator implements ChoiceGenerator {
  @override
  ChoiceRound next(Rng rng, AgeBand band, int level) {
    switch (band) {
      case AgeBand.b3a4:
        return _visual(rng, band, level);
      case AgeBand.b5a6:
        return level >= 4 ? _numeric(rng, band, level) : _visual(rng, band, level);
      case AgeBand.b7a8:
      case AgeBand.b9a11:
        return _numeric(rng, band, level);
    }
  }

  // ------------------------------------------------------------ visuales

  ChoiceRound _visual(Rng rng, AgeBand band, int level) {
    // Estructura del patrón según el nivel.
    List<int> estructura; // índices de elemento, por ejemplo AB = [0,1]
    if (band == AgeBand.b3a4) {
      estructura = level <= 2 ? <int>[0, 1] : (level == 3 ? <int>[0, 1, 1] : <int>[0, 1, 2]);
    } else {
      estructura = level == 1 ? <int>[0, 1, 2] : (level == 2 ? rng.pick(<List<int>>[<int>[0, 1, 1], <int>[0, 0, 1]]) : <int>[0, 1, 2, 3]);
    }
    final int distintos = estructura.reduce((int a, int b) => a > b ? a : b) + 1;
    final bool usaEmoji = band != AgeBand.b3a4 && rng.chance(0.5);
    final bool porColor = band == AgeBand.b3a4 ? (level == 1 || level == 4 || rng.chance(0.5)) : rng.chance(0.5);

    final List<_Elem> elems = <_Elem>[];
    if (usaEmoji) {
      final List<VocabItem> pool = rng.sample(Vocab.withTag('animal'), distintos);
      for (final VocabItem v in pool) {
        elems.add(_Elem.emoji(v));
      }
    } else if (porColor) {
      final ShapeKind k = rng.pick(<ShapeKind>[ShapeKind.circle, ShapeKind.square, ShapeKind.star, ShapeKind.heart]);
      final List<NamedColor> colores = rng.sample(NamedColor.basicos.sublist(0, 6), distintos);
      for (final NamedColor c in colores) {
        elems.add(_Elem.shape(k, c, formaConColor(k, c), colorConcordado(c, generoForma(k))));
      }
    } else {
      final NamedColor c = rng.pick(NamedColor.basicos.sublist(0, 6));
      final List<ShapeKind> formas = rng.sample(<ShapeKind>[ShapeKind.circle, ShapeKind.square, ShapeKind.triangle, ShapeKind.star, ShapeKind.heart], distintos);
      for (final ShapeKind k in formas) {
        elems.add(_Elem.shape(k, c, nombreForma(k), nombreForma(k)));
      }
    }

    // Secuencia visible: dos o tres repeticiones y luego la incógnita.
    final int repeticiones = estructura.length <= 2 ? 3 : 2;
    final List<_Elem> secuencia = <_Elem>[];
    for (int r = 0; r < repeticiones; r++) {
      for (final int i in estructura) {
        secuencia.add(elems[i]);
      }
    }
    // La incógnita es el primer elemento del siguiente ciclo, o uno intermedio.
    final int posicionIncognita = rng.nextInt(estructura.length);
    for (int i = 0; i < posicionIncognita; i++) {
      secuencia.add(elems[estructura[i]]);
    }
    final _Elem correcto = elems[estructura[posicionIncognita]];

    final List<ChoiceOption> options = <ChoiceOption>[];
    final Set<String> usados = <String>{};
    options.add(correcto.option('correcto'));
    usados.add(correcto.key);
    int k = 0;
    for (final _Elem e in elems) {
      if (options.length >= 3) {
        break;
      }
      if (!usados.contains(e.key)) {
        options.add(e.option('d$k'));
        usados.add(e.key);
        k += 1;
      }
    }
    // Si solo había dos elementos distintos, se añade un distractor nuevo.
    while (options.length < 3) {
      final _Elem extra = _extraDistractor(rng, elems, usaEmoji, porColor, usados);
      options.add(extra.option('d$k'));
      usados.add(extra.key);
      k += 1;
    }
    rng.shuffle(options);

    final String patronNombre = estructura.map((int i) => elems[i].nombreCorto).join(', ');
    return ChoiceRound(
      instruction: '¿Qué sigue?',
      prompt: (BuildContext context) => PromptRow(
        semanticsLabel: '${secuencia.map((_Elem e) => e.nombre).join(', ')}, y falta uno',
        children: <Widget>[
          for (final _Elem e in secuencia) e.build(52),
          const QuestionSlot(size: 52),
        ],
      ),
      options: options,
      correctId: 'correcto',
      hint: 'Dilo en voz alta: $patronNombre, $patronNombre... ¿qué viene?',
      explain: 'El patrón es $patronNombre. Sigue ${correcto.nombreCorto}.',
      praise: 'El patrón es $patronNombre.',
      optionSize: 80,
    );
  }

  _Elem _extraDistractor(Rng rng, List<_Elem> elems, bool usaEmoji, bool porColor, Set<String> usados) {
    for (int i = 0; i < 40; i++) {
      _Elem candidato;
      if (usaEmoji) {
        candidato = _Elem.emoji(rng.pick(Vocab.withTag('animal')));
      } else if (porColor) {
        final _Elem base = elems.first;
        final NamedColor c = rng.pick(NamedColor.basicos);
        candidato = _Elem.shape(base.shape!, c, formaConColor(base.shape!, c), colorConcordado(c, generoForma(base.shape!)));
      } else {
        final _Elem base = elems.first;
        final ShapeKind k = rng.pick(<ShapeKind>[ShapeKind.circle, ShapeKind.square, ShapeKind.triangle, ShapeKind.star, ShapeKind.heart, ShapeKind.hexagon]);
        candidato = _Elem.shape(k, base.color!, nombreForma(k), nombreForma(k));
      }
      if (!usados.contains(candidato.key)) {
        return candidato;
      }
    }
    return elems.first;
  }

  // ------------------------------------------------------------ numéricas

  ChoiceRound _numeric(Rng rng, AgeBand band, int level) {
    late List<int> serie;
    late String regla;
    late int siguiente;
    const int largo = 5;

    if (band == AgeBand.b5a6) {
      // Contar de 1 en 1, de 2 en 2 o de 10 en 10.
      final int paso = rng.pick(<int>[1, 2, 10]);
      final int inicio = paso == 10 ? 10 : rng.range(1, 6);
      serie = List<int>.generate(largo, (int i) => inicio + paso * i);
      siguiente = inicio + paso * largo;
      regla = 'suma $paso cada vez';
    } else if (band == AgeBand.b7a8) {
      if (level <= 2) {
        final int paso = rng.pick(<int>[2, 3, 4, 5, 10]);
        final int inicio = rng.range(1, 20);
        serie = List<int>.generate(largo, (int i) => inicio + paso * i);
        siguiente = inicio + paso * largo;
        regla = 'suma $paso cada vez';
      } else if (level == 3) {
        final bool resta = rng.chance(0.5);
        final int paso = rng.pick(<int>[2, 3, 5, 10]);
        if (resta) {
          final int inicio = rng.range(paso * (largo + 1), paso * (largo + 1) + 40);
          serie = List<int>.generate(largo, (int i) => inicio - paso * i);
          siguiente = inicio - paso * largo;
          regla = 'resta $paso cada vez';
        } else {
          final int inicio = rng.range(1, 10);
          serie = List<int>.generate(largo, (int i) => inicio * (1 << i));
          siguiente = inicio * (1 << largo);
          regla = 'multiplica por 2 cada vez';
        }
      } else {
        final int m = rng.pick(<int>[3, 4, 6, 7, 8, 9]);
        final int inicio = rng.range(1, 4);
        serie = List<int>.generate(largo, (int i) => m * (inicio + i));
        siguiente = m * (inicio + largo);
        regla = 'son los números de la tabla del $m';
      }
    } else {
      // 9 a 11: dos reglas, cuadrados, alternancia.
      final int tipo = level <= 1 ? 0 : rng.nextInt(level >= 3 ? 4 : 2);
      if (tipo == 0) {
        // Paso creciente: +1, +2, +3...
        final int inicio = rng.range(1, 10);
        int v = inicio;
        serie = <int>[v];
        for (int i = 1; i < largo; i++) {
          v += i;
          serie.add(v);
        }
        siguiente = v + largo;
        regla = 'suma 1, luego 2, luego 3 y así sigue';
      } else if (tipo == 1) {
        final int inicio = rng.range(1, 5);
        serie = List<int>.generate(largo, (int i) => (inicio + i) * (inicio + i));
        siguiente = (inicio + largo) * (inicio + largo);
        regla = 'cada número es otro multiplicado por sí mismo (1 × 1, 2 × 2, 3 × 3…)';
      } else if (tipo == 2) {
        // Suma más de lo que resta: la serie nunca baja de cero.
        final int a = rng.range(3, 6);
        final int b = rng.range(1, a - 1);
        final int inicio = rng.range(1, 10);
        serie = <int>[inicio];
        int v = inicio;
        for (int i = 1; i < largo; i++) {
          v = i.isOdd ? v + a : v - b;
          serie.add(v);
        }
        siguiente = largo.isOdd ? v + a : v - b;
        regla = 'suma $a y luego resta $b, una y otra vez';
      } else {
        final int f = rng.pick(<int>[3, 4, 5]);
        final int inicio = rng.range(1, 3);
        serie = List<int>.generate(largo, (int i) => inicio * _pow(f, i));
        siguiente = inicio * _pow(f, largo);
        regla = 'multiplica por $f cada vez';
      }
    }

    final List<int> distractores = <int>{siguiente + 1, siguiente - 1, siguiente + 2, siguiente - 2, siguiente + 10, siguiente - 10, serie.last}
        .where((int n) => n != siguiente && n >= 0)
        .toList();
    final List<int> elegidos = rng.sample(distractores, 2);
    final List<ChoiceOption> options = <ChoiceOption>[Opt.number(siguiente), for (final int d in elegidos) Opt.number(d)];
    rng.shuffle(options);
    final String serieTexto = serie.join(', ');
    return ChoiceRound(
      instruction: '¿Qué número sigue?',
      prompt: (BuildContext context) => PromptRow(
        size: 56,
        semanticsLabel: '$serieTexto, y falta uno',
        children: <Widget>[
          for (final int n in serie)
            Text('$n', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: PilasPalette.of(context).tinta)),
          const QuestionSlot(size: 52),
        ],
      ),
      options: options,
      correctId: 'n$siguiente',
      hint: 'Mira cuánto cambia de un número al siguiente: $serieTexto.',
      explain: 'La regla es: $regla. Después de ${serie.last} viene $siguiente.',
      praise: 'La regla es: $regla.',
    );
  }

  static int _pow(int base, int exp) {
    int r = 1;
    for (int i = 0; i < exp; i++) {
      r *= base;
    }
    return r;
  }
}

/// Un elemento de patrón: figura con color o pictograma.
class _Elem {
  _Elem._(this.key, this.nombre, this.nombreCorto, this.shape, this.color, this.vocab);

  factory _Elem.shape(ShapeKind k, NamedColor c, String nombre, String corto) => _Elem._('${k.name}_${c.id}', nombre, corto, k, c, null);

  factory _Elem.emoji(VocabItem v) => _Elem._('v_${v.id}', v.nombre, v.nombre, null, null, v);

  final String key;
  final String nombre;
  final String nombreCorto;
  final ShapeKind? shape;
  final NamedColor? color;
  final VocabItem? vocab;

  Widget build(double size) {
    if (vocab != null) {
      return EmojiImage(vocab!.emoji, size: size, semanticsLabel: vocab!.nombre);
    }
    return ShapeIcon(kind: shape!, color: color!.color, size: size, mark: color!.mark);
  }

  ChoiceOption option(String id) {
    if (vocab != null) {
      return Opt.emoji(id, vocab!.emoji, vocab!.nombre);
    }
    return Opt.shape(id, shape!, color!, nombre);
  }
}
