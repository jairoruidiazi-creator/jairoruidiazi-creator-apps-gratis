/// Sonido con el que empieza una palabra en el español de Colombia.
///
/// Se compara por fonema, no por letra: con seseo (c ante e/i, z y s suenan
/// igual), yeísmo (ll = y), b = v, h muda, c/qu/k = /k/, g ante e/i y j = /x/,
/// gue/gui = /g/ y r inicial fuerte. Las palabras que empiezan con "hue" o
/// "hui" suenan /we/, /wi/: se marcan aparte ('w') para no mezclarlas con la u.
class Fonema {
  Fonema._();

  /// Vocales.
  static const List<String> vocales = <String>['a', 'e', 'i', 'o', 'u'];

  /// Consonantes fáciles de alargar o de oír al principio (primeros niveles).
  static const List<String> consonantesFaciles = <String>['m', 'p', 's', 'l', 't', 'n'];

  /// Resto de consonantes que se trabajan.
  static const List<String> consonantesMas = <String>['b', 'k', 'd', 'g', 'x', 'r', 'f', 'ch', 'y'];

  static const Map<String, String> _sinTilde = <String, String>{'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'};

  static String _plano(String s) {
    final StringBuffer b = StringBuffer();
    for (final int r in s.toLowerCase().trim().runes) {
      final String ch = String.fromCharCode(r);
      b.write(_sinTilde[ch] ?? ch);
    }
    return b.toString();
  }

  static bool _esVocal(String ch) => 'aeiou'.contains(ch) && ch.isNotEmpty;

  /// Fonema inicial de [palabra]: una vocal ('a'…'u'), 'w' (hue-, hui-), o
  /// una consonante: 'b', 'k', 's', 'd', 'f', 'g', 'x' (jota), 'ch', 'y'
  /// (ll, y), 'l', 'm', 'n', 'ñ', 'p', 'r', 't'.
  static String inicial(String palabra) {
    String w = _plano(palabra);
    if (w.isEmpty) {
      return '';
    }
    if (w.startsWith('h')) {
      // La hache no suena.
      w = w.substring(1);
      if (w.startsWith('ue') || w.startsWith('ui')) {
        return 'w';
      }
      if (w.startsWith('ie')) {
        return 'y';
      }
      if (w.isEmpty) {
        return '';
      }
    }
    final String c0 = w[0];
    final String c1 = w.length > 1 ? w[1] : '';
    if (w.startsWith('ch')) {
      return 'ch';
    }
    if (w.startsWith('ll')) {
      return 'y';
    }
    if (w.startsWith('qu')) {
      return 'k';
    }
    switch (c0) {
      case 'c':
        return c1 == 'e' || c1 == 'i' ? 's' : 'k';
      case 'k':
        return 'k';
      case 'z':
      case 's':
      case 'x':
        return 's';
      case 'g':
        return c1 == 'e' || c1 == 'i' ? 'x' : 'g';
      case 'j':
        return 'x';
      case 'v':
      case 'b':
        return 'b';
      case 'w':
        return 'w';
      case 'y':
        return _esVocal(c1) ? 'y' : 'i';
      case 'r':
        return 'r';
    }
    if (c0 == 'u' && _esVocal(c1) && c1 != 'u') {
      // "uo", "ue" al principio sin hache: también suena como semivocal.
      return 'w';
    }
    return c0;
  }

  /// Letras con las que se escribe ese sonido al principio de palabra (para
  /// las explicaciones: "suenan igual aunque se escriben distinto").
  static bool mismaLetraInicial(String a, String b) {
    final String pa = _plano(a);
    final String pb = _plano(b);
    if (pa.isEmpty || pb.isEmpty) {
      return false;
    }
    String l(String s) {
      if (s.startsWith('ch') || s.startsWith('ll') || s.startsWith('qu')) {
        return s.substring(0, 2);
      }
      return s[0];
    }

    return l(pa) == l(pb);
  }
}
