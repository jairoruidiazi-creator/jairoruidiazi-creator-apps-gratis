import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/content/money.dart';
import 'package:pilas/content/vocab.dart';
import 'package:pilas/core/es.dart';
import 'package:pilas/core/rng.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/games/banco/bank_generator.dart';
import 'package:pilas/games/banco/cuerpo_bank.dart';
import 'package:pilas/games/banco/decisiones_bank.dart';
import 'package:pilas/games/banco/laboratorio_bank.dart';
import 'package:pilas/games/choice/choice_body.dart';
import 'package:pilas/games/choice/choice_round.dart';
import 'package:pilas/games/memoria/memoria_board.dart';
import 'package:pilas/games/reloj/reloj_generator.dart';
import 'package:pilas/games/tienda/tienda_generator.dart';
import 'package:pilas/model/age_band.dart';

import 'support/choice_generators.dart';

void checkRound(ChoiceRound r, String where) {
  expect(r.options.length, greaterThanOrEqualTo(2), reason: '$where: pocas opciones');
  final Set<String> ids = r.options.map((ChoiceOption o) => o.id).toSet();
  expect(ids.length, r.options.length, reason: '$where: ids repetidos');
  expect(ids.contains(r.correctId), isTrue, reason: '$where: la respuesta no está entre las opciones');
  expect(r.instruction.trim(), isNotEmpty, reason: '$where: sin instrucción');
  expect(r.hint.trim(), isNotEmpty, reason: '$where: sin pista');
  expect(r.explain.trim(), isNotEmpty, reason: '$where: sin explicación');
  final Map<String, int> labels = <String, int>{};
  for (final ChoiceOption o in r.options) {
    expect(o.label.trim(), isNotEmpty, reason: '$where: opción sin nombre');
    labels[o.label.toLowerCase()] = (labels[o.label.toLowerCase()] ?? 0) + 1;
  }
  // Dos opciones con el mismo nombre serían indistinguibles para la voz. La
  // única excepción es «¿Cuál es diferente?» de 3 a 4 años: las figuras del
  // grupo son copias iguales a propósito, y la diferente tiene otro nombre.
  final String correcta = r.options.firstWhere((ChoiceOption o) => o.id == r.correctId).label.toLowerCase();
  expect(labels[correcta], 1, reason: '$where: la respuesta se llama igual que otra opción');
  if (r.instruction != '¿Cuál es diferente?') {
    labels.forEach((String l, int n) => expect(n, 1, reason: '$where: dos opciones se llaman "$l"'));
  } else {
    expect(labels.length, 2, reason: '$where: el grupo debe ser de copias iguales');
  }
}

void main() {
  test('Las opciones se reparten sin huecos grandes ni casillas enormes', () {
    // Teléfono de pie: tres opciones en una columna, no 2 + 1.
    final OptionGridSpec telefono = OptionGridSpec.compute(3, 336, 500);
    expect(telefono.cols, 1);
    // Tableta de pie: tres opciones sin hueco y sin casillas gigantes.
    final OptionGridSpec tableta = OptionGridSpec.compute(3, 1132, 1000);
    expect(tableta.cols * tableta.rows, 3);
    expect(tableta.tileWidth, lessThanOrEqualTo(OptionGridSpec.maxUseful * 1.25 + 16.01));
    expect(tableta.tileHeight, lessThanOrEqualTo(OptionGridSpec.maxUseful * 1.25 + 16.01));
    // Cuatro opciones en una tableta: 2 × 2.
    final OptionGridSpec cuatro = OptionGridSpec.compute(4, 1132, 1000);
    expect(<int>[cuatro.cols, cuatro.rows], <int>[2, 2]);
    // Una franja acostada: tres en fila.
    expect(OptionGridSpec.compute(3, 600, 200).cols, 3);
  });

  for (final GeneratorCase c in choiceGeneratorCases()) {
    test('${c.gameId} genera rondas válidas en todos sus tramos y niveles', () {
      for (final AgeBand band in AgeBand.values) {
        if (!c.game.supports(band)) {
          continue;
        }
        for (int level = 1; level <= c.game.levelsFor(band); level++) {
          for (int seed = 0; seed < 40; seed++) {
            final ChoiceRound r = c.generator().next(Rng(seed * 31 + level), band, level);
            checkRound(r, '${c.gameId} ${band.id} nivel $level semilla $seed');
          }
        }
      }
    });
  }

  test('Los bancos de preguntas están completos y generan rondas válidas', () {
    final Map<String, List<BankQuestion>> bancos = <String, List<BankQuestion>>{'cuerpo': CuerpoBank.all, 'laboratorio': LaboratorioBank.all, 'decisiones': DecisionesBank.all};
    final Map<String, Map<AgeBand, String>> pistas = <String, Map<AgeBand, String>>{'cuerpo': CuerpoBank.pistaGeneral, 'laboratorio': LaboratorioBank.pistaGeneral, 'decisiones': DecisionesBank.pistaGeneral};
    bancos.forEach((String nombre, List<BankQuestion> banco) {
      final Set<String> textos = <String>{};
      for (final BankQuestion q in banco) {
        expect(textos.add(q.texto), isTrue, reason: '$nombre: pregunta repetida "${q.texto}"');
        expect(q.opciones.length, 3, reason: '$nombre: ${q.texto}');
        expect(q.correcta, inInclusiveRange(0, 2), reason: '$nombre: ${q.texto}');
        expect(q.opciones.toSet().length, 3, reason: '$nombre: opciones repetidas en "${q.texto}"');
        expect(q.level, inInclusiveRange(1, 4));
        if (q.band == AgeBand.b3a4 || q.band == AgeBand.b5a6) {
          expect(q.emojis, isNotNull, reason: '$nombre: "${q.texto}" sin pictogramas para un tramo que no lee');
          expect(q.emojis!.length, 3, reason: '$nombre: ${q.texto}');
        }
      }
      final BankGenerator g = BankGenerator(banco, pistaGeneral: pistas[nombre]!);
      for (final AgeBand band in AgeBand.values) {
        // Las preguntas sin pista propia usan la pista general del tramo, que
        // orienta a pensar sin descartar ninguna opción.
        for (final BankQuestion q in banco.where((BankQuestion q) => q.band == band && q.pista == null)) {
          final String h = g.hintFor(q, band);
          expect(h, pistas[nombre]![band] ?? BankGenerator.pistaPorDefecto, reason: '$nombre: ${q.texto}');
          expect(h.contains('No es'), isFalse, reason: '$nombre: la pista descarta una opción');
          expect(h.contains('"'), isFalse, reason: '$nombre: la pista cita una opción');
        }
        for (int level = 1; level <= 4; level++) {
          final List<BankQuestion> pool = g.poolFor(band, level);
          if (banco.any((BankQuestion q) => q.band == band)) {
            expect(pool.length, greaterThanOrEqualTo(3), reason: '$nombre ${band.id} nivel $level');
          }
          if (pool.isEmpty) {
            continue;
          }
          for (int seed = 0; seed < 10; seed++) {
            checkRound(g.next(Rng(seed), band, level), '$nombre ${band.id} nivel $level');
          }
        }
      }
    });
    // Cada tramo tiene al menos 12 preguntas en cuerpo y laboratorio.
    for (final AgeBand b in AgeBand.values) {
      expect(CuerpoBank.all.where((BankQuestion q) => q.band == b).length, greaterThanOrEqualTo(12), reason: 'cuerpo ${b.id}');
      expect(LaboratorioBank.all.where((BankQuestion q) => q.band == b).length, greaterThanOrEqualTo(12), reason: 'laboratorio ${b.id}');
    }
  });

  test('Las fracciones se nombran en palabras', () {
    expect(Es.fraccion(1, 2), 'un medio');
    expect(Es.fraccion(3, 4), 'tres cuartos');
    expect(Es.fraccion(1, 3), 'un tercio');
    expect(Es.fraccion(5, 8), 'cinco octavos');
    expect(Es.fraccion(4, 9), 'cuatro novenos');
  });

  test('El reloj nombra las horas como se dicen en Colombia', () {
    expect(RelojGenerator.nombreHora(1, 0), 'la una en punto');
    expect(RelojGenerator.nombreHora(3, 30), 'las tres y media');
    expect(RelojGenerator.nombreHora(5, 15), 'las cinco y cuarto');
    expect(RelojGenerator.nombreHora(12, 45), 'la una menos cuarto');
    expect(RelojGenerator.nombreHora(8, 45), 'las nueve menos cuarto');
    expect(RelojGenerator.nombreHora(10, 20), 'las diez y veinte');
    expect(RelojGenerator.esLaHora(1, 30), 'Es la una y media');
    expect(RelojGenerator.esLaHora(12, 45), 'Es la una menos cuarto');
    expect(RelojGenerator.esLaHora(3, 20), 'Son las tres y veinte');
    expect(RelojGenerator.digital(9, 5), '9:05');
  });

  test('La tienda genera rondas válidas de elegir y de pagar', () {
    final TiendaGenerator g = TiendaGenerator();
    for (final AgeBand band in AgeBand.values) {
      for (int level = 1; level <= GameRegistry.byId('tienda')!.levelsFor(band); level++) {
        for (int seed = 0; seed < 40; seed++) {
          final TiendaRound r = g.next(Rng(seed * 17 + level), band, level);
          if (r.choice != null) {
            checkRound(r.choice!, 'tienda ${band.id} nivel $level semilla $seed');
          } else {
            final PagoRound p = r.pago!;
            expect(p.total, greaterThan(0));
            expect(p.denominaciones, isNotEmpty);
            final int menor = p.denominaciones.map((Denominacion d) => d.valor).reduce((int a, int b) => a < b ? a : b);
            expect(p.total % menor, 0, reason: 'el total debe poder pagarse exacto');
          }
        }
      }
    }
  });

  test('La tienda cobra precios razonables: nada de fresas de catorce mil pesos', () {
    for (final VocabItem v in TiendaGenerator.productos) {
      expect(TiendaGenerator.rangoPrecio.containsKey(v.id), isTrue, reason: '${v.id} no tiene precio razonable');
    }
    bool razonable(Producto p) {
      final List<int> r = TiendaGenerator.rangoPrecio[p.item.id]!;
      return p.precio >= r[0] && p.precio <= r[1];
    }

    final TiendaGenerator g = TiendaGenerator();
    for (final AgeBand band in AgeBand.values) {
      for (int level = 1; level <= GameRegistry.byId('tienda')!.levelsFor(band); level++) {
        for (int seed = 0; seed < 80; seed++) {
          final TiendaRound r = g.next(Rng(seed * 31 + level), band, level);
          if (r.pago != null) {
            for (final Producto p in r.pago!.productos) {
              expect(razonable(p), isTrue, reason: '${p.item.nombre} a ${p.precio} pesos (${band.id} nivel $level)');
            }
          }
        }
      }
    }
    // Para cualquier precio que sale en las rondas hay algo que cuesta eso.
    for (int precio = 100; precio <= 45000; precio += 100) {
      final VocabItem v = TiendaGenerator.productoPara(Rng(precio), precio);
      final List<int> r = TiendaGenerator.rangoPrecio[v.id]!;
      expect(precio >= r[0] && precio <= r[1], isTrue, reason: '$precio pesos: ${v.nombre}');
    }
  });

  test('El tablero de memoria tiene cada pareja dos veces', () {
    for (final AgeBand band in AgeBand.values) {
      for (int level = 1; level <= 4; level++) {
        final MemoryBoard b = MemoryBoard.generate(Rng(level), band, level);
        expect(b.cards.length, b.pairs * 2);
        final Map<int, int> count = <int, int>{};
        for (final MemoryCard c in b.cards) {
          count[c.pairId] = (count[c.pairId] ?? 0) + 1;
        }
        expect(count.values.every((int n) => n == 2), isTrue);
        expect(b.pairs, MemoryBoard.pairsFor(band, level));
      }
    }
  });
}
