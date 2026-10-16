import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/rng.dart';
import '../../core/theme.dart';
import '../../model/age_band.dart';
import '../choice/choice_round.dart';
import '../choice/option_builders.dart';

/// Reloj analógico dibujado con código.
class ClockFace extends StatelessWidget {
  const ClockFace({super.key, required this.hour, required this.minute, this.size = 160, this.showMinuteNumbers = false});

  final int hour;
  final int minute;
  final double size;
  final bool showMinuteNumbers;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(size, size), painter: _ClockPainter(hour: hour, minute: minute, showMinuteNumbers: showMinuteNumbers));
  }
}

class _ClockPainter extends CustomPainter {
  const _ClockPainter({required this.hour, required this.minute, required this.showMinuteNumbers});

  final int hour;
  final int minute;
  final bool showMinuteNumbers;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final double r = size.width / 2;
    canvas.drawCircle(c, r - 2, Paint()..color = Colors.white);
    canvas.drawCircle(c, r - 2, Paint()..color = PilasColors.tinta..style = PaintingStyle.stroke..strokeWidth = 3);
    for (int i = 1; i <= 12; i++) {
      final double a = -math.pi / 2 + i * math.pi / 6;
      final Offset tick1 = c + Offset(math.cos(a), math.sin(a)) * (r - 8);
      final Offset tick2 = c + Offset(math.cos(a), math.sin(a)) * (r - 16);
      canvas.drawLine(tick1, tick2, Paint()..color = PilasColors.tinta..strokeWidth = 2.5);
      final TextPainter tp = TextPainter(
        text: TextSpan(text: '$i', style: TextStyle(fontSize: r * 0.19, fontWeight: FontWeight.w700, color: PilasColors.tinta, fontFamily: 'Lexend')),
        textDirection: TextDirection.ltr,
      )..layout();
      final Offset pos = c + Offset(math.cos(a), math.sin(a)) * (r - 30);
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
      if (showMinuteNumbers) {
        final TextPainter mp = TextPainter(
          text: TextSpan(text: '${(i % 12) * 5}', style: TextStyle(fontSize: r * 0.1, color: PilasColors.azul, fontFamily: 'Lexend')),
          textDirection: TextDirection.ltr,
        )..layout();
        final Offset mpos = c + Offset(math.cos(a), math.sin(a)) * (r + 10);
        mp.paint(canvas, mpos - Offset(mp.width / 2, mp.height / 2));
      }
    }
    for (int i = 0; i < 60; i++) {
      if (i % 5 == 0) {
        continue;
      }
      final double a = -math.pi / 2 + i * math.pi / 30;
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * (r - 6), c + Offset(math.cos(a), math.sin(a)) * (r - 11), Paint()..color = PilasColors.tintaSuave..strokeWidth = 1);
    }
    final double hourAngle = -math.pi / 2 + ((hour % 12) + minute / 60) * math.pi / 6;
    final double minAngle = -math.pi / 2 + minute * math.pi / 30;
    canvas.drawLine(c, c + Offset(math.cos(hourAngle), math.sin(hourAngle)) * (r * 0.5), Paint()..color = PilasColors.tinta..strokeWidth = 6..strokeCap = StrokeCap.round);
    canvas.drawLine(c, c + Offset(math.cos(minAngle), math.sin(minAngle)) * (r * 0.74), Paint()..color = PilasColors.azul..strokeWidth = 4..strokeCap = StrokeCap.round);
    canvas.drawCircle(c, 5, Paint()..color = PilasColors.tinta);
  }

  @override
  bool shouldRepaint(covariant _ClockPainter oldDelegate) => oldDelegate.hour != hour || oldDelegate.minute != minute || oldDelegate.showMinuteNumbers != showMinuteNumbers;
}

/// El reloj: leer horas en punto, medias, cuartos y minutos; relacionar con rutinas.
class RelojGenerator implements ChoiceGenerator {
  static const Map<int, String> rutinas = <int, String>{
    7: 'levantarse', 8: 'ir al colegio', 10: 'el descanso', 12: 'almorzar', 15: 'hacer tareas', 17: 'jugar', 19: 'cenar', 20: 'bañarse', 21: 'dormir',
  };

  @override
  ChoiceRound next(Rng rng, AgeBand band, int level) {
    List<int> minutos;
    switch (band) {
      case AgeBand.b3a4:
      case AgeBand.b5a6:
        minutos = level <= 2 ? <int>[0] : <int>[0, 30];
        break;
      case AgeBand.b7a8:
        minutos = level == 1 ? <int>[0, 30] : (level == 2 ? <int>[0, 15, 30, 45] : <int>[0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]);
        break;
      case AgeBand.b9a11:
        minutos = <int>[for (int m = 0; m < 60; m += 5) m];
        break;
    }
    final int tipo = band.index >= 2 && level >= 3 ? rng.nextInt(3) : (rng.chance(0.5) ? 0 : 1);
    final int hora = rng.range(1, 12);
    final int minuto = rng.pick(minutos);
    if (tipo == 2) {
      return _cuantoFalta(rng, hora, minuto);
    }
    if (tipo == 1) {
      return _elegirReloj(rng, hora, minuto, minutos);
    }
    return _leerHora(rng, hora, minuto, minutos);
  }

  static String nombreHora(int h, int m) {
    final String horaTxt = h == 1 ? 'la una' : 'las $h';
    if (m == 0) {
      return '$horaTxt en punto';
    }
    if (m == 30) {
      return '$horaTxt y media';
    }
    if (m == 15) {
      return '$horaTxt y cuarto';
    }
    if (m == 45) {
      final int sig = h == 12 ? 1 : h + 1;
      return '${sig == 1 ? 'la una' : 'las $sig'} menos cuarto';
    }
    return '$horaTxt y $m';
  }

  static String digital(int h, int m) => '$h:${m.toString().padLeft(2, '0')}';

  ChoiceRound _leerHora(Rng rng, int hora, int minuto, List<int> minutos) {
    final Set<String> ids = <String>{'${hora}_$minuto'};
    // Las opciones se muestran en formato digital: los de 5 y 6 años ya
    // reconocen los numerales aunque no lean palabras.
    final List<ChoiceOption> options = <ChoiceOption>[Opt.text('${hora}_$minuto', digital(hora, minuto), fontSize: 34, label: nombreHora(hora, minuto))];
    int guard = 0;
    while (options.length < 3 && guard < 50) {
      guard += 1;
      final int h2 = rng.chance(0.5) ? hora : rng.range(1, 12);
      final int m2 = rng.pick(minutos);
      final String id = '${h2}_$m2';
      if (ids.contains(id)) {
        continue;
      }
      ids.add(id);
      options.add(Opt.text(id, digital(h2, m2), fontSize: 34, label: nombreHora(h2, m2)));
    }
    rng.shuffle(options);
    final String rutina = rutinas[hora] ?? rutinas[hora + 12] ?? '';
    return ChoiceRound(
      instruction: '¿Qué hora marca el reloj?',
      prompt: (BuildContext context) => BigPrompt(child: ClockFace(hour: hora, minute: minuto, showMinuteNumbers: minuto % 15 != 0)),
      options: options,
      correctId: '${hora}_$minuto',
      hint: minuto == 0 ? 'La manecilla corta señala la hora y la larga está en el 12: en punto.' : 'La manecilla corta dice la hora y la larga los minutos: cada número son 5 minutos.',
      explain: 'Son ${nombreHora(hora, minuto)}.${rutina.isEmpty ? '' : ' A esa hora suele ser hora de $rutina.'}',
      praise: 'Son ${nombreHora(hora, minuto)}.',
    );
  }

  ChoiceRound _elegirReloj(Rng rng, int hora, int minuto, List<int> minutos) {
    final Set<String> ids = <String>{'${hora}_$minuto'};
    final List<ChoiceOption> options = <ChoiceOption>[_relojOption(hora, minuto)];
    int guard = 0;
    while (options.length < 3 && guard < 50) {
      guard += 1;
      final int h2 = rng.chance(0.5) ? hora : rng.range(1, 12);
      final int m2 = rng.pick(minutos);
      final String id = '${h2}_$m2';
      if (ids.contains(id)) {
        continue;
      }
      ids.add(id);
      options.add(_relojOption(h2, m2));
    }
    rng.shuffle(options);
    final String rutina = rutinas[hora] ?? rutinas[hora + 12] ?? '';
    return ChoiceRound(
      instruction: rutina.isEmpty ? '¿Cuál reloj marca ${nombreHora(hora, minuto)}?' : 'Es hora de $rutina: ${nombreHora(hora, minuto)}. ¿Cuál reloj lo marca?',
      options: options,
      correctId: '${hora}_$minuto',
      hint: 'Busca primero la manecilla corta en el $hora y luego mira la larga.',
      explain: 'Este reloj marca ${nombreHora(hora, minuto)}.',
      optionSize: 120,
    );
  }

  ChoiceOption _relojOption(int h, int m) {
    return ChoiceOption(
      id: '${h}_$m',
      label: nombreHora(h, m),
      build: (BuildContext context, double size) => ClockFace(hour: h, minute: m, size: size),
    );
  }

  ChoiceRound _cuantoFalta(Rng rng, int hora, int minuto) {
    final int faltan = rng.pick(<int>[5, 10, 15, 20, 25, 30, 45]);
    int m2 = minuto + faltan;
    int h2 = hora;
    if (m2 >= 60) {
      m2 -= 60;
      h2 = hora == 12 ? 1 : hora + 1;
    }
    final Set<int> opciones = <int>{faltan};
    while (opciones.length < 3) {
      final int d = rng.pick(<int>[5, 10, 15, 20, 25, 30, 45, 60]);
      opciones.add(d);
    }
    final List<ChoiceOption> options = <ChoiceOption>[for (final int o in opciones) Opt.text('n$o', '$o min', fontSize: 30, label: '$o minutos')];
    rng.shuffle(options);
    return ChoiceRound(
      instruction: 'Son ${nombreHora(hora, minuto)}. ¿Cuántos minutos faltan para ${nombreHora(h2, m2)}?',
      prompt: (BuildContext context) => BigPrompt(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClockFace(hour: hora, minute: minuto, size: 120, showMinuteNumbers: true),
            const SizedBox(width: 16),
            const Icon(Icons.arrow_forward_rounded, size: 36, color: PilasColors.tinta),
            const SizedBox(width: 16),
            ClockFace(hour: h2, minute: m2, size: 120, showMinuteNumbers: true),
          ],
        ),
      ),
      options: options,
      correctId: 'n$faltan',
      hint: 'Cuenta de 5 en 5 desde la manecilla larga hasta donde debe llegar.',
      explain: 'De ${nombreHora(hora, minuto)} a ${nombreHora(h2, m2)} faltan $faltan minutos.',
    );
  }
}
