/// Ayudas de gramática del español para los textos que se generan: artículos,
/// contracciones, plurales, mayúscula inicial y números en palabras. Todo lo
/// que la voz lee en alto pasa por aquí, para que no aparezcan "a el",
/// "1 manzanas" ni "veintidos".
class Es {
  Es._();

  /// Pone en mayúscula la primera letra, aunque el texto empiece con signos
  /// de apertura (¿, ¡) o comillas.
  static String cap(String s) {
    for (int i = 0; i < s.length; i++) {
      final String ch = s[i];
      if ('¿¡"«“\''.contains(ch) || ch == ' ') {
        continue;
      }
      return s.substring(0, i) + ch.toUpperCase() + s.substring(i + 1);
    }
    return s;
  }

  /// Contrae "a el" en "al" y "de el" en "del" (no toca "a él", el pronombre).
  static String contraer(String s) {
    return s
        .replaceAllMapped(RegExp(r'\b([Aa]) el\b'), (Match m) => m.group(1) == 'A' ? 'Al' : 'al')
        .replaceAllMapped(RegExp(r'\b([Dd])e el\b'), (Match m) => m.group(1) == 'D' ? 'Del' : 'del');
  }

  /// Artículo según género ('m' o 'f') y número.
  static String articulo(String genero, {bool plural = false, bool definido = true}) {
    final bool f = genero == 'f';
    if (definido) {
      return f ? (plural ? 'las' : 'la') : (plural ? 'los' : 'el');
    }
    return f ? (plural ? 'unas' : 'una') : (plural ? 'unos' : 'un');
  }

  /// "a" + artículo + nombre, contraído si hace falta: "al gato", "a la vaca".
  static String aEl(String genero, String nombre, {bool plural = false}) => contraer('a ${articulo(genero, plural: plural)} $nombre');

  /// "de" + artículo + nombre, contraído si hace falta: "del libro", "de la casa".
  static String deEl(String genero, String nombre, {bool plural = false}) => contraer('de ${articulo(genero, plural: plural)} $nombre');

  static const String _vocales = 'aeiouáéíóú';

  /// Plural de un sustantivo común. Cubre los casos del vocabulario de la app:
  /// vocal + s, consonante + es, z → ces, agudas en -ón, -án, -én, -ín y -és
  /// pierden la tilde, y las graves terminadas en s o x no cambian.
  static String plural(String palabra) {
    if (palabra.isEmpty) {
      return palabra;
    }
    final int espacio = palabra.indexOf(' ');
    if (espacio > 0) {
      // "carro de bomberos" → "carros de bomberos": cambia el primer sustantivo.
      return plural(palabra.substring(0, espacio)) + palabra.substring(espacio);
    }
    final String last = palabra[palabra.length - 1];
    if (last == 's' || last == 'x') {
      // Graves terminadas en s o x (cactus, lunes, tórax) no cambian; las
      // agudas y las de una sílaba sí (autobús → autobuses, bus → buses).
      final bool aguda = RegExp('[áéíóú][^aeiouáéíóú]*\$').hasMatch(palabra);
      final bool unaSilaba = RegExp('[aeiouáéíóú]+').allMatches(palabra).length == 1;
      return aguda || unaSilaba ? '${_sinTildeFinal(palabra)}es' : palabra;
    }
    if (last == 'z') {
      return '${palabra.substring(0, palabra.length - 1)}ces';
    }
    if ('áéó'.contains(last)) {
      return '${palabra}s';
    }
    if ('íú'.contains(last)) {
      return '${palabra}es';
    }
    if (_vocales.contains(last)) {
      return '${palabra}s';
    }
    if (last == 'y') {
      return '${palabra}es';
    }
    return '${_sinTildeFinal(palabra)}es';
  }

  /// Quita la tilde de la última sílaba (camión → camion-) para formar el plural.
  static String _sinTildeFinal(String s) {
    const Map<String, String> sin = <String, String>{'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u'};
    for (int i = s.length - 1; i >= 0; i--) {
      final String? plain = sin[s[i]];
      if (plain != null) {
        // Solo si es la última vocal de la palabra (aguda).
        final String resto = s.substring(i + 1);
        if (!RegExp('[aeiou]').hasMatch(resto)) {
          return s.substring(0, i) + plain + resto;
        }
        return s;
      }
    }
    return s;
  }

  /// "1 manzana", "3 manzanas" (con cifras).
  static String cantidad(int n, String singular, {String? pluralForm}) => n == 1 ? '1 $singular' : '$n ${pluralForm ?? plural(singular)}';

  /// "un vaso", "dos vasos", "una manzana", "tres manzanas" (en palabras).
  static String cantidadEnPalabras(int n, String singular, {required String genero, String? pluralForm}) {
    if (n == 1) {
      return '${genero == 'f' ? 'una' : 'un'} $singular';
    }
    return '${numero(n, femenino: genero == 'f', apocope: true)} ${pluralForm ?? plural(singular)}';
  }

  static const List<String> _unidades = <String>[
    'cero', 'uno', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete', 'ocho', 'nueve', 'diez',
    'once', 'doce', 'trece', 'catorce', 'quince', 'dieciséis', 'diecisiete', 'dieciocho', 'diecinueve', 'veinte',
    'veintiuno', 'veintidós', 'veintitrés', 'veinticuatro', 'veinticinco', 'veintiséis', 'veintisiete', 'veintiocho', 'veintinueve',
  ];
  static const List<String> _decenas = <String>['', '', 'veinte', 'treinta', 'cuarenta', 'cincuenta', 'sesenta', 'setenta', 'ochenta', 'noventa'];
  static const List<String> _centenas = <String>['', 'ciento', 'doscientos', 'trescientos', 'cuatrocientos', 'quinientos', 'seiscientos', 'setecientos', 'ochocientos', 'novecientos'];

  /// Número en palabras, con las tildes de la norma (veintidós, veintitrés,
  /// veintiséis). Con [femenino], "una", "veintiuna", "doscientas"; con
  /// [apocope], "un" y "veintiún" (delante de un sustantivo masculino).
  static String numero(int n, {bool femenino = false, bool apocope = false}) {
    if (n < 0) {
      return 'menos ${numero(-n, femenino: femenino, apocope: apocope)}';
    }
    String out = _numero(n, femenino);
    if (apocope && !femenino) {
      if (out.endsWith('veintiuno')) {
        out = '${out.substring(0, out.length - 9)}veintiún';
      } else if (out == 'uno' || out.endsWith(' uno')) {
        out = '${out.substring(0, out.length - 3)}un';
      }
    }
    return out;
  }

  static String _numero(int n, bool fem) {
    if (n < 30) {
      final String u = _unidades[n];
      if (fem && n == 1) {
        return 'una';
      }
      if (fem && n == 21) {
        return 'veintiuna';
      }
      return u;
    }
    if (n < 100) {
      final int d = n ~/ 10;
      final int u = n % 10;
      return u == 0 ? _decenas[d] : '${_decenas[d]} y ${_numero(u, fem)}';
    }
    if (n == 100) {
      return 'cien';
    }
    if (n < 1000) {
      final int c = n ~/ 100;
      final int r = n % 100;
      String cent = _centenas[c];
      if (fem && c > 1) {
        cent = '${cent.substring(0, cent.length - 2)}as';
      }
      return r == 0 ? cent : '$cent ${_numero(r, fem)}';
    }
    if (n < 1000000) {
      final int m = n ~/ 1000;
      final int r = n % 1000;
      // Delante de "mil" va la forma corta: "veintiún mil", "treinta y un mil"
      // (o "veintiuna mil" con sustantivo femenino, que no se usa en la app).
      final String miles = m == 1 ? 'mil' : '${numero(m, femenino: fem, apocope: !fem)} mil';
      return r == 0 ? miles : '$miles ${_numero(r, fem)}';
    }
    final int mm = n ~/ 1000000;
    final int r = n % 1000000;
    final String millones = mm == 1 ? 'un millón' : '${numero(mm, apocope: true)} millones';
    return r == 0 ? millones : '$millones ${_numero(r, fem)}';
  }

  static const Map<int, List<String>> _partes = <int, List<String>>{
    2: <String>['medio', 'medios'],
    3: <String>['tercio', 'tercios'],
    4: <String>['cuarto', 'cuartos'],
    5: <String>['quinto', 'quintos'],
    6: <String>['sexto', 'sextos'],
    7: <String>['séptimo', 'séptimos'],
    8: <String>['octavo', 'octavos'],
    9: <String>['noveno', 'novenos'],
    10: <String>['décimo', 'décimos'],
    12: <String>['doceavo', 'doceavos'],
  };

  /// Fracción en palabras: "un medio", "dos tercios", "tres cuartos",
  /// "cuatro novenos".
  static String fraccion(int num, int den) {
    final List<String>? p = _partes[den];
    if (p == null) {
      return '${numero(num, apocope: true)} de ${numero(den)}';
    }
    return num == 1 ? 'un ${p[0]}' : '${numero(num, apocope: true)} ${p[1]}';
  }

  /// Ordinal corto para las casillas: 1.º, 2.º…
  static String ordinalCorto(int n) => '$n.º';

  /// "o", o "u" delante de una palabra que empieza con el sonido o ("siete u
  /// ocho", "perro u oso", "u hormiga").
  static String o(String siguiente) {
    final String s = siguiente.trim().toLowerCase();
    if (s.startsWith('o') || s.startsWith('ó') || s.startsWith('ho') || s.startsWith('hó')) {
      return 'u';
    }
    if (s.startsWith('8') || s == '11' || s.startsWith('11 ') || s.startsWith('11.')) {
      return 'u';
    }
    return 'o';
  }

  /// "y", o "e" delante de una palabra que empieza con el sonido i ("agua e
  /// hielo"), salvo los diptongos de "hie" ("agua y hierro").
  static String y(String siguiente) {
    final String s = siguiente.trim().toLowerCase();
    if ((s.startsWith('i') || s.startsWith('í') || s.startsWith('hi') || s.startsWith('hí')) && !s.startsWith('hie') && !s.startsWith('ia') && !s.startsWith('ie') && !s.startsWith('io')) {
      return 'e';
    }
    return 'y';
  }

  /// Une una lista con comas y "y" ("rojo, azul y verde").
  static String listaY(List<String> items) {
    if (items.isEmpty) {
      return '';
    }
    if (items.length == 1) {
      return items.first;
    }
    final List<String> rest = List<String>.from(items);
    final String last = rest.removeLast();
    return '${rest.join(', ')} ${y(last)} $last';
  }
}
