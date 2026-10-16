import '../../content/vocab.dart';
import '../../core/rng.dart';
import '../../model/age_band.dart';
import '../choice/choice_round.dart';
import '../choice/option_builders.dart';
import '../shell/widgets.dart';

/// Un criterio de grupo: el grupo comparte [groupTag] y el intruso tiene
/// [intruderTag] y no tiene [groupTag]. Siempre hay una sola respuesta.
class _Criterio {
  const _Criterio(this.groupTag, this.intruderTag, this.grupoNombre, this.intrusoDescripcion);

  final String groupTag;
  final String intruderTag;

  /// "son animales", "son frutas".
  final String grupoNombre;

  /// "es una verdura", "es un vehículo".
  final String intrusoDescripcion;
}

/// El intruso: toca el que no pertenece al grupo.
class IntrusoGenerator implements ChoiceGenerator {
  static const List<_Criterio> _b3a4 = <_Criterio>[
    _Criterio('animal', 'fruta', 'son animales', 'es una fruta'),
    _Criterio('fruta', 'animal', 'son frutas', 'es un animal'),
    _Criterio('vehiculo', 'animal', 'son vehículos', 'es un animal'),
    _Criterio('ropa', 'comida', 'son ropa', 'es comida'),
    _Criterio('comida', 'juguete', 'son comida', 'es un juguete'),
    _Criterio('animal', 'vehiculo', 'son animales', 'es un vehículo'),
  ];

  static const List<_Criterio> _b5a6 = <_Criterio>[
    _Criterio('granja', 'selva', 'viven en la granja', 'vive en la selva'),
    _Criterio('selva', 'granja', 'viven en la selva', 'vive en la granja'),
    _Criterio('fruta', 'verdura', 'son frutas', 'es una verdura'),
    _Criterio('verdura', 'fruta', 'son verduras', 'es una fruta'),
    _Criterio('mar', 'granja', 'viven en el agua', 'vive en la granja'),
    _Criterio('vuela', 'nada', 'vuelan', 'nada en el agua'),
    _Criterio('frio', 'calor', 'son para el frío', 'es para el calor'),
    _Criterio('instrumento', 'cocina', 'son instrumentos', 'es de la cocina'),
    _Criterio('escuela', 'bano', 'son de la escuela', 'es del baño'),
  ];

  static const List<_Criterio> _b7a8 = <_Criterio>[
    _Criterio('mamifero', 'ave', 'son mamíferos', 'es un ave'),
    _Criterio('ave', 'mamifero', 'son aves', 'es un mamífero'),
    _Criterio('reptil', 'mamifero', 'son reptiles', 'es un mamífero'),
    _Criterio('insecto', 'ave', 'son insectos', 'es un ave'),
    _Criterio('cuerdas', 'viento', 'son instrumentos de cuerda', 'es de viento'),
    _Criterio('viento', 'percusion', 'son instrumentos de viento', 'es de percusión'),
    _Criterio('planta', 'animal', 'son plantas', 'es un animal'),
    _Criterio('organo', 'objeto', 'son órganos del cuerpo', 'es un objeto'),
    _Criterio('aire', 'tierra', 'van por el aire', 'va por tierra'),
    _Criterio('colombia', 'frio', 'son de Colombia y la región', 'es de lugares fríos'),
  ];

  @override
  ChoiceRound next(Rng rng, AgeBand band, int level) {
    if (band == AgeBand.b3a4 && (level == 2 || level == 4)) {
      return _shapesRound(rng, level);
    }
    if (band == AgeBand.b7a8 && level >= 3 && rng.chance(0.5)) {
      return _numbersRound(rng, level);
    }
    List<_Criterio> pool;
    int count;
    switch (band) {
      case AgeBand.b3a4:
        pool = _b3a4;
        count = level <= 2 ? 3 : 4;
        break;
      case AgeBand.b5a6:
        pool = _b5a6;
        count = level <= 2 ? 4 : 5;
        break;
      case AgeBand.b7a8:
      case AgeBand.b9a11:
        pool = _b7a8;
        count = level <= 2 ? 5 : 6;
        break;
    }
    for (int attempt = 0; attempt < 20; attempt++) {
      final _Criterio c = rng.pick(pool);
      final List<VocabItem> group = Vocab.all.where((VocabItem v) => v.has(c.groupTag) && !v.has(c.intruderTag) && !v.nombre.contains(' ')).toList();
      final List<VocabItem> intruders = Vocab.all.where((VocabItem v) => v.has(c.intruderTag) && !v.has(c.groupTag) && !v.nombre.contains(' ')).toList();
      if (group.length < count - 1 || intruders.isEmpty) {
        continue;
      }
      final List<VocabItem> chosen = rng.sample(group, count - 1);
      final VocabItem intruder = rng.pick(intruders);
      final List<ChoiceOption> options = <ChoiceOption>[
        for (final VocabItem v in chosen) Opt.vocab(v),
        Opt.vocab(intruder),
      ];
      rng.shuffle(options);
      final String nombres = chosen.map((VocabItem v) => v.conArticulo).join(', ');
      return ChoiceRound(
        instruction: '¿Cuál no va con los demás?',
        options: options,
        correctId: intruder.id,
        hint: 'Mira bien: $nombres ${c.grupoNombre}.',
        explain: '${_cap(intruder.conArticulo)} ${c.intrusoDescripcion}; los demás ${c.grupoNombre}.',
        praise: '${_cap(intruder.conArticulo)} ${c.intrusoDescripcion}.',
      );
    }
    return _shapesRound(rng, level);
  }

  /// Figuras: igual forma y distinto color, o igual color y distinta forma.
  ChoiceRound _shapesRound(Rng rng, int level) {
    final bool byColor = rng.chance(0.5);
    final int count = level <= 2 ? 3 : 4;
    final List<ShapeKind> shapes = <ShapeKind>[ShapeKind.circle, ShapeKind.square, ShapeKind.triangle, ShapeKind.star, ShapeKind.heart];
    final List<NamedColor> colors = NamedColor.basicos.sublist(0, 6);
    final List<ChoiceOption> options = <ChoiceOption>[];
    String correctId;
    String hint;
    String explain;
    if (byColor) {
      final ShapeKind k = rng.pick(shapes);
      final NamedColor c = rng.pick(colors);
      final NamedColor other = rng.pickExcept(colors, <NamedColor>[c]);
      for (int i = 0; i < count - 1; i++) {
        options.add(Opt.shape('s$i', k, c.color, '${nombreForma(k)} ${c.nombre}'));
      }
      correctId = 'intruso';
      options.add(Opt.shape(correctId, k, other.color, '${nombreForma(k)} ${other.nombre}'));
      hint = 'Fíjate en los colores. Casi todos son de color ${c.nombre}.';
      explain = 'Todos son ${c.nombre} menos uno, que es ${other.nombre}.';
    } else {
      final NamedColor c = rng.pick(colors);
      final ShapeKind k = rng.pick(shapes);
      final ShapeKind other = rng.pickExcept(shapes, <ShapeKind>[k]);
      for (int i = 0; i < count - 1; i++) {
        options.add(Opt.shape('s$i', k, c.color, nombreForma(k)));
      }
      correctId = 'intruso';
      options.add(Opt.shape(correctId, other, c.color, nombreForma(other)));
      hint = 'Fíjate en la forma. Casi todos son ${_plural(nombreForma(k))}.';
      explain = 'Todos son ${_plural(nombreForma(k))} menos uno, que es un ${nombreForma(other)}.';
    }
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿Cuál es diferente?',
      options: options,
      correctId: correctId,
      hint: hint,
      explain: explain,
      optionSize: 84,
    );
  }

  /// Números: pares e impares, múltiplos, mayor que.
  ChoiceRound _numbersRound(Rng rng, int level) {
    final int kind = rng.nextInt(3);
    final List<int> group = <int>[];
    int intruder;
    String regla;
    String porque;
    if (kind == 0) {
      final bool pares = rng.chance(0.5);
      while (group.length < 4) {
        final int n = rng.range(1, 40);
        if ((n.isEven == pares) && !group.contains(n)) {
          group.add(n);
        }
      }
      do {
        intruder = rng.range(1, 40);
      } while (intruder.isEven == pares);
      regla = pares ? 'son pares' : 'son impares';
      porque = pares ? 'es impar' : 'es par';
    } else if (kind == 1) {
      final int m = rng.pick(<int>[2, 3, 5, 10]);
      while (group.length < 4) {
        final int n = m * rng.range(1, 10);
        if (!group.contains(n)) {
          group.add(n);
        }
      }
      do {
        intruder = rng.range(1, m * 10);
      } while (intruder % m == 0);
      regla = 'están en la tabla del $m';
      porque = 'no está en la tabla del $m';
    } else {
      final int limit = rng.pick(<int>[10, 20, 50]);
      while (group.length < 4) {
        final int n = rng.range(limit + 1, limit + 30);
        if (!group.contains(n)) {
          group.add(n);
        }
      }
      intruder = rng.range(1, limit - 1);
      regla = 'son mayores que $limit';
      porque = 'es menor que $limit';
    }
    final List<ChoiceOption> options = <ChoiceOption>[for (final int n in group) Opt.number(n), Opt.number(intruder)];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿Qué número no va con los demás?',
      options: options,
      correctId: 'n$intruder',
      hint: 'Piensa qué tienen en común casi todos: $regla.',
      explain: 'El $intruder $porque; los demás $regla.',
    );
  }

  static String _cap(String s) => s.isEmpty ? s : s.substring(0, 1).toUpperCase() + s.substring(1);

  static String _plural(String s) {
    if (s.endsWith('ón')) {
      return '${s.substring(0, s.length - 2)}ones';
    }
    if (s.endsWith('z')) {
      return '${s.substring(0, s.length - 1)}ces';
    }
    return '${s}s';
  }
}
