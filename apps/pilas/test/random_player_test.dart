import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/core/rng.dart';
import 'package:pilas/engine/game_def.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/engine/mastery.dart';
import 'package:pilas/games/choice/choice_round.dart';
import 'package:pilas/games/oracion/oracion_generator.dart';
import 'package:pilas/games/palabra/palabra_round.dart';
import 'package:pilas/games/rutinas/rutinas_generator.dart';
import 'package:pilas/games/shell/order_game_screen.dart';
import 'package:pilas/games/shell/tile_order_board.dart';
import 'package:pilas/games/tienda/tienda_generator.dart';
import 'package:pilas/model/age_band.dart';

import 'support/choice_generators.dart';

/// Probabilidad de lograr al menos [k] aciertos en [n] rondas si cada ronda
/// se acierta con probabilidad [p] (cola de la binomial).
double colaBinomial(int n, int k, double p) {
  double total = 0;
  for (int j = k; j <= n; j++) {
    total += _comb(n, j) * math.pow(p, j) * math.pow(1 - p, n - j);
  }
  return total;
}

double _comb(int n, int k) {
  double r = 1;
  for (int i = 1; i <= k; i++) {
    r = r * (n - k + i) / i;
  }
  return r;
}

/// Ordenaciones distintas de una lista con repetidos (multiconjunto).
double _ordenacionesDistintas(List<String> valores) {
  final Map<String, int> cuenta = <String, int>{};
  for (final String v in valores) {
    cuenta[v] = (cuenta[v] ?? 0) + 1;
  }
  double r = 1;
  for (int i = 2; i <= valores.length; i++) {
    r *= i;
  }
  for (final int c in cuenta.values) {
    for (int i = 2; i <= c; i++) {
      r /= i;
    }
  }
  return r;
}

/// Un jugador que toca al azar no debe subir de nivel (ni lograr la
/// habilidad del último nivel) en más del 5 % de las ventanas de la regla de
/// dominio. Solo cuenta el primer intento, así que la probabilidad de acertar
/// una ronda al azar es 1 entre el número de opciones; en los juegos de
/// ordenar, las órdenes válidas entre todas las ordenaciones posibles.
void main() {
  const double umbral = 0.05;

  test('La regla de elegir con tres opciones da menos del 2 % al azar', () {
    const MasteryRule r = MasteryRule.eleccion;
    expect(colaBinomial(r.window, r.toAdvance, 1 / 3), lessThan(0.02));
    // Con dos opciones no alcanzaría: por eso ningún juego de elegir se queda
    // en dos opciones de forma habitual.
    expect(colaBinomial(r.window, r.toAdvance, 1 / 2), greaterThan(umbral));
  });

  for (final GeneratorCase c in choiceGeneratorCases()) {
    test('${c.gameId}: tocar al azar no sube de nivel', () {
      final GameDef game = c.game;
      for (final AgeBand band in AgeBand.values) {
        if (!game.supports(band)) {
          continue;
        }
        for (int level = 1; level <= game.levelsFor(band); level++) {
          final ChoiceGenerator g = c.generator();
          double suma = 0;
          const int n = 300;
          for (int seed = 0; seed < n; seed++) {
            final ChoiceRound r = g.next(Rng(seed * 7 + level), band, level);
            suma += 1 / r.options.length;
          }
          final double p = suma / n;
          final double cola = colaBinomial(game.mastery.window, game.mastery.toAdvance, p);
          expect(cola, lessThan(umbral), reason: '${c.gameId} ${band.id} nivel $level: al azar acierta el ${(p * 100).toStringAsFixed(1)} % de las rondas y sube de nivel en el ${(cola * 100).toStringAsFixed(1)} % de las ventanas');
        }
      }
    });
  }

  test('La tienda: tocar al azar no sube de nivel', () {
    final GameDef game = GameRegistry.byId('tienda')!;
    final TiendaGenerator g = TiendaGenerator();
    for (final AgeBand band in AgeBand.values) {
      for (int level = 1; level <= game.levelsFor(band); level++) {
        double suma = 0;
        int rondas = 0;
        for (int seed = 0; seed < 300; seed++) {
          final TiendaRound r = g.next(Rng(seed * 11 + level), band, level);
          if (r.choice != null) {
            suma += 1 / r.choice!.options.length;
            rondas += 1;
          } else {
            // Pagar exacto tocando monedas al azar casi nunca da el total:
            // se cuenta, por lo alto, como una ronda de tres opciones.
            suma += 1 / 3;
            rondas += 1;
          }
        }
        final double p = suma / rondas;
        expect(colaBinomial(game.mastery.window, game.mastery.toAdvance, p), lessThan(umbral), reason: 'tienda ${band.id} nivel $level');
      }
    }
  });

  test('Los juegos de ordenar: ordenar al azar no sube de nivel', () {
    final Map<String, OrderRoundBuilder> juegos = <String, OrderRoundBuilder>{'palabra': palabraRound, 'oracion': oracionRound, 'rutinas': rutinaRound};
    juegos.forEach((String id, OrderRoundBuilder builder) {
      final GameDef game = GameRegistry.byId(id)!;
      for (final AgeBand band in AgeBand.values) {
        if (!game.supports(band)) {
          continue;
        }
        for (int level = 1; level <= game.levelsFor(band); level++) {
          double suma = 0;
          const int n = 200;
          for (int seed = 0; seed < n; seed++) {
            final OrderRound r = builder(Rng(seed * 13 + level), band, level);
            final List<String> valores = <String>[for (final OrderTile t in r.ordered) t.value];
            final int validas = r.validOrders.map((List<String> o) => o.join('|')).toSet().length;
            suma += validas / _ordenacionesDistintas(valores);
          }
          final double p = suma / n;
          expect(colaBinomial(game.mastery.window, game.mastery.toAdvance, p), lessThan(umbral), reason: '$id ${band.id} nivel $level: p=${p.toStringAsFixed(3)}');
        }
      }
    });
  });
}
