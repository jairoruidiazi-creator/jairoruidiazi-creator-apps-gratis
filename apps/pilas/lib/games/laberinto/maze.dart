import 'dart:collection';

import '../../core/rng.dart';
import '../../model/age_band.dart';

/// Un personaje y lo que busca, para dar sentido al laberinto.
class MazeTheme {
  const MazeTheme(this.heroe, this.heroeNombre, this.meta, this.metaNombre);

  final String heroe;
  final String heroeNombre;
  final String meta;
  final String metaNombre;

  static const List<MazeTheme> all = <MazeTheme>[
    MazeTheme('1f407', 'el conejo', '1f955', 'la zanahoria'),
    MazeTheme('1f415', 'el perro', '1f9b4', 'el hueso'),
    MazeTheme('1f41d', 'la abeja', '1f33b', 'la flor'),
    MazeTheme('1f408', 'el gato', '1f41f', 'el pescado'),
    MazeTheme('1f9d2', 'el niño', '1f3e1', 'la casa'),
    MazeTheme('1f412', 'el mono', '1f34c', 'el banano'),
    MazeTheme('1f422', 'la tortuga', '1f30a', 'el mar'),
    MazeTheme('1f680', 'el cohete', '1f319', 'la luna'),
  ];
}

/// Laberinto en cuadrícula. Cada celda guarda sus paredes como bits:
/// 1 = norte, 2 = este, 4 = sur, 8 = oeste.
class Maze {
  Maze._(this.cols, this.rows, this.walls, this.theme, {required this.keyCell});

  final int cols;
  final int rows;
  final List<int> walls;
  final MazeTheme theme;

  /// Celda de la llave que hay que recoger antes de la meta, o -1 si no hay.
  final int keyCell;

  static const int n = 1;
  static const int e = 2;
  static const int s = 4;
  static const int w = 8;

  int get start => 0;

  int get goal => cols * rows - 1;

  int index(int c, int r) => r * cols + c;

  int colOf(int i) => i % cols;

  int rowOf(int i) => i ~/ cols;

  bool hasWall(int cell, int dir) => walls[cell] & dir != 0;

  /// Vecino en la dirección dada si no hay pared; -1 si no se puede pasar.
  int neighbor(int cell, int dir) {
    if (hasWall(cell, dir)) {
      return -1;
    }
    final int c = colOf(cell);
    final int r = rowOf(cell);
    switch (dir) {
      case n:
        return r > 0 ? index(c, r - 1) : -1;
      case e:
        return c < cols - 1 ? index(c + 1, r) : -1;
      case s:
        return r < rows - 1 ? index(c, r + 1) : -1;
      default:
        return c > 0 ? index(c - 1, r) : -1;
    }
  }

  /// Si dos celdas son vecinas y no hay pared entre ellas.
  bool canMove(int from, int to) {
    for (final int d in <int>[n, e, s, w]) {
      if (neighbor(from, d) == to) {
        return true;
      }
    }
    return false;
  }

  /// Longitud del camino más corto entre dos celdas (en pasos).
  int shortest(int from, int to) {
    final List<int> dist = List<int>.filled(cols * rows, -1);
    final Queue<int> q = Queue<int>()..add(from);
    dist[from] = 0;
    while (q.isNotEmpty) {
      final int cur = q.removeFirst();
      if (cur == to) {
        return dist[cur];
      }
      for (final int d in <int>[n, e, s, w]) {
        final int nx = neighbor(cur, d);
        if (nx >= 0 && dist[nx] < 0) {
          dist[nx] = dist[cur] + 1;
          q.add(nx);
        }
      }
    }
    return -1;
  }

  /// Pasos mínimos para resolverlo (pasando por la llave si la hay).
  int get optimalSteps => keyCell < 0 ? shortest(start, goal) : shortest(start, keyCell) + shortest(keyCell, goal);

  static int sizeFor(AgeBand band, int level) {
    switch (band) {
      case AgeBand.b3a4:
        return <int>[3, 4, 4, 5][level - 1];
      case AgeBand.b5a6:
        return <int>[5, 6, 7, 8][level - 1];
      case AgeBand.b7a8:
        return <int>[8, 9, 10, 11][level - 1];
      case AgeBand.b9a11:
        return <int>[11, 12, 13, 15][level - 1];
    }
  }

  static bool keyFor(AgeBand band, int level) => (band == AgeBand.b7a8 && level >= 3) || (band == AgeBand.b9a11 && level >= 2);

  /// Genera un laberinto perfecto (un solo camino entre dos celdas) con el
  /// algoritmo de retroceso. Para los más pequeños se abren algunas paredes
  /// extra, para que haya menos callejones sin salida.
  static Maze generate(Rng rng, AgeBand band, int level) {
    final int size = sizeFor(band, level);
    final int cols = size;
    final int rows = size;
    final List<int> walls = List<int>.filled(cols * rows, n | e | s | w);
    final List<bool> visited = List<bool>.filled(cols * rows, false);
    final List<int> stack = <int>[0];
    visited[0] = true;
    while (stack.isNotEmpty) {
      final int cur = stack.last;
      final int c = cur % cols;
      final int r = cur ~/ cols;
      final List<List<int>> options = <List<int>>[];
      if (r > 0 && !visited[cur - cols]) {
        options.add(<int>[cur - cols, n, s]);
      }
      if (c < cols - 1 && !visited[cur + 1]) {
        options.add(<int>[cur + 1, e, w]);
      }
      if (r < rows - 1 && !visited[cur + cols]) {
        options.add(<int>[cur + cols, s, n]);
      }
      if (c > 0 && !visited[cur - 1]) {
        options.add(<int>[cur - 1, w, e]);
      }
      if (options.isEmpty) {
        stack.removeLast();
        continue;
      }
      final List<int> pick = rng.pick(options);
      walls[cur] &= ~pick[1];
      walls[pick[0]] &= ~pick[2];
      visited[pick[0]] = true;
      stack.add(pick[0]);
    }
    // Abrir paredes extra para los pequeños (más de un camino, menos frustración).
    final double extra = band == AgeBand.b3a4 ? 0.35 : (band == AgeBand.b5a6 ? 0.12 : 0.0);
    if (extra > 0) {
      for (int i = 0; i < cols * rows; i++) {
        final int c = i % cols;
        final int r = i ~/ cols;
        if (c < cols - 1 && (walls[i] & e) != 0 && rng.chance(extra)) {
          walls[i] &= ~e;
          walls[i + 1] &= ~w;
        }
        if (r < rows - 1 && (walls[i] & s) != 0 && rng.chance(extra)) {
          walls[i] &= ~s;
          walls[i + cols] &= ~n;
        }
      }
    }
    final MazeTheme theme = rng.pick(MazeTheme.all);
    int keyCell = -1;
    final Maze base = Maze._(cols, rows, walls, theme, keyCell: -1);
    if (keyFor(band, level)) {
      // La llave va en una celda lejos de la línea recta, que alargue el recorrido.
      int best = -1;
      int bestScore = -1;
      for (int t = 0; t < 12; t++) {
        final int cand = rng.range(1, cols * rows - 2);
        final int score = base.shortest(0, cand) + base.shortest(cand, cols * rows - 1) - base.shortest(0, cols * rows - 1);
        if (score > bestScore) {
          bestScore = score;
          best = cand;
        }
      }
      keyCell = best;
    }
    return Maze._(cols, rows, walls, theme, keyCell: keyCell);
  }
}
