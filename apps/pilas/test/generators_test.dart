import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/content/money.dart';
import 'package:pilas/core/rng.dart';
import 'package:pilas/games/banco/bank_generator.dart';
import 'package:pilas/games/banco/cuerpo_bank.dart';
import 'package:pilas/games/banco/decisiones_bank.dart';
import 'package:pilas/games/banco/laboratorio_bank.dart';
import 'package:pilas/games/carrera/carrera_generator.dart';
import 'package:pilas/games/choice/choice_round.dart';
import 'package:pilas/games/clasifica/clasifica_generator.dart';
import 'package:pilas/games/cocina/cocina_generator.dart';
import 'package:pilas/games/emociones/emociones_generator.dart';
import 'package:pilas/games/figuras/figuras_generator.dart';
import 'package:pilas/games/intruso/intruso_generator.dart';
import 'package:pilas/games/memoria/memoria_board.dart';
import 'package:pilas/games/patrones/patrones_generator.dart';
import 'package:pilas/games/reloj/reloj_generator.dart';
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
  final List<ChoiceGenerator> generators = <ChoiceGenerator>[IntrusoGenerator(), SonidosGenerator(), PatronesGenerator(), EmocionesGenerator(), ClasificaGenerator(), CarreraGenerator(), RelojGenerator(), CocinaGenerator(), FigurasGenerator()];
  final Map<Type, List<AgeBand>> bands = <Type, List<AgeBand>>{
    IntrusoGenerator: <AgeBand>[AgeBand.b3a4, AgeBand.b5a6, AgeBand.b7a8],
    SonidosGenerator: <AgeBand>[AgeBand.b3a4, AgeBand.b5a6],
    PatronesGenerator: AgeBand.values,
    EmocionesGenerator: <AgeBand>[AgeBand.b3a4, AgeBand.b5a6, AgeBand.b7a8],
    ClasificaGenerator: AgeBand.values,
    CarreraGenerator: <AgeBand>[AgeBand.b5a6, AgeBand.b7a8, AgeBand.b9a11],
    RelojGenerator: <AgeBand>[AgeBand.b5a6, AgeBand.b7a8, AgeBand.b9a11],
    CocinaGenerator: <AgeBand>[AgeBand.b5a6, AgeBand.b7a8, AgeBand.b9a11],
    FigurasGenerator: AgeBand.values,
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

  test('Los bancos de preguntas están completos y generan rondas válidas', () {
    final Map<String, List<BankQuestion>> bancos = <String, List<BankQuestion>>{'cuerpo': CuerpoBank.all, 'laboratorio': LaboratorioBank.all, 'decisiones': DecisionesBank.all};
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
      final BankGenerator g = BankGenerator(banco);
      for (final AgeBand band in AgeBand.values) {
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

  test('Las fracciones se nombran bien', () {
    expect(CocinaGenerator.nombreFraccion(1, 2), 'un medio');
    expect(CocinaGenerator.nombreFraccion(3, 4), '3 cuartos');
    expect(CocinaGenerator.nombreFraccion(1, 3), 'un tercio');
    expect(CocinaGenerator.nombreFraccion(5, 8), '5 octavos');
  });

  test('El reloj nombra las horas como se dicen en Colombia', () {
    expect(RelojGenerator.nombreHora(1, 0), 'la una en punto');
    expect(RelojGenerator.nombreHora(3, 30), 'las 3 y media');
    expect(RelojGenerator.nombreHora(5, 15), 'las 5 y cuarto');
    expect(RelojGenerator.nombreHora(12, 45), 'la una menos cuarto');
    expect(RelojGenerator.nombreHora(8, 45), 'las 9 menos cuarto');
    expect(RelojGenerator.nombreHora(10, 20), 'las 10 y 20');
    expect(RelojGenerator.digital(9, 5), '9:05');
  });

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
