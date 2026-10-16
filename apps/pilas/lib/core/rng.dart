import 'dart:math';

/// Azar con semilla opcional, para que los generadores de juegos sean
/// reproducibles en las pruebas.
class Rng {
  Rng([int? seed]) : _random = Random(seed);

  final Random _random;

  int nextInt(int max) => max <= 0 ? 0 : _random.nextInt(max);

  /// Entero en [min, max], ambos incluidos.
  int range(int min, int max) {
    if (max <= min) {
      return min;
    }
    return min + _random.nextInt(max - min + 1);
  }

  double nextDouble() => _random.nextDouble();

  bool chance(double probability) => _random.nextDouble() < probability;

  T pick<T>(List<T> items) {
    if (items.isEmpty) {
      throw ArgumentError('No hay elementos para elegir');
    }
    return items[_random.nextInt(items.length)];
  }

  /// Elige un elemento distinto de los excluidos.
  T pickExcept<T>(List<T> items, Iterable<T> exclude) {
    final Set<T> ex = exclude.toSet();
    final List<T> pool = items.where((T e) => !ex.contains(e)).toList();
    return pick(pool);
  }

  /// Muestra sin repetición de [count] elementos.
  List<T> sample<T>(List<T> items, int count) {
    final List<T> copy = List<T>.from(items);
    shuffle(copy);
    if (count >= copy.length) {
      return copy;
    }
    return copy.sublist(0, count);
  }

  void shuffle<T>(List<T> items) {
    for (int i = items.length - 1; i > 0; i--) {
      final int j = _random.nextInt(i + 1);
      final T tmp = items[i];
      items[i] = items[j];
      items[j] = tmp;
    }
  }

  List<T> shuffled<T>(List<T> items) {
    final List<T> copy = List<T>.from(items);
    shuffle(copy);
    return copy;
  }
}
