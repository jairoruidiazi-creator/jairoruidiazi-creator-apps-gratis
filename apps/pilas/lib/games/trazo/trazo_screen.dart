import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/rng.dart';
import '../../core/sfx.dart';
import '../../core/theme.dart';
import '../../engine/game_def.dart';
import '../../engine/round_engine.dart';
import '../shell/game_frame.dart';
import '../shell/widgets.dart';
import 'trazo_templates.dart';

/// Resultado de comparar lo dibujado con la plantilla.
class TraceScore {
  const TraceScore(this.coverage, this.precision);

  /// Fracción de la plantilla que quedó cubierta por el trazo del niño.
  final double coverage;

  /// Fracción del trazo del niño que cae cerca de la plantilla.
  final double precision;

  bool get good => coverage >= 0.72 && precision >= 0.55;

  /// Evalúa en coordenadas de la plantilla (0-100).
  static TraceScore evaluate(List<Offset> templatePts, List<List<Offset>> drawn, double tol) {
    final List<Offset> all = <Offset>[for (final List<Offset> s in drawn) ...s];
    if (all.isEmpty || templatePts.isEmpty) {
      return const TraceScore(0, 0);
    }
    final double tol2 = tol * tol;
    int covered = 0;
    for (final Offset t in templatePts) {
      for (final Offset d in all) {
        final double dx = d.dx - t.dx;
        final double dy = d.dy - t.dy;
        if (dx * dx + dy * dy <= tol2) {
          covered += 1;
          break;
        }
      }
    }
    int near = 0;
    final double tolPrec2 = (tol * 1.4) * (tol * 1.4);
    for (final Offset d in all) {
      for (final Offset t in templatePts) {
        final double dx = d.dx - t.dx;
        final double dy = d.dy - t.dy;
        if (dx * dx + dy * dy <= tolPrec2) {
          near += 1;
          break;
        }
      }
    }
    return TraceScore(covered / templatePts.length, near / all.length);
  }
}

/// Trazo de letras: seguir con el dedo la guía de pre-escritura, letras y
/// números. Se evalúa cuánto de la guía quedó cubierta, sin cronómetro.
class TrazoScreen extends StatefulWidget {
  const TrazoScreen({super.key, required this.launch});

  final GameLaunch launch;

  @override
  State<TrazoScreen> createState() => _TrazoScreenState();
}

class _TrazoScreenState extends State<TrazoScreen> {
  late final RoundEngine _engine;
  final Rng _rng = Rng();
  TraceTemplate? _template;
  List<Offset> _templatePts = <Offset>[];
  final List<List<Offset>> _strokes = <List<Offset>>[];
  bool _started = false;
  String _instruction = '';

  @override
  void initState() {
    super.initState();
    final Services s = AppScope.read(context);
    _engine = RoundEngine(app: s.state, voice: s.voice, sfx: s.sfx, launch: widget.launch, onNextRound: _newRound);
    _engine.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _newRound();
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _newRound() {
    if (!mounted) {
      return;
    }
    TraceTemplate t = TraceCatalog.pick(_rng, widget.launch.band, _engine.level);
    if (_template != null && t.id == _template!.id) {
      t = TraceCatalog.pick(_rng, widget.launch.band, _engine.level);
    }
    setState(() {
      _template = t;
      _templatePts = t.sample(3);
      _strokes.clear();
      _instruction = 'Sigue la línea con el dedo: ${t.nombre}.';
    });
    _engine.startRound();
    _engine.say('${t.dicho} Empieza en el punto verde y sigue la línea.');
  }

  void _clear() {
    if (_engine.busy) {
      return;
    }
    unawaited(AppScope.read(context).sfx.play(SfxId.tap));
    setState(() => _strokes.clear());
  }

  void _check() {
    final TraceTemplate? t = _template;
    if (t == null || _engine.busy) {
      return;
    }
    if (_strokes.isEmpty) {
      AppScope.read(context).voice.sayLater('Primero dibuja sobre la línea gris.');
      return;
    }
    final double tol = TraceCatalog.tolerance(widget.launch.band, _engine.level);
    final TraceScore score = TraceScore.evaluate(_templatePts, _strokes, tol);
    if (score.good) {
      _engine.correct(praise: '¡Muy bien! ${t.nombre}.');
      return;
    }
    final String hint = score.coverage < 0.72
        ? 'Falta un pedazo: pasa el dedo por toda la línea gris, desde el punto verde hasta el final.'
        : 'Te saliste un poco de la línea. Ve más despacio y sigue la guía.';
    _engine.wrong(hint: hint, explain: 'Así se hace ${t.nombre}: ${t.dicho} Mira la guía y vuelve a intentarlo en la siguiente.');
    if (_engine.attempts == 1) {
      // Tras la pista se limpia el lienzo para volver a intentar.
      setState(() => _strokes.clear());
    }
  }

  @override
  void dispose() {
    _engine.removeListener(_refresh);
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TraceTemplate? t = _template;
    return GameFrame(
      launch: widget.launch,
      engine: _engine,
      instruction: _instruction,
      actions: <Widget>[
        RoundIconButton(icon: Icons.refresh_rounded, tooltip: 'Borrar', onPressed: _clear),
      ],
      child: t == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: <Widget>[
                  if (t.ejemplo != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          EmojiImage(t.ejemplo!, size: 40),
                          const SizedBox(width: 10),
                          Text(t.dicho, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: PilasColors.tintaSuave)),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
                          final double side = c.maxWidth;
                          final double k = side / 100;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (DragStartDetails d) {
                              if (_engine.busy) {
                                return;
                              }
                              setState(() => _strokes.add(<Offset>[d.localPosition / k]));
                            },
                            onPanUpdate: (DragUpdateDetails d) {
                              if (_engine.busy || _strokes.isEmpty) {
                                return;
                              }
                              final Offset p = d.localPosition / k;
                              if (p.dx < -5 || p.dy < -5 || p.dx > 105 || p.dy > 105) {
                                return;
                              }
                              setState(() => _strokes.last.add(p));
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(Dim.radio),
                                border: Border.all(color: PilasColors.borde, width: 2),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(Dim.radio),
                                child: CustomPaint(
                                  painter: _TracePainter(template: t, strokes: _strokes, scale: k, guide: _engine.level < 4 || widget.launch.band.index == 0),
                                  size: Size(side, side),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _engine.busy ? null : _check,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Listo', style: TextStyle(fontSize: 20)),
                    style: FilledButton.styleFrom(minimumSize: const Size(180, 56)),
                  ),
                ],
              ),
            ),
    );
  }
}

class _TracePainter extends CustomPainter {
  _TracePainter({required this.template, required this.strokes, required this.scale, required this.guide});

  final TraceTemplate template;
  final List<List<Offset>> strokes;
  final double scale;
  final bool guide;

  @override
  void paint(Canvas canvas, Size size) {
    // Guía gris (gruesa) o punteada (niveles altos).
    final Paint guidePaint = Paint()
      ..color = const Color(0xFFD9D4C7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = scale * (guide ? 9 : 4)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final List<Offset> s in template.strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first * scale, scale * 4.5, Paint()..color = const Color(0xFFD9D4C7));
        continue;
      }
      final Path p = Path()..moveTo(s.first.dx * scale, s.first.dy * scale);
      for (int i = 1; i < s.length; i++) {
        p.lineTo(s[i].dx * scale, s[i].dy * scale);
      }
      canvas.drawPath(p, guidePaint);
    }
    // Puntos de inicio con número de orden y flecha de dirección.
    for (int i = 0; i < template.strokes.length; i++) {
      final List<Offset> s = template.strokes[i];
      final Offset start = s.first * scale;
      canvas.drawCircle(start, scale * 4, Paint()..color = PilasColors.verde);
      final TextPainter tp = TextPainter(
        text: TextSpan(text: '${i + 1}', style: TextStyle(fontSize: scale * 5, color: Colors.white, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, start - Offset(tp.width / 2, tp.height / 2));
      if (s.length > 1) {
        // Flecha pequeña en la dirección del trazo, un poco después del inicio.
        final Offset a = s[(s.length * 0.3).floor().clamp(1, s.length - 1).toInt()] * scale;
        final Offset prev = s[(s.length * 0.3).floor().clamp(1, s.length - 1).toInt() - 1] * scale;
        final Offset dir = (a - prev).distance == 0 ? const Offset(1, 0) : (a - prev) / (a - prev).distance;
        final Offset normal = Offset(-dir.dy, dir.dx);
        final Path arrow = Path()
          ..moveTo(a.dx + dir.dx * scale * 3, a.dy + dir.dy * scale * 3)
          ..lineTo(a.dx - dir.dx * scale * 1.5 + normal.dx * scale * 2.2, a.dy - dir.dy * scale * 1.5 + normal.dy * scale * 2.2)
          ..lineTo(a.dx - dir.dx * scale * 1.5 - normal.dx * scale * 2.2, a.dy - dir.dy * scale * 1.5 - normal.dy * scale * 2.2)
          ..close();
        canvas.drawPath(arrow, Paint()..color = PilasColors.naranja);
      }
    }
    // Trazo del niño.
    final Paint ink = Paint()
      ..color = PilasColors.azul
      ..style = PaintingStyle.stroke
      ..strokeWidth = scale * 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final List<Offset> s in strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first * scale, scale * 2.5, Paint()..color = PilasColors.azul);
        continue;
      }
      final Path p = Path()..moveTo(s.first.dx * scale, s.first.dy * scale);
      for (int i = 1; i < s.length; i++) {
        p.lineTo(s[i].dx * scale, s[i].dy * scale);
      }
      canvas.drawPath(p, ink);
    }
  }

  @override
  bool shouldRepaint(covariant _TracePainter old) => true;
}
