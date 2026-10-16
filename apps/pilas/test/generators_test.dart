import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/content/money.dart';
import 'package:pilas/core/rng.dart';
import 'package:pilas/games/choice/choice_round.dart';
import 'package:pilas/games/clasifica/clasifica_generator.dart';
import 'package:pilas/games/emociones/emociones_generator.dart';
import 'package:pilas/games/intruso/intruso_generator.dart';
import 'package:pilas/games/memoria/memoria_board.dart';
import 'package:pilas/games/patrones/patrones_generator.dart';
import 'package:pilas/games/sonidos/sonidos_generator.dart';
import 'package:pilas/games/tienda/tienda_generator.dart';
import 'package:pilas/model/age_band.dart';

void checkRound(ChoiceRound r, String where) {
  expect(r.options.length, greaterThanOrEqualTo(2), reason: '$where: pocas opciones');
  final Set<String> ids = r.options.map((ChoiceOption o) => o.id).toSet();
  expect(ids.length, r.options.length, reason: '$where: ids repetidos');
  expect(ids.contains(r.correctId), isTrue, reason: '$where: la respuesta no está entre las opciones');
  expect(r.instruction.trim(), isNotEmpty, reason: '$where: sin instrucción');
  expect(r.hint.trim(), isNotEmpty, reason: '$where: sin pista');
  expect(r.explain.trim(), isNotEmpty, reason: '$where: sin explicación');
  for (final ChoiceOption o in r.options) {
    expect(o.label.trim(), isNotEmpty, reason: '$where: opción sin nombre');
  }
}

void main() {
  final List<ChoiceGenerator> generators = <ChoiceGenerator>[IntrusoGenerator(), SonidosGenerator(), PatronesGenerator(), EmocionesGenerator(), ClasificaGenerator()];
  final Map<Type, List<AgeBand>> bands = <Type, List<AgeBand>>{
    IntrusoGenerator: <AgeBand>[AgeBand.b3a4, AgeBand.b5a6, AgeBand.b7a8],
    SonidosGenerator: <AgeBand>[AgeBand.b3a4, AgeBand.b5a6],
    PatronesGenerator: AgeBand.values,
    EmocionesGenerator: <AgeBand>[AgeBand.b3a4, AgeBand.b5a6, AgeBand.b7a8],
    ClasificaGenerator: AgeBand.values,
  };

  for (final ChoiceGenerator g in generators) {
    test('${g.runtimeType} genera rondas válidas en todos los tramos y niveles', () {
      for (final AgeBand band in bands[g.runtimeType]!) {
        for (int level = 1; level <= 4; level++) {
          for (int seed = 0; seed < 25; seed++) {
            final ChoiceRound r = g.next(Rng(seed * 31 + level), band, level);
            checkRound(r, '${g.runtimeType} ${band.id} nivel $level semilla $seed');
          }
        }
      }
    });
  }

  test('La tienda genera rondas válidas de elegir y de pagar', () {
    final TiendaGenerator g = TiendaGenerator();
    for (final AgeBand band in AgeBand.values) {
      for (int level = 1; level <= 4; level++) {
        for (int seed = 0; seed < 25; seed++) {
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
