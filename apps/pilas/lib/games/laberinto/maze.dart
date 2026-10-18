import 'dart:collection';

import '../../core/es.dart';
import '../../core/rng.dart';
import '../../model/age_band.dart';

/// Un personaje y lo que busca, para dar sentido al laberinto.
class MazeTheme {
  const MazeTheme(this.heroe, this.heroeNombre, this.heroeGenero, this.meta, this.metaNombre, this.metaGenero);

  final String heroe;
  final String heroeNombre;
  final String heroeGenero;
  final String meta;
  final String metaNombre;
  final String metaGenero;

  /// "el conejo", "la abeja".
  String get heroeConArticulo => Es.con(heroeGenero, heroeNombre);

  /// "al conejo", "a la abeja".
  String get aHeroe => Es.aEl(heroeGenero, heroeNombre);

  /// "la zanahoria", "el mar".
  String get metaConArticulo => Es.con(metaGenero, metaNombre);

  /// "a la zanahoria", "al mar".
  String get aMeta => Es.aEl(metaGenero, metaNombre);

  static const List<MazeTheme> all = <MazeTheme>[
    MazeTheme('1f407', 'conejo', 'm', '1f955', 'zanahoria', 'f'),
    MazeTheme('1f415', 'perro', 'm', '1f9b4', 'hueso', 'm'),
    MazeTheme('1f41d', 'abeja', 'f', '1f33b', 'flor', 'f'),
    MazeTheme('1f408', 'gato', 'm', '1f41f', 'pescado', 'm'),
    MazeTheme('1f9d2', 'niño', 'm', '1f3e1', 'casa', 'f'),
    MazeTheme('1f412', 'mono', 'm', '1f34c', 'banano', 'm'),
    MazeTheme('1f422', 'tortuga', 'f', '1f30a', 'mar', 'm'),
    MazeTheme('1f680', 'cohete', 'm', '1f319', 'luna', 'f'),
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

  /// Si [steps] pasos cuentan como un recorrido eficiente: hasta un 60 % más
  /// que el mínimo, y dos pasos de gracia. Caminar al azar casi nunca lo
  /// logra (test/random_player_test.dart).
  bool eficiente(int steps) => steps <= optimalSteps * 1.6 + 2;

  /// Pasos mínimos para resolverlo (pasando por la llave si la hay).
  int get optimalSteps => keyCell < 0 ? shortest(start, goal) : shortest(start, keyCell) + shortest(keyCell, goal);

  /// Columnas y filas (acostado) de cada tramo y nivel. Los laberintos son
  /// rectangulares para que en un teléfono, de pie o acostado, cada casilla
  /// mida al menos 24 dp: de pie se muestran girados (filas por columnas), que
  /// es el mismo laberinto con el mismo camino.
  static List<int> sizeFor(AgeBand band, int level) {
    const Map<AgeBand, List<List<int>>> tamanos = <AgeBand, List<List<int>>>{
      AgeBand.b3a4: <List<int>>[<int>[4, 4], <int>[5, 4], <int>[6, 4], <int>[6, 5]],
      AgeBand.b5a6: <List<int>>[<int>[6, 4], <int>[7, 5], <int>[8, 6], <int>[9, 7]],
      AgeBand.b7a8: <List<int>>[<int>[9, 7], <int>[10, 8], <int>[12, 8], <int>[13, 9]],
      AgeBand.b9a11: <List<int>>[<int>[13, 9], <int>[14, 10], <int>[15, 11], <int>[16, 12]],
    };
    return tamanos[band]![(level - 1).clamp(0, 3).toInt()];
  }

  /// El mismo laberinto girado: la columna pasa a ser fila. La salida sigue
  /// arriba a la izquierda y la meta abajo a la derecha.
  Maze transposed() {
    final List<int> muros = List<int>.filled(cols * rows, 0);
    for (int i = 0; i < cols * rows; i++) {
      int bits = 0;
      // Al girar, el norte pasa a ser el oeste y el este pasa a ser el sur.
      if (hasWall(i, n)) {
        bits |= w;
      }
      if (hasWall(i, w)) {
        bits |= n;
      }
      if (hasWall(i, s)) {
        bits |= e;
      }
      if (hasWall(i, e)) {
        bits |= s;
      }
      muros[transposeIndex(i)] = bits;
    }
    return Maze._(rows, cols, muros, theme, keyCell: keyCell < 0 ? -1 : transposeIndex(keyCell));
  }

  /// Índice de una celda en el laberinto girado.
  int transposeIndex(int i) => colOf(i) * rows + rowOf(i);


  static bool keyFor(AgeBand band, int level) => (band == AgeBand.b7a8 && level >= 3) || (band == AgeBand.b9a11 && level >= 2);

  /// Genera un laberinto perfecto (un solo camino entre dos celdas) con el
  /// algoritmo de retroceso. Para los más pequeños se abren algunas paredes
  /// extra, para que haya menos callejones sin salida.
  static Maze generate(Rng rng, AgeBand band, int level) {
    final List<int> size = sizeFor(band, level);
    final int cols = size[0];
    final int rows = size[1];
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
