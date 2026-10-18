/// Perfil de instrumento: nombre y afinación de sus órdenes (cursos) de
/// cuerdas en números MIDI, en el orden físico del instrumento (de la cuarta
/// a la primera en el tiple, de la sexta a la primera en la guitarra). Cada
/// orden lleva primero su altura nominal y después las cuerdas que suenan a
/// la octava (el tiple tiene en los órdenes 2.º a 4.º una cuerda central una
/// octava más grave). Los instrumentos sin cuerdas (voz, vientos) solo llevan
/// el rango habitual para el afinador.
class Instrument {
  const Instrument(this.id, this.nameEs, this.nameEn, this.courses, {this.transposition = 0, this.lowMidi = 24, this.highMidi = 108, this.stringsPerCourse = 1});

  final String id;
  final String nameEs;
  final String nameEn;

  /// Órdenes de cuerdas: altura nominal y, si las hay, sus octavas.
  final List<List<int>> courses;

  /// Transposición sugerida en semitonos (clarinete en Si♭ = 2).
  final int transposition;
  final int lowMidi;
  final int highMidi;

  /// Cuerdas por orden (1 = cuerdas simples, 2 = pareadas, 3 = triples).
  final int stringsPerCourse;

  bool get hasStrings => courses.isNotEmpty;

  /// Altura nominal de cada orden.
  List<int> get strings => <int>[for (final List<int> c in courses) c.first];

  String name(bool spanish) => spanish ? nameEs : nameEn;

  /// Orden cuya altura (o la de alguna de sus octavas), subida [capo]
  /// trastes, queda más cerca de [midi] (fraccionario y sonante).
  CourseMatch nearestCourse(double midi, {int capo = 0}) {
    int bestCourse = 0;
    int bestPitch = courses.isEmpty ? 0 : courses.first.first;
    double bestDist = double.infinity;
    for (int i = 0; i < courses.length; i++) {
      for (final int pitch in courses[i]) {
        final double d = (pitch + capo - midi).abs();
        if (d < bestDist) {
          bestDist = d;
          bestCourse = i;
          bestPitch = pitch;
        }
      }
    }
    return CourseMatch(bestCourse, bestPitch + capo);
  }

  /// La altura del orden [course] (o de su octava) más cercana a [midi],
  /// con el capo puesto: es la meta cuando la cuerda está fijada.
  int targetInCourse(int course, double midi, {int capo = 0}) {
    final List<int> c = courses[course];
    int best = c.first + capo;
    double bestDist = double.infinity;
    for (final int pitch in c) {
      final double d = (pitch + capo - midi).abs();
      if (d < bestDist) {
        bestDist = d;
        best = pitch + capo;
      }
    }
    return best;
  }
}

/// Resultado de buscar el orden más cercano: el orden y la altura sonante
/// (con el capo) de la cuerda que coincide.
class CourseMatch {
  const CourseMatch(this.course, this.midi);

  final int course;
  final int midi;
}

class Instruments {
  Instruments._();

  // MIDI: Do4 = 60, La4 = 69, Mi2 = 40.
  static const List<Instrument> all = <Instrument>[
    Instrument('cromatico', 'Cromático', 'Chromatic', <List<int>>[], lowMidi: 12, highMidi: 108),
    Instrument('guitarra', 'Guitarra', 'Guitar', <List<int>>[<int>[40], <int>[45], <int>[50], <int>[55], <int>[59], <int>[64]]),
    Instrument('guitarra_drop_d', 'Guitarra (Drop D)', 'Guitar (Drop D)', <List<int>>[<int>[38], <int>[45], <int>[50], <int>[55], <int>[59], <int>[64]]),
    Instrument('bajo', 'Bajo eléctrico', 'Bass guitar', <List<int>>[<int>[28], <int>[33], <int>[38], <int>[43]]),
    Instrument('bajo5', 'Bajo de 5 cuerdas', '5-string bass', <List<int>>[<int>[23], <int>[28], <int>[33], <int>[38], <int>[43]]),
    Instrument('ukelele', 'Ukelele', 'Ukulele', <List<int>>[<int>[67], <int>[60], <int>[64], <int>[69]]),
    // Tiple colombiano, afinación en Do (Re-Sol-Si-Mi, del 4.º al 1.er orden):
    // el 1.er orden son tres Mi4 al unísono; en los otros tres órdenes las dos
    // cuerdas lisas van en Re4, Sol4 y Si4 y la central entorchada, una octava
    // más grave. Fuentes en docs/DECISIONES.md.
    Instrument('tiple', 'Tiple colombiano', 'Colombian tiple', <List<int>>[<int>[62, 50], <int>[67, 55], <int>[71, 59], <int>[64]], stringsPerCourse: 3),
    // Requinto (tiple requinto) colombiano: los mismos órdenes del tiple con
    // las tres cuerdas de cada orden al unísono, sin cuerdas entorchadas.
    Instrument('requinto', 'Requinto colombiano', 'Colombian requinto', <List<int>>[<int>[62], <int>[67], <int>[71], <int>[64]], stringsPerCourse: 3),
    // Bandola andina: seis órdenes pareados al unísono, por cuartas.
    Instrument('bandola', 'Bandola andina', 'Andean bandola', <List<int>>[<int>[54], <int>[59], <int>[64], <int>[69], <int>[74], <int>[79]], stringsPerCourse: 2),
    Instrument('cuatro', 'Cuatro', 'Cuatro', <List<int>>[<int>[57], <int>[62], <int>[66], <int>[59]]),
    // Charango: el 3.er orden lleva un Mi4 y un Mi5.
    Instrument('charango', 'Charango', 'Charango', <List<int>>[<int>[67], <int>[72], <int>[64, 76], <int>[69], <int>[76]], stringsPerCourse: 2),
    // Requinto de seis cuerdas (guitarra pequeña afinada una cuarta arriba).
    Instrument('requinto_guitarra', 'Requinto (guitarra)', 'Requinto (guitar)', <List<int>>[<int>[45], <int>[50], <int>[55], <int>[60], <int>[64], <int>[69]]),
    Instrument('mandolina', 'Mandolina', 'Mandolin', <List<int>>[<int>[55], <int>[62], <int>[69], <int>[76]], stringsPerCourse: 2),
    Instrument('banjo', 'Banjo (5 cuerdas)', 'Banjo (5-string)', <List<int>>[<int>[67], <int>[50], <int>[55], <int>[59], <int>[62]]),
    Instrument('violin', 'Violín', 'Violin', <List<int>>[<int>[55], <int>[62], <int>[69], <int>[76]]),
    Instrument('viola', 'Viola', 'Viola', <List<int>>[<int>[48], <int>[55], <int>[62], <int>[69]]),
    Instrument('cello', 'Violonchelo', 'Cello', <List<int>>[<int>[36], <int>[43], <int>[50], <int>[57]]),
    Instrument('contrabajo', 'Contrabajo', 'Double bass', <List<int>>[<int>[28], <int>[33], <int>[38], <int>[43]]),
    Instrument('arpa_llanera', 'Arpa llanera (notas guía)', 'Llanera harp (guide notes)', <List<int>>[<int>[36], <int>[48], <int>[60], <int>[72]]),
    Instrument('voz', 'Voz', 'Voice', <List<int>>[], lowMidi: 40, highMidi: 84),
    Instrument('flauta', 'Flauta', 'Flute', <List<int>>[], lowMidi: 60, highMidi: 96),
    Instrument('clarinete', 'Clarinete en Si♭', 'B♭ clarinet', <List<int>>[], transposition: 2, lowMidi: 50, highMidi: 91),
    Instrument('trompeta', 'Trompeta en Si♭', 'B♭ trumpet', <List<int>>[], transposition: 2, lowMidi: 52, highMidi: 84),
    Instrument('saxo_alto', 'Saxofón alto en Mi♭', 'E♭ alto sax', <List<int>>[], transposition: 9, lowMidi: 49, highMidi: 81),
    Instrument('saxo_tenor', 'Saxofón tenor en Si♭', 'B♭ tenor sax', <List<int>>[], transposition: 14, lowMidi: 44, highMidi: 76),
    Instrument('trompa', 'Trompa en Fa', 'F horn', <List<int>>[], transposition: 7, lowMidi: 41, highMidi: 77),
    Instrument('piano', 'Piano / teclado', 'Piano / keyboard', <List<int>>[], lowMidi: 21, highMidi: 108),
  ];

  static Instrument byId(String? id) => maybeById(id) ?? all.first;

  /// null si [id] no es un perfil conocido (por ejemplo, una toma sin
  /// instrumento).
  static Instrument? maybeById(String? id) {
    for (final Instrument i in all) {
      if (i.id == id) {
        return i;
      }
    }
    return null;
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
