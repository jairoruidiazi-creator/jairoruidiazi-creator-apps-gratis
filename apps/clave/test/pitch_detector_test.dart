// Detector de tono (B1): senos de Do0 a Do8, timbres con muchos armónicos,
// fundamental débil, fases al azar, voz, ruido y cada cuerda de cada perfil.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clave/audio/pitch_detector.dart';
import 'package:clave/music/instruments.dart';
import 'package:flutter_test/flutter_test.dart';

const int sr = 44100;

double hzOf(int midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

double centsBetween(double f, double ref) => 1200 * math.log(f / ref) / math.ln2;

/// Tono con los armónicos [amps] (el primero es la fundamental), fases al
/// azar y nivel máximo [amp]. [inharm] es la inarmonía de las cuerdas
/// rígidas (f_k = k·f0·√(1 + B·k²)) y [vibCents] un vibrato de 5,5 Hz.
Float32List tone(math.Random rnd, double f0, List<double> amps, {int n = 8192, double amp = 0.3, double inharm = 0, double vibCents = 0}) {
  final double t0 = 0.1 + rnd.nextDouble() * 1.9;
  final List<double> v = List<double>.filled(n, 0);
  final List<double> phases = <double>[for (int k = 0; k < amps.length; k++) rnd.nextDouble() * 2 * math.pi];
  // Fase acumulada de la fundamental con vibrato.
  final List<double> ph0 = List<double>.filled(n, 0);
  if (vibCents != 0) {
    double acc = 2 * math.pi * f0 * t0;
    for (int i = 0; i < n; i++) {
      final double t = t0 + i / sr;
      acc += 2 * math.pi * f0 * math.pow(2, vibCents / 1200 * math.sin(2 * math.pi * 5.5 * t)).toDouble() / sr;
      ph0[i] = acc;
    }
  }
  for (int k = 1; k <= amps.length; k++) {
    final double fk = k * f0 * math.sqrt(1 + inharm * k * k);
    if (fk >= 20000) {
      break;
    }
    final double a = amps[k - 1];
    final double ph = phases[k - 1];
    for (int i = 0; i < n; i++) {
      v[i] += vibCents != 0 ? a * math.sin(k * ph0[i] + ph) : a * math.sin(2 * math.pi * fk * (t0 + i / sr) + ph);
    }
  }
  double m = 0;
  for (final double x in v) {
    m = math.max(m, x.abs());
  }
  return Float32List.fromList(<double>[for (final double x in v) m > 0 ? amp * x / m : 0]);
}

/// Paso alto Butterworth de 2.º orden (micrófono de teléfono, caja de guitarra).
Float32List highPass(Float32List x, double fc) {
  final double k = math.tan(math.pi * fc / sr);
  const double q = 0.7071067811865476;
  final double norm = 1 / (1 + k / q + k * k);
  final double b0 = norm, b1 = -2 * norm, b2 = norm;
  final double a1 = 2 * (k * k - 1) * norm, a2 = (1 - k / q + k * k) * norm;
  final Float32List y = Float32List(x.length);
  double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  for (int i = 0; i < x.length; i++) {
    final double xi = x[i];
    final double yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1;
    x1 = xi;
    y2 = y1;
    y1 = yi;
    y[i] = yi;
  }
  return y;
}

Float32List tail(Float32List x, int n) => Float32List.sublistView(x, x.length - n);

/// Ruido gaussiano (Box-Muller).
double gauss(math.Random rnd) {
  final double u = 1 - rnd.nextDouble();
  final double v = rnd.nextDouble();
  return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
}

double rmsOf(Float32List x) {
  double s = 0;
  for (final double v in x) {
    s += v * v;
  }
  return math.sqrt(s / x.length);
}

/// Ganancia de los formantes de una vocal (resonadores de 2.º orden).
double formantGain(double f, List<List<double>> formants) {
  final double w = 2 * math.pi * f / sr;
  double g = 1;
  for (final List<double> fb in formants) {
    final double r = math.exp(-math.pi * fb[1] / sr);
    final double th = 2 * math.pi * fb[0] / sr;
    final double a1 = -2 * r * math.cos(th);
    final double a2 = r * r;
    final double re = 1 + a1 * math.cos(w) + a2 * math.cos(2 * w);
    final double im = -(a1 * math.sin(w) + a2 * math.sin(2 * w));
    g *= (1 + a1 + a2).abs() / math.sqrt(re * re + im * im);
  }
  return g;
}

const Map<String, List<List<double>>> vowels = <String, List<List<double>>>{
  'a': <List<double>>[<double>[730, 90], <double>[1090, 110], <double>[2440, 170]],
  'i': <List<double>>[<double>[270, 60], <double>[2290, 100], <double>[3010, 120]],
  'u': <List<double>>[<double>[300, 60], <double>[870, 90], <double>[2240, 120]],
  'e': <List<double>>[<double>[530, 70], <double>[1840, 100], <double>[2480, 120]],
  'o': <List<double>>[<double>[570, 80], <double>[840, 90], <double>[2410, 120]],
};

List<double> voiceAmps(double f0, String vowel, double slope) => <double>[
      for (int k = 1; k < 60 && k * f0 <= 6000; k++) 1 / math.pow(k, slope) * formantGain(k * f0, vowels[vowel]!),
    ];

const List<double> violin = <double>[1.0, 0.8, 0.6, 0.5, 0.4, 0.3, 0.25, 0.2, 0.15, 0.1];
const List<double> guitar = <double>[1.0, 0.8, 0.9, 0.5, 0.4, 0.3, 0.2, 0.15, 0.1, 0.08];
const List<double> bass = <double>[1.0, 0.9, 0.7, 0.5, 0.35, 0.25, 0.18, 0.12, 0.08, 0.05];
const List<double> weak30dB = <double>[0.03, 1.0, 0.8, 0.5, 0.3, 0.2];
const List<double> weak = <double>[0.3, 1.0, 0.6, 0.3];
const List<double> flute = <double>[1.0, 0.35, 0.12, 0.05];
final List<double> saw = <double>[for (int k = 1; k < 40; k++) 1 / k];

void main() {
  final PitchDetector det = PitchDetector();

  /// Cuántas notas de [midis] se detectan mal (más de [tolCents] o sin claridad).
  List<String> misses(Iterable<int> midis, Float32List Function(double f0) gen, {double tolCents = 2, int reps = 1}) {
    final List<String> out = <String>[];
    for (final int m in midis) {
      final double f0 = hzOf(m);
      for (int r = 0; r < reps; r++) {
        final PitchResult res = det.detect(gen(f0));
        final double c = res.hasPitch ? centsBetween(res.frequency, f0) : double.nan;
        if (!res.hasPitch || res.clarity < 0.6 || c.isNaN || c.abs() >= tolCents) {
          out.add('midi $m (${f0.toStringAsFixed(2)} Hz) → ${res.frequency.toStringAsFixed(2)} Hz (${c.toStringAsFixed(1)} c, claridad ${res.clarity.toStringAsFixed(2)})');
        }
      }
    }
    return out;
  }

  test('Senos de Do0 (16,35 Hz) a Do8 (4186 Hz), cualquier nivel y fase: menos de 1 cent', () {
    final math.Random rnd = math.Random(11);
    expect(misses(<int>[for (int m = 12; m <= 108; m++) m], (double f) => tone(rnd, f, const <double>[1.0], amp: 0.02 + rnd.nextDouble() * 0.78), tolCents: 1), isEmpty);
  });

  test('Violín (10 armónicos) de Sol3 a Do8, también en el registro agudo', () {
    final math.Random rnd = math.Random(12);
    expect(misses(<int>[for (int m = 55; m <= 108; m++) m], (double f) => tone(rnd, f, violin), reps: 2), isEmpty);
  });

  test('Sierra (39 armónicos) de Do1 a Do8', () {
    final math.Random rnd = math.Random(13);
    expect(misses(<int>[for (int m = 24; m <= 108; m++) m], (double f) => tone(rnd, f, saw)), isEmpty);
  });

  test('Fundamental débil: no salta a la octava de arriba', () {
    final math.Random rnd = math.Random(14);
    expect(misses(<int>[for (int m = 23; m <= 72; m++) m], (double f) => tone(rnd, f, weak30dB)), isEmpty);
    expect(misses(<int>[for (int m = 23; m <= 108; m++) m], (double f) => tone(rnd, f, weak)), isEmpty);
  });

  test('Guitarra y bajo con el paso alto de un micrófono de teléfono', () {
    final math.Random rnd = math.Random(15);
    expect(misses(<int>[for (int m = 40; m <= 96; m++) m], (double f) => tail(highPass(tone(rnd, f, guitar, n: 16384), 100), 8192)), isEmpty);
    expect(misses(<int>[for (int m = 23; m <= 55; m++) m], (double f) => tail(highPass(tone(rnd, f, bass, n: 16384), 80), 8192)), isEmpty);
  });

  test('Flauta de Do4 a Do7', () {
    final math.Random rnd = math.Random(16);
    expect(misses(<int>[for (int m = 60; m <= 96; m++) m], (double f) => tone(rnd, f, flute)), isEmpty);
  });

  test('Voz cantada: cinco vocales con dos pendientes espectrales', () {
    final math.Random rnd = math.Random(17);
    for (final double slope in <double>[2.0, 1.0]) {
      for (final String v in vowels.keys) {
        expect(misses(<int>[for (int m = 40; m <= 84; m += 2) m], (double f) => tone(rnd, f, voiceAmps(f, v, slope)), tolCents: 3), isEmpty, reason: '/$v/ pendiente $slope');
      }
    }
  });

  test('Vibrato de ±15 cents en el registro agudo: la nota central', () {
    final math.Random rnd = math.Random(18);
    expect(misses(<int>[for (int m = 76; m <= 108; m += 2) m], (double f) => tone(rnd, f, violin, vibCents: 15), tolCents: 25), isEmpty);
  });

  test('Guitarra con ruido (20 y 10 dB de relación señal/ruido)', () {
    final math.Random rnd = math.Random(19);
    for (final double snr in <double>[20, 10]) {
      Float32List gen(double f) {
        final Float32List s = tone(rnd, f, guitar);
        final double sd = rmsOf(s) * math.pow(10, -snr / 20).toDouble();
        return Float32List.fromList(<double>[for (final double x in s) x + sd * gauss(rnd)]);
      }

      expect(misses(<int>[for (int m = 40; m <= 96; m += 3) m], gen, tolCents: 5), isEmpty, reason: 'SNR $snr dB');
    }
  });

  test('Ruido blanco, ruido rosa y silencio no dan nota', () {
    final math.Random rnd = math.Random(20);
    int notes = 0;
    for (int k = 0; k < 40; k++) {
      final Float32List w = Float32List.fromList(<double>[for (int i = 0; i < 8192; i++) 0.1 * gauss(rnd)]);
      final PitchResult r = det.detect(w);
      if (r.hasPitch && r.clarity >= 0.6) {
        notes++;
      }
    }
    for (int k = 0; k < 30; k++) {
      // Ruido rosa con el filtro de Paul Kellet.
      double b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0;
      final List<double> p = <double>[];
      for (int i = 0; i < 8192 + 2048; i++) {
        final double white = gauss(rnd);
        b0 = 0.99886 * b0 + white * 0.0555179;
        b1 = 0.99332 * b1 + white * 0.0750759;
        b2 = 0.96900 * b2 + white * 0.1538520;
        b3 = 0.86650 * b3 + white * 0.3104856;
        b4 = 0.55000 * b4 + white * 0.5329522;
        b5 = -0.7616 * b5 - white * 0.0168980;
        p.add(b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362);
        b6 = white * 0.115926;
      }
      final Float32List x = Float32List.fromList(p.sublist(2048));
      final double sd = rmsOf(x);
      for (int i = 0; i < x.length; i++) {
        x[i] = 0.1 * x[i] / sd;
      }
      final PitchResult r = det.detect(x);
      if (r.hasPitch && r.clarity >= 0.6) {
        notes++;
      }
    }
    expect(notes, 0);
    expect(det.detect(Float32List(8192)).hasPitch, isFalse);
  });

  test('Cada cuerda de cada perfil se detecta y se asigna a su orden', () {
    final math.Random rnd = math.Random(21);
    for (final Instrument inst in Instruments.all) {
      for (int c = 0; c < inst.courses.length; c++) {
        for (final int midi in inst.courses[c]) {
          final double f0 = hzOf(midi);
          final PitchResult r = det.detect(tail(highPass(tone(rnd, f0, guitar, n: 16384), 80), 8192));
          expect(r.hasPitch, isTrue, reason: '${inst.id} orden ${c + 1} ($midi)');
          final double cents = centsBetween(r.frequency, f0);
          expect(cents.abs(), lessThan(2), reason: '${inst.id} orden ${c + 1} ($midi): $cents c');
          final double heard = 69 + 12 * math.log(r.frequency / 440) / math.ln2;
          // Un orden que tenga esa misma altura (en el charango, el Mi5 está
          // en el 3.er y en el 5.º orden).
          final CourseMatch match = inst.nearestCourse(heard);
          expect(inst.courses[match.course], contains(midi), reason: '${inst.id}: $midi se asignó al orden ${match.course + 1}');
          expect(match.midi, midi);
        }
      }
    }
  });

  test('Piano de A0 con inarmonía: el error queda en lo que da la propia cuerda', () {
    final math.Random rnd = math.Random(22);
    const List<double> piano = <double>[0.4, 1.0, 0.9, 0.7, 0.6, 0.5, 0.4, 0.3, 0.25, 0.2, 0.15, 0.1];
    expect(misses(<int>[for (int m = 21; m <= 108; m += 3) m], (double f) => tone(rnd, f, piano, inharm: f < 100 ? 2e-4 : 5e-5), tolCents: 15), isEmpty);
  });

  test('Bloques cortos y señal plana no dan nota; pcm16ToFloat convierte extremos', () {
    expect(det.detect(Float32List(1024)).hasPitch, isFalse);
    expect(det.detect(Float32List.fromList(List<double>.filled(8192, 0.5))).hasPitch, isFalse);
    final ByteData b = ByteData(4)
      ..setInt16(0, 32767, Endian.little)
      ..setInt16(2, -32768, Endian.little);
    final Float32List f = pcm16ToFloat(b.buffer.asUint8List());
    expect(f[0], closeTo(1, 1e-3));
    expect(f[1], -1);
  });
}
