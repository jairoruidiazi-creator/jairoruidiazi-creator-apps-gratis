import '../../core/rng.dart';
import '../../model/age_band.dart';

/// Tablero de sudoku de 4×4, 6×6 o 9×9. Los valores van de 1 a [size];
/// 0 es casilla vacía.
class SudokuBoard {
  SudokuBoard._({required this.size, required this.boxRows, required this.boxCols, required this.solution, required this.given, required this.emojis});

  final int size;

  /// Filas y columnas de cada región.
  final int boxRows;
  final int boxCols;
  final List<int> solution;

  /// Valores dados (0 = vacío). El niño rellena [cells].
  final List<int> given;
  late final List<int> cells = List<int>.from(given);

  /// Pictogramas para los símbolos (vacío = se usan números).
  final List<String> emojis;

  bool get usesEmoji => emojis.isNotEmpty;

  int index(int r, int c) => r * size + c;

  bool isGiven(int i) => given[i] != 0;

  bool get complete => !cells.contains(0);

  /// Si hay un valor repetido en la fila, la columna o la región de [i]
  /// (sin contar la casilla misma).
  bool conflicts(int i, int value) {
    final int r = i ~/ size;
    final int c = i % size;
    for (int k = 0; k < size; k++) {
      final int ri = index(r, k);
      final int ci = index(k, c);
      if (ri != i && cells[ri] == value) {
        return true;
      }
      if (ci != i && cells[ci] == value) {
        return true;
      }
    }
    final int br = (r ~/ boxRows) * boxRows;
    final int bc = (c ~/ boxCols) * boxCols;
    for (int rr = br; rr < br + boxRows; rr++) {
      for (int cc = bc; cc < bc + boxCols; cc++) {
        final int bi = index(rr, cc);
        if (bi != i && cells[bi] == value) {
          return true;
        }
      }
    }
    return false;
  }

  /// Dónde está el conflicto, para la pista: 'fila', 'columna' o 'región'.
  String conflictPlace(int i, int value) {
    final int r = i ~/ size;
    final int c = i % size;
    for (int k = 0; k < size; k++) {
      if (index(r, k) != i && cells[index(r, k)] == value) {
        return 'fila';
      }
    }
    for (int k = 0; k < size; k++) {
      if (index(k, c) != i && cells[index(k, c)] == value) {
        return 'columna';
      }
    }
    return 'región';
  }

  String label(int value) => value <= 0 ? '' : (usesEmoji ? emojis[value - 1] : '$value');

  // ------------------------------------------------------------ generación

  static const List<List<String>> _emojiSets = <List<String>>[
    <String>['1f34e', '1f34c', '1f347', '1f353'], // frutas
    <String>['1f408', '1f415', '1f407', '1f41f'], // animales
    <String>['2600', '1f319', '2b50', '2601'], // cielo
    <String>['1f697', '1f6b2', '1f6a4', '2708'], // transporte
  ];

  static int sizeFor(AgeBand band, int level) {
    switch (band) {
      case AgeBand.b3a4:
      case AgeBand.b5a6:
        return 4;
      case AgeBand.b7a8:
        return 6;
      case AgeBand.b9a11:
        return level == 1 ? 6 : 9;
    }
  }

  static int givensFor(AgeBand band, int level) {
    switch (band) {
      case AgeBand.b3a4:
      case AgeBand.b5a6:
        return <int>[11, 9, 8, 7][level - 1];
      case AgeBand.b7a8:
        return <int>[26, 22, 19, 16][level - 1];
      case AgeBand.b9a11:
        return <int>[16, 46, 40, 34][level - 1];
    }
  }

  static SudokuBoard generate(Rng rng, AgeBand band, int level) {
    final int size = sizeFor(band, level);
    final int boxRows = size == 9 ? 3 : (size == 6 ? 2 : 2);
    final int boxCols = size == 9 ? 3 : (size == 6 ? 3 : 2);
    // Solución base por desplazamiento y mezcla de símbolos, filas y columnas.
    final List<int> symbols = <int>[for (int i = 1; i <= size; i++) i];
    rng.shuffle(symbols);
    final List<int> rowOrder = _shuffledLines(rng, size, boxRows);
    final List<int> colOrder = _shuffledLines(rng, size, boxCols);
    final List<int> solution = List<int>.filled(size * size, 0);
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        final int rr = rowOrder[r];
        final int cc = colOrder[c];
        final int base = (boxCols * (rr % boxRows) + rr ~/ boxRows + cc) % size;
        solution[r * size + c] = symbols[base];
      }
    }
    // Quitar casillas manteniendo solución única.
    final List<int> given = List<int>.from(solution);
    final List<int> order = <int>[for (int i = 0; i < size * size; i++) i];
    rng.shuffle(order);
    int remaining = size * size;
    final int target = givensFor(band, level);
    for (final int i in order) {
      if (remaining <= target) {
        break;
      }
      final int backup = given[i];
      given[i] = 0;
      if (_countSolutions(given, size, boxRows, boxCols, 2) == 1) {
        remaining -= 1;
      } else {
        given[i] = backup;
      }
    }
    final bool emoji = size == 4 && level <= 2;
    return SudokuBoard._(
      size: size,
      boxRows: boxRows,
      boxCols: boxCols,
      solution: solution,
      given: given,
      emojis: emoji ? rng.pick(_emojiSets) : const <String>[],
    );
  }

  static List<int> _shuffledLines(Rng rng, int size, int band) {
    final int bands = size ~/ band;
    final List<int> bandOrder = <int>[for (int i = 0; i < bands; i++) i];
    rng.shuffle(bandOrder);
    final List<int> out = <int>[];
    for (final int b in bandOrder) {
      final List<int> lines = <int>[for (int i = 0; i < band; i++) b * band + i];
      rng.shuffle(lines);
      out.addAll(lines);
    }
    return out;
  }

  static bool _allowed(List<int> grid, int size, int boxRows, int boxCols, int i, int v) {
    final int r = i ~/ size;
    final int c = i % size;
    for (int k = 0; k < size; k++) {
      if (grid[r * size + k] == v || grid[k * size + c] == v) {
        return false;
      }
    }
    final int br = (r ~/ boxRows) * boxRows;
    final int bc = (c ~/ boxCols) * boxCols;
    for (int rr = br; rr < br + boxRows; rr++) {
      for (int cc = bc; cc < bc + boxCols; cc++) {
        if (grid[rr * size + cc] == v) {
          return false;
        }
      }
    }
    return true;
  }

  /// Cuenta soluciones hasta [cap], eligiendo siempre la casilla con menos
  /// candidatos para que el conteo sea rápido incluso en 9×9.
  static int _countSolutions(List<int> grid, int size, int boxRows, int boxCols, int cap) {
    int best = -1;
    List<int> bestCands = const <int>[];
    for (int i = 0; i < grid.length; i++) {
      if (grid[i] != 0) {
        continue;
      }
      final List<int> cands = <int>[];
      for (int v = 1; v <= size; v++) {
        if (_allowed(grid, size, boxRows, boxCols, i, v)) {
          cands.add(v);
        }
      }
      if (cands.isEmpty) {
        return 0;
      }
      if (best < 0 || cands.length < bestCands.length) {
        best = i;
        bestCands = cands;
        if (cands.length == 1) {
          break;
        }
      }
    }
    if (best < 0) {
      return 1;
    }
    int count = 0;
    for (final int v in bestCands) {
      grid[best] = v;
      count += _countSolutions(grid, size, boxRows, boxCols, cap - count);
      grid[best] = 0;
      if (count >= cap) {
        return count;
      }
    }
    return count;
  }
}
