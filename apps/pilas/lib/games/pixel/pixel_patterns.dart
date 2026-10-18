import 'package:flutter/material.dart';

/// Paleta del pixel art: letra → color. El punto es "sin pintar" (blanco).
class PixelPalette {
  PixelPalette._();

  static const Map<String, Color> colors = <String, Color>{
    'r': Color(0xFFE53935),
    'o': Color(0xFFFB8C00),
    'y': Color(0xFFFDD835),
    'g': Color(0xFF43A047),
    'b': Color(0xFF1E88E5),
    'c': Color(0xFF4FC3F7),
    'p': Color(0xFF8E24AA),
    'i': Color(0xFFEC407A),
    'n': Color(0xFF6D4C41),
    'k': Color(0xFF263238),
    's': Color(0xFFF5CBA7),
  };

  /// Orden de la paleta en pantalla.
  static const List<String> order = <String>['r', 'o', 'y', 'g', 'b', 'c', 'p', 'i', 'n', 'k', 's'];

  static const Map<String, String> names = <String, String>{
    'r': 'rojo',
    'o': 'naranja',
    'y': 'amarillo',
    'g': 'verde',
    'b': 'azul',
    'c': 'celeste',
    'p': 'morado',
    'i': 'rosado',
    'n': 'café',
    'k': 'negro',
    's': 'durazno',
  };
}

/// Un modelo para copiar o completar en espejo.
class PixelPattern {
  const PixelPattern(this.id, this.nombre, this.rows);

  final String id;

  /// Con artículo: "el corazón", "la mariposa".
  final String nombre;

  /// Filas de la misma longitud; '.' = sin pintar.
  final List<String> rows;

  int get size => rows.length;

  String at(int r, int c) => rows[r][c];

  /// Si el patrón es simétrico respecto al eje vertical (para el modo espejo).
  bool get symmetric {
    for (final String row in rows) {
      for (int c = 0; c < row.length ~/ 2; c++) {
        if (row[c] != row[row.length - 1 - c]) {
          return false;
        }
      }
    }
    return true;
  }
}

/// Modelos de 6×6, 8×8, 10×10 y 12×12: cada nivel agranda la cuadrícula.
/// test/content_test.dart comprueba que todos son cuadrados, que usan solo
/// colores de la paleta y que hay modelos simétricos de cada tamaño.
class PixelPatterns {
  PixelPatterns._();

  /// Lado de la cuadrícula según el tramo y el nivel.
  static int sizeFor(bool mayores, int level) {
    final List<int> sizes = mayores ? const <int>[8, 10, 12] : const <int>[6, 8, 10, 12];
    return sizes[(level - 1).clamp(0, sizes.length - 1)];
  }

  static List<PixelPattern> ofSize(int n) => all.where((PixelPattern p) => p.size == n).toList();

  static List<PixelPattern> symmetricOfSize(int n) => all.where((PixelPattern p) => p.size == n && p.symmetric).toList();

  static const List<PixelPattern> all = <PixelPattern>[
    PixelPattern('corazon6', 'el corazón', <String>[
      '......',
      '.r..r.',
      'rrrrrr',
      'rrrrrr',
      '.rrrr.',
      '..rr..',
    ]),
    PixelPattern('flor6', 'la flor', <String>[
      '..ii..',
      '.iyyi.',
      '..ii..',
      '..gg..',
      'g.gg.g',
      '.gggg.',
    ]),
    PixelPattern('casa6', 'la casa', <String>[
      '..rr..',
      '.rrrr.',
      'rrrrrr',
      '.cyyc.',
      '.ynny.',
      '.ynny.',
    ]),
    PixelPattern('hongo6', 'el hongo', <String>[
      '.rrrr.',
      'rryyrr',
      'rrrrrr',
      '..ss..',
      '..ss..',
      '.ssss.',
    ]),
    PixelPattern('gato6', 'el gato', <String>[
      'o....o',
      'oo..oo',
      'oooooo',
      'okooko',
      'oooooo',
      '.oiio.',
    ]),
    PixelPattern('sol6', 'el sol', <String>[
      'y.yy.y',
      '.yyyy.',
      'yyyyyy',
      'yyyyyy',
      '.yyyy.',
      'y.yy.y',
    ]),
    PixelPattern('pez6', 'el pez', <String>[
      '......',
      'b..bb.',
      'bbbbkb',
      'bbbbbb',
      'b..bb.',
      '......',
    ]),
    PixelPattern('barco6', 'el barco', <String>[
      '..r...',
      '..rr..',
      '..rrr.',
      'nnnnnn',
      '.nnnn.',
      'cccccc',
    ]),
    PixelPattern('corazon8', 'el corazón', <String>[
      '........',
      '.rr..rr.',
      'rrrrrrrr',
      'rrrrrrrr',
      'rrrrrrrr',
      '.rrrrrr.',
      '..rrrr..',
      '...rr...',
    ]),
    PixelPattern('hongo8', 'el hongo', <String>[
      '..rrrr..',
      '.ryrryr.',
      'rrryyrrr',
      'ryrrrryr',
      'rrrrrrrr',
      '..ssss..',
      '..skks..',
      '..ssss..',
    ]),
    PixelPattern('gato8', 'el gato', <String>[
      'o......o',
      'oo....oo',
      'oooooooo',
      'ookookoo',
      'oooooooo',
      'ooiooioo',
      'oooooooo',
      '.oooooo.',
    ]),
    PixelPattern('flor8', 'la flor', <String>[
      '...ii...',
      '..iyyi..',
      '.iyyyyi.',
      '..iyyi..',
      '...ii...',
      '...gg...',
      '.g.gg.g.',
      '.gggggg.',
    ]),
    PixelPattern('barco8', 'el barco', <String>[
      '...r....',
      '...rr...',
      '...rrr..',
      '...rrrr.',
      '...n....',
      'nnnnnnnn',
      '.nnnnnn.',
      'cccccccc',
    ]),
    PixelPattern('cohete8', 'el cohete', <String>[
      '...rr...',
      '..rrrr..',
      '..rccr..',
      '..rccr..',
      '..rrrr..',
      '.rrrrrr.',
      'rr.yy.rr',
      '...oo...',
    ]),
    PixelPattern('arbol8', 'el árbol', <String>[
      '...gg...',
      '..gggg..',
      '.gggggg.',
      '..gggg..',
      '.gggggg.',
      '.gggggg.',
      '...nn...',
      '...nn...',
    ]),
    PixelPattern('casa8', 'la casa', <String>[
      '...rr...',
      '..rrrr..',
      '.rrrrrr.',
      'rrrrrrrr',
      'yyyyyyyy',
      'ycyyyycy',
      'yyynnyyy',
      'yyynnyyy',
    ]),
    PixelPattern('mariposa8', 'la mariposa', <String>[
      'p......p',
      'pp.kk.pp',
      'ppykkypp',
      '.ppkkpp.',
      '.ppkkpp.',
      'ppykkypp',
      'pp.kk.pp',
      'p......p',
    ]),
    PixelPattern('pez8', 'el pez', <String>[
      '........',
      '..cccc..',
      '.cccccc.',
      'ccckcccc',
      'cccccccc',
      '.cccccc.',
      '..cccc..',
      '........',
    ]),
    PixelPattern('guacamaya8', 'la guacamaya', <String>[
      '..rrr...',
      '.rrrrr..',
      'rrkrryy.',
      'rrrrrr..',
      '.rrrrr..',
      '..bbbb..',
      '..bbbbb.',
      '...bb.b.',
    ]),
    PixelPattern('sol8', 'el sol', <String>[
      'y..yy..y',
      '.yyyyyy.',
      '.yyyyyy.',
      'yyyyyyyy',
      'yyyyyyyy',
      '.yyyyyy.',
      '.yyyyyy.',
      'y..yy..y',
    ]),
    PixelPattern('carita10', 'la carita feliz', <String>[
      '..yyyyyy..',
      '.yyyyyyyy.',
      'yyykyykyyy',
      'yyykyykyyy',
      'yyyyyyyyyy',
      'ykyyyyyyky',
      'yykyyyykyy',
      'yyykkkkyyy',
      '.yyyyyyyy.',
      '..yyyyyy..',
    ]),
    PixelPattern('cohete10', 'el cohete', <String>[
      '....rr....',
      '...rrrr...',
      '...rccr...',
      '...rccr...',
      '...rrrr...',
      '...rrrr...',
      '..rrrrrr..',
      '.rr.rr.rr.',
      '.r..oo..r.',
      '....yy....',
    ]),
    PixelPattern('mariposa10', 'la mariposa', <String>[
      'pp......pp',
      'ppp.kk.ppp',
      'ppppkkpppp',
      'pyppkkppyp',
      '.pppkkppp.',
      '..ppkkpp..',
      '.pppkkppp.',
      'pippkkppip',
      'ppp.kk.ppp',
      'pp......pp',
    ]),
    PixelPattern('helado10', 'el ponquecito', <String>[
      '....rr....',
      '...iiii...',
      '..iiiiii..',
      '.iiiiiiii.',
      '.iiiiiiii.',
      '.nnnnnnnn.',
      '..nnnnnn..',
      '..nnnnnn..',
      '...nnnn...',
      '....nn....',
    ]),
    PixelPattern('casa10', 'la casa', <String>[
      '....rr....',
      '...rrrr...',
      '..rrrrrr..',
      '.rrrrrrrr.',
      'rrrrrrrrrr',
      '.yyyyyyyy.',
      '.ycyyyycy.',
      '.yyynnyyy.',
      '.yyynnyyy.',
      'gggggggggg',
    ]),
    PixelPattern('gato10', 'el gato', <String>[
      '.o......o.',
      '.oo....oo.',
      '.oooooooo.',
      'oooooooooo',
      'ookooookoo',
      'oooooooooo',
      'ooooiioooo',
      '.oooooooo.',
      '..oooooo..',
      '..........',
    ]),
    PixelPattern('carro10', 'el carro', <String>[
      '..........',
      '..........',
      '...rrrr...',
      '..rcrrcr..',
      '.rccrrccr.',
      'rrrrrrrrrr',
      'rrrrrrrrry',
      'rrkkrrkkrr',
      '..kk..kk..',
      '..........',
    ]),
    PixelPattern('pez10', 'el pez', <String>[
      '..........',
      '....bbb...',
      'b..bbbbb..',
      'bbbbbbbkb.',
      'bbbbbbbbbb',
      'bbbbbbbbb.',
      'b..bbbbb..',
      '....bbb...',
      '..........',
      'cccccccccc',
    ]),
    PixelPattern('buho12', 'el búho', <String>[
      '.n........n.',
      '.nn......nn.',
      '.nnnnnnnnnn.',
      'nnyyynnyyynn',
      'nykyynnyykyn',
      'nnyyynnyyynn',
      'nnnnnoonnnnn',
      'nsnsnnnnsnsn',
      '.nnnnnnnnnn.',
      '..nnnnnnnn..',
      '...o....o...',
      '..oo....oo..',
    ]),
    PixelPattern('robot12', 'el robot', <String>[
      '.....kk.....',
      '.....kk.....',
      '..bbbbbbbb..',
      '..bccbbccb..',
      '..bbbbbbbb..',
      '..bbrrrrbb..',
      '..bbbbbbbb..',
      'kbbbbbbbbbbk',
      'k.bbybbybb.k',
      '..bbbbbbbb..',
      '...bb..bb...',
      '..kkk..kkk..',
    ]),
    PixelPattern('flor12', 'la flor', <String>[
      '.....ii.....',
      '...iiiiii...',
      '..iiiyyiii..',
      '..iiyyyyii..',
      '...iiiiii...',
      '.....gg.....',
      '.gg..gg..gg.',
      '..gg.gg.gg..',
      '...gggggg...',
      '.....gg.....',
      '....nnnn....',
      '...nnnnnn...',
    ]),
    PixelPattern('rana12', 'la rana', <String>[
      '..gg....gg..',
      '.gkkg..gkkg.',
      '.gggggggggg.',
      'gggggggggggg',
      'ggkggggggkgg',
      'gggkkkkkkggg',
      '.gggggggggg.',
      '..gggggggg..',
      '.gg.gggg.gg.',
      'gg..gggg..gg',
      'g...g..g...g',
      '............',
    ]),
    PixelPattern('barco12', 'el velero', <String>[
      '.....k......',
      '.....kr.....',
      '.....krr....',
      '.....krrr...',
      '....ykrrrr..',
      '...yykrrrrr.',
      '..yyykrrrrrr',
      '.....k......',
      'nnnnnnnnnnnn',
      '.nnnnnnnnnn.',
      '..nnnnnnnn..',
      'cccccccccccc',
    ]),
    PixelPattern('caracol12', 'el caracol', <String>[
      '............',
      '......nnnn..',
      '.....nooonn.',
      '....noonnon.',
      '....nonoono.',
      '....nonnnon.',
      '.k..noooon..',
      '.ss..nnnn...',
      'sssssssssss.',
      'ssssssssssss',
      '............',
      'gggggggggggg',
    ]),
  ];
}
