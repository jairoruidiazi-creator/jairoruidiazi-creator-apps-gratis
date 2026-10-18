import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/rng.dart';
import '../../core/sfx.dart';
import '../../core/theme.dart';
import '../../engine/game_def.dart';
import '../../engine/round_engine.dart';
import '../../model/age_band.dart';
import '../shell/canvas_saver.dart';
import '../shell/game_frame.dart';
import '../shell/widgets.dart';
import 'pixel_patterns.dart';

enum PixelMode { libre, copiar, espejo }

/// Pixel art: pintar casillas con una paleta. Tres modos: libre, copiar un
/// modelo y completar la mitad en espejo (simetría). El tamaño de la
/// cuadrícula crece con el nivel.
class PixelScreen extends StatefulWidget {
  const PixelScreen({super.key, required this.launch});

  final GameLaunch launch;

  @override
  State<PixelScreen> createState() => _PixelScreenState();
}

class _PixelScreenState extends State<PixelScreen> {
  late final RoundEngine _engine;
  final Rng _rng = Rng();
  final GlobalKey _canvasKey = GlobalKey();
  PixelMode _mode = PixelMode.libre;
  PixelPattern? _model;
  int _n = 8;
  List<String> _cells = <String>[];
  String _color = 'r';
  bool _started = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final Services s = AppScope.read(context);
    _engine = RoundEngine(app: s.state, voice: s.voice, sfx: s.sfx, launch: widget.launch, onNextRound: _newBoard);
    _engine.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _newBoard();
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  int _sizeFor(int level) {
    if (widget.launch.band == AgeBand.b9a11) {
      return level <= 2 ? 12 : 16;
    }
    return level <= 2 ? 8 : 12;
  }

  void _newBoard() {
    if (!mounted) {
      return;
    }
    final int level = _engine.level;
    PixelPattern? model;
    int n = _sizeFor(level);
    if (_mode != PixelMode.libre) {
      final List<PixelPattern> pool = _mode == PixelMode.espejo ? PixelPatterns.symmetric : PixelPatterns.all;
      final PixelPattern elegido = _rng.pick(pool);
      model = elegido;
      n = elegido.size;
    }
    final List<String> cells = List<String>.filled(n * n, '.');
    if (_mode == PixelMode.espejo && model != null) {
      // Se da la mitad izquierda; el niño completa la derecha.
      for (int r = 0; r < n; r++) {
        for (int c = 0; c < n ~/ 2; c++) {
          cells[r * n + c] = model.at(r, c);
        }
      }
    }
    setState(() {
      _model = model;
      _n = n;
      _cells = cells;
    });
    _engine.startRound();
    switch (_mode) {
      case PixelMode.libre:
        _engine.say('Pinta las casillas con los colores que quieras.');
        break;
      case PixelMode.copiar:
        _engine.say('Copia el modelo: ${model!.nombre}. Fíjate en la fila y la columna de cada casilla.');
        break;
      case PixelMode.espejo:
        _engine.say('Completa la mitad que falta como en un espejo: ${model!.nombre}.');
        break;
    }
  }

  void _setMode(PixelMode m) {
    if (_mode == m || _engine.busy) {
      return;
    }
    setState(() => _mode = m);
    _newBoard();
  }

  void _paint(Offset local, double side) {
    if (_engine.busy) {
      return;
    }
    final double cell = side / _n;
    final int c = (local.dx / cell).floor();
    final int r = (local.dy / cell).floor();
    if (c < 0 || r < 0 || c >= _n || r >= _n) {
      return;
    }
    if (_mode == PixelMode.espejo && c < _n ~/ 2) {
      return; // la mitad dada no se cambia
    }
    final int i = r * _n + c;
    if (_cells[i] == _color) {
      return;
    }
    setState(() => _cells[i] = _color);
  }

  void _clear() {
    if (_engine.busy) {
      return;
    }
    unawaited(AppScope.read(context).sfx.play(SfxId.tap));
    _newBoard();
  }

  Future<void> _check() async {
    if (_engine.busy) {
      return;
    }
    if (_mode == PixelMode.libre) {
      if (!_cells.any((String c) => c != '.')) {
        AppScope.read(context).voice.sayLater('Primero pinta algunas casillas.');
        return;
      }
      await _save(silencioso: true);
      if (mounted) {
        await _engine.completeFree();
      }
      return;
    }
    final PixelPattern m = _model!;
    int total = 0;
    int ok = 0;
    for (int r = 0; r < _n; r++) {
      for (int c = 0; c < _n; c++) {
        if (_mode == PixelMode.espejo && c < _n ~/ 2) {
          continue;
        }
        total += 1;
        final String want = m.at(r, c);
        final String have = _cells[r * _n + c];
        if (want == have || (want == '.' && have == 'w') || (want == 'w' && have == '.')) {
          ok += 1;
        }
      }
    }
    final double score = total == 0 ? 1 : ok / total;
    if (score >= 0.92) {
      await _save(silencioso: true);
      if (mounted) {
        await _engine.finishBoard(success: true, message: _mode == PixelMode.espejo ? '¡Quedó simétrico! Las dos mitades son iguales.' : '¡Igualito al modelo!');
      }
      return;
    }
    final int faltan = total - ok;
    _engine.wrong(
      hint: 'Faltan $faltan casillas. ${_mode == PixelMode.espejo ? 'Cada casilla de la derecha debe ser igual a la que está a la misma distancia del centro, a la izquierda.' : 'Compara fila por fila con el modelo.'}',
      explain: 'Quedaron $faltan casillas distintas. Mira el modelo con calma y sigue fila por fila.',
    );
  }

  Future<void> _save({bool silencioso = false}) async {
    if (_saving) {
      return;
    }
    _saving = true;
    try {
      await saveCanvasPng(context, _canvasKey, widget.launch.profile.id, silencioso: silencioso, pixelRatio: 3);
    } finally {
      _saving = false;
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
    final String instruction = _mode == PixelMode.libre ? 'Pinta lo que quieras.' : (_mode == PixelMode.copiar ? 'Copia el modelo.' : 'Completa la otra mitad en espejo.');
    return GameFrame(
      launch: widget.launch,
      engine: _engine,
      instruction: instruction,
      actions: <Widget>[
        RoundIconButton(icon: Icons.refresh_rounded, tooltip: 'Empezar de nuevo', onPressed: _clear),
        const SizedBox(width: 6),
        RoundIconButton(icon: Icons.save_alt_rounded, tooltip: 'Guardar', onPressed: () => _save()),
      ],
      child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        final bool wide = c.maxWidth > c.maxHeight * 1.15;
        final Widget modes = Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          // En un teléfono angosto los tres modos van sin ícono para no desbordar.
          child: SegmentedButton<PixelMode>(
            segments: <ButtonSegment<PixelMode>>[
              ButtonSegment<PixelMode>(value: PixelMode.libre, label: const Text('Libre'), icon: c.maxWidth >= 440 ? const Icon(Icons.brush_rounded) : null),
              ButtonSegment<PixelMode>(value: PixelMode.copiar, label: const Text('Copiar'), icon: c.maxWidth >= 440 ? const Icon(Icons.copy_rounded) : null),
              ButtonSegment<PixelMode>(value: PixelMode.espejo, label: const Text('Espejo'), icon: c.maxWidth >= 440 ? const Icon(Icons.flip_rounded) : null),
            ],
            selected: <PixelMode>{_mode},
            onSelectionChanged: (Set<PixelMode> s) => _setMode(s.first),
            showSelectedIcon: false,
          ),
        );
        final Widget grid = Center(
          child: AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(builder: (BuildContext context, BoxConstraints k) {
              final double side = k.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (TapDownDetails d) => _paint(d.localPosition, side),
                onPanStart: (DragStartDetails d) => _paint(d.localPosition, side),
                onPanUpdate: (DragUpdateDetails d) => _paint(d.localPosition, side),
                child: RepaintBoundary(
                  key: _canvasKey,
                  child: CustomPaint(
                    size: Size(side, side),
                    painter: _PixelPainter(n: _n, cells: _cells, mirrorGuide: _mode == PixelMode.espejo),
                  ),
                ),
              );
            }),
          ),
        );
        final Widget model = _model == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('Modelo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: PilasColors.tintaSuave)),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 96,
                      height: 96,
                      child: CustomPaint(painter: _PixelPainter(n: _model!.size, cells: <String>[for (final String row in _model!.rows) ...row.split('')], mirrorGuide: false, thin: true)),
                    ),
                  ],
                ),
              );
        final Widget palette = _Palette(selected: _color, onPick: (String k) => setState(() => _color = k), vertical: wide);
        final Widget done = Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: FilledButton.icon(
            onPressed: _engine.busy ? null : _check,
            icon: Icon(_mode == PixelMode.libre ? Icons.check_rounded : Icons.compare_rounded),
            label: Text(_mode == PixelMode.libre ? 'Terminé' : 'Comparar', style: const TextStyle(fontSize: 18)),
            style: FilledButton.styleFrom(minimumSize: const Size(160, 50)),
          ),
        );
        if (wide) {
          return Column(
            children: <Widget>[
              modes,
              Expanded(
                child: Row(
                  children: <Widget>[
                    Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 8, 8), child: grid)),
                    Column(children: <Widget>[model, Expanded(child: palette)]),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
              done,
            ],
          );
        }
        return Column(
          children: <Widget>[
            modes,
            Expanded(
              child: Row(
                children: <Widget>[
                  Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 8, 0), child: grid)),
                  if (_model != null) model,
                ],
              ),
            ),
            palette,
            done,
          ],
        );
      }),
    );
  }
}

class _PixelPainter extends CustomPainter {
  _PixelPainter({required this.n, required this.cells, required this.mirrorGuide, this.thin = false});

  final int n;
  final List<String> cells;
  final bool mirrorGuide;
  final bool thin;

  @override
  void paint(Canvas canvas, Size size) {
    final double cell = size.width / n;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final Paint line = Paint()
      ..color = const Color(0xFFE3DED2)
      ..strokeWidth = thin ? 0.5 : 1;
    for (int i = 0; i < n * n; i++) {
      final String k = cells[i];
      if (k == '.') {
        continue;
      }
      final Color? c = PixelPalette.colors[k];
      if (c == null) {
        continue;
      }
      final Rect r = Rect.fromLTWH((i % n) * cell, (i ~/ n) * cell, cell, cell);
      canvas.drawRect(r, Paint()..color = c);
    }
    for (int i = 0; i <= n; i++) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, size.height), line);
      canvas.drawLine(Offset(0, i * cell), Offset(size.width, i * cell), line);
    }
    if (mirrorGuide) {
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        Paint()
          ..color = PilasColors.naranja
          ..strokeWidth = 3,
      );
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = PilasColors.tinta
        ..style = PaintingStyle.stroke
        ..strokeWidth = thin ? 1 : 2,
    );
  }

  @override
  bool shouldRepaint(covariant _PixelPainter old) => true;
}

class _Palette extends StatelessWidget {
  const _Palette({required this.selected, required this.onPick, required this.vertical});

  final String selected;
  final ValueChanged<String> onPick;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = <Widget>[
      for (final String k in PixelPalette.order)
        Padding(
          padding: const EdgeInsets.all(3),
          child: Semantics(
            button: true,
            selected: selected == k,
            label: PixelPalette.names[k],
            child: GestureDetector(
              onTap: () {
                unawaited(AppScope.read(context).sfx.play(SfxId.tap));
                onPick(k);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: selected == k ? 44 : 38,
                height: selected == k ? 44 : 38,
                decoration: BoxDecoration(
                  color: PixelPalette.colors[k],
                  shape: BoxShape.circle,
                  border: Border.all(color: selected == k ? PilasColors.tinta : Colors.black.withValues(alpha: 0.2), width: selected == k ? 4 : 1.5),
                ),
                child: k == 'w' ? const Icon(Icons.cleaning_services_rounded, size: 18, color: PilasColors.tintaSuave) : null,
              ),
            ),
          ),
        ),
    ];
    if (vertical) {
      return SizedBox(
        width: 110,
        child: SingleChildScrollView(child: Wrap(alignment: WrapAlignment.center, children: items)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Wrap(alignment: WrapAlignment.center, children: items),
    );
  }
}
