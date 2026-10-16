/// Perfil de instrumento: nombre y afinación de sus cuerdas (números MIDI,
/// de la más grave a la más aguda). Los instrumentos sin cuerdas (voz,
/// vientos) solo llevan el rango habitual para el afinador.
class Instrument {
  const Instrument(this.id, this.nameEs, this.nameEn, this.strings, {this.transposition = 0, this.lowMidi = 24, this.highMidi = 108, this.courses});

  final String id;
  final String nameEs;
  final String nameEn;

  /// Cuerdas (o cursos) de grave a aguda. Vacío para instrumentos sin cuerdas.
  final List<int> strings;

  /// Transposición sugerida en semitonos (clarinete en Si♭ = 2).
  final int transposition;
  final int lowMidi;
  final int highMidi;

  /// Para instrumentos de cursos dobles o triples: cuántas cuerdas por curso.
  final int? courses;

  bool get hasStrings => strings.isNotEmpty;

  String name(bool spanish) => spanish ? nameEs : nameEn;

  /// Índice de la cuerda cuya altura está más cerca de [midi] (fraccionario).
  int nearestString(double midi) {
    int best = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < strings.length; i++) {
      final double d = (strings[i] - midi).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }
}

class Instruments {
  Instruments._();

  // MIDI: Do4 = 60, La4 = 69, Mi2 = 40.
  static const List<Instrument> all = <Instrument>[
    Instrument('cromatico', 'Cromático', 'Chromatic', <int>[], lowMidi: 12, highMidi: 108),
    Instrument('guitarra', 'Guitarra', 'Guitar', <int>[40, 45, 50, 55, 59, 64]),
    Instrument('guitarra_drop_d', 'Guitarra (Drop D)', 'Guitar (Drop D)', <int>[38, 45, 50, 55, 59, 64]),
    Instrument('bajo', 'Bajo eléctrico', 'Bass guitar', <int>[28, 33, 38, 43]),
    Instrument('bajo5', 'Bajo de 5 cuerdas', '5-string bass', <int>[23, 28, 33, 38, 43]),
    Instrument('ukelele', 'Ukelele', 'Ukulele', <int>[67, 60, 64, 69]),
    Instrument('tiple', 'Tiple colombiano', 'Colombian tiple', <int>[62, 55, 59, 64], courses: 3),
    Instrument('bandola', 'Bandola andina', 'Andean bandola', <int>[54, 59, 64, 69, 74, 79], courses: 2),
    Instrument('cuatro', 'Cuatro', 'Cuatro', <int>[57, 62, 66, 59]),
    Instrument('requinto', 'Requinto', 'Requinto', <int>[45, 50, 55, 60, 64, 69]),
    Instrument('charango', 'Charango', 'Charango', <int>[67, 72, 64, 69, 76], courses: 2),
    Instrument('mandolina', 'Mandolina', 'Mandolin', <int>[55, 62, 69, 76], courses: 2),
    Instrument('banjo', 'Banjo (5 cuerdas)', 'Banjo (5-string)', <int>[67, 50, 55, 59, 62]),
    Instrument('violin', 'Violín', 'Violin', <int>[55, 62, 69, 76]),
    Instrument('viola', 'Viola', 'Viola', <int>[48, 55, 62, 69]),
    Instrument('cello', 'Violonchelo', 'Cello', <int>[36, 43, 50, 57]),
    Instrument('contrabajo', 'Contrabajo', 'Double bass', <int>[28, 33, 38, 43]),
    Instrument('arpa_llanera', 'Arpa llanera (notas guía)', 'Llanera harp (guide notes)', <int>[36, 48, 60, 72]),
    Instrument('voz', 'Voz', 'Voice', <int>[], lowMidi: 40, highMidi: 84),
    Instrument('flauta', 'Flauta', 'Flute', <int>[], lowMidi: 60, highMidi: 96),
    Instrument('clarinete', 'Clarinete en Si♭', 'B♭ clarinet', <int>[], transposition: 2, lowMidi: 50, highMidi: 91),
    Instrument('trompeta', 'Trompeta en Si♭', 'B♭ trumpet', <int>[], transposition: 2, lowMidi: 52, highMidi: 84),
    Instrument('saxo_alto', 'Saxofón alto en Mi♭', 'E♭ alto sax', <int>[], transposition: 9, lowMidi: 49, highMidi: 81),
    Instrument('saxo_tenor', 'Saxofón tenor en Si♭', 'B♭ tenor sax', <int>[], transposition: 14, lowMidi: 44, highMidi: 76),
    Instrument('trompa', 'Trompa en Fa', 'F horn', <int>[], transposition: 7, lowMidi: 41, highMidi: 77),
    Instrument('piano', 'Piano / teclado', 'Piano / keyboard', <int>[], lowMidi: 21, highMidi: 108),
  ];

  static Instrument byId(String? id) {
    for (final Instrument i in all) {
      if (i.id == id) {
        return i;
      }
    }
    return all.first;
  }
}

/// Indicaciones de tempo con sus rangos habituales de BPM.
class TempoMark {
  const TempoMark(this.name, this.min, this.max);

  final String name;
  final int min;
  final int max;

  static const List<TempoMark> all = <TempoMark>[
    TempoMark('Grave', 20, 40),
    TempoMark('Largo', 40, 60),
    TempoMark('Larghetto', 60, 66),
    TempoMark('Adagio', 66, 76),
    TempoMark('Andante', 76, 108),
    TempoMark('Moderato', 108, 120),
    TempoMark('Allegro', 120, 168),
    TempoMark('Vivace', 168, 176),
    TempoMark('Presto', 176, 200),
    TempoMark('Prestissimo', 200, 400),
  ];

  static String forBpm(num bpm) {
    for (final TempoMark m in all) {
      if (bpm < m.max) {
        return m.name;
      }
    }
    return all.last.name;
  }
}
