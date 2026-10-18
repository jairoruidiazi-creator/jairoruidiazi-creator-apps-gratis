import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/content/coloring_pages.dart';
import 'package:pilas/core/rng.dart';
import 'package:pilas/engine/game_def.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/engine/mastery.dart';
import 'package:pilas/games/choice/choice_round.dart';
import 'package:pilas/games/colorear/colorear_screen.dart';
import 'package:pilas/games/laberinto/maze.dart';
import 'package:pilas/games/memoria/memoria_board.dart';
import 'package:pilas/games/oracion/oracion_generator.dart';
import 'package:pilas/games/palabra/palabra_round.dart';
import 'package:pilas/games/pixel/pixel_patterns.dart';
import 'package:pilas/games/rompecabezas/rompecabezas_screen.dart';
import 'package:pilas/games/rutinas/rutinas_generator.dart';
import 'package:pilas/games/shell/order_game_screen.dart';
import 'package:pilas/games/shell/tile_order_board.dart';
import 'package:pilas/games/sudoku/sudoku_board.dart';
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

  group('Tableros (M1): un jugador que toca al azar no sube de nivel', () {
    // La regla de los tableros: dos tableros eficientes de los últimos tres.
    double ventana(double p) => colaBinomial(MasteryRule.tablero.window, MasteryRule.tablero.toAdvance, p);
    const int tableros = 1500;

    /// Recorre los niveles de un tablero y comprueba la ventana.
    void porNivel(String id, double Function(AgeBand band, int level) probabilidad) {
      final GameDef game = GameRegistry.byId(id)!;
      expect(game.mastery, MasteryRule.tablero);
      for (final AgeBand band in AgeBand.values) {
        if (!game.supports(band)) {
          continue;
        }
        for (int level = 1; level <= game.levelsFor(band); level++) {
          final double p = probabilidad(band, level);
          expect(ventana(p), lessThan(umbral), reason: '$id ${band.id} nivel $level: al azar sale eficiente el ${(p * 100).toStringAsFixed(1)} % de los tableros');
        }
      }
    }

    test('Memoria: voltear cartas al azar', () {
      porNivel('memoria', (AgeBand band, int level) {
        int bien = 0;
        int bienConMemoria = 0;
        for (int seed = 0; seed < tableros; seed++) {
          final math.Random azar = math.Random(seed);
          // Al azar: dos cartas sin pareja cualesquiera.
          final MemoryBoard b = MemoryBoard.generate(Rng(seed * 3 + level), band, level);
          while (!b.done) {
            final List<MemoryCard> quedan = b.cards.where((MemoryCard c) => !c.matched).toList()..shuffle(azar);
            if (quedan[0].pairId == quedan[1].pairId) {
              quedan[0].matched = true;
              quedan[1].matched = true;
            } else {
              b.mismatches += 1;
            }
          }
          if (b.efficient) {
            bien += 1;
          }
          // Con memoria: recuerda cada carta que ya vio.
          final MemoryBoard m = MemoryBoard.generate(Rng(seed * 3 + level), band, level);
          final Map<int, int> vistas = <int, int>{};
          while (!m.done) {
            MemoryCard? a;
            MemoryCard? c;
            final Map<int, MemoryCard> porPareja = <int, MemoryCard>{};
            for (final MemoryCard x in m.cards.where((MemoryCard x) => !x.matched && vistas.containsKey(x.id))) {
              final MemoryCard? otra = porPareja[x.pairId];
              if (otra != null) {
                a = otra;
                c = x;
                break;
              }
              porPareja[x.pairId] = x;
            }
            final MemoryCard primera;
            final MemoryCard segunda;
            if (a != null && c != null) {
              primera = a;
              segunda = c;
            } else {
              final List<MemoryCard> nuevas = m.cards.where((MemoryCard x) => !x.matched && !vistas.containsKey(x.id)).toList()..shuffle(azar);
              primera = nuevas.first;
              vistas[primera.id] = primera.pairId;
              segunda = porPareja[primera.pairId] ?? nuevas[1];
              vistas[segunda.id] = segunda.pairId;
            }
            if (primera.pairId == segunda.pairId) {
              primera.matched = true;
              segunda.matched = true;
            } else {
              m.mismatches += 1;
            }
          }
          if (m.efficient) {
            bienConMemoria += 1;
          }
        }
        // El umbral no es tan estricto que castigue a quien sí recuerda.
        expect(bienConMemoria / tableros, greaterThan(0.95), reason: 'memoria ${band.id} nivel $level con memoria perfecta');
        return bien / tableros;
      });
    });

    test('Laberintos: caminar al azar', () {
      porNivel('laberintos', (AgeBand band, int level) {
        int bien = 0;
        for (int seed = 0; seed < tableros; seed++) {
          final math.Random azar = math.Random(seed);
          final Maze m = Maze.generate(Rng(seed * 5 + level), band, level);
          final int tope = (m.optimalSteps * 1.6 + 2).floor();
          int pos = m.start;
          int pasos = 0;
          bool llave = m.keyCell < 0;
          while (pasos <= tope && !(pos == m.goal && llave)) {
            final List<int> vecinos = <int>[
              for (final int d in <int>[Maze.n, Maze.e, Maze.s, Maze.w])
                if (m.neighbor(pos, d) >= 0) m.neighbor(pos, d),
            ];
            pos = vecinos[azar.nextInt(vecinos.length)];
            pasos += 1;
            if (pos == m.keyCell) {
              llave = true;
            }
          }
          if (pos == m.goal && llave && m.eficiente(pasos)) {
            bien += 1;
          }
        }
        return bien / tableros;
      });
    });

    test('Rompecabezas: soltar piezas o cambiar fichas al azar', () {
      porNivel('rompecabezas', (AgeBand band, int level) {
        int bien = 0;
        for (int seed = 0; seed < tableros; seed++) {
          final math.Random azar = math.Random(seed);
          if (band == AgeBand.b3a4 || band == AgeBand.b5a6) {
            final EncajeRound r = EncajeRound.generate(Rng(seed * 7 + level), band, level);
            final List<EncajePiece> siluetas = List<EncajePiece>.from(r.targets);
            final List<EncajePiece> bandeja = List<EncajePiece>.from(r.tray);
            int errores = 0;
            while (siluetas.isNotEmpty && errores <= EncajeRound.erroresPermitidos) {
              final EncajePiece pieza = bandeja[azar.nextInt(bandeja.length)];
              final EncajePiece silueta = siluetas[azar.nextInt(siluetas.length)];
              if (EncajeRound.encaja(pieza, silueta)) {
                siluetas.remove(silueta);
                bandeja.remove(pieza);
              } else {
                errores += 1;
              }
            }
            if (siluetas.isEmpty && errores <= EncajeRound.erroresPermitidos) {
              bien += 1;
            }
          } else {
            final SwapPuzzle p = SwapPuzzle.generate(Rng(seed * 7 + level), band, level);
            final int tope = p.minInicial + p.n;
            while (!p.solved && p.swaps <= tope) {
              final int a = azar.nextInt(p.order.length);
              int b = azar.nextInt(p.order.length - 1);
              if (b >= a) {
                b += 1;
              }
              final int t = p.order[a];
              p.order[a] = p.order[b];
              p.order[b] = t;
              p.swaps += 1;
            }
            if (p.solved && p.eficiente) {
              bien += 1;
            }
          }
        }
        return bien / tableros;
      });
    });

    test('Sudoku: poner símbolos al azar', () {
      porNivel('sudoku', (AgeBand band, int level) {
        int bien = 0;
        const int n = 300;
        for (int seed = 0; seed < n; seed++) {
          final math.Random azar = math.Random(seed);
          final SudokuBoard b = SudokuBoard.generate(Rng(seed * 11 + level), band, level);
          int errores = 0;
          while (!b.complete && errores <= b.erroresPermitidos) {
            final List<int> vacias = <int>[for (int i = 0; i < b.cells.length; i++) if (b.cells[i] == 0) i];
            final int i = vacias[azar.nextInt(vacias.length)];
            final int v = 1 + azar.nextInt(b.size);
            if (b.conflicts(i, v)) {
              errores += 1;
              continue;
            }
            b.cells[i] = v;
            if (!b.complete && b.deadEndCell() != null) {
              // La app marca las casillas equivocadas: el jugador las quita.
              errores += 1;
              for (final int w in b.wrongCells()) {
                b.cells[w] = 0;
              }
            }
          }
          if (b.complete && errores <= b.erroresPermitidos) {
            bien += 1;
          }
        }
        return bien / n;
      });
    });

    test('Colorear por números: tocar zonas con colores al azar', () {
      // Cada zona se toca con colores al azar hasta acertar: los errores de
      // una zona siguen una geométrica con p = 1/colores. La probabilidad de
      // terminar con pocos errores es la de la binomial negativa.
      final List<ColoringPage> paginas = <ColoringPage>[
        for (final FileSystemEntity f in Directory('assets/coloring').listSync())
          if (f is File && f.path.endsWith('.json') && !f.path.endsWith('index.json')) ColoringPage.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>),
      ];
      expect(paginas, isNotEmpty);
      double peor = 0;
      for (final ColoringPage page in paginas) {
        final int zonas = page.regions.length;
        final double q = 1 / page.palette.length;
        double p = 0;
        for (int k = 0; k <= ColoringSession.erroresPermitidos; k++) {
          p += _comb(zonas + k - 1, k) * math.pow(q, zonas) * math.pow(1 - q, k);
        }
        peor = math.max(peor, p);
        expect(ventana(p), lessThan(umbral), reason: '${page.id}: $zonas zonas y ${page.palette.length} colores');
      }
      expect(GameRegistry.byId('colorear_numeros')!.mastery, MasteryRule.tablero);
      expect(peor, lessThan(0.05));
    });

    test('Pixel art: pintar casillas al azar', () {
      // Cada casilla al azar entre los colores de la paleta y "sin pintar":
      // cota de la probabilidad de no pasar de la tolerancia.
      final int opciones = PixelPalette.order.length + 1;
      for (final int lado in <int>[6, 8, 10, 12]) {
        for (final bool espejo in <bool>[false, true]) {
          final int casillas = espejo ? lado * (lado - lado ~/ 2) : lado * lado;
          double p = 0;
          for (int k = 0; k <= PixelPatterns.tolerancia(lado); k++) {
            p += _comb(casillas, k) * math.pow((opciones - 1) / opciones, k) * math.pow(1 / opciones, casillas - k);
          }
          expect(ventana(p), lessThan(umbral), reason: 'pixel $lado×$lado');
        }
      }
      expect(GameRegistry.byId('pixel')!.mastery, MasteryRule.tablero);
    });
  });
}
