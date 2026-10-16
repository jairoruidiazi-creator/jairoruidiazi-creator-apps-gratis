import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/core/rng.dart';
import 'package:pilas/games/laberinto/maze.dart';
import 'package:pilas/games/oracion/oracion_generator.dart';
import 'package:pilas/games/palabra/palabra_generator.dart';
import 'package:pilas/games/rutinas/rutinas_generator.dart';
import 'package:pilas/games/shell/order_game_screen.dart';
import 'package:pilas/games/sudoku/sudoku_board.dart';
import 'package:pilas/model/age_band.dart';

void main() {
  test('Los laberintos siempre tienen salida y la llave es alcanzable', () {
    for (final AgeBand band in AgeBand.values) {
      for (int level = 1; level <= 4; level++) {
        for (int seed = 0; seed < 6; seed++) {
          final Maze m = Maze.generate(Rng(seed * 7 + level), band, level);
          expect(m.cols, Maze.sizeFor(band, level));
          expect(m.shortest(m.start, m.goal), greaterThan(0), reason: '${band.id} nivel $level semilla $seed');
          expect(m.optimalSteps, greaterThan(0));
          if (Maze.keyFor(band, level)) {
            expect(m.keyCell, greaterThanOrEqualTo(0));
            expect(m.keyCell, isNot(m.start));
            expect(m.keyCell, isNot(m.goal));
          } else {
            expect(m.keyCell, -1);
          }
          // Las paredes son coherentes entre vecinos.
          for (int i = 0; i < m.cols * m.rows; i++) {
            final int east = m.colOf(i) < m.cols - 1 ? i + 1 : -1;
            if (east >= 0) {
              expect(m.hasWall(i, Maze.e), m.hasWall(east, Maze.w), reason: 'pared este/oeste incoherente en $i');
            }
            final int south = m.rowOf(i) < m.rows - 1 ? i + m.cols : -1;
            if (south >= 0) {
              expect(m.hasWall(i, Maze.s), m.hasWall(south, Maze.n), reason: 'pared sur/norte incoherente en $i');
            }
          }
        }
      }
    }
  });

  test('Los sudokus tienen solución válida, única y el número de pistas esperado', () {
    for (final AgeBand band in <AgeBand>[AgeBand.b5a6, AgeBand.b7a8, AgeBand.b9a11]) {
      for (int level = 1; level <= 4; level++) {
        for (int seed = 0; seed < 3; seed++) {
          final SudokuBoard b = SudokuBoard.generate(Rng(seed * 13 + level), band, level);
          final int n = b.size;
          expect(n, SudokuBoard.sizeFor(band, level));
          // La solución respeta filas, columnas y regiones.
          for (int r = 0; r < n; r++) {
            expect(<int>{for (int c = 0; c < n; c++) b.solution[r * n + c]}.length, n, reason: 'fila $r');
            expect(<int>{for (int c = 0; c < n; c++) b.solution[c * n + r]}.length, n, reason: 'columna $r');
          }
          for (int br = 0; br < n; br += b.boxRows) {
            for (int bc = 0; bc < n; bc += b.boxCols) {
              final Set<int> vals = <int>{};
              for (int r = br; r < br + b.boxRows; r++) {
                for (int c = bc; c < bc + b.boxCols; c++) {
                  vals.add(b.solution[r * n + c]);
                }
              }
              expect(vals.length, n, reason: 'región $br,$bc');
            }
          }
          // Las pistas son parte de la solución.
          final int givens = b.given.where((int v) => v != 0).length;
          for (int i = 0; i < n * n; i++) {
            if (b.given[i] != 0) {
              expect(b.given[i], b.solution[i]);
            }
          }
          expect(givens, lessThanOrEqualTo(SudokuBoard.givensFor(band, level) + 6), reason: '${band.id} nivel $level: demasiadas pistas ($givens)');
          expect(givens, greaterThan(0));
          // Colocar la solución completa nunca produce conflictos.
          for (int i = 0; i < n * n; i++) {
            if (b.cells[i] == 0) {
              expect(b.conflicts(i, b.solution[i]), isFalse);
              b.cells[i] = b.solution[i];
            }
          }
          expect(b.complete, isTrue);
          expect(b.usesEmoji, n == 4 && level <= 2);
        }
      }
    }
  });

  test('Arma la palabra: las fichas contienen todas las letras y los distractores no repiten', () {
    final PalabraGenerator g = PalabraGenerator();
    for (final AgeBand band in <AgeBand>[AgeBand.b5a6, AgeBand.b7a8, AgeBand.b9a11]) {
      for (int level = 1; level <= 4; level++) {
        for (int seed = 0; seed < 30; seed++) {
          final PalabraRound r = g.next(Rng(seed * 3 + level), band, level);
          final List<String> fichas = List<String>.from(r.fichas);
          for (final String l in r.letras) {
            expect(fichas.remove(l), isTrue, reason: 'falta la letra $l de ${r.palabra}');
          }
          // Lo que sobra son distractores, ninguno igual a una letra de la palabra.
          for (final String d in fichas) {
            expect(r.letras.contains(d), isFalse, reason: 'distractor $d repetido en ${r.palabra}');
          }
          expect(r.pista, isNotEmpty);
          if (band == AgeBand.b9a11 && level < 4) {
            expect(RegExp('[áéíóú]').hasMatch(r.palabra), isTrue, reason: '${r.palabra} debería llevar tilde');
          }
        }
      }
    }
  });

  test('Ordena la oración y rutinas producen rondas coherentes', () {
    for (final AgeBand band in AgeBand.values) {
      for (int level = 1; level <= 4; level++) {
        for (int seed = 0; seed < 10; seed++) {
          final Rng rng = Rng(seed + level * 100);
          final OrderRound o = oracionRound(rng, band, level);
          expect(o.ordered.length, o.shuffled.length);
          expect(o.ordered.length, greaterThanOrEqualTo(3));
          final OrderRound r = rutinaRound(rng, band, level);
          expect(r.ordered.length, r.shuffled.length);
          expect(r.ordered.length, greaterThanOrEqualTo(3));
          expect(r.ordered.length, lessThanOrEqualTo(5));
          expect(r.slotLabels!.length, r.ordered.length);
        }
      }
    }
    // Las oraciones empiezan con mayúscula y terminan con punto.
    for (final List<Oracion> banco in <List<Oracion>>[OracionBank.b5a6, OracionBank.b7a8, OracionBank.b9a11]) {
      for (final Oracion o in banco) {
        expect(o.palabras.first[0], o.palabras.first[0].toUpperCase(), reason: o.texto);
        expect(o.palabras.last.endsWith('.'), isTrue, reason: o.texto);
      }
    }
    // Cada rutina tiene ids de paso únicos.
    for (final Rutina r in RutinaBank.all) {
      expect(r.pasos.map((Paso p) => p.id).toSet().length, r.pasos.length, reason: r.id);
    }
  });
}
