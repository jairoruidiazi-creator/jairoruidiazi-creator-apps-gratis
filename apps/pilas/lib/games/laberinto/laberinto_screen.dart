import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/rng.dart';
import '../../core/sfx.dart';
import '../../core/theme.dart';
import '../../engine/game_def.dart';
import '../../engine/round_engine.dart';
import '../../model/age_band.dart';
import '../shell/game_frame.dart';
import '../shell/widgets.dart';
import 'maze.dart';

/// Laberintos: llevar al personaje hasta la meta arrastrando el dedo o
/// tocando la celda vecina. Sin tiempo; cuenta los pasos frente al camino
/// más corto para registrar el dominio.
class LaberintoScreen extends StatefulWidget {
  const LaberintoScreen({super.key, required this.launch});

  final GameLaunch launch;

  @override
  State<LaberintoScreen> createState() => _LaberintoScreenState();
}

class _LaberintoScreenState extends State<LaberintoScreen> {
  late final RoundEngine _engine;
  final Rng _rng = Rng();
  Maze? _maze;
  int _pos = 0;
  bool _hasKey = false;
  List<int> _trail = <int>[0];
  int _steps = 0;
  bool _started = false;
  bool _solved = false;
  String _instruction = '';

  @override
  void initState() {
    super.initState();
    final Services s = AppScope.read(context);
    _engine = RoundEngine(app: s.state, voice: s.voice, sfx: s.sfx, launch: widget.launch, onNextRound: _newMaze);
    _engine.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _newMaze();
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _newMaze() {
    if (!mounted) {
      return;
    }
    final Maze m = Maze.generate(_rng, widget.launch.band, _engine.level);
    final String conLlave = m.keyCell >= 0 ? ' Primero recoge la llave.' : '';
    setState(() {
      _maze = m;
      _pos = 0;
      _hasKey = false;
      _trail = <int>[0];
      _steps = 0;
      _solved = false;
      _instruction = 'Lleva a ${m.theme.heroeNombre} hasta ${m.theme.metaNombre}.$conLlave';
    });
    _engine.startRound();
    _engine.say('$_instruction Arrastra el dedo por el camino.');
  }

  void _tryMove(int target) {
    final Maze? m = _maze;
    if (m == null || _solved || _engine.busy || target == _pos) {
      return;
    }
    if (!m.canMove(_pos, target)) {
      return;
    }
    final Services s = AppScope.read(context);
    setState(() {
      _pos = target;
      _steps += 1;
      // Si vuelve sobre sus pasos, se acorta la huella.
      if (_trail.length >= 2 && _trail[_trail.length - 2] == target) {
        _trail.removeLast();
      } else {
        _trail.add(target);
      }
      if (target == m.keyCell && !_hasKey) {
        _hasKey = true;
        unawaited(s.sfx.play(SfxId.pop));
        s.voice.sayLater('¡Tienes la llave! Ahora, a la meta.');
      }
    });
    if (target == m.goal) {
      if (m.keyCell >= 0 && !_hasKey) {
        unawaited(s.sfx.play(SfxId.hint));
        s.voice.sayLater('Falta la llave. Devuélvete a buscarla.');
        return;
      }
      _solved = true;
      unawaited(s.sfx.play(SfxId.pop));
      final int optimal = m.optimalSteps;
      final bool eficiente = _steps <= optimal * 1.6 + 2;
      final String msg = eficiente
          ? '¡${_cap(m.theme.heroeNombre)} llegó a ${m.theme.metaNombre}!'
          : '¡Llegaste! Diste muchas vueltas: la próxima vez mira todo el camino antes de empezar.';
      _engine.finishBoard(success: eficiente, message: msg);
    }
  }

  String _cap(String t) => t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);

  void _handlePointer(Offset local, Size size) {
    final Maze? m = _maze;
    if (m == null) {
      return;
    }
    final double cell = size.width / m.cols;
    final int c = (local.dx / cell).floor();
    final int r = (local.dy / cell).floor();
    if (c < 0 || r < 0 || c >= m.cols || r >= m.rows) {
      return;
    }
    final int target = m.index(c, r);
    if (target == _pos) {
      return;
    }
    // Permite deslizar varias celdas: avanza paso a paso mientras sean vecinas.
    if (m.canMove(_pos, target)) {
      _tryMove(target);
      return;
    }
    // Si saltó una celda en línea recta, intenta el paso intermedio.
    final int dc = c - m.colOf(_pos);
    final int dr = r - m.rowOf(_pos);
    if ((dc == 0 && dr.abs() == 2) || (dr == 0 && dc.abs() == 2)) {
      final int mid = m.index(m.colOf(_pos) + dc ~/ 2, m.rowOf(_pos) + dr ~/ 2);
      if (m.canMove(_pos, mid)) {
        _tryMove(mid);
        if (m.canMove(_pos, target)) {
          _tryMove(target);
        }
      }
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
    final Maze? m = _maze;
    const Color areaColor = PilasColors.morado;
    return GameFrame(
      launch: widget.launch,
      engine: _engine,
      instruction: _instruction,
      child: m == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: m.cols / m.rows,
                        child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
                          final Size size = Size(c.maxWidth, c.maxHeight);
                          final double cell = size.width / m.cols;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (DragStartDetails d) => _handlePointer(d.localPosition, size),
                            onPanUpdate: (DragUpdateDetails d) => _handlePointer(d.localPosition, size),
                            onTapDown: (TapDownDetails d) => _handlePointer(d.localPosition, size),
                            child: Stack(
                              children: <Widget>[
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _MazePainter(maze: m, trail: _trail, color: areaColor),
                                  ),
                                ),
                                Positioned(
                                  left: m.colOf(m.goal) * cell + cell * 0.12,
                                  top: m.rowOf(m.goal) * cell + cell * 0.12,
                                  child: EmojiImage(m.theme.meta, size: cell * 0.76, semanticsLabel: m.theme.metaNombre),
                                ),
                                if (m.keyCell >= 0 && !_hasKey)
                                  Positioned(
                                    left: m.colOf(m.keyCell) * cell + cell * 0.15,
                                    top: m.rowOf(m.keyCell) * cell + cell * 0.15,
                                    child: EmojiImage('1f511', size: cell * 0.7, semanticsLabel: 'llave'),
                                  ),
                                AnimatedPositioned(
                                  duration: const Duration(milliseconds: 120),
                                  left: m.colOf(_pos) * cell + cell * 0.1,
                                  top: m.rowOf(_pos) * cell + cell * 0.1,
                                  child: EmojiImage(m.theme.heroe, size: cell * 0.8, semanticsLabel: m.theme.heroeNombre),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Icon(Icons.directions_walk_rounded, color: PilasColors.tintaSuave),
                      const SizedBox(width: 6),
                      Text('$_steps pasos', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: PilasColors.tintaSuave)),
                      if (widget.launch.band.readsText) ...<Widget>[
                        const SizedBox(width: 16),
                        Text('Mínimo: ${m.optimalSteps}', style: const TextStyle(fontSize: 16, color: PilasColors.tintaSuave)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _MazePainter extends CustomPainter {
  _MazePainter({required this.maze, required this.trail, required this.color});

  final Maze maze;
  final List<int> trail;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double cell = size.width / maze.cols;
    final RRect fondo = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12));
    canvas.drawRRect(fondo, Paint()..color = Colors.white);
    // Celda de salida y de meta.
    canvas.drawRect(Rect.fromLTWH(0, 0, cell, cell), Paint()..color = PilasColors.azulClaro);
    canvas.drawRect(Rect.fromLTWH((maze.cols - 1) * cell, (maze.rows - 1) * cell, cell, cell), Paint()..color = PilasColors.verdeClaro);
    // Huella.
    if (trail.length > 1) {
      final Path p = Path();
      for (int i = 0; i < trail.length; i++) {
        final Offset o = Offset(maze.colOf(trail[i]) * cell + cell / 2, maze.rowOf(trail[i]) * cell + cell / 2);
        if (i == 0) {
          p.moveTo(o.dx, o.dy);
        } else {
          p.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(
        p,
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.28
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    // Paredes.
    final Paint wall = Paint()
      ..color = PilasColors.tinta
      ..strokeWidth = (cell * 0.12).clamp(3.0, 8.0).toDouble()
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < maze.cols * maze.rows; i++) {
      final double x = maze.colOf(i) * cell;
      final double y = maze.rowOf(i) * cell;
      if (maze.hasWall(i, Maze.n)) {
        canvas.drawLine(Offset(x, y), Offset(x + cell, y), wall);
      }
      if (maze.hasWall(i, Maze.w)) {
        canvas.drawLine(Offset(x, y), Offset(x, y + cell), wall);
      }
      if (maze.hasWall(i, Maze.e)) {
        canvas.drawLine(Offset(x + cell, y), Offset(x + cell, y + cell), wall);
      }
      if (maze.hasWall(i, Maze.s)) {
        canvas.drawLine(Offset(x, y + cell), Offset(x + cell, y + cell), wall);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MazePainter old) => old.maze != maze || old.trail.length != trail.length || (trail.isNotEmpty && old.trail.isNotEmpty && old.trail.last != trail.last);
}
