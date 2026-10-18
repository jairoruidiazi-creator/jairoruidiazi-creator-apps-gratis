import 'dart:math' as math;
import 'dart:ui';

import '../../core/rng.dart';
import '../../model/age_band.dart';

/// Un trazo guiado: nombre, lo que se dice, y sus líneas en un cuadro de
/// 100×100 (cada línea es una lista de puntos en orden de escritura).
class TraceTemplate {
  const TraceTemplate(this.id, this.nombre, this.dicho, this.strokes, {this.ejemplo, this.zurdoInvierte = const <int>[], this.dichoZurdo});

  final String id;
  final String nombre;

  /// Lo que dice la voz al presentarlo ("la a, como en avión").
  final String dicho;
  final List<List<Offset>> strokes;

  /// Palabra de ejemplo con pictograma (para letras).
  final String? ejemplo;

  /// Trazos de pre-escritura acostados que, en modo zurdo, empiezan por la
  /// derecha (las letras y los números se escriben siempre igual).
  final List<int> zurdoInvierte;
  final String? dichoZurdo;

  /// Versión para una mano zurda: los trazos acostados de pre-escritura van
  /// de derecha a izquierda.
  TraceTemplate paraZurdo() {
    if (zurdoInvierte.isEmpty) {
      return this;
    }
    return TraceTemplate(
      id,
      nombre,
      dichoZurdo ?? dicho,
      <List<Offset>>[for (int i = 0; i < strokes.length; i++) zurdoInvierte.contains(i) ? strokes[i].reversed.toList() : strokes[i]],
      ejemplo: ejemplo,
    );
  }

  /// Si la línea [k] termina donde empieza (círculos, el cuadrado, la o).
  bool closed(int k) => strokes[k].length > 2 && (strokes[k].first - strokes[k].last).distance < 8;

  /// Puntos de muestreo uniformes a lo largo de la línea [k].
  List<Offset> sampleStroke(int k, double step) => _sampleOne(strokes[k], step);

  static List<Offset> _sampleOne(List<Offset> s, double step) {
    final List<Offset> out = <Offset>[s.first];
    if (s.length == 1) {
      return out;
    }
    double carry = 0;
    for (int i = 1; i < s.length; i++) {
      final Offset a = s[i - 1];
      final Offset b = s[i];
      final double len = (b - a).distance;
      if (len == 0) {
        continue;
      }
      double t = step - carry;
      while (t <= len) {
        out.add(Offset.lerp(a, b, t / len)!);
        t += step;
      }
      carry = len - (t - step);
    }
    if ((out.last - s.last).distance > 0.01) {
      out.add(s.last);
    }
    return out;
  }

  /// Puntos de muestreo uniformes a lo largo de todas las líneas.
  List<Offset> sample(double step) => <Offset>[for (final List<Offset> s in strokes) ..._sampleOne(s, step)];
}

List<Offset> _l(List<double> xy) => <Offset>[for (int i = 0; i + 1 < xy.length; i += 2) Offset(xy[i], xy[i + 1])];

/// Arco muestreado: centro, radio, ángulo inicial y final en grados
/// (sentido horario en pantalla porque el eje y crece hacia abajo).
List<Offset> _arc(double cx, double cy, double r, double a0, double a1, {double rx = -1, int n = 18}) {
  final double radX = rx < 0 ? r : rx;
  final List<Offset> out = <Offset>[];
  for (int i = 0; i <= n; i++) {
    final double a = (a0 + (a1 - a0) * i / n) * math.pi / 180;
    out.add(Offset(cx + radX * math.cos(a), cy + r * math.sin(a)));
  }
  return out;
}

List<Offset> _join(List<List<Offset>> parts) => <Offset>[for (final List<Offset> p in parts) ...p];

/// Catálogo de trazos: pre-escritura, letras mayúsculas, minúsculas básicas y dígitos.
class TraceCatalog {
  TraceCatalog._();

  static final List<TraceTemplate> preescritura = <TraceTemplate>[
    TraceTemplate('h_line', 'línea acostada', 'Una línea acostada, de izquierda a derecha.', <List<Offset>>[_l(<double>[15, 50, 85, 50])], zurdoInvierte: <int>[0], dichoZurdo: 'Una línea acostada, de derecha a izquierda.'),
    TraceTemplate('v_line', 'línea parada', 'Una línea parada, de arriba hacia abajo.', <List<Offset>>[_l(<double>[50, 15, 50, 85])]),
    TraceTemplate('circle', 'círculo', 'Un círculo: empieza arriba y da la vuelta.', <List<Offset>>[_arc(50, 50, 32, -90, -450)]),
    TraceTemplate('zigzag', 'zigzag', 'Un zigzag: sube y baja como una montaña.', <List<Offset>>[_l(<double>[10, 70, 30, 30, 50, 70, 70, 30, 90, 70])], zurdoInvierte: <int>[0]),
    TraceTemplate('wave', 'ola', 'Una ola: sube y baja suavecito.', <List<Offset>>[_join(<List<Offset>>[_arc(28, 50, 16, 180, 360), _arc(60, 50, 16, 180, 0), _arc(92, 50, 16, 180, 270)])], zurdoInvierte: <int>[0]),
    TraceTemplate('cross', 'cruz', 'Una cruz: primero parada y luego acostada.', <List<Offset>>[_l(<double>[50, 15, 50, 85]), _l(<double>[15, 50, 85, 50])], zurdoInvierte: <int>[1]),
    TraceTemplate('spiral', 'caracol', 'Un caracol: empieza en el centro y da vueltas hacia afuera.', <List<Offset>>[
      <Offset>[for (int i = 0; i <= 60; i++) Offset(50 + (2 + i * 0.55) * math.cos(i * 0.21), 50 + (2 + i * 0.55) * math.sin(i * 0.21))],
    ]),
    TraceTemplate('square', 'cuadrado', 'Un cuadrado: cuatro lados iguales.', <List<Offset>>[_l(<double>[22, 22, 78, 22, 78, 78, 22, 78, 22, 22])]),
  ];

  static final List<TraceTemplate> mayusculas = <TraceTemplate>[
    TraceTemplate('A', 'a mayúscula', 'La a, como en avión.', <List<Offset>>[_l(<double>[50, 15, 20, 85]), _l(<double>[50, 15, 80, 85]), _l(<double>[32, 60, 68, 60])], ejemplo: '2708'),
    TraceTemplate('B', 'be mayúscula', 'La be, como en bicicleta.', <List<Offset>>[_l(<double>[25, 15, 25, 85]), _join(<List<Offset>>[_l(<double>[25, 15, 55, 15]), _arc(55, 32, 17, -90, 90), _l(<double>[55, 49, 25, 49])]), _join(<List<Offset>>[_l(<double>[25, 49, 58, 49]), _arc(58, 67, 18, -90, 90), _l(<double>[58, 85, 25, 85])])], ejemplo: '1f6b2'),
    TraceTemplate('C', 'ce mayúscula', 'La ce, como en casa.', <List<Offset>>[_arc(55, 50, 35, -50, -310, rx: 32)], ejemplo: '1f3e1'),
    TraceTemplate('D', 'de mayúscula', 'La de, como en dado.', <List<Offset>>[_l(<double>[25, 15, 25, 85]), _join(<List<Offset>>[_l(<double>[25, 15, 45, 15]), _arc(45, 50, 35, -90, 90, rx: 32), _l(<double>[45, 85, 25, 85])])], ejemplo: '1f3b2'),
    TraceTemplate('E', 'e mayúscula', 'La e, como en elefante.', <List<Offset>>[_l(<double>[72, 15, 25, 15, 25, 85, 72, 85]), _l(<double>[25, 50, 62, 50])], ejemplo: '1f418'),
    TraceTemplate('F', 'efe mayúscula', 'La efe, como en flor.', <List<Offset>>[_l(<double>[72, 15, 25, 15, 25, 85]), _l(<double>[25, 50, 62, 50])], ejemplo: '1f33b'),
    TraceTemplate('G', 'ge mayúscula', 'La ge, como en gato.', <List<Offset>>[_join(<List<Offset>>[_arc(52, 50, 35, -45, -315, rx: 32), _l(<double>[84, 60, 84, 55, 56, 55])])], ejemplo: '1f408'),
    TraceTemplate('H', 'hache mayúscula', 'La hache, como en helado.', <List<Offset>>[_l(<double>[25, 15, 25, 85]), _l(<double>[75, 15, 75, 85]), _l(<double>[25, 50, 75, 50])], ejemplo: '1f366'),
    TraceTemplate('I', 'i mayúscula', 'La i, como en isla.', <List<Offset>>[_l(<double>[50, 15, 50, 85])], ejemplo: '1f3dd'),
    TraceTemplate('J', 'jota mayúscula', 'La jota, como en jirafa.', <List<Offset>>[_join(<List<Offset>>[_l(<double>[62, 15, 62, 65]), _arc(44, 65, 18, 0, 180)])], ejemplo: '1f992'),
    TraceTemplate('K', 'ka mayúscula', 'La ka, como en koala.', <List<Offset>>[_l(<double>[25, 15, 25, 85]), _l(<double>[72, 15, 25, 55]), _l(<double>[40, 42, 75, 85])], ejemplo: '1f428'),
    TraceTemplate('L', 'ele mayúscula', 'La ele, como en luna.', <List<Offset>>[_l(<double>[28, 15, 28, 85, 75, 85])], ejemplo: '1f319'),
    TraceTemplate('M', 'eme mayúscula', 'La eme, como en mango.', <List<Offset>>[_l(<double>[18, 85, 18, 15, 50, 60, 82, 15, 82, 85])], ejemplo: '1f96d'),
    TraceTemplate('N', 'ene mayúscula', 'La ene, como en nube.', <List<Offset>>[_l(<double>[25, 85, 25, 15, 75, 85, 75, 15])], ejemplo: '2601'),
    TraceTemplate('Ñ', 'eñe mayúscula', 'La eñe, como en piña.', <List<Offset>>[_l(<double>[25, 85, 25, 25, 75, 85, 75, 25]), _join(<List<Offset>>[_arc(38, 12, 5, 180, 360, rx: 10), _arc(62, 12, 5, 180, 0, rx: 10)])], ejemplo: '1f34d'),
    TraceTemplate('O', 'o mayúscula', 'La o, como en oso.', <List<Offset>>[_arc(50, 50, 35, -90, -450, rx: 30)], ejemplo: '1f43b'),
    TraceTemplate('P', 'pe mayúscula', 'La pe, como en pato.', <List<Offset>>[_l(<double>[25, 85, 25, 15]), _join(<List<Offset>>[_l(<double>[25, 15, 55, 15]), _arc(55, 34, 19, -90, 90), _l(<double>[55, 53, 25, 53])])], ejemplo: '1f986'),
    TraceTemplate('Q', 'cu mayúscula', 'La cu, como en queso.', <List<Offset>>[_arc(50, 48, 33, -90, -450, rx: 30), _l(<double>[58, 66, 80, 88])], ejemplo: '1f9c0'),
    TraceTemplate('R', 'erre mayúscula', 'La erre, como en ratón.', <List<Offset>>[_l(<double>[25, 85, 25, 15]), _join(<List<Offset>>[_l(<double>[25, 15, 55, 15]), _arc(55, 34, 19, -90, 90), _l(<double>[55, 53, 25, 53])]), _l(<double>[45, 53, 78, 85])], ejemplo: '1f401'),
    TraceTemplate('S', 'ese mayúscula', 'La ese, como en sol.', <List<Offset>>[_join(<List<Offset>>[_arc(50, 33, 17, -40, -180, rx: 22), _arc(50, 67, 17, -90, 140, rx: 22)])], ejemplo: '2600'),
    TraceTemplate('T', 'te mayúscula', 'La te, como en tortuga.', <List<Offset>>[_l(<double>[20, 15, 80, 15]), _l(<double>[50, 15, 50, 85])], ejemplo: '1f422'),
    TraceTemplate('U', 'u mayúscula', 'La u, como en uva.', <List<Offset>>[_join(<List<Offset>>[_l(<double>[25, 15, 25, 60]), _arc(50, 60, 25, 180, 0), _l(<double>[75, 60, 75, 15])])], ejemplo: '1f347'),
    TraceTemplate('V', 've mayúscula', 'La ve, como en vaca.', <List<Offset>>[_l(<double>[20, 15, 50, 85, 80, 15])], ejemplo: '1f404'),
    TraceTemplate('W', 'doble ve', 'La doble ve, como en wafle.', <List<Offset>>[_l(<double>[12, 15, 30, 85, 50, 35, 70, 85, 88, 15])], ejemplo: '1f9c7'),
    TraceTemplate('X', 'equis', 'La equis, como en taxi.', <List<Offset>>[_l(<double>[22, 15, 78, 85]), _l(<double>[78, 15, 22, 85])], ejemplo: '1f695'),
    TraceTemplate('Y', 'ye', 'La ye, como en yoyó.', <List<Offset>>[_l(<double>[22, 15, 50, 52]), _l(<double>[78, 15, 50, 52, 50, 85])], ejemplo: '1fa80'),
    TraceTemplate('Z', 'zeta', 'La zeta, como en zapato.', <List<Offset>>[_l(<double>[22, 15, 78, 15, 22, 85, 78, 85])], ejemplo: '1f45e'),
  ];

  static final List<TraceTemplate> minusculas = <TraceTemplate>[
    TraceTemplate('a', 'a minúscula', 'La a pequeña: un círculo hacia la izquierda y un palito.', <List<Offset>>[_arc(48, 62, 20, -30, -390, rx: 18), _l(<double>[66, 42, 66, 82])]),
    TraceTemplate('e', 'e minúscula', 'La e pequeña: una rayita y la vuelta.', <List<Offset>>[_join(<List<Offset>>[_l(<double>[30, 62, 68, 62]), _arc(49, 62, 20, 0, -230, rx: 19)])]),
    TraceTemplate('i', 'i minúscula', 'La i pequeña: un palito y su punto.', <List<Offset>>[_l(<double>[50, 42, 50, 82]), _l(<double>[50, 28, 50, 28])]),
    TraceTemplate('o', 'o minúscula', 'La o pequeña: un círculo hacia la izquierda.', <List<Offset>>[_arc(50, 62, 20, -90, -450, rx: 18)]),
    TraceTemplate('u', 'u minúscula', 'La u pequeña: baja, sube y otro palito.', <List<Offset>>[_join(<List<Offset>>[_l(<double>[32, 42, 32, 68]), _arc(49, 68, 14, 180, 0, rx: 17), _l(<double>[66, 68, 66, 42, 66, 82])])]),
    TraceTemplate('l', 'ele minúscula', 'La ele pequeña: un palito alto.', <List<Offset>>[_l(<double>[50, 15, 50, 82])]),
    TraceTemplate('m', 'eme minúscula', 'La eme pequeña: un palito y dos montañitas.', <List<Offset>>[_join(<List<Offset>>[_l(<double>[22, 42, 22, 82, 22, 56]), _arc(36, 56, 14, 180, 360), _l(<double>[50, 56, 50, 82, 50, 56]), _arc(64, 56, 14, 180, 360), _l(<double>[78, 56, 78, 82])])]),
    TraceTemplate('n', 'ene minúscula', 'La ene pequeña: un palito y una montañita.', <List<Offset>>[_join(<List<Offset>>[_l(<double>[32, 42, 32, 82, 32, 60]), _arc(50, 60, 18, 180, 360), _l(<double>[68, 60, 68, 82])])]),
    TraceTemplate('p', 'pe minúscula', 'La pe pequeña: baja mucho y hace la pancita.', <List<Offset>>[_l(<double>[34, 42, 34, 95]), _arc(50, 60, 18, -90, 270, rx: 16)]),
    TraceTemplate('s', 'ese minúscula', 'La ese pequeña: como una culebrita.', <List<Offset>>[_join(<List<Offset>>[_arc(50, 52, 10, -40, -180, rx: 13), _arc(50, 72, 10, -90, 140, rx: 13)])]),
    TraceTemplate('t', 'te minúscula', 'La te pequeña: un palito y una rayita.', <List<Offset>>[_l(<double>[50, 22, 50, 82]), _l(<double>[34, 42, 66, 42])]),
  ];

  static final List<TraceTemplate> digitos = <TraceTemplate>[
    TraceTemplate('0', 'cero', 'El cero: un óvalo, como un huevo.', <List<Offset>>[_arc(50, 50, 35, -90, -450, rx: 24)]),
    TraceTemplate('1', 'uno', 'El uno: una rayita y bajas derecho.', <List<Offset>>[_l(<double>[35, 32, 52, 15, 52, 85])]),
    TraceTemplate('2', 'dos', 'El dos: curva, baja y una línea abajo.', <List<Offset>>[_join(<List<Offset>>[_arc(50, 34, 20, -160, 40), _l(<double>[65, 47, 28, 85, 75, 85])])]),
    TraceTemplate('3', 'tres', 'El tres: dos pancitas.', <List<Offset>>[_join(<List<Offset>>[_arc(48, 33, 18, -150, 90), _arc(48, 68, 18, -90, 150)])]),
    TraceTemplate('4', 'cuatro', 'El cuatro: baja, cruza y un palito largo.', <List<Offset>>[_l(<double>[60, 15, 25, 60, 80, 60]), _l(<double>[60, 15, 60, 85])]),
    TraceTemplate('5', 'cinco', 'El cinco: una línea arriba, baja y la pancita.', <List<Offset>>[_join(<List<Offset>>[_l(<double>[72, 15, 32, 15, 29, 48]), _arc(50, 64, 21, -110, 150)])]),
    TraceTemplate('6', 'seis', 'El seis: baja curvando y cierra el círculo.', <List<Offset>>[_join(<List<Offset>>[_l(<double>[66, 15, 52, 30, 40, 50, 31, 64]), _arc(50, 64, 19, 180, -180)])]),
    TraceTemplate('7', 'siete', 'El siete: línea arriba y bajas de lado.', <List<Offset>>[_l(<double>[25, 15, 75, 15, 42, 85])]),
    TraceTemplate('8', 'ocho', 'El ocho: una bolita arriba y otra abajo.', <List<Offset>>[_arc(50, 33, 17, -90, -450, rx: 16), _arc(50, 67, 18, -90, 270, rx: 17)]),
    TraceTemplate('9', 'nueve', 'El nueve: un círculo arriba y bajas derecho.', <List<Offset>>[_join(<List<Offset>>[_arc(48, 35, 19, 0, -360, rx: 18), _l(<double>[66, 35, 62, 85])])]),
  ];

  /// Plantilla para un tramo y nivel ([zurdo]: versión para mano zurda).
  static TraceTemplate pick(Rng rng, AgeBand band, int level, {bool zurdo = false}) {
    List<TraceTemplate> pool;
    if (band == AgeBand.b3a4) {
      if (level == 1) {
        pool = preescritura;
      } else if (level == 2) {
        pool = mayusculas.where((TraceTemplate t) => 'AEIOU'.contains(t.id)).toList();
      } else if (level == 3) {
        pool = digitos.sublist(1, 6);
      } else {
        pool = <TraceTemplate>[...mayusculas.where((TraceTemplate t) => 'AEIOUL'.contains(t.id)), ...digitos.sublist(6)];
      }
    } else {
      if (level == 1) {
        pool = mayusculas.where((TraceTemplate t) => 'AEFHIKLMNTVWXYZ'.contains(t.id)).toList();
      } else if (level == 2) {
        pool = mayusculas.where((TraceTemplate t) => 'BCDGJOPQRSUÑ'.contains(t.id)).toList();
      } else if (level == 3) {
        pool = minusculas;
      } else {
        pool = digitos;
      }
    }
    final TraceTemplate t = rng.pick(pool);
    return zurdo ? t.paraZurdo() : t;
  }

  /// Tolerancia (en unidades de 100) según el tramo y el nivel.
  static double tolerance(AgeBand band, int level) {
    final double base = band == AgeBand.b3a4 ? 13 : 10;
    return base - (level - 1) * 1.2;
  }
}
