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
import '../../model/age_band.dart';
import '../shell/canvas_saver.dart';
import '../shell/game_frame.dart';
import '../shell/widgets.dart';
import 'pixel_patterns.dart';

enum PixelMode { libre, copiar, espejo }

/// Pixel art: pintar casillas con una paleta. Tres modos: libre (sin
/// evaluación), copiar un modelo y completar la mitad en espejo. Cada nivel
/// agranda la cuadrícula (de 6×6 a 12×12), salvo que en esa pantalla las
/// casillas quedaran de menos de 24 dp (teléfono pequeño con letra grande):
/// entonces se usa la cuadrícula más grande que cabe.
///
/// Al comparar, si algo no coincide se marcan las casillas por arreglar y el
/// tablero sigue: nunca se descarta lo pintado. El tablero cuenta como
/// resuelto con eficiencia si la primera comparación ya estaba bien (con una
/// o dos casillas de tolerancia en las cuadrículas grandes).
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
  late PixelMode _mode;
  PixelPattern? _model;
  int _n = 8;
  List<String> _cells = <String>[];
  final Set<int> _marked = <int>{};

  /// Color elegido; '.' es el borrador.
  String _color = 'r';
  int _checks = 0;
  int _firstDiff = 0;
  bool _started = false;
  bool _saving = false;

  /// Lado máximo de cuadrícula que cabe en la pantalla con casillas de 24 dp
  /// (0 mientras no se conoce el espacio).
  int _tope = 0;

  static const List<int> _tamanos = <int>[6, 8, 10, 12];

  bool get _mayores => widget.launch.band == AgeBand.b9a11;

  @override
  void initState() {
    super.initState();
    _mode = _mayores ? PixelMode.espejo : PixelMode.copiar;
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

  /// Casillas distintas que todavía cuentan como primera comparación buena.
  int get _tolerance => PixelPatterns.tolerancia(_n);

  String get _instruction {
    switch (_mode) {
      case PixelMode.libre:
        return 'Pinta lo que quieras y toca Listo.';
      case PixelMode.copiar:
        return Es.contraer('Copia ${_model?.nombre ?? 'el modelo'} casilla por casilla y toca Listo.');
      case PixelMode.espejo:
        return Es.contraer('Completa la otra mitad de ${_model?.nombre ?? 'la figura'}, como en un espejo.');
    }
  }

  /// El tamaño del nivel, o el más grande que cabe si el del nivel no cabe.
  int get _tamano {
    final int n = PixelPatterns.sizeFor(_mayores, _engine.level);
    if (_tope <= 0 || n <= _tope) {
      return n;
    }
    int mejor = _tamanos.first;
    for (final int t in _tamanos) {
      if (t <= _tope && t > mejor) {
        mejor = t;
      }
    }
    return mejor;
  }

  void _newBoard() {
    if (!mounted) {
      return;
    }
    _prepararTablero();
    _engine.startRound();
    _engine.say(_instruction);
  }

  /// Elige el modelo y deja la cuadrícula lista (sin empezar otra ronda).
  void _prepararTablero() {
    final int n = _tamano;
    PixelPattern? model;
    if (_mode != PixelMode.libre) {
      final List<PixelPattern> pool = _mode == PixelMode.espejo ? PixelPatterns.symmetricOfSize(n) : PixelPatterns.ofSize(n);
      model = _rng.pick(pool);
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
      _marked.clear();
      _checks = 0;
      _firstDiff = 0;
    });
  }

  /// Ajusta el tope al espacio del tablero. Si la cuadrícula actual no cabe
  /// con casillas de 24 dp y el niño todavía no pintó nada, se cambia por una
  /// que quepa (con su propio modelo).
  void _ajustarTope(double side) {
    final int tope = (side / Dim.minCell).floor();
    if (tope == _tope) {
      return;
    }
    _tope = tope;
    if (_tamano == _n || _hasPaint || _checks > 0 || _engine.busy) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasPaint || _checks > 0 || _engine.busy || _tamano == _n) {
        return;
      }
      _prepararTablero();
      _engine.say(_instruction);
    });
  }

  void _setMode(PixelMode m) {
    if (_mode == m || _engine.busy) {
      return;
    }
    unawaited(AppScope.read(context).sfx.play(SfxId.tap));
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
    setState(() {
      _cells[i] = _color;
      final PixelPattern? m = _model;
      if (m != null && _marked.contains(i) && m.at(r, c) == _color) {
        _marked.remove(i);
      }
    });
  }

  /// Borra lo pintado (en espejo, solo la mitad del niño). Es el mismo tablero.
  void _clear() {
    if (_engine.busy) {
      return;
    }
    unawaited(AppScope.read(context).sfx.play(SfxId.tap));
    setState(() {
      for (int i = 0; i < _cells.length; i++) {
        if (_mode == PixelMode.espejo && i % _n < _n ~/ 2) {
          continue;
        }
        _cells[i] = '.';
      }
      _marked.clear();
    });
  }

  bool get _hasPaint {
    for (int i = 0; i < _cells.length; i++) {
      if (_cells[i] != '.' && !(_mode == PixelMode.espejo && i % _n < _n ~/ 2)) {
        return true;
      }
    }
    return false;
  }

  List<int> _diff() {
    final PixelPattern m = _model!;
    final List<int> out = <int>[];
    for (int r = 0; r < _n; r++) {
      for (int c = 0; c < _n; c++) {
        if (_mode == PixelMode.espejo && c < _n ~/ 2) {
          continue;
        }
        if (m.at(r, c) != _cells[r * _n + c]) {
          out.add(r * _n + c);
        }
      }
    }
    return out;
  }

  Future<void> _check() async {
    if (_engine.busy) {
      return;
    }
    final Services s = AppScope.read(context);
    if (!_hasPaint) {
      s.voice.sayLater('Primero pinta algunas casillas.');
      return;
    }
    if (_mode == PixelMode.libre) {
      unawaited(_save(silencioso: true));
      await _engine.completeFree(message: '¡Quedó muy bonito! Lo guardé en Mis dibujos.');
      return;
    }
    final List<int> wrong = _diff();
    _checks += 1;
    if (_checks == 1) {
      _firstDiff = wrong.length;
    }
    if (wrong.isEmpty) {
      unawaited(_save(silencioso: true));
      final bool ok = _firstDiff <= _tolerance;
      final String bien = _mode == PixelMode.espejo ? '¡Quedó simétrico! Las dos mitades son iguales.' : '¡Igualito al modelo!';
      unawaited(_engine.finishBoard(success: ok, message: ok ? bien : '¡Lo lograste! La próxima vez revisa fila por fila antes de comparar.'));
      return;
    }
    setState(() {
      _marked
        ..clear()
        ..addAll(wrong);
    });
    final String cuantas = wrong.length == 1 ? 'Hay 1 casilla por arreglar' : 'Hay ${wrong.length} casillas por arreglar';
    _engine.showHint(_mode == PixelMode.espejo
        ? '$cuantas: están marcadas. Mira la casilla de la izquierda que está a la misma distancia de la línea.'
        : '$cuantas: están marcadas. Compara fila por fila con el modelo.');
  }

  Future<void> _save({bool silencioso = false}) async {
    if (_saving) {
      return;
    }
    if (!_hasPaint) {
      if (!silencioso) {
        AppScope.read(context).voice.sayLater('Primero pinta algunas casillas.');
      }
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
    // Los botones de borrar y guardar van junto al tablero (no en la
    // cabecera) para que la cabecera ocupe una sola fila y la cuadrícula
    // tenga más espacio.
    return GameFrame(
      launch: widget.launch,
      engine: _engine,
      instruction: _instruction,
      child: LayoutBuilder(builder: _layout),
    );
  }

  Widget _layout(BuildContext context, BoxConstraints c) {
    const double pad = 8;
    final bool leftHanded = widget.launch.profile.leftHanded;
    final bool copiar = _mode == PixelMode.copiar && _model != null;
    final Widget done = FilledButton.icon(
      key: const ValueKey<String>('pixel-comparar'),
      onPressed: _engine.busy ? null : _check,
      icon: Icon(_mode == PixelMode.libre ? Icons.check_rounded : Icons.compare_rounded),
      label: const Text('Listo'),
      style: FilledButton.styleFrom(minimumSize: const Size(100, 52), padding: const EdgeInsets.symmetric(horizontal: 14)),
    );
    final Widget clear = RoundIconButton(key: const ValueKey<String>('pixel-borrar-todo'), icon: Icons.layers_clear_rounded, tooltip: 'Borrar lo pintado', onPressed: _clear, size: 52);
    final Widget save = RoundIconButton(key: const ValueKey<String>('pixel-guardar'), icon: Icons.save_alt_rounded, tooltip: 'Guardar en Mis dibujos', onPressed: () => _save(), size: 52);
    // El tablero ocupa el lado menor del espacio que le queda: siempre cuadrado.
    final Widget board = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints k) {
        final double side = math.min(k.maxWidth, k.maxHeight);
        _ajustarTope(side);
        return Center(child: _board(side));
      },
    );
    if (c.maxWidth > c.maxHeight) {
      // Acostado: el tablero a un lado y una columna con el modo, los
      // botones, el modelo, la paleta y el botón de comparar.
      const double colW = 196;
      final Widget column = SizedBox(
        width: colW,
        child: Column(
          children: <Widget>[
            Row(children: <Widget>[Expanded(child: _modeButton()), const SizedBox(width: 4), clear, const SizedBox(width: 4), save]),
            const SizedBox(height: 6),
            if (copiar) Flexible(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints k) => Center(child: _modelThumb(math.min(k.maxWidth, k.maxHeight))))),
            FittedBox(fit: BoxFit.scaleDown, child: _Palette(selected: _color, columns: 4, onPick: _pick)),
            const SizedBox(height: 6),
            SizedBox(width: colW, child: FittedBox(fit: BoxFit.scaleDown, child: done)),
          ],
        ),
      );
      final List<Widget> items = <Widget>[Expanded(child: board), const SizedBox(width: pad), column];
      return Padding(
        padding: const EdgeInsets.all(pad),
        child: Row(children: leftHanded ? items.reversed.toList() : items),
      );
    }
    // De pie: el tablero; debajo el modelo (si se copia) con la paleta; y
    // abajo el modo, borrar, guardar y comparar.
    Widget middle;
    if (copiar) {
      final List<Widget> row = <Widget>[
        Expanded(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints k) => Center(child: _modelThumb(math.min(k.maxWidth, k.maxHeight))))),
        const SizedBox(width: 8),
        _Palette(selected: _color, columns: 4, onPick: _pick),
      ];
      middle = SizedBox(height: 144, child: Row(children: leftHanded ? row.reversed.toList() : row));
    } else {
      final int perRow = math.max(4, math.min(12, ((c.maxWidth - 2 * pad) / 48).floor()));
      final int rows = (12 / perRow).ceil();
      middle = _Palette(selected: _color, columns: (12 / rows).ceil(), onPick: _pick);
    }
    // En un teléfono angosto el modo queda solo con su ícono (el nombre va
    // en la etiqueta) y «Listo» se achica un poco si la letra es muy grande:
    // así la fila nunca se sale de la pantalla y el tablero no pierde alto.
    final bool angosto = c.maxWidth < 440;
    final Widget mode = angosto ? SizedBox(width: 60, child: _modeButton()) : Expanded(child: Align(alignment: leftHanded ? Alignment.centerRight : Alignment.centerLeft, child: _modeButton()));
    final List<Widget> bottom = <Widget>[
      mode,
      const SizedBox(width: 8),
      clear,
      const SizedBox(width: 8),
      save,
      const SizedBox(width: 8),
      if (angosto) Expanded(child: Align(alignment: leftHanded ? Alignment.centerLeft : Alignment.centerRight, child: FittedBox(fit: BoxFit.scaleDown, child: done))) else done,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        children: <Widget>[
          Expanded(child: board),
          const SizedBox(height: 8),
          middle,
          const SizedBox(height: 8),
          Row(children: leftHanded ? bottom.reversed.toList() : bottom),
        ],
      ),
    );
  }

  void _pick(String k) {
    unawaited(AppScope.read(context).sfx.play(SfxId.tap));
    setState(() => _color = k);
    AppScope.read(context).voice.sayLater(k == '.' ? 'Borrador' : PixelPalette.names[k]!);
  }

  static String _modeName(PixelMode m) => m == PixelMode.libre ? 'Libre' : (m == PixelMode.copiar ? 'Copiar' : 'Espejo');

  static IconData _modeIcon(PixelMode m) => m == PixelMode.libre ? Icons.brush_rounded : (m == PixelMode.copiar ? Icons.copy_rounded : Icons.flip_rounded);

  /// Botón del modo (libre, copiar o espejo) con su menú.
  Widget _modeButton() {
    final PilasPalette pal = PilasPalette.of(context);
    return PopupMenuButton<PixelMode>(
      key: const ValueKey<String>('pixel-modo'),
      tooltip: 'Cambiar de modo',
      enabled: !_engine.busy,
      initialValue: _mode,
      onSelected: _setMode,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<PixelMode>>[
        for (final PixelMode m in PixelMode.values)
          PopupMenuItem<PixelMode>(
            value: m,
            height: 52,
            child: Row(children: <Widget>[Icon(_modeIcon(m), color: pal.tinta), const SizedBox(width: 12), Text(_modeName(m), style: TextStyle(fontSize: 18, color: pal.tinta))]),
          ),
      ],
      child: LayoutBuilder(builder: (BuildContext context, BoxConstraints k) {
        // Con poco espacio queda solo el ícono (el nombre va en la etiqueta).
        final bool conNombre = k.maxWidth >= 132;
        return Semantics(
          label: 'Modo: ${_modeName(_mode)}',
          child: Container(
            constraints: const BoxConstraints(minHeight: 52, minWidth: 52),
            padding: EdgeInsets.symmetric(horizontal: conNombre ? 12 : 4),
            decoration: BoxDecoration(color: pal.tarjeta, borderRadius: BorderRadius.circular(18), border: Border.all(color: pal.bordeFuerte, width: 1.5)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(_modeIcon(_mode), color: pal.tinta),
                if (conNombre) ...<Widget>[
                  const SizedBox(width: 6),
                  Flexible(child: Text(_modeName(_mode), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: pal.tinta))),
                ],
                Icon(Icons.arrow_drop_down_rounded, color: pal.tinta),
              ],
            ),
          ),
        );
      }),
    );
  }

  /// Miniatura del modelo; al tocarla se ve en grande.
  Widget _modelThumb(double size) {
    final PixelPattern m = _model!;
    final PilasPalette pal = PilasPalette.of(context);
    final double side = size.clamp(48.0, 220.0).toDouble();
    return Semantics(
      button: true,
      label: 'Modelo: ${m.nombre}. Toca para verlo en grande',
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey<String>('pixel-modelo'),
        onTap: () => _showModel(m),
        child: Stack(
          children: <Widget>[
            SizedBox(
              width: side,
              height: side,
              child: CustomPaint(painter: _PixelPainter(n: m.size, cells: m.rows.join().split(''), grid: pal.cuadricula, frame: pal.tinta, thin: true)),
            ),
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                decoration: BoxDecoration(color: pal.tarjeta, shape: BoxShape.circle, border: Border.all(color: pal.bordeFuerte)),
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.zoom_in_rounded, size: 18, color: pal.tinta),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showModel(PixelPattern m) async {
    final PilasPalette pal = PilasPalette.of(context);
    unawaited(AppScope.read(context).sfx.play(SfxId.tap));
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(builder: (BuildContext context, BoxConstraints k) {
            final Size screen = MediaQuery.sizeOf(context);
            final double side = math.min(math.min(k.maxWidth, 420.0), screen.height - 200).clamp(120.0, 420.0).toDouble();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(Es.cap(m.nombre), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: pal.tinta)),
                const SizedBox(height: 10),
                SizedBox(width: side, height: side, child: CustomPaint(painter: _PixelPainter(n: m.size, cells: m.rows.join().split(''), grid: pal.cuadricula, frame: pal.tinta))),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Volver a pintar')),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _board(double side) {
    final PilasPalette pal = PilasPalette.of(context);
    final int pintadas = _cells.where((String k) => k != '.').length;
    return Semantics(
      label: 'Cuadrícula de $_n por $_n, ${pintadas == 1 ? '1 casilla pintada' : '$pintadas casillas pintadas'}',
      child: SizedBox(
        key: ValueKey<String>('tablero-${_n}x$_n'),
        width: side,
        height: side,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (TapDownDetails d) => _paint(d.localPosition, side),
          onPanStart: (DragStartDetails d) => _paint(d.localPosition, side),
          onPanUpdate: (DragUpdateDetails d) => _paint(d.localPosition, side),
          child: Stack(
            children: <Widget>[
              RepaintBoundary(
                key: _canvasKey,
                child: CustomPaint(size: Size(side, side), painter: _PixelPainter(n: _n, cells: _cells, grid: pal.cuadricula, frame: pal.tinta)),
              ),
              IgnorePointer(
                child: CustomPaint(
                  size: Size(side, side),
                  painter: _OverlayPainter(n: _n, marked: _marked.toList(), mirror: _mode == PixelMode.espejo, guide: pal.acento, mark: pal.pista),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PixelPainter extends CustomPainter {
  _PixelPainter({required this.n, required this.cells, required this.grid, required this.frame, this.thin = false});

  final int n;
  final List<String> cells;
  final Color grid;
  final Color frame;
  final bool thin;

  @override
  void paint(Canvas canvas, Size size) {
    final double cell = size.width / n;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    for (int i = 0; i < n * n && i < cells.length; i++) {
      final Color? c = PixelPalette.colors[cells[i]];
      if (c == null) {
        continue;
      }
      canvas.drawRect(Rect.fromLTWH((i % n) * cell, (i ~/ n) * cell, cell, cell), Paint()..color = c);
    }
    final Paint line = Paint()
      ..color = grid
      ..strokeWidth = thin ? 0.5 : 1;
    for (int i = 1; i < n; i++) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, size.height), line);
      canvas.drawLine(Offset(0, i * cell), Offset(size.width, i * cell), line);
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = frame
        ..style = PaintingStyle.stroke
        ..strokeWidth = thin ? 1 : 2,
    );
  }

  @override
  bool shouldRepaint(covariant _PixelPainter old) => true;
}

/// Línea del espejo y marcas de las casillas por arreglar (no se guardan con
/// el dibujo).
class _OverlayPainter extends CustomPainter {
  _OverlayPainter({required this.n, required this.marked, required this.mirror, required this.guide, required this.mark});

  final int n;
  final List<int> marked;
  final bool mirror;
  final Color guide;
  final Color mark;

  @override
  void paint(Canvas canvas, Size size) {
    final double cell = size.width / n;
    if (mirror) {
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        Paint()
          ..color = guide
          ..strokeWidth = 4,
      );
    }
    final Paint ring = Paint()
      ..color = mark
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.5, cell * 0.12);
    for (final int i in marked) {
      final Rect r = Rect.fromLTWH((i % n) * cell, (i ~/ n) * cell, cell, cell).deflate(ring.strokeWidth / 2 + 1);
      canvas.drawRect(r, ring);
      canvas.drawLine(r.topLeft, r.bottomRight, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) => true;
}

class _Palette extends StatelessWidget {
  const _Palette({required this.selected, required this.columns, required this.onPick});

  final String selected;
  final int columns;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    final List<String> keys = <String>[...PixelPalette.order, '.'];
    final List<Widget> items = <Widget>[
      for (final String k in keys)
        Semantics(
          button: true,
          selected: selected == k,
          label: k == '.' ? 'Borrador' : PixelPalette.names[k],
          excludeSemantics: true,
          child: GestureDetector(
            key: ValueKey<String>('pixel-color-$k'),
            behavior: HitTestBehavior.opaque,
            onTap: () => onPick(k),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: k == '.' ? pal.tarjeta : PixelPalette.colors[k],
                    shape: BoxShape.circle,
                    border: Border.all(color: selected == k ? pal.tinta : pal.bordeFuerte, width: selected == k ? 4 : 1.5),
                  ),
                  child: k == '.'
                      ? Icon(Icons.auto_fix_normal_rounded, size: 22, color: pal.tinta)
                      : (selected == k ? Icon(Icons.check_rounded, size: 20, color: k == 'y' || k == 's' || k == 'c' ? Colors.black : Colors.white) : null),
                ),
              ),
            ),
          ),
        ),
    ];
    final int rows = (items.length / columns).ceil();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int r = 0; r < rows; r++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[for (int k = r * columns; k < math.min(items.length, (r + 1) * columns); k++) items[k]],
          ),
      ],
    );
  }
}
