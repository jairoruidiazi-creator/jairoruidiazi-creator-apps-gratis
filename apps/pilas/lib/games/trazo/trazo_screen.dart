import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/es.dart';
import '../../core/rng.dart';
import '../../core/sfx.dart';
import '../../core/theme.dart';
import '../../engine/game_def.dart';
import '../../engine/round_engine.dart';
import '../shell/game_frame.dart';
import '../shell/widgets.dart';
import 'trazo_templates.dart';

/// Qué faltó en un trazo, para elegir la pista.
enum TraceProblem { none, empty, coverage, precision, order, direction }

/// Resultado de comparar lo dibujado con la plantilla: cuánto de la guía se
/// cubrió, cuánto del trazo cae sobre la guía, y si se respetaron el orden de
/// las líneas y su dirección.
class TraceScore {
  const TraceScore(this.coverage, this.precision, {this.orderOk = true, this.directionOk = true});

  /// Fracción de la plantilla que quedó cubierta por el trazo del niño.
  final double coverage;

  /// Fracción del trazo del niño que cae cerca de la plantilla.
  final double precision;

  /// Las líneas se empezaron en el orden de los números.
  final bool orderOk;

  /// Cada línea se empezó por su punto de inicio (y los círculos giran hacia
  /// el mismo lado que la flecha).
  final bool directionOk;

  static const double minCoverage = 0.72;
  static const double minPrecision = 0.55;

  bool get good => problem == TraceProblem.none;

  TraceProblem get problem {
    if (coverage < minCoverage) {
      return coverage == 0 && precision == 0 ? TraceProblem.empty : TraceProblem.coverage;
    }
    if (precision < minPrecision) {
      return TraceProblem.precision;
    }
    if (!orderOk) {
      return TraceProblem.order;
    }
    if (!directionOk) {
      return TraceProblem.direction;
    }
    return TraceProblem.none;
  }

  /// Evalúa en coordenadas de la plantilla (0-100) con tolerancia [tol].
  static TraceScore evaluate(TraceTemplate t, List<List<Offset>> drawn, double tol) {
    final List<List<Offset>> tpl = <List<Offset>>[for (int k = 0; k < t.strokes.length; k++) t.sampleStroke(k, 3)];
    final List<Offset> tplAll = <Offset>[for (final List<Offset> s in tpl) ...s];
    final List<Offset> all = <Offset>[for (final List<Offset> s in drawn) ...s];
    if (all.isEmpty || tplAll.isEmpty) {
      return const TraceScore(0, 0);
    }
    final double tol2 = tol * tol;
    final double near2 = (tol * 1.4) * (tol * 1.4);
    int covered = 0;
    for (final Offset p in tplAll) {
      if (all.any((Offset d) => (d - p).distanceSquared <= tol2)) {
        covered += 1;
      }
    }
    int near = 0;
    for (final Offset d in all) {
      if (tplAll.any((Offset p) => (d - p).distanceSquared <= near2)) {
        near += 1;
      }
    }

    // A qué línea de la plantilla corresponde cada trazo del niño (-1: a
    // ninguna, por ejemplo un garabato suelto).
    final List<int> assigned = <int>[];
    for (final List<Offset> s in drawn) {
      final List<int> votes = List<int>.filled(tpl.length, 0);
      for (final Offset d in s) {
        int best = -1;
        double bestD = near2;
        for (int k = 0; k < tpl.length; k++) {
          for (final Offset p in tpl[k]) {
            final double dd = (d - p).distanceSquared;
            if (dd <= bestD) {
              bestD = dd;
              best = k;
            }
          }
        }
        if (best >= 0) {
          votes[best] += 1;
        }
      }
      int k = -1;
      for (int i = 0; i < votes.length; i++) {
        if (votes[i] > 0 && (k < 0 || votes[i] > votes[k])) {
          k = i;
        }
      }
      assigned.add(k >= 0 && votes[k] >= s.length * 0.4 ? k : -1);
    }

    // Orden: la primera vez que se toca cada línea va en orden creciente.
    bool orderOk = true;
    int last = -1;
    final Set<int> seen = <int>{};
    for (final int k in assigned) {
      if (k < 0 || seen.contains(k)) {
        continue;
      }
      if (k < last) {
        orderOk = false;
      }
      seen.add(k);
      last = math.max(last, k);
    }

    // Dirección: el primer trazo de cada línea empieza más cerca de su
    // inicio que de su final; en las líneas cerradas (círculos), gira hacia
    // el mismo lado que la plantilla.
    bool directionOk = true;
    for (int k = 0; k < tpl.length; k++) {
      final int idx = assigned.indexOf(k);
      if (idx < 0 || t.strokes[k].length < 2) {
        continue;
      }
      final List<Offset> s = drawn[idx];
      if (s.length < 3) {
        continue;
      }
      if (t.closed(k)) {
        final double want = _area(t.strokes[k]);
        final double got = _area(s);
        if (got.abs() >= want.abs() * 0.15 && got.sign != want.sign) {
          directionOk = false;
        }
      } else {
        final Offset start = t.strokes[k].first;
        final Offset end = t.strokes[k].last;
        if ((s.first - start).distance > (s.first - end).distance) {
          directionOk = false;
        }
      }
    }
    return TraceScore(covered / tplAll.length, near / all.length, orderOk: orderOk, directionOk: directionOk);
  }

  /// Área con signo (fórmula del cordón): el signo dice hacia dónde gira.
  static double _area(List<Offset> pts) {
    double a = 0;
    for (int i = 0; i < pts.length; i++) {
      final Offset p = pts[i];
      final Offset q = pts[(i + 1) % pts.length];
      a += p.dx * q.dy - q.dx * p.dy;
    }
    return a / 2;
  }
}

/// Trazo de letras: seguir con el dedo la guía de pre-escritura, letras y
/// números, empezando en el punto 1 y siguiendo las flechas. Se evalúa cuánto
/// de la guía quedó cubierta, el orden de las líneas y su dirección, sin
/// cronómetro. En modo zurdo, los botones van a la izquierda y las líneas
/// acostadas de pre-escritura empiezan por la derecha.
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
  final List<List<Offset>> _strokes = <List<Offset>>[];
  bool _started = false;
  String _instruction = '';

  bool get _zurdo => widget.launch.profile.leftHanded;

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
    TraceTemplate t = TraceCatalog.pick(_rng, widget.launch.band, _engine.level, zurdo: _zurdo);
    if (_template != null && t.id == _template!.id) {
      t = TraceCatalog.pick(_rng, widget.launch.band, _engine.level, zurdo: _zurdo);
    }
    setState(() {
      _template = t;
      _strokes.clear();
      final int n = t.strokes.length;
      _instruction = n == 1
          ? '${t.dicho} Empieza en el punto 1 y sigue la flecha.'
          : '${t.dicho} Empieza en el punto 1, sigue las flechas y después haz ${n == 2 ? 'la línea 2' : 'las líneas ${Es.listaY(<String>[for (int i = 2; i <= n; i++) '$i'])}'}.';
    });
    _engine.startRound();
    _engine.say(_instruction);
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
      AppScope.read(context).voice.sayLater('Primero pasa el dedo por la línea gris.');
      return;
    }
    final double tol = TraceCatalog.tolerance(widget.launch.band, _engine.level);
    final TraceScore score = TraceScore.evaluate(t, _strokes, tol);
    if (score.good) {
      unawaited(_engine.correct(praise: '¡Muy bien! ${t.nombre}.'));
      return;
    }
    String hint;
    switch (score.problem) {
      case TraceProblem.order:
        hint = 'Sigue el orden de los números: primero la línea 1 y después la 2.';
        break;
      case TraceProblem.direction:
        hint = 'Empieza en el punto 1 y ve hacia donde apunta la flecha.';
        break;
      case TraceProblem.precision:
        hint = 'Te saliste un poco de la línea. Ve más despacio y sigue la guía.';
        break;
      case TraceProblem.coverage:
      case TraceProblem.empty:
      case TraceProblem.none:
        hint = 'Falta un pedazo: pasa el dedo por toda la línea gris, desde el punto 1 hasta el final.';
        break;
    }
    unawaited(_engine.wrong(hint: hint, explain: 'Así se hace ${t.nombre}: ${t.dicho} Mira los números y las flechas, y en la siguiente lo intentas otra vez.'));
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
      child: t == null ? const SizedBox.shrink() : LayoutBuilder(builder: (BuildContext context, BoxConstraints c) => _layout(t, c)),
    );
  }

  Widget _layout(TraceTemplate t, BoxConstraints c) {
    final PilasPalette pal = PilasPalette.of(context);
    final Widget listo = FilledButton.icon(
      key: const ValueKey<String>('trazo-listo'),
      onPressed: _engine.busy ? null : _check,
      icon: const Icon(Icons.check_rounded),
      label: const Text('Listo'),
      style: FilledButton.styleFrom(minimumSize: const Size(140, 56)),
    );
    final Widget borrar = RoundIconButton(key: const ValueKey<String>('trazo-borrar'), icon: Icons.refresh_rounded, tooltip: 'Borrar y empezar otra vez', onPressed: _clear);
    final Widget? ejemplo = t.ejemplo == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              EmojiImage(t.ejemplo!, size: 40, semanticsLabel: t.dicho),
              const SizedBox(width: 10),
              Flexible(child: Text(t.nombre, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: pal.tinta))),
            ],
          );
    final Widget canvas = LayoutBuilder(builder: (BuildContext context, BoxConstraints k) {
      final double side = math.min(k.maxWidth, k.maxHeight);
      return Center(child: SizedBox(width: side, height: side, child: _canvas(t, side, pal)));
    });
    if (c.maxWidth > c.maxHeight * 1.1) {
      // Acostado: el lienzo a un lado y los botones al otro (a la izquierda
      // en modo zurdo).
      final Widget side = SizedBox(
        width: math.min(220, c.maxWidth * 0.36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (ejemplo != null) ...<Widget>[FittedBox(fit: BoxFit.scaleDown, child: ejemplo), const SizedBox(height: 12)],
            borrar,
            const SizedBox(height: 12),
            FittedBox(fit: BoxFit.scaleDown, child: listo),
          ],
        ),
      );
      final List<Widget> items = <Widget>[Expanded(child: canvas), const SizedBox(width: 12), side];
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: _zurdo ? items.reversed.toList() : items),
      );
    }
    final List<Widget> bottom = <Widget>[borrar, const SizedBox(width: 16), listo];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: <Widget>[
          if (ejemplo != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: ejemplo),
          Expanded(child: canvas),
          const SizedBox(height: 10),
          // Con la letra al doble, los dos botones se achican antes que salirse.
          FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: _zurdo ? bottom.reversed.toList() : bottom)),
        ],
      ),
    );
  }

  Widget _canvas(TraceTemplate t, double side, PilasPalette pal) {
    final double k = side / 100;
    return Semantics(
      label: 'Zona para trazar: ${t.nombre}',
      child: GestureDetector(
        key: const ValueKey<String>('trazo-lienzo'),
        behavior: HitTestBehavior.opaque,
        // Un toque suelto también cuenta (el punto de la i).
        onTapUp: (TapUpDetails d) {
          if (_engine.busy) {
            return;
          }
          setState(() => _strokes.add(<Offset>[d.localPosition / k]));
        },
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
            color: pal.tarjeta,
            borderRadius: BorderRadius.circular(Dim.radio),
            border: Border.all(color: pal.altoContraste ? pal.bordeFuerte : pal.borde, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Dim.radio),
            child: CustomPaint(
              painter: _TracePainter(
                template: t,
                strokes: _strokes,
                scale: k,
                thickGuide: _engine.level < 4 || widget.launch.band.index == 0,
                guide: pal.guia,
                start: pal.correcto,
                onStart: pal.sobreAcento,
                arrow: pal.acento,
                ink: pal.acento,
              ),
              size: Size(side, side),
            ),
          ),
        ),
      ),
    );
  }
}

class _TracePainter extends CustomPainter {
  _TracePainter({
    required this.template,
    required this.strokes,
    required this.scale,
    required this.thickGuide,
    required this.guide,
    required this.start,
    required this.onStart,
    required this.arrow,
    required this.ink,
  });

  final TraceTemplate template;
  final List<List<Offset>> strokes;
  final double scale;
  final bool thickGuide;
  final Color guide;
  final Color start;
  final Color onStart;
  final Color arrow;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    // Guía gruesa (o delgada en los niveles altos de 5 a 6 años).
    final Paint guidePaint = Paint()
      ..color = guide
      ..style = PaintingStyle.stroke
      ..strokeWidth = scale * (thickGuide ? 9 : 4)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final List<Offset> s in template.strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first * scale, scale * 4.5, Paint()..color = guide);
        continue;
      }
      final Path p = Path()..moveTo(s.first.dx * scale, s.first.dy * scale);
      for (int i = 1; i < s.length; i++) {
        p.lineTo(s[i].dx * scale, s[i].dy * scale);
      }
      canvas.drawPath(p, guidePaint);
    }
    // Flechas de dirección a lo largo de cada línea.
    for (final List<Offset> s in template.strokes) {
      if (s.length < 2) {
        continue;
      }
      for (final double f in <double>[0.3, 0.7]) {
        final int i = (s.length * f).floor().clamp(1, s.length - 1).toInt();
        final Offset a = s[i] * scale;
        final Offset prev = s[i - 1] * scale;
        final double len = (a - prev).distance;
        final Offset dir = len == 0 ? const Offset(1, 0) : (a - prev) / len;
        final Offset normal = Offset(-dir.dy, dir.dx);
        final Path head = Path()
          ..moveTo(a.dx + dir.dx * scale * 3.2, a.dy + dir.dy * scale * 3.2)
          ..lineTo(a.dx - dir.dx * scale * 1.6 + normal.dx * scale * 2.6, a.dy - dir.dy * scale * 1.6 + normal.dy * scale * 2.6)
          ..lineTo(a.dx - dir.dx * scale * 1.6 - normal.dx * scale * 2.6, a.dy - dir.dy * scale * 1.6 - normal.dy * scale * 2.6)
          ..close();
        canvas.drawPath(head, Paint()..color = arrow);
      }
    }
    // Puntos de inicio con el número de orden.
    for (int i = 0; i < template.strokes.length; i++) {
      final Offset p = template.strokes[i].first * scale;
      canvas.drawCircle(p, scale * 4.6, Paint()..color = start);
      final TextPainter tp = TextPainter(
        text: TextSpan(text: '${i + 1}', style: TextStyle(fontSize: scale * 5.5, color: onStart, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
    // Trazo del niño.
    final Paint inkPaint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = scale * 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final List<Offset> s in strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first * scale, scale * 2.5, Paint()..color = ink);
        continue;
      }
      final Path p = Path()..moveTo(s.first.dx * scale, s.first.dy * scale);
      for (int i = 1; i < s.length; i++) {
        p.lineTo(s[i].dx * scale, s[i].dy * scale);
      }
      canvas.drawPath(p, inkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TracePainter old) => true;
}
