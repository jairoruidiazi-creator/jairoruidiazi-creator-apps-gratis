import '../../content/vocab.dart';
import '../../core/rng.dart';
import '../../model/age_band.dart';

/// Una carta del tablero de memoria. Las parejas comparten [pairId].
class MemoryCard {
  MemoryCard({required this.id, required this.pairId, this.emoji, this.text, required this.label});

  final int id;
  final int pairId;

  /// Pictograma, si la carta es una imagen.
  final String? emoji;

  /// Texto, si la carta es una palabra, un número o una operación.
  final String? text;

  /// Nombre para la voz.
  final String label;
  bool faceUp = false;
  bool matched = false;
}

/// Tablero generado por reglas: parejas iguales para los pequeños y pareja
/// concepto-ejemplo u operación-resultado en primaria.
class MemoryBoard {
  MemoryBoard({required this.cards, required this.pairs, required this.previewSeconds, required this.columns, required this.descripcion});

  final List<MemoryCard> cards;
  final int pairs;

  /// Segundos que las cartas empiezan boca arriba (0 = ninguno).
  final int previewSeconds;
  final int columns;

  /// Qué tipo de parejas hay, para la instrucción.
  final String descripcion;

  int flips = 0;
  int mismatches = 0;

  bool get done => cards.every((MemoryCard c) => c.matched);

  /// Fallos con los que el tablero todavía cuenta como bien resuelto: con
  /// cuatro parejas o menos, uno menos que las parejas; desde cinco, uno más.
  /// Quien recuerda cada carta que ya vio siempre lo logra; quien toca al
  /// azar, en menos del 12 % de los tableros, y la regla de dominio casi
  /// nunca le sube de nivel (test/random_player_test.dart).
  static int fallosPermitidos(int pairs) => pairs <= 4 ? pairs - 1 : pairs + 1;

  /// Eficiencia: termina con pocos fallos para la cantidad de parejas.
  bool get efficient => mismatches <= fallosPermitidos(pairs);

  static int pairsFor(AgeBand band, int level) {
    switch (band) {
      case AgeBand.b3a4:
        // Con dos o tres parejas, tocar al azar se parece demasiado a
        // recordar: desde el primer nivel hay cuatro (y una vista previa).
        return <int>[4, 4, 4, 5][level.clamp(1, 4).toInt() - 1];
      case AgeBand.b5a6:
        return <int>[4, 5, 6, 6][level.clamp(1, 4).toInt() - 1];
      case AgeBand.b7a8:
        return <int>[6, 6, 8, 8][level.clamp(1, 4).toInt() - 1];
      case AgeBand.b9a11:
        return <int>[8, 8, 10, 10][level.clamp(1, 4).toInt() - 1];
    }
  }

  static int previewFor(AgeBand band, int level) {
    if (band == AgeBand.b3a4) {
      return <int>[4, 3, 0, 0][level.clamp(1, 4).toInt() - 1];
    }
    if (band == AgeBand.b5a6 && level == 1) {
      return 2;
    }
    return 0;
  }

  static MemoryBoard generate(Rng rng, AgeBand band, int level) {
    final int pairs = pairsFor(band, level);
    final List<MemoryCard> cards = <MemoryCard>[];
    String descripcion;
    int id = 0;
    if (band == AgeBand.b3a4 || band == AgeBand.b5a6) {
      final List<VocabItem> items = rng.sample(Vocab.withTag('animal').where((VocabItem v) => !v.nombre.contains(' ')).toList(), pairs);
      for (int p = 0; p < items.length; p++) {
        final VocabItem v = items[p];
        cards.add(MemoryCard(id: id++, pairId: p, emoji: v.emoji, label: v.nombre));
        cards.add(MemoryCard(id: id++, pairId: p, emoji: v.emoji, label: v.nombre));
      }
      descripcion = 'Encuentra las parejas iguales.';
    } else if (band == AgeBand.b7a8) {
      if (level <= 2) {
        // Grupo y ejemplo: "ave" con un pájaro.
        final List<String> tags = <String>['mamifero', 'ave', 'pez', 'reptil', 'insecto', 'fruta', 'verdura', 'vehiculo', 'ropa', 'instrumento'];
        final Map<String, String> nombres = <String, String>{
          'mamifero': 'mamífero', 'ave': 'ave', 'pez': 'pez', 'reptil': 'reptil', 'insecto': 'insecto',
          'fruta': 'fruta', 'verdura': 'verdura', 'vehiculo': 'vehículo', 'ropa': 'ropa', 'instrumento': 'instrumento',
        };
        final List<String> elegidos = rng.sample(tags, pairs);
        int p = 0;
        for (final String tag in elegidos) {
          final List<VocabItem> pool = Vocab.withTag(tag).where((VocabItem v) => !v.nombre.contains(' ')).toList();
          if (pool.isEmpty) {
            continue;
          }
          final VocabItem v = rng.pick(pool);
          cards.add(MemoryCard(id: id++, pairId: p, text: nombres[tag], label: nombres[tag] ?? tag));
          cards.add(MemoryCard(id: id++, pairId: p, emoji: v.emoji, label: v.nombre));
          p += 1;
        }
        descripcion = 'Une cada grupo con su ejemplo.';
      } else {
        // Suma o resta con su resultado.
        final Set<int> usados = <int>{};
        int p = 0;
        while (p < pairs) {
          final bool suma = rng.chance(0.6);
          final int a = rng.range(2, 12);
          final int b = rng.range(1, 9);
          final int r = suma ? a + b : (a > b ? a - b : b - a);
          if (usados.contains(r)) {
            continue;
          }
          usados.add(r);
          final String op = suma ? '$a + $b' : (a > b ? '$a − $b' : '$b − $a');
          cards.add(MemoryCard(id: id++, pairId: p, text: op, label: op.replaceAll('−', 'menos').replaceAll('+', 'más')));
          cards.add(MemoryCard(id: id++, pairId: p, text: '$r', label: '$r'));
          p += 1;
        }
        descripcion = 'Une cada operación con su resultado.';
      }
    } else {
      final Set<int> usados = <int>{};
      int p = 0;
      while (p < pairs) {
        final int tipo = level <= 2 ? 0 : rng.nextInt(3);
        String op;
        int r;
        if (tipo == 0) {
          final int a = rng.range(2, 9);
          final int b = rng.range(2, 9);
          op = '$a × $b';
          r = a * b;
        } else if (tipo == 1) {
          final int b = rng.range(2, 9);
          final int q = rng.range(2, 9);
          op = '${b * q} ÷ $b';
          r = q;
          // Se lee "cuarenta y ocho dividido entre seis".
        } else {
          final int n = rng.range(2, 25);
          op = 'doble de $n';
          r = n * 2;
        }
        if (usados.contains(r)) {
          continue;
        }
        usados.add(r);
        cards.add(MemoryCard(id: id++, pairId: p, text: op, label: op.replaceAll('×', 'por').replaceAll('÷', 'dividido entre')));
        cards.add(MemoryCard(id: id++, pairId: p, text: '$r', label: '$r'));
        p += 1;
      }
      descripcion = 'Une cada operación con su resultado.';
    }
    rng.shuffle(cards);
    final int total = cards.length;
    int columns;
    if (total <= 4) {
      columns = 2;
    } else if (total <= 8) {
      columns = total == 6 ? 3 : 4;
    } else if (total <= 12) {
      columns = total == 10 ? 5 : 4;
    } else if (total <= 16) {
      columns = 4;
    } else {
      columns = 5;
    }
    return MemoryBoard(cards: cards, pairs: cards.length ~/ 2, previewSeconds: previewFor(band, level), columns: columns, descripcion: descripcion);
  }
}
