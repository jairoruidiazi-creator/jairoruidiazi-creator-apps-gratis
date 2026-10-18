import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/rng.dart';
import '../../core/sfx.dart';
import '../../core/theme.dart';
import '../../engine/game_def.dart';
import '../../engine/round_engine.dart';
import '../shell/game_frame.dart';
import '../shell/widgets.dart';
import 'sudoku_board.dart';

/// Sudoku de dibujos (4×4) y de números (4×4, 6×6 y 9×9).
///
/// Si el niño pone algo que choca con la fila, la columna o el recuadro, se
/// le dice dónde está el choque. Si el tablero queda sin salida (una casilla
/// en la que ya no cabe nada), se marcan las casillas que no van y se le
/// pide revisarlas: nunca queda atascado.
class SudokuScreen extends StatefulWidget {
  const SudokuScreen({super.key, required this.launch});

  final GameLaunch launch;

  @override
  State<SudokuScreen> createState() => _SudokuScreenState();
}

class _SudokuScreenState extends State<SudokuScreen> {
  late final RoundEngine _engine;
  final Rng _rng = Rng();
  SudokuBoard? _board;
  int _selected = -1;
  int _highlight = 0;
  int _errors = 0;
  final Set<int> _flash = <int>{};
  final Set<int> _marked = <int>{};
  int _deadEnd = -1;
  Timer? _flashTimer;
  bool _started = false;
  String _instruction = '';

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

  /// Errores que todavía cuentan como tablero resuelto con eficiencia.
  int get _allowedErrors => _board?.erroresPermitidos ?? 1;

  void _newBoard() {
    if (!mounted) {
      return;
    }
    final SudokuBoard b = SudokuBoard.generate(_rng, widget.launch.band, _engine.level);
    final String que = b.usesEmoji ? 'cada dibujo' : 'cada número';
    setState(() {
      _board = b;
      _selected = -1;
      _highlight = 0;
      _errors = 0;
      _flash.clear();
      _marked.clear();
      _deadEnd = -1;
      _instruction = 'Completa el tablero: $que va una sola vez en cada fila, en cada columna y en cada recuadro de borde grueso. Toca una casilla vacía y luego elige.';
    });
    _engine.startRound();
    _engine.say(_instruction);
  }

  void _tapCell(int i) {
    final SudokuBoard? b = _board;
    if (b == null || _engine.busy) {
      return;
    }
    unawaited(AppScope.read(context).sfx.play(SfxId.tap));
    setState(() {
      if (b.isGiven(i)) {
        // Tocar una casilla fija resalta dónde más está ese símbolo.
        _selected = -1;
        _highlight = _highlight == b.cells[i] ? 0 : b.cells[i];
      } else {
        _selected = _selected == i ? -1 : i;
        _highlight = _selected >= 0 ? b.cells[i] : 0;
      }
    });
  }

  String _lugar(String place) => place == 'región' ? 'este recuadro' : 'esta $place';

  void _place(int value) {
    final SudokuBoard? b = _board;
    if (b == null || _engine.busy) {
      return;
    }
    final Services s = AppScope.read(context);
    if (_selected < 0) {
      s.voice.sayLater('Primero toca una casilla vacía.');
      return;
    }
    final int i = _selected;
    if (value == 0) {
      unawaited(s.sfx.play(SfxId.tap));
      setState(() {
        b.cells[i] = 0;
        _marked.remove(i);
        _highlight = 0;
        if (_marked.isEmpty) {
          _deadEnd = -1;
        }
      });
      return;
    }
    final int? other = b.conflictCell(i, value);
    if (other != null) {
      _errors += 1;
      final String donde = _lugar(b.conflictPlace(i, other));
      final String que = b.usesEmoji ? 'Ese dibujo' : 'El $value';
      _engine.showHint('$que ya está en $donde. Busca otro.');
      setState(() {
        _flash
          ..clear()
          ..add(i)
          ..add(other);
      });
      _flashTimer?.cancel();
      _flashTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) {
          setState(_flash.clear);
        }
      });
      return;
    }
    unawaited(s.sfx.play(SfxId.pop));
    setState(() {
      b.cells[i] = value;
      _marked.remove(i);
      _selected = -1;
      _highlight = value;
    });
    if (b.complete) {
      // Sin choques y con solución única, un tablero lleno es la solución.
      final bool ok = _errors <= _allowedErrors;
      unawaited(_engine.finishBoard(
        success: ok,
        message: ok ? '¡Completaste el sudoku!' : '¡Lo completaste! Antes de poner uno, revisa la fila, la columna y el recuadro.',
      ));
      return;
    }
    final int? dead = b.deadEndCell();
    if (dead != null) {
      _errors += 1;
      setState(() {
        _deadEnd = dead;
        _marked
          ..clear()
          ..addAll(b.wrongCells());
      });
      _engine.showHint('Así ya no se puede terminar: en la casilla que parpadea no cabe nada. Las casillas marcadas no van así: bórralas y piensa otra vez.');
      return;
    }
    if (_marked.isEmpty) {
      _deadEnd = -1;
      _engine.clearHint();
    }
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _engine.removeListener(_refresh);
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SudokuBoard? b = _board;
    return GameFrame(
      launch: widget.launch,
      engine: _engine,
      instruction: _instruction,
      child: b == null ? const SizedBox.shrink() : LayoutBuilder(builder: (BuildContext context, BoxConstraints c) => _layout(b, c)),
    );
  }

  Widget _layout(SudokuBoard b, BoxConstraints c) {
    const double pad = 12;
    const double cellBtn = 56; // botón de 52 más su margen
    final int buttons = b.size + 1;
    final bool side = c.maxWidth > c.maxHeight;
    final bool leftHanded = widget.launch.profile.leftHanded;
    double boardSide;
    int cols;
    if (side) {
      final int rowsFit = math.max(1, ((c.maxHeight - 2 * pad - 16) / cellBtn).floor());
      cols = (buttons / rowsFit).ceil();
      final double paletteW = cols * cellBtn + 16;
      boardSide = math.min(c.maxWidth - paletteW - 3 * pad, c.maxHeight - 2 * pad);
    } else {
      final int perRow = math.max(1, ((c.maxWidth - 2 * pad - 16) / cellBtn).floor());
      final int rows = (buttons / perRow).ceil();
      cols = (buttons / rows).ceil();
      final double paletteH = rows * cellBtn + 16;
      boardSide = math.min(c.maxWidth - 2 * pad, c.maxHeight - paletteH - 3 * pad);
    }
    boardSide = math.max(boardSide, b.size * Dim.minCell);
    final Widget grid = _grid(b, boardSide);
    final Widget palette = _Palette(board: b, columns: cols, onPick: _place, active: _selected >= 0);
    if (side) {
      final List<Widget> items = <Widget>[Expanded(child: Center(child: grid)), const SizedBox(width: pad), Center(child: palette)];
      return Padding(
        padding: const EdgeInsets.all(pad),
        child: Row(children: leftHanded ? items.reversed.toList() : items),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(pad),
      child: Column(children: <Widget>[Expanded(child: Center(child: grid)), const SizedBox(height: pad), palette]),
    );
  }

  Widget _grid(SudokuBoard b, double side) {
    final PilasPalette pal = PilasPalette.of(context);
    return Container(
      key: ValueKey<String>('tablero-${b.size}x${b.size}'),
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: pal.tarjeta,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: pal.tinta, width: 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Column(
          children: <Widget>[
            for (int r = 0; r < b.size; r++)
              Expanded(
                child: Row(
                  children: <Widget>[
                    for (int col = 0; col < b.size; col++) Expanded(child: _cell(b, r, col, pal)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(SudokuBoard b, int r, int col, PilasPalette pal) {
    final int i = b.index(r, col);
    final int v = b.cells[i];
    final bool given = b.isGiven(i);
    final bool selected = i == _selected;
    final bool same = _highlight != 0 && v == _highlight && !selected;
    final bool flash = _flash.contains(i);
    final bool marked = _marked.contains(i);
    final bool dead = i == _deadEnd && v == 0;
    final BorderSide thin = BorderSide(color: pal.cuadricula, width: 1);
    final BorderSide thick = BorderSide(color: pal.tinta, width: 2.5);
    Color bg = given ? pal.fondo : pal.tarjeta;
    if (same) {
      bg = pal.acentoClaro;
    }
    if (marked || dead) {
      bg = pal.pistaClaro;
    }
    if (flash) {
      bg = pal.errorClaro;
    }
    if (selected) {
      bg = pal.acentoClaro;
    }
    final String estado = v == 0 ? 'vacía' : '${b.nombre(v)}${given ? ', fija' : ''}${marked ? ', revisar' : ''}';
    return Semantics(
      button: !given,
      selected: selected,
      label: 'Fila ${r + 1}, columna ${col + 1}: $estado',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey<String>('casilla-$i'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _tapCell(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              right: col == b.size - 1 ? BorderSide.none : ((col + 1) % b.boxCols == 0 ? thick : thin),
              bottom: r == b.size - 1 ? BorderSide.none : ((r + 1) % b.boxRows == 0 ? thick : thin),
            ),
          ),
          foregroundDecoration: selected || marked || dead
              ? BoxDecoration(border: Border.all(color: selected ? pal.acento : pal.pista, width: dead ? 4 : 3))
              : null,
          child: dead ? _Blink(color: pal.pista) : Center(child: v == 0 ? null : _symbol(b, v, given, pal)),
        ),
      ),
    );
  }

  Widget _symbol(SudokuBoard b, int v, bool given, PilasPalette pal) {
    if (b.usesEmoji) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: LayoutBuilder(builder: (BuildContext c2, BoxConstraints k) => EmojiImage(b.emojiOf(v), size: math.min(k.maxWidth, k.maxHeight))),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Text(
          b.nombre(v),
          textScaler: TextScaler.noScaling,
          style: TextStyle(fontSize: b.size == 9 ? 24 : 32, fontWeight: given ? FontWeight.w800 : FontWeight.w600, color: given ? pal.tinta : pal.acento),
        ),
      ),
    );
  }
}

/// Marco que parpadea en la casilla sin salida.
class _Blink extends StatefulWidget {
  const _Blink({required this.color});

  final Color color;

  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void initState() {
    super.initState();
    // Parpadea unas veces y se queda quieto (sin animaciones sin fin).
    unawaited(_c.repeat(reverse: true, count: 4));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1).animate(_c),
      child: Container(color: widget.color.withValues(alpha: 0.35)),
    );
  }
}

class _Palette extends StatelessWidget {
  const _Palette({required this.board, required this.columns, required this.onPick, required this.active});

  final SudokuBoard board;
  final int columns;
  final void Function(int value) onPick;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    final List<Widget> items = <Widget>[
      for (int v = 1; v <= board.size; v++)
        _PaletteButton(
          key: ValueKey<String>('sudoku-valor-$v'),
          active: active,
          onTap: () => onPick(v),
          label: board.nombre(v),
          child: board.usesEmoji
              ? EmojiImage(board.emojiOf(v), size: 36)
              : Text('$v', textScaler: TextScaler.noScaling, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: pal.tinta)),
        ),
      _PaletteButton(
        key: const ValueKey<String>('sudoku-borrar'),
        active: active,
        onTap: () => onPick(0),
        label: 'Borrar la casilla',
        child: Icon(Icons.backspace_outlined, color: pal.tinta, size: 28),
      ),
    ];
    final int rows = (items.length / columns).ceil();
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: pal.tarjeta, borderRadius: BorderRadius.circular(Dim.radio), border: Border.all(color: pal.altoContraste ? pal.bordeFuerte : pal.borde, width: 2)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int r = 0; r < rows; r++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[for (int k = r * columns; k < math.min(items.length, (r + 1) * columns); k++) items[k]],
            ),
        ],
      ),
    );
  }
}

class _PaletteButton extends StatelessWidget {
  const _PaletteButton({super.key, required this.active, required this.onTap, required this.label, required this.child});

  final bool active;
  final VoidCallback onTap;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        button: true,
        enabled: active,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: active ? pal.fondo : pal.tarjeta,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: active ? pal.bordeFuerte : pal.borde, width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            // Siempre se puede tocar: sin casilla elegida, la voz explica qué hacer.
            onTap: onTap,
            child: SizedBox(width: 52, height: 52, child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}
