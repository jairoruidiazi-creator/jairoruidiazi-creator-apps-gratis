import '../../content/vocab.dart';
import '../../core/rng.dart';
import '../../model/age_band.dart';

/// Una ronda de "Arma la palabra": la palabra, sus letras en orden y las
/// fichas revueltas (con distractores según el tramo).
class PalabraRound {
  const PalabraRound({
    required this.item,
    required this.letras,
    required this.fichas,
    required this.mostrarModelo,
    required this.pista,
  });

  final VocabItem item;

  /// Letras de la palabra en orden.
  final List<String> letras;

  /// Letras de las fichas, revueltas, con distractores.
  final List<String> fichas;

  /// Si se muestra la palabra escrita como modelo (primeros niveles).
  final bool mostrarModelo;

  /// Pista que se da al primer error.
  final String pista;

  String get palabra => item.nombre;
}

class PalabraGenerator {
  static const Map<String, String> _confusables = <String, String>{
    'b': 'v', 'v': 'b', 'y': 'i', 'z': 's', 's': 'z', 'c': 's', 'j': 'g', 'g': 'j', 'k': 'c', 'q': 'k', 'h': 'j', 'ñ': 'n', 'r': 'l',
    'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u',
  };
  static const Map<String, String> _acentuada = <String, String>{'a': 'á', 'e': 'é', 'i': 'í', 'o': 'ó', 'u': 'ú'};
  static const String _alfabeto = 'abcdefghijlmnopqrstuvyz';

  static bool _tieneTilde(String s) => RegExp('[áéíóú]').hasMatch(s);

  static bool _dificil(String s) => RegExp('(b|v|h|ll|y|z|ce|ci|ge|gi|j|qu|gu|rr)').hasMatch(s);

  static List<VocabItem> _pool(AgeBand band, int level) {
    final List<VocabItem> sinEspacio = Vocab.all.where((VocabItem v) => !v.nombre.contains(' ') && !v.nombre.contains('-')).toList();
    List<VocabItem> out;
    switch (band) {
      case AgeBand.b3a4:
      case AgeBand.b5a6:
        final int min = level <= 1 ? 3 : (level == 2 ? 4 : (level == 3 ? 5 : 6));
        final int max = level <= 1 ? 4 : (level == 2 ? 5 : (level == 3 ? 6 : 8));
        out = sinEspacio.where((VocabItem v) => v.nombre.length >= min && v.nombre.length <= max && !_tieneTilde(v.nombre)).toList();
        break;
      case AgeBand.b7a8:
        final int minLargo = level <= 2 ? 4 : 6;
        final int maxLargo = level <= 2 ? 7 : 11;
        out = sinEspacio.where((VocabItem v) => v.nombre.length >= minLargo && v.nombre.length <= maxLargo && _dificil(v.nombre)).toList();
        break;
      case AgeBand.b9a11:
        if (level == 4) {
          out = sinEspacio.where((VocabItem v) => v.nombre.length >= 6).toList();
        } else {
          out = sinEspacio.where((VocabItem v) => _tieneTilde(v.nombre)).toList();
        }
        break;
    }
    if (out.length < 5) {
      out = sinEspacio.where((VocabItem v) => v.nombre.length <= 7).toList();
    }
    return out;
  }

  PalabraRound next(Rng rng, AgeBand band, int level) {
    final VocabItem item = rng.pick(_pool(band, level));
    final List<String> letras = item.nombre.split('');
    final List<String> fichas = List<String>.from(letras);

    int distractores;
    switch (band) {
      case AgeBand.b3a4:
      case AgeBand.b5a6:
        distractores = level >= 4 ? 1 : 0;
        break;
      case AgeBand.b7a8:
        distractores = level <= 1 ? 1 : (level <= 3 ? 2 : 3);
        break;
      case AgeBand.b9a11:
        distractores = level <= 2 ? 2 : 3;
        break;
    }
    final Set<String> presentes = letras.toSet();
    final List<String> candidatos = <String>[];
    // Primero los confusables de las letras de la palabra.
    for (final String l in letras) {
      final String? c = _confusables[l];
      if (c != null && !presentes.contains(c) && !candidatos.contains(c)) {
        candidatos.add(c);
      }
    }
    if (band == AgeBand.b9a11) {
      // Siempre una vocal con tilde "tentadora" cuando la palabra no la lleva,
      // y la vocal sin tilde cuando sí la lleva (ya añadida por los confusables).
      for (final String l in letras) {
        final String? a = _acentuada[l];
        if (a != null && !presentes.contains(a) && !candidatos.contains(a)) {
          candidatos.add(a);
          break;
        }
      }
    }
    rng.shuffle(candidatos);
    final List<String> elegidos = candidatos.take(distractores).toList();
    int guard = 0;
    while (elegidos.length < distractores && guard < 50) {
      guard += 1;
      final String l = _alfabeto[rng.nextInt(_alfabeto.length)];
      if (!presentes.contains(l) && !elegidos.contains(l)) {
        elegidos.add(l);
      }
    }
    fichas.addAll(elegidos);
    rng.shuffle(fichas);
    // Que no quede ya ordenada por azar.
    if (fichas.length > 2 && fichas.join() == item.nombre) {
      final String t = fichas[0];
      fichas[0] = fichas[fichas.length - 1];
      fichas[fichas.length - 1] = t;
    }

    final bool modelo = (band == AgeBand.b3a4 || band == AgeBand.b5a6) && level <= 2;
    final String silabas = item.silabas.join(' - ');
    String pista;
    if (band == AgeBand.b9a11 && _tieneTilde(item.nombre)) {
      pista = 'Di la palabra despacio: $silabas. La sílaba que suena más fuerte lleva tilde.';
    } else if (band == AgeBand.b7a8) {
      pista = 'Di la palabra por sílabas: $silabas. Piensa con qué letra se escribe ese sonido.';
    } else {
      pista = 'Di la palabra despacio: $silabas. ¿Qué letra suena ahora?';
    }
    return PalabraRound(item: item, letras: letras, fichas: fichas, mostrarModelo: modelo, pista: pista);
  }
}
