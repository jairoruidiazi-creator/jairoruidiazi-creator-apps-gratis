import 'dart:math' as math;

import '../../content/vocab.dart';
import '../../core/es.dart';
import '../../core/rng.dart';
import '../../model/age_band.dart';
import '../choice/choice_round.dart';
import '../choice/option_builders.dart';
import '../shell/widgets.dart';

/// Un criterio de grupo: los del grupo cumplen [enGrupo]; el intruso cumple
/// [intruso] y no [enGrupo].
class CriterioIntruso {
  const CriterioIntruso(this.id, this.enGrupo, this.intruso, this.grupoFrase, this.intrusoFrase);

  final String id;
  final bool Function(VocabItem v) enGrupo;
  final bool Function(VocabItem v) intruso;

  /// "son animales", "viven en la granja" (para los demás, en plural).
  final String grupoFrase;

  /// "es una fruta" o "son frutas", según el número del intruso.
  final String Function(VocabItem v) intrusoFrase;
}

bool _animal(VocabItem v) => v.esAnimal;
bool _fruta(VocabItem v) => v.has('fruta');
bool _verdura(VocabItem v) => v.has('verdura');
bool _comidaNoFruta(VocabItem v) => v.has('comida') && !v.has('fruta') && !v.has('verdura');

/// El intruso: toca el que no pertenece al grupo.
///
/// Además del criterio de la ronda, se descarta cualquier grupo en el que
/// otra opción también quede sola por otra propiedad sencilla (su categoría,
/// su grupo de animal, el lugar donde vive o el medio por el que va): así no
/// hay dos respuestas defendibles.
class IntrusoGenerator implements ChoiceGenerator {
  static final List<CriterioIntruso> b3a4 = <CriterioIntruso>[
    CriterioIntruso('animales-fruta', _animal, _fruta, 'son animales', (VocabItem v) => v.verbo('es una fruta', 'son frutas')),
    CriterioIntruso('frutas-animal', _fruta, _animal, 'son frutas', (VocabItem v) => v.verbo('es un animal', 'son animales')),
    CriterioIntruso('vehiculos-animal', (VocabItem v) => v.has('medio:tierra') && !v.has('juguete'), _animal, 'son vehículos', (VocabItem v) => v.verbo('es un animal', 'son animales')),
    CriterioIntruso('ropa-fruta', (VocabItem v) => v.has('ropa'), _fruta, 'son ropa', (VocabItem v) => v.verbo('es una fruta', 'son frutas')),
    CriterioIntruso('comida-juguete', _comidaNoFruta, (VocabItem v) => v.has('juguete') && !v.has('vehiculo'), 'son comida', (VocabItem v) => v.verbo('es un juguete', 'son juguetes')),
  ];

  static final List<CriterioIntruso> b5a6 = <CriterioIntruso>[
    CriterioIntruso('granja-otro', (VocabItem v) => v.esAnimal && v.habitats.contains('granja'), (VocabItem v) => v.esAnimal && v.habitats.isNotEmpty && !v.habitats.contains('granja'), 'viven en la granja', (VocabItem v) => v.verbo('no vive en la granja', 'no viven en la granja')),
    CriterioIntruso('mar-granja', (VocabItem v) => v.esAnimal && v.habitats.contains('mar'), (VocabItem v) => v.esAnimal && v.habitats.contains('granja') && !v.habitats.contains('mar'), 'viven en el mar', (VocabItem v) => v.verbo('vive en la granja', 'viven en la granja')),
    CriterioIntruso('frutas-verdura', _fruta, _verdura, 'son frutas', (VocabItem v) => v.verbo('es una verdura', 'son verduras')),
    CriterioIntruso('verduras-fruta', _verdura, _fruta, 'son verduras', (VocabItem v) => v.verbo('es una fruta', 'son frutas')),
    CriterioIntruso('vuelan-nada', (VocabItem v) => v.mueve('vuela') == true && v.mueve('nada') == false, (VocabItem v) => v.mueve('nada') == true && v.mueve('vuela') == false, 'vuelan', (VocabItem v) => v.verbo('nada y no vuela', 'nadan y no vuelan')),
    CriterioIntruso('frio-calor', (VocabItem v) => v.has('uso:frio'), (VocabItem v) => v.has('uso:calor'), 'son para el frío', (VocabItem v) => v.verbo('es para el calor', 'son para el calor')),
    CriterioIntruso('instrumentos-cocina', (VocabItem v) => v.has('instrumento'), (VocabItem v) => v.has('cocina'), 'son instrumentos musicales', (VocabItem v) => v.verbo('es de la cocina', 'son de la cocina')),
    CriterioIntruso('escuela-bano', (VocabItem v) => v.has('escuela'), (VocabItem v) => v.has('bano'), 'son de la escuela', (VocabItem v) => v.verbo('es del baño', 'son del baño')),
  ];

  static final List<CriterioIntruso> b7a8 = <CriterioIntruso>[
    for (final List<String> par in const <List<String>>[
      <String>['mamifero', 'ave'],
      <String>['ave', 'mamifero'],
      <String>['mamifero', 'pez'],
      <String>['reptil', 'mamifero'],
      <String>['insecto', 'ave'],
      <String>['ave', 'reptil'],
      <String>['mamifero', 'anfibio'],
    ])
      CriterioIntruso('${par[0]}-${par[1]}', (VocabItem v) => v.grupo == par[0], (VocabItem v) => v.grupo == par[1], 'son ${_plural[par[0]]}', (VocabItem v) => v.verbo('es un ${_singular[par[1]]}', 'son ${_plural[par[1]]}')),
    CriterioIntruso('cuerdas-viento', (VocabItem v) => v.has('inst:cuerdas'), (VocabItem v) => v.has('inst:viento'), 'son instrumentos de cuerda', (VocabItem v) => v.verbo('es de viento', 'son de viento')),
    CriterioIntruso('viento-percusion', (VocabItem v) => v.has('inst:viento'), (VocabItem v) => v.has('inst:percusion'), 'son instrumentos de viento', (VocabItem v) => v.verbo('es de percusión', 'son de percusión')),
    CriterioIntruso('plantas-animal', (VocabItem v) => v.has('planta'), _animal, 'son plantas', (VocabItem v) => v.verbo('es un animal', 'son animales')),
    CriterioIntruso('organos-objeto', (VocabItem v) => v.has('organo'), (VocabItem v) => v.has('objeto') && v.has('hogar'), 'son órganos del cuerpo', (VocabItem v) => v.verbo('es un objeto', 'son objetos')),
    CriterioIntruso('aire-tierra', (VocabItem v) => v.has('medio:aire'), (VocabItem v) => v.has('medio:tierra') && !v.has('juguete'), 'van por el aire', (VocabItem v) => v.verbo('va por tierra', 'van por tierra')),
    CriterioIntruso('agua-tierra', (VocabItem v) => v.has('medio:agua'), (VocabItem v) => v.has('medio:tierra') && !v.has('juguete'), 'van por el agua', (VocabItem v) => v.verbo('va por tierra', 'van por tierra')),
  ];

  static const Map<String, String> _singular = <String, String>{'mamifero': 'mamífero', 'ave': 'ave', 'pez': 'pez', 'reptil': 'reptil', 'anfibio': 'anfibio', 'insecto': 'insecto'};
  static const Map<String, String> _plural = <String, String>{'mamifero': 'mamíferos', 'ave': 'aves', 'pez': 'peces', 'reptil': 'reptiles', 'anfibio': 'anfibios', 'insecto': 'insectos'};

  /// Palabras que se pueden usar como opción: sueltas (sin "de" largos) y con
  /// un pictograma que se reconoce solo.
  static final List<VocabItem> _pool = Vocab.all.where((VocabItem v) => !v.nombre.contains(' ') && v.id != 'unicornio').toList();

  @override
  ChoiceRound next(Rng rng, AgeBand band, int level) {
    if (band == AgeBand.b3a4 && (level == 2 || level == 4)) {
      return shapesRound(rng, level);
    }
    if (band == AgeBand.b7a8 && level >= 3 && rng.chance(0.5)) {
      return numbersRound(rng);
    }
    List<CriterioIntruso> criterios;
    int count;
    switch (band) {
      case AgeBand.b3a4:
        criterios = b3a4;
        count = level <= 2 ? 3 : 4;
        break;
      case AgeBand.b5a6:
        criterios = b5a6;
        count = level <= 2 ? 4 : 5;
        break;
      case AgeBand.b7a8:
      case AgeBand.b9a11:
        criterios = b7a8;
        count = level <= 2 ? 5 : 6;
        break;
    }
    for (int intento = 0; intento < 60; intento++) {
      final CriterioIntruso c = rng.pick(criterios);
      final ChoiceRound? r = roundFor(rng, c, count);
      if (r != null) {
        return r;
      }
    }
    return shapesRound(rng, level);
  }

  /// Una ronda con el criterio [c], o null si no hay una sin ambigüedad.
  ChoiceRound? roundFor(Rng rng, CriterioIntruso c, int count) {
    final List<VocabItem> grupo = _pool.where((VocabItem v) => c.enGrupo(v) && !c.intruso(v)).toList();
    final List<VocabItem> intrusos = _pool.where((VocabItem v) => c.intruso(v) && !c.enGrupo(v)).toList();
    // Con grupos pequeños (tres instrumentos de viento) la ronda tiene menos
    // opciones, pero nunca menos de tres.
    final int n = math.min(count, grupo.length + 1);
    if (n < 3 || intrusos.isEmpty) {
      return null;
    }
    for (int intento = 0; intento < 12; intento++) {
      final List<VocabItem> elegidos = rng.sample(grupo, n - 1);
      final VocabItem intruso = rng.pick(intrusos);
      if (ambiguo(<VocabItem>[...elegidos, intruso], intruso)) {
        continue;
      }
      final List<ChoiceOption> options = <ChoiceOption>[for (final VocabItem v in elegidos) Opt.vocab(v), Opt.vocab(intruso)];
      rng.shuffle(options);
      final String nombres = Es.listaY(elegidos.map((VocabItem v) => v.conArticulo).toList());
      final String sujeto = Es.cap(intruso.conArticulo);
      return ChoiceRound(
        instruction: '¿Cuál no va con los demás?',
        options: options,
        correctId: intruso.id,
        hint: 'Mira bien qué tienen en común casi todos. ¿Cuáles ${c.grupoFrase}?',
        explain: '$sujeto ${c.intrusoFrase(intruso)}; ${Es.contraer(nombres)} ${c.grupoFrase}.',
        praise: '$sujeto ${c.intrusoFrase(intruso)}.',
      );
    }
    return null;
  }

  /// Propiedades sencillas con las que un niño también podría agrupar.
  static Map<String, String> propiedades(VocabItem v) {
    String categoria = 'otro';
    for (final String c in <String>['animal', 'fruta', 'verdura', 'vehiculo', 'ropa', 'instrumento', 'planta', 'organo', 'juguete', 'comida', 'cuerpo', 'escuela', 'cocina', 'bano', 'hogar', 'naturaleza']) {
      if (v.has(c)) {
        categoria = c;
        break;
      }
    }
    String medio = '';
    for (final String m in <String>['medio:tierra', 'medio:aire', 'medio:agua']) {
      if (v.has(m)) {
        medio = m;
      }
    }
    return <String, String>{
      'categoria': categoria,
      'grupo': v.grupo ?? (v.esAnimal ? 'sin-grupo' : ''),
      'agua': v.esAnimal ? '${v.habitats.contains('mar') || v.habitats.contains('rio')}' : '',
      'granja': v.esAnimal ? '${v.habitats.contains('granja')}' : '',
      'medio': medio,
    };
  }

  /// Si alguna opción distinta del intruso queda sola por otra propiedad
  /// mientras todas las demás la comparten.
  static bool ambiguo(List<VocabItem> opciones, VocabItem intruso) {
    final List<Map<String, String>> props = opciones.map(propiedades).toList();
    for (final String clave in props.first.keys) {
      final List<String> valores = props.map((Map<String, String> p) => p[clave]!).toList();
      if (valores.any((String x) => x.isEmpty)) {
        continue;
      }
      for (int i = 0; i < opciones.length; i++) {
        if (identical(opciones[i], intruso)) {
          continue;
        }
        final String mio = valores[i];
        final Iterable<String> resto = <String>[for (int j = 0; j < valores.length; j++) if (j != i) valores[j]];
        if (resto.every((String x) => x == resto.first) && resto.first != mio) {
          return true;
        }
      }
    }
    return false;
  }

  /// Figuras: igual forma y distinto color, o igual color y distinta forma.
  ChoiceRound shapesRound(Rng rng, int level) {
    final bool byColor = rng.chance(0.5);
    final int count = level <= 2 ? 3 : 4;
    final List<ShapeKind> shapes = <ShapeKind>[ShapeKind.circle, ShapeKind.square, ShapeKind.triangle, ShapeKind.star, ShapeKind.heart];
    final List<NamedColor> colors = NamedColor.basicos.sublist(0, 6);
    final List<ChoiceOption> options = <ChoiceOption>[];
    String hint;
    String explain;
    if (byColor) {
      final ShapeKind k = rng.pick(shapes);
      final NamedColor c = rng.pick(colors);
      final NamedColor other = rng.pickExcept(colors, <NamedColor>[c]);
      for (int i = 0; i < count - 1; i++) {
        options.add(Opt.shape('s$i', k, c, formaConColor(k, c)));
      }
      options.add(Opt.shape('intruso', k, other, formaConColor(k, other)));
      final String g = generoForma(k);
      hint = 'Fíjate en los colores. ¿De qué color son casi todos?';
      explain = '${g == 'f' ? 'Todas' : 'Todos'} son ${pluralForma(k)} ${_colorPlural(c, g)} menos ${g == 'f' ? 'una' : 'uno'}, que es ${colorConcordado(other, g)}.';
    } else {
      final NamedColor c = rng.pick(colors);
      final ShapeKind k = rng.pick(shapes);
      final ShapeKind other = rng.pickExcept(shapes, <ShapeKind>[k]);
      for (int i = 0; i < count - 1; i++) {
        options.add(Opt.shape('s$i', k, c, formaConColor(k, c)));
      }
      options.add(Opt.shape('intruso', other, c, formaConColor(other, c)));
      final String g = generoForma(k);
      hint = 'Fíjate en la forma. ¿Qué forma tienen casi todos?';
      explain = '${g == 'f' ? 'Todas' : 'Todos'} son ${pluralForma(k)} menos ${g == 'f' ? 'una' : 'uno'}, que es ${Es.articulo(generoForma(other), definido: false)} ${nombreForma(other)}.';
    }
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '¿Cuál es diferente?',
      options: options,
      correctId: 'intruso',
      hint: hint,
      explain: explain,
      optionSize: 84,
    );
  }

  /// "rojos", "rojas", "verdes", "azules", "naranja" (los colores que son
  /// nombres de cosas no cambian: "círculos naranja", "estrellas café").
  static String _colorPlural(NamedColor c, String genero) {
    switch (c.id) {
      case 'naranja':
      case 'cafe':
        return c.nombre;
      case 'azul':
        return 'azules';
      case 'verde':
        return 'verdes';
      default:
        return '${colorConcordado(c, genero)}s';
    }
  }

  /// Números: pares e impares, tablas o mayores que un número. Solo se usa un
  /// grupo si ninguna otra regla sencilla deja sola a otra opción.
  ChoiceRound numbersRound(Rng rng) {
    for (int intento = 0; intento < 200; intento++) {
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
        final int m = rng.pick(<int>[3, 5, 10]);
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
      final List<int> todos = <int>[...group, intruder];
      if (todos.toSet().length != todos.length || numerosAmbiguos(todos, intruder)) {
        continue;
      }
      final List<ChoiceOption> options = <ChoiceOption>[for (final int n in todos) Opt.number(n)];
      rng.shuffle(options);
      return ChoiceRound(
        instruction: '¿Qué número no va con los demás?',
        options: options,
        correctId: 'n$intruder',
        hint: 'Piensa qué tienen en común casi todos: ¿son pares?, ¿están en una tabla?, ¿son grandes o pequeños?',
        explain: 'El $intruder $porque; los demás $regla.',
      );
    }
    return shapesRound(rng, 4);
  }

  /// Si alguna regla sencilla deja sola a una opción que no es el intruso.
  static bool numerosAmbiguos(List<int> numeros, int intruder) {
    final List<bool Function(int)> reglas = <bool Function(int)>[
      (int n) => n.isEven,
      (int n) => n % 3 == 0,
      (int n) => n % 5 == 0,
      (int n) => n % 10 == 0,
      (int n) => n > 10,
      (int n) => n > 20,
      (int n) => n > 50,
      (int n) => n < 10,
    ];
    for (final bool Function(int) r in reglas) {
      final List<int> cumplen = numeros.where(r).toList();
      final List<int> noCumplen = numeros.where((int n) => !r(n)).toList();
      if (cumplen.length == 1 && cumplen.first != intruder) {
        return true;
      }
      if (noCumplen.length == 1 && noCumplen.first != intruder) {
        return true;
      }
    }
    return false;
  }
}
