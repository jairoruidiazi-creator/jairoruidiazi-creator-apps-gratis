import 'dart:math' as math;

/// Notaciones de nombres de notas.
enum Notation { solfeo, english, german, indian }

/// Temperamentos disponibles. Los históricos se definen como desviación en
/// cents de cada grado cromático respecto al temperamento igual, tomando Do
/// como nota de referencia.
enum Temperament { equal, just, pythagorean, meantone, custom }

class Notes {
  Notes._();

  static const List<String> solfeoSharp = <String>['Do', 'Do♯', 'Re', 'Re♯', 'Mi', 'Fa', 'Fa♯', 'Sol', 'Sol♯', 'La', 'La♯', 'Si'];
  static const List<String> solfeoFlat = <String>['Do', 'Re♭', 'Re', 'Mi♭', 'Mi', 'Fa', 'Sol♭', 'Sol', 'La♭', 'La', 'Si♭', 'Si'];
  static const List<String> englishSharp = <String>['C', 'C♯', 'D', 'D♯', 'E', 'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B'];
  static const List<String> englishFlat = <String>['C', 'D♭', 'D', 'E♭', 'E', 'F', 'G♭', 'G', 'A♭', 'A', 'B♭', 'B'];
  static const List<String> germanSharp = <String>['C', 'Cis', 'D', 'Dis', 'E', 'F', 'Fis', 'G', 'Gis', 'A', 'Ais', 'H'];
  static const List<String> germanFlat = <String>['C', 'Des', 'D', 'Es', 'E', 'F', 'Ges', 'G', 'As', 'A', 'B', 'H'];
  static const List<String> indian = <String>['Sa', 're', 'Re', 'ga', 'Ga', 'Ma', 'Ma♯', 'Pa', 'dha', 'Dha', 'ni', 'Ni'];

  /// Nombre de una clase de altura (0 = Do ... 11 = Si). En la notación
  /// india, Sa es la tónica [indianTonic] (clase de altura, Do por defecto).
  static String name(int pitchClass, Notation notation, {bool flats = false, int indianTonic = 0}) {
    final int pc = ((pitchClass % 12) + 12) % 12;
    switch (notation) {
      case Notation.solfeo:
        return (flats ? solfeoFlat : solfeoSharp)[pc];
      case Notation.english:
        return (flats ? englishFlat : englishSharp)[pc];
      case Notation.german:
        return (flats ? germanFlat : germanSharp)[pc];
      case Notation.indian:
        return indian[((pc - indianTonic) % 12 + 12) % 12];
    }
  }

  /// Número MIDI → frecuencia en temperamento igual con [a4] como referencia.
  static double midiToHz(double midi, {double a4 = 440}) => a4 * math.pow(2, (midi - 69) / 12).toDouble();

  /// Frecuencia → número MIDI fraccionario (temperamento igual).
  static double hzToMidi(double hz, {double a4 = 440}) => 69 + 12 * (math.log(hz / a4) / math.ln2);

  /// Octava científica de un número MIDI (Do4 = 60).
  static int octaveOf(int midi) => (midi ~/ 12) - 1;

  static int pitchClassOf(int midi) => ((midi % 12) + 12) % 12;

  /// Desviaciones en cents de cada grado respecto al temperamento igual,
  /// con la tónica en el índice 0.
  static List<double> temperamentOffsets(Temperament t, {List<double>? custom}) {
    switch (t) {
      case Temperament.equal:
        return List<double>.filled(12, 0);
      case Temperament.just:
        // Entonación justa de 5 límites: 1, 16/15, 9/8, 6/5, 5/4, 4/3, 45/32, 3/2, 8/5, 5/3, 9/5, 15/8.
        return _ratiosToOffsets(<double>[1, 16 / 15, 9 / 8, 6 / 5, 5 / 4, 4 / 3, 45 / 32, 3 / 2, 8 / 5, 5 / 3, 9 / 5, 15 / 8]);
      case Temperament.pythagorean:
        return _ratiosToOffsets(<double>[1, 256 / 243, 9 / 8, 32 / 27, 81 / 64, 4 / 3, 729 / 512, 3 / 2, 128 / 81, 27 / 16, 16 / 9, 243 / 128]);
      case Temperament.meantone:
        // Mesotónico de cuarto de coma: quinta de 696,58 cents, desde Mi♭ hasta Sol♯.
        const double fifth = 696.578;
        final List<double> cents = List<double>.filled(12, 0);
        // Posiciones en el círculo de quintas respecto a Do: Mi♭ = -3 ... Sol♯ = +8.
        const List<int> fifthsFromC = <int>[0, 7, 2, -3, 4, -1, 6, 1, 8, 3, -2, 5];
        for (int pc = 0; pc < 12; pc++) {
          final double c = (fifthsFromC[pc] * fifth) % 1200;
          cents[pc] = c - pc * 100;
        }
        return cents;
      case Temperament.custom:
        final List<double> c = custom ?? List<double>.filled(12, 0);
        return List<double>.generate(12, (int i) => i < c.length ? c[i] : 0);
    }
  }

  static List<double> _ratiosToOffsets(List<double> ratios) {
    return List<double>.generate(12, (int i) => 1200 * math.log(ratios[i]) / math.ln2 - i * 100);
  }

  /// Frecuencia de un número MIDI en el temperamento dado, con [root] como
  /// tónica (clase de altura) del temperamento.
  static double frequency(int midi, {double a4 = 440, Temperament temperament = Temperament.equal, int root = 0, List<double>? custom}) {
    final List<double> offsets = temperamentOffsets(temperament, custom: custom);
    final int degree = ((midi - root) % 12 + 12) % 12;
    // Se mantiene La4 (o la nota de referencia) exacta restando su propio desplazamiento.
    final int refDegree = ((69 - root) % 12 + 12) % 12;
    final double cents = offsets[degree] - offsets[refDegree];
    return midiToHz(midi + cents / 100, a4: a4);
  }
}

/// Resultado de interpretar una frecuencia como nota.
class NoteReading {
  const NoteReading({required this.midi, required this.cents, required this.targetHz, required this.hz});

  /// Nota más cercana (número MIDI).
  final int midi;

  /// Desviación respecto a la nota, en cents (-50 a 50).
  final double cents;

  /// Frecuencia exacta de la nota en el temperamento vigente.
  final double targetHz;
  final double hz;

  int get pitchClass => Notes.pitchClassOf(midi);

  int get octave => Notes.octaveOf(midi);
}

/// Ajustes de interpretación de alturas: referencia, temperamento,
/// transposición y capo.
class PitchSettings {
  const PitchSettings({
    this.a4 = 440,
    this.temperament = Temperament.equal,
    this.temperamentRoot = 0,
    this.custom,
    this.transposition = 0,
    this.capo = 0,
    this.notation = Notation.solfeo,
    this.flats = false,
    this.indianTonic = 0,
  });

  final double a4;
  final Temperament temperament;

  /// Tónica del temperamento (clase de altura sonante).
  final int temperamentRoot;
  final List<double>? custom;

  /// Semitonos que se suman al nombre mostrado. Instrumento en Si♭ = +2
  /// (un Do escrito suena Si♭; el afinador muestra Do cuando oye Si♭).
  final int transposition;

  /// Traste del capo: las cuerdas al aire suben esos semitonos (las metas y
  /// los nombres de las cuerdas suben con él; la nota oída se nombra igual).
  final int capo;
  final Notation notation;
  final bool flats;

  /// Sa de la notación india (clase de altura escrita).
  final int indianTonic;

  PitchSettings copyWith({double? a4, Temperament? temperament, int? temperamentRoot, List<double>? custom, int? transposition, int? capo, Notation? notation, bool? flats, int? indianTonic}) {
    return PitchSettings(
      a4: a4 ?? this.a4,
      temperament: temperament ?? this.temperament,
      temperamentRoot: temperamentRoot ?? this.temperamentRoot,
      custom: custom ?? this.custom,
      transposition: transposition ?? this.transposition,
      capo: capo ?? this.capo,
      notation: notation ?? this.notation,
      flats: flats ?? this.flats,
      indianTonic: indianTonic ?? this.indianTonic,
    );
  }

  /// Frecuencia de una nota sonante en el temperamento vigente.
  double frequencyOf(int midi) => Notes.frequency(midi, a4: a4, temperament: temperament, root: temperamentRoot, custom: custom);

  /// Interpreta [hz] como la nota más cercana del temperamento.
  NoteReading read(double hz) {
    if (hz <= 0) {
      return NoteReading(midi: 69, cents: 0, targetHz: a4, hz: hz);
    }
    final double approx = Notes.hzToMidi(hz, a4: a4);
    int best = approx.round();
    double bestCents = 1e9;
    double bestTarget = a4;
    // Se revisan las vecinas porque el temperamento mueve las notas hasta 20 cents.
    for (int m = best - 1; m <= best + 1; m++) {
      final double target = Notes.frequency(m, a4: a4, temperament: temperament, root: temperamentRoot, custom: custom);
      final double c = 1200 * math.log(hz / target) / math.ln2;
      if (c.abs() < bestCents.abs()) {
        bestCents = c;
        best = m;
        bestTarget = target;
      }
    }
    return NoteReading(midi: best, cents: bestCents, targetHz: bestTarget, hz: hz);
  }

  /// Altura escrita (la que lee el músico) de una nota sonante.
  int writtenMidi(int sounding) => sounding + transposition;

  /// Altura sonante de una nota escrita.
  int soundingMidi(int written) => written - transposition;

  /// Nombre que se muestra para un número MIDI sonante, aplicando la
  /// transposición del instrumento.
  String displayName(int midi) => nameOfWritten(writtenMidi(midi));

  /// Nombre de una altura ya escrita (sin transponer).
  String nameOfWritten(int written) => Notes.name(Notes.pitchClassOf(written), notation, flats: flats, indianTonic: indianTonic);

  int displayOctave(int midi) => Notes.octaveOf(writtenMidi(midi));

  /// Nombre y octava juntos, por ejemplo "La4".
  String displayFull(int midi) => '${displayName(midi)}${displayOctave(midi)}';
}

/// Formato de frecuencia con un decimal y coma decimal (es) o punto (en).
String formatHz(double hz, {bool comma = true}) {
  final String s = hz.toStringAsFixed(1);
  return comma ? s.replaceAll('.', ',') : s;
}

/// Cents redondeados con signo: "+3", "−12" y "0" (nunca "−0").
String formatCents(double cents) {
  final int r = cents.round();
  if (r == 0) {
    return '0';
  }
  return r > 0 ? '+$r' : '−${-r}';
}
