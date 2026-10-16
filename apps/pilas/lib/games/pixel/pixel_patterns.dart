import 'package:flutter/material.dart';

/// Paleta del pixel art: letra → color. El punto es "sin pintar".
class PixelPalette {
  PixelPalette._();

  static const Map<String, Color> colors = <String, Color>{
    'r': Color(0xFFE53935),
    'o': Color(0xFFFB8C00),
    'y': Color(0xFFFDD835),
    'g': Color(0xFF43A047),
    'l': Color(0xFF9CCC65),
    'b': Color(0xFF1E88E5),
    'c': Color(0xFF4FC3F7),
    'p': Color(0xFF8E24AA),
    'i': Color(0xFFEC407A),
    'n': Color(0xFF6D4C41),
    'k': Color(0xFF263238),
    'w': Color(0xFFFFFFFF),
    's': Color(0xFFF5CBA7),
    'a': Color(0xFF90A4AE),
  };

  static const List<String> order = <String>['r', 'o', 'y', 'g', 'l', 'b', 'c', 'p', 'i', 'n', 'k', 's', 'a', 'w'];

  static const Map<String, String> names = <String, String>{
    'r': 'rojo', 'o': 'naranja', 'y': 'amarillo', 'g': 'verde', 'l': 'verde claro', 'b': 'azul', 'c': 'celeste', 'p': 'morado', 'i': 'rosado', 'n': 'café', 'k': 'negro', 'w': 'blanco', 's': 'piel', 'a': 'gris',
  };
}

/// Un modelo para copiar o completar en espejo.
class PixelPattern {
  const PixelPattern(this.id, this.nombre, this.rows);

  final String id;
  final String nombre;

  /// Filas de la misma longitud; '.' = vacío.
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

class PixelPatterns {
  PixelPatterns._();

  static const List<PixelPattern> all = <PixelPattern>[
    PixelPattern('corazon', 'corazón', <String>[
      '........',
      '.rr..rr.',
      'rrrrrrrr',
      'rrrrrrrr',
      'rrrrrrrr',
      '.rrrrrr.',
      '..rrrr..',
      '...rr...',
    ]),
    PixelPattern('hongo', 'hongo', <String>[
      '..rrrr..',
      '.rwrrwr.',
      'rrrwwrrr',
      'rwrrrrwr',
      'rrrrrrrr',
      '..ssss..',
      '..skks..',
      '..ssss..',
    ]),
    PixelPattern('gato', 'gato', <String>[
      'o......o',
      'oo....oo',
      'oooooooo',
      'ookookoo',
      'oooooooo',
      'ooiooioo',
      'oooooooo',
      '.oooooo.',
    ]),
    PixelPattern('flor', 'flor', <String>[
      '...ii...',
      '..iyyi..',
      '.iyyyyi.',
      '..iyyi..',
      '...ii...',
      '...gg...',
      '.g.gg.g.',
      '.gggggg.',
    ]),
    PixelPattern('barco', 'barco', <String>[
      '...w....',
      '...ww...',
      '...www..',
      '...wwww.',
      '...w....',
      'nnnnnnnn',
      '.nnnnnn.',
      'cccccccc',
    ]),
    PixelPattern('cohete', 'cohete', <String>[
      '...rr...',
      '..rrrr..',
      '..raar..',
      '..raar..',
      '..rrrr..',
      '.rrrrrr.',
      'rr.yy.rr',
      '...oo...',
    ]),
    PixelPattern('arbol', 'árbol', <String>[
      '...gg...',
      '..gggg..',
      '.gggggg.',
      '..gggg..',
      '.gggggg.',
      '.gggggg.',
      '...nn...',
      '...nn...',
    ]),
    PixelPattern('casa', 'casa', <String>[
      '...rr...',
      '..rrrr..',
      '.rrrrrr.',
      'rrrrrrrr',
      'yyyyyyyy',
      'ycyyyycy',
      'yyynnyyy',
      'yyynnyyy',
    ]),
    PixelPattern('mariposa', 'mariposa', <String>[
      'p......p',
      'pp.kk.pp',
      'ppykkypp',
      '.ppkkpp.',
      '.ppkkpp.',
      'ppykkypp',
      'pp.kk.pp',
      'p......p',
    ]),
    PixelPattern('pez', 'pez', <String>[
      '........',
      '..cccc..',
      '.cccccc.',
      'ccckcccc',
      'cccccccc',
      '.cccccc.',
      '..cccc..',
      '........',
    ]),
    PixelPattern('guacamaya', 'guacamaya', <String>[
      '..rrr...',
      '.rrrrr..',
      'rrkrryy.',
      'rrrrrr..',
      '.rrrrr..',
      '..bbbb..',
      '..bbbbb.',
      '...bb.b.',
    ]),
    PixelPattern('sol', 'sol', <String>[
      'y..yy..y',
      '.yyyyyy.',
      '.yyyyyy.',
      'yyyyyyyy',
      'yyyyyyyy',
      '.yyyyyy.',
      '.yyyyyy.',
      'y..yy..y',
    ]),
  ];

  static List<PixelPattern> get symmetric => all.where((PixelPattern p) => p.symmetric).toList();
}
