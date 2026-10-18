import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/es.dart';
import '../../core/rng.dart';
import '../../core/theme.dart';
import '../../model/age_band.dart';
import '../choice/choice_round.dart';
import '../choice/option_builders.dart';

/// Reloj analógico dibujado con código. Con [showMinuteNumbers], los minutos
/// de cinco en cinco van en un anillo dentro de la esfera, en azul, y las
/// horas más adentro.
class ClockFace extends StatelessWidget {
  const ClockFace({super.key, required this.hour, required this.minute, this.size = 180, this.showMinuteNumbers = false});

  final int hour;
  final int minute;
  final double size;
  final bool showMinuteNumbers;

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    return Semantics(
      label: 'Reloj que marca ${RelojGenerator.nombreHora(hour, minute)}',
      excludeSemantics: true,
      child: CustomPaint(
        size: Size(size, size),
        painter: _ClockPainter(hour: hour, minute: minute, showMinuteNumbers: showMinuteNumbers, ink: pal.tinta, soft: pal.tintaSuave, accent: pal.acento, paper: pal.tarjeta),
      ),
    );
  }
}

class _ClockPainter extends CustomPainter {
  const _ClockPainter({required this.hour, required this.minute, required this.showMinuteNumbers, required this.ink, required this.soft, required this.accent, required this.paper});

  final int hour;
  final int minute;
  final bool showMinuteNumbers;
  final Color ink;
  final Color soft;
  final Color accent;
  final Color paper;

  void _text(Canvas canvas, String t, Offset at, double fontSize, Color color, FontWeight weight) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontSize: fontSize, fontWeight: weight, color: color, fontFamily: 'Lexend')),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final double r = size.width / 2 - 2;
    canvas.drawCircle(c, r, Paint()..color = paper);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.5, r * 0.035),
    );
    // Anillo de minutos (dentro de la esfera) y marcas.
    final double tickOuter = showMinuteNumbers ? r * 0.74 : r * 0.94;
    for (int i = 0; i < 60; i++) {
      final double a = -math.pi / 2 + i * math.pi / 30;
      final Offset dir = Offset(math.cos(a), math.sin(a));
      final bool hora = i % 5 == 0;
      canvas.drawLine(
        c + dir * tickOuter,
        c + dir * (tickOuter - (hora ? r * 0.09 : r * 0.045)),
        Paint()
          ..color = hora ? ink : soft
          ..strokeWidth = hora ? math.max(2, r * 0.025) : 1,
      );
      if (showMinuteNumbers && hora) {
        _text(canvas, '$i', c + dir * (r * 0.86), r * 0.12, accent, FontWeight.w700);
      }
    }
    final double hourRadius = showMinuteNumbers ? r * 0.5 : r * 0.7;
    for (int i = 1; i <= 12; i++) {
      final double a = -math.pi / 2 + i * math.pi / 6;
      _text(canvas, '$i', c + Offset(math.cos(a), math.sin(a)) * hourRadius, r * (showMinuteNumbers ? 0.15 : 0.19), ink, FontWeight.w700);
    }
    final double hourAngle = -math.pi / 2 + ((hour % 12) + minute / 60) * math.pi / 6;
    final double minAngle = -math.pi / 2 + minute * math.pi / 30;
    canvas.drawLine(
      c,
      c + Offset(math.cos(hourAngle), math.sin(hourAngle)) * (r * 0.42),
      Paint()
        ..color = ink
        ..strokeWidth = math.max(5, r * 0.07)
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      c,
      c + Offset(math.cos(minAngle), math.sin(minAngle)) * (r * (showMinuteNumbers ? 0.7 : 0.78)),
      Paint()
        ..color = accent
        ..strokeWidth = math.max(3.5, r * 0.045)
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(c, math.max(4, r * 0.05), Paint()..color = ink);
  }

  @override
  bool shouldRepaint(covariant _ClockPainter oldDelegate) =>
      oldDelegate.hour != hour || oldDelegate.minute != minute || oldDelegate.showMinuteNumbers != showMinuteNumbers || oldDelegate.ink != ink || oldDelegate.accent != accent;
}

/// Una rutina asociada a una hora del día.
class RutinaHora {
  const RutinaHora(this.hora, this.frase);

  /// Hora en formato de 24 horas.
  final int hora;

  /// Qué se hace a esa hora, en infinitivo: "levantarse", "almorzar".
  final String frase;
}

/// El reloj: leer horas en punto, medias, cuartos y minutos; calcular cuánto
/// falta y a qué hora termina una actividad.
class RelojGenerator implements ChoiceGenerator {
  static const List<RutinaHora> rutinas = <RutinaHora>[
    RutinaHora(7, 'levantarse'),
    RutinaHora(8, 'ir al colegio'),
    RutinaHora(10, 'salir al descanso'),
    RutinaHora(12, 'almorzar'),
    RutinaHora(15, 'hacer las tareas'),
    RutinaHora(17, 'jugar'),
    RutinaHora(19, 'comer'),
    RutinaHora(20, 'bañarse'),
    RutinaHora(21, 'dormir'),
  ];

  /// Actividades con su duración en minutos (9 a 11 años).
  static const List<List<Object>> actividades = <List<Object>>[
    <Object>['La película', 'dura', 90],
    <Object>['El partido de fútbol', 'dura', 50],
    <Object>['La clase de música', 'dura', 45],
    <Object>['El viaje en bus', 'dura', 35],
    <Object>['La torta', 'necesita', 40],
    <Object>['La práctica de natación', 'dura', 55],
  ];

  @override
  ChoiceRound next(Rng rng, AgeBand band, int level) {
    final List<int> cincos = <int>[for (int m = 0; m < 60; m += 5) m];
    switch (band) {
      case AgeBand.b3a4:
      case AgeBand.b5a6:
        final List<int> minutos = level <= 2 ? <int>[0] : <int>[0, 30];
        return rng.chance(0.5) ? leerHora(rng, rng.range(1, 12), rng.pick(minutos), minutos) : elegirReloj(rng, rng.range(1, 12), rng.pick(minutos), minutos);
      case AgeBand.b7a8:
        final List<int> minutos = level == 1 ? <int>[0, 30] : (level == 2 ? <int>[0, 15, 30, 45] : cincos);
        if (level == 4 && rng.chance(0.5)) {
          return cuantoFalta(rng, <int>[5, 10, 15, 20, 30]);
        }
        return rng.chance(0.5) ? leerHora(rng, rng.range(1, 12), rng.pick(minutos), minutos) : elegirReloj(rng, rng.range(1, 12), rng.pick(minutos), minutos);
      case AgeBand.b9a11:
        if (level == 1) {
          return rng.chance(0.5) ? leerHora(rng, rng.range(1, 12), rng.pick(cincos), cincos) : elegirReloj(rng, rng.range(1, 12), rng.pick(cincos), cincos);
        }
        if (level == 2) {
          return cuantoFalta(rng, <int>[5, 10, 15, 20, 25, 30]);
        }
        if (level == 3) {
          return cuantoFalta(rng, <int>[15, 20, 25, 30, 35, 40, 45, 50]);
        }
        return aQueHoraTermina(rng);
    }
  }

  /// "las tres en punto", "la una y media", "las cinco menos cuarto",
  /// "las siete y veinticinco".
  static String nombreHora(int h, int m) {
    String horaTxt(int x) => x == 1 ? 'la una' : 'las ${Es.numero(x, femenino: true)}';
    if (m == 0) {
      return '${horaTxt(h)} en punto';
    }
    if (m == 30) {
      return '${horaTxt(h)} y media';
    }
    if (m == 15) {
      return '${horaTxt(h)} y cuarto';
    }
    if (m == 45) {
      final int sig = h == 12 ? 1 : h + 1;
      return '${horaTxt(sig)} menos cuarto';
    }
    return '${horaTxt(h)} y ${Es.numero(m)}';
  }

  /// "Es la una en punto", "Son las tres y veinte" (con la una, el verbo va
  /// en singular).
  static String esLaHora(int h, int m) {
    final int mostrada = m == 45 ? (h == 12 ? 1 : h + 1) : h;
    return '${mostrada == 1 ? 'Es' : 'Son'} ${nombreHora(h, m)}';
  }

  static String digital(int h, int m) => '$h:${m.toString().padLeft(2, '0')}';

  static String? rutinaDe(int h) {
    for (final RutinaHora r in rutinas) {
      if (r.hora == h || r.hora == h + 12) {
        return r.frase;
      }
    }
    return null;
  }

  /// Opciones de hora distintas entre sí: la correcta y dos que confunden
  /// (las manecillas cambiadas o la hora de al lado).
  static List<List<int>> _horasParecidas(Rng rng, int hora, int minuto, List<int> minutos) {
    final List<List<int>> out = <List<int>>[<int>[hora, minuto]];
    final Set<String> ids = <String>{'${hora}_$minuto'};
    void add(int h, int m) {
      final int hh = ((h - 1) % 12 + 12) % 12 + 1;
      if (minutos.contains(m) && ids.add('${hh}_$m')) {
        out.add(<int>[hh, m]);
      }
    }

    // Manecillas cambiadas: la corta leída como larga.
    if (minuto % 5 == 0) {
      add(minuto == 0 ? 12 : minuto ~/ 5, (hora % 12) * 5);
    }
    add(hora + 1, minuto);
    add(hora - 1, minuto);
    int guard = 0;
    while (out.length < 3 && guard < 60) {
      guard += 1;
      add(rng.chance(0.5) ? hora : rng.range(1, 12), rng.pick(minutos));
    }
    while (out.length < 3) {
      add(rng.range(1, 12), minuto);
    }
    return out.take(3).toList();
  }

  ChoiceRound leerHora(Rng rng, int hora, int minuto, List<int> minutos) {
    final List<ChoiceOption> options = <ChoiceOption>[
      for (final List<int> hm in _horasParecidas(rng, hora, minuto, minutos)) Opt.text('${hm[0]}_${hm[1]}', digital(hm[0], hm[1]), fontSize: 34, label: nombreHora(hm[0], hm[1])),
    ];
    rng.shuffle(options);
    final String? rutina = rutinaDe(hora);
    return ChoiceRound(
      instruction: '¿Qué hora marca el reloj?',
      prompt: (BuildContext context) => BigPrompt(child: ClockFace(hour: hora, minute: minuto, size: 200, showMinuteNumbers: minuto % 30 != 0)),
      options: options,
      correctId: '${hora}_$minuto',
      hint: minuto == 0 ? 'La manecilla corta señala la hora. Si la larga está en el 12, es en punto.' : 'La manecilla corta dice la hora y la larga los minutos: cada número del reloj son cinco minutos.',
      explain: '${esLaHora(hora, minuto)}${rutina == null || minuto != 0 ? '' : ': puede ser la hora de $rutina'}.',
      praise: '${esLaHora(hora, minuto)}.',
      readOptionsAloud: true,
    );
  }

  ChoiceRound elegirReloj(Rng rng, int hora, int minuto, List<int> minutos) {
    final List<ChoiceOption> options = <ChoiceOption>[for (final List<int> hm in _horasParecidas(rng, hora, minuto, minutos)) _relojOption(hm[0], hm[1])];
    rng.shuffle(options);
    final String? rutina = minuto == 0 ? rutinaDe(hora) : null;
    final String antes = rutina == null ? '' : 'Es la hora de $rutina. ';
    return ChoiceRound(
      instruction: '$antes¿Cuál reloj marca ${nombreHora(hora, minuto)}?',
      options: options,
      correctId: '${hora}_$minuto',
      hint: 'Busca primero dónde está la manecilla corta y luego mira la larga.',
      explain: 'Este reloj marca ${nombreHora(hora, minuto)}.',
      optionSize: 140,
    );
  }

  ChoiceOption _relojOption(int h, int m) {
    return ChoiceOption(
      id: '${h}_$m',
      label: nombreHora(h, m),
      build: (BuildContext context, double size) => ClockFace(hour: h, minute: m, size: size),
    );
  }

  /// "Son las tres y diez. ¿Cuántos minutos faltan para las tres y media?"
  ChoiceRound cuantoFalta(Rng rng, List<int> saltos) {
    final int hora = rng.range(1, 12);
    final int minuto = rng.pick(<int>[for (int m = 0; m < 60; m += 5) m]);
    final int faltan = rng.pick(saltos);
    int m2 = minuto + faltan;
    int h2 = hora;
    if (m2 >= 60) {
      m2 -= 60;
      h2 = hora == 12 ? 1 : hora + 1;
    }
    final Set<int> opciones = <int>{faltan};
    for (final int d in <int>[faltan + 5, faltan - 5, faltan + 10, faltan - 10, 60 - faltan]) {
      if (opciones.length < 3 && d > 0 && d < 60) {
        opciones.add(d);
      }
    }
    final List<ChoiceOption> options = <ChoiceOption>[for (final int o in opciones) Opt.text('n$o', '$o min', fontSize: 30, label: '${Es.numero(o)} minutos')];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: '${esLaHora(hora, minuto)}. ¿Cuántos minutos faltan para ${nombreHora(h2, m2)}?',
      prompt: (BuildContext context) => BigPrompt(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClockFace(hour: hora, minute: minuto, size: 150, showMinuteNumbers: true),
            const SizedBox(width: 12),
            Icon(Icons.arrow_forward_rounded, size: 36, color: PilasPalette.of(context).tinta),
            const SizedBox(width: 12),
            ClockFace(hour: h2, minute: m2, size: 150, showMinuteNumbers: true),
          ],
        ),
      ),
      options: options,
      correctId: 'n$faltan',
      hint: 'Cuenta de cinco en cinco desde donde está la manecilla larga hasta donde tiene que llegar.',
      explain: 'De ${nombreHora(hora, minuto)} a ${nombreHora(h2, m2)} faltan ${Es.numero(faltan)} minutos.',
    );
  }

  /// "La película empieza a las cuatro y veinte y dura noventa minutos.
  /// ¿A qué hora termina?"
  ChoiceRound aQueHoraTermina(Rng rng) {
    final List<Object> act = rng.pick(actividades);
    final String que = act[0] as String;
    final String verbo = act[1] as String;
    final int dura = act[2] as int;
    final int hora = rng.range(1, 11);
    final int minuto = rng.pick(<int>[for (int m = 0; m < 60; m += 5) m]);
    final int total = hora * 60 + minuto + dura;
    final int h2 = ((total ~/ 60) - 1) % 12 + 1;
    final int m2 = total % 60;
    final List<List<int>> opciones = <List<int>>[<int>[h2, m2]];
    final Set<String> ids = <String>{'${h2}_$m2'};
    for (final int delta in <int>[-10, 10, -60, 60, -30, 30]) {
      final int t = total + delta;
      final int hh = ((t ~/ 60) - 1) % 12 + 1;
      final int mm = t % 60;
      if (opciones.length < 3 && ids.add('${hh}_$mm')) {
        opciones.add(<int>[hh, mm]);
      }
    }
    final List<ChoiceOption> options = <ChoiceOption>[for (final List<int> hm in opciones) Opt.text('${hm[0]}_${hm[1]}', digital(hm[0], hm[1]), fontSize: 34, label: nombreHora(hm[0], hm[1]))];
    rng.shuffle(options);
    final String duracion = dura >= 60 ? '${Es.numero(dura)} minutos, es decir, una hora y ${Es.numero(dura - 60)} minutos' : '${Es.numero(dura)} minutos';
    final String accion = verbo == 'necesita' ? '$que entra al horno a ${nombreHora(hora, minuto)} y necesita $duracion' : '$que empieza a ${nombreHora(hora, minuto)} y $verbo $duracion';
    return ChoiceRound(
      instruction: '$accion. ¿A qué hora ${verbo == 'necesita' ? 'sale' : 'termina'}?',
      prompt: (BuildContext context) => BigPrompt(child: ClockFace(hour: hora, minute: minuto, size: 200, showMinuteNumbers: true), caption: '+ $dura min'),
      options: options,
      correctId: '${h2}_$m2',
      hint: 'Suma primero las horas completas y después los minutos que faltan. Si pasas de sesenta minutos, cambia la hora.',
      explain: 'Si a ${nombreHora(hora, minuto)} le sumas ${Es.numero(dura)} minutos, llegas a ${nombreHora(h2, m2)}.',
      readOptionsAloud: true,
    );
  }
}
