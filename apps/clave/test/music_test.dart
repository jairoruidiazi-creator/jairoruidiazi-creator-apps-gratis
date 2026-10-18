import 'dart:math' as math;

import 'package:clave/music/instruments.dart';
import 'package:clave/music/notes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Notas', () {
    test('La4 = 440 Hz y Do4 = 261,63 Hz en temperamento igual', () {
      expect(Notes.midiToHz(69), 440);
      expect(Notes.midiToHz(60), closeTo(261.63, 0.01));
      expect(Notes.hzToMidi(880), closeTo(81, 1e-9));
      expect(Notes.octaveOf(60), 4);
      expect(Notes.octaveOf(21), 0);
      expect(Notes.octaveOf(12), 0);
      expect(Notes.pitchClassOf(61), 1);
      expect(Notes.pitchClassOf(-1), 11);
    });

    test('Los nombres cambian con la notación y los bemoles', () {
      expect(Notes.name(0, Notation.solfeo), 'Do');
      expect(Notes.name(1, Notation.solfeo), 'Do♯');
      expect(Notes.name(1, Notation.solfeo, flats: true), 'Re♭');
      expect(Notes.name(11, Notation.german), 'H');
      expect(Notes.name(10, Notation.german, flats: true), 'B');
      expect(Notes.name(9, Notation.english), 'A');
      expect(Notes.name(7, Notation.indian), 'Pa');
    });

    test('En la notación india, Sa es la tónica elegida (M5)', () {
      expect(Notes.name(2, Notation.indian, indianTonic: 2), 'Sa');
      expect(Notes.name(9, Notation.indian, indianTonic: 2), 'Pa');
      const PitchSettings ps = PitchSettings(notation: Notation.indian, indianTonic: 7);
      expect(ps.displayName(67), 'Sa'); // Sol sonante
      expect(ps.displayName(74), 'Pa'); // Re, una quinta arriba
      // Con transposición, Sa se fija en la altura escrita.
      const PitchSettings sib = PitchSettings(notation: Notation.indian, indianTonic: 0, transposition: 2);
      expect(sib.displayName(58), 'Sa'); // Si♭ sonante = Do escrito
    });

    test('Los temperamentos históricos desvían como manda la teoría', () {
      final List<double> just = Notes.temperamentOffsets(Temperament.just);
      expect(just[7], closeTo(1.955, 0.01)); // quinta justa 3/2 = 701,955 cents
      expect(just[4], closeTo(-13.69, 0.01)); // tercera mayor 5/4 = 386,31 cents
      final List<double> pyth = Notes.temperamentOffsets(Temperament.pythagorean);
      expect(pyth[4], closeTo(7.82, 0.01)); // 81/64 = 407,82 cents
      final List<double> mean = Notes.temperamentOffsets(Temperament.meantone);
      expect(mean[4], closeTo(-13.69, 0.1)); // tercera pura en mesotónico de 1/4 de coma
      expect(mean[7], closeTo(-3.42, 0.1));
      expect(Notes.temperamentOffsets(Temperament.equal).every((double d) => d == 0), isTrue);
    });

    test('La referencia La4 se mantiene exacta en cualquier temperamento', () {
      for (final Temperament tmp in Temperament.values) {
        expect(Notes.frequency(69, temperament: tmp, a4: 442), closeTo(442, 1e-9), reason: tmp.name);
      }
      final double mi = Notes.frequency(64, temperament: Temperament.just);
      expect(1200 * math.log(mi / Notes.midiToHz(64)) / math.ln2, closeTo(-13.69 + 15.64, 0.05));
    });

    test('PitchSettings lee frecuencias y transpone; el capo no cambia el nombre de lo que suena (G9)', () {
      const PitchSettings ps = PitchSettings();
      final NoteReading r = ps.read(445);
      expect(r.midi, 69);
      expect(r.cents, closeTo(19.56, 0.05));
      expect(ps.read(430).midi, 69);
      expect(ps.read(430).cents, lessThan(0));
      const PitchSettings sib = PitchSettings(transposition: 2);
      expect(sib.displayName(70), 'Do'); // Si♭ sonante se muestra como Do
      expect(sib.writtenMidi(70), 72);
      expect(sib.soundingMidi(72), 70);
      expect(sib.displayFull(70), 'Do5');
      // Un Fa♯ que suena con capo sigue siendo un Fa♯.
      const PitchSettings capo = PitchSettings(capo: 2, notation: Notation.english);
      expect(capo.displayName(66), 'F♯');
      expect(const PitchSettings(a4: 432).read(432).midi, 69);
    });

    test('Formato de hercios y de cents: nunca "−0" (M15)', () {
      expect(formatHz(440.04), '440,0');
      expect(formatHz(261.626, comma: false), '261.6');
      expect(formatCents(0), '0');
      expect(formatCents(-0.4), '0');
      expect(formatCents(0.49), '0');
      expect(formatCents(-0.6), '−1');
      expect(formatCents(3.2), '+3');
      expect(formatCents(-12.4), '−12');
    });
  });

  group('Instrumentos', () {
    test('Cuerdas de la guitarra y orden más cercano', () {
      final Instrument g = Instruments.byId('guitarra');
      expect(g.strings, <int>[40, 45, 50, 55, 59, 64]);
      expect(g.nearestCourse(Notes.hzToMidi(110)).course, 1); // La2
      expect(g.nearestCourse(Notes.hzToMidi(330)).course, 5); // Mi4
      expect(Instruments.byId('clarinete').transposition, 2);
      expect(Instruments.byId('no-existe').id, 'cromatico');
      expect(Instruments.maybeById('no-existe'), isNull);
      expect(Instruments.maybeById(''), isNull);
      final Set<String> ids = Instruments.all.map((Instrument i) => i.id).toSet();
      expect(ids.length, Instruments.all.length);
    });

    test('Tiple: tres cuerdas por orden y la central de los órdenes 2.º a 4.º a la octava (G8)', () {
      final Instrument t = Instruments.byId('tiple');
      expect(t.name(true), 'Tiple colombiano');
      expect(t.stringsPerCourse, 3);
      expect(t.courses, <List<int>>[<int>[62, 50], <int>[67, 55], <int>[71, 59], <int>[64]]);
      expect(t.strings, <int>[62, 67, 71, 64]); // Re4 Sol4 Si4 Mi4
      // La cuerda entorchada (Re3) cuenta como el 4.º orden y su meta es Re3.
      final CourseMatch low = t.nearestCourse(50.2);
      expect(low.course, 0);
      expect(low.midi, 50);
      expect(t.targetInCourse(0, 50.3), 50);
      expect(t.targetInCourse(0, 61.6), 62);
      expect(t.nearestCourse(58.8).course, 2); // Si3, octava del 2.º orden
    });

    test('Requinto colombiano al unísono y requinto de seis cuerdas aparte (G8)', () {
      final Instrument r = Instruments.byId('requinto');
      expect(r.name(true), 'Requinto colombiano');
      expect(r.courses.every((List<int> c) => c.length == 1), isTrue);
      expect(r.strings, <int>[62, 67, 71, 64]);
      expect(r.stringsPerCourse, 3);
      final Instrument g = Instruments.byId('requinto_guitarra');
      expect(g.name(true), 'Requinto (guitarra)');
      expect(g.name(false), 'Requinto (guitar)');
      expect(g.strings, <int>[45, 50, 55, 60, 64, 69]);
      final Instrument b = Instruments.byId('bandola');
      expect(b.courses.length, 6);
      expect(b.stringsPerCourse, 2);
    });

    test('Con capo, las metas y las cuerdas suben (G9)', () {
      final Instrument g = Instruments.byId('guitarra');
      // Capo en el 2.º traste: la quinta cuerda (La2) suena Si2.
      final CourseMatch m = g.nearestCourse(47.1, capo: 2);
      expect(m.course, 1);
      expect(m.midi, 47);
      expect(g.targetInCourse(1, 46.6, capo: 2), 47);
      // Sin capo, el mismo Si2 queda entre cuerdas y se asigna a La2.
      expect(g.nearestCourse(47.1).course, 1);
      expect(g.nearestCourse(47.1).midi, 45);
    });

    test('Indicaciones de tempo', () {
      expect(TempoMark.forBpm(50), 'Largo');
      expect(TempoMark.forBpm(100), 'Andante');
      expect(TempoMark.forBpm(140), 'Allegro');
      expect(TempoMark.forBpm(300), 'Prestissimo');
    });
  });
}
