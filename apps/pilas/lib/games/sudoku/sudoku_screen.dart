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
import 'sudoku_board.dart';

/// Sudoku de figuras (4×4) y de números (6×6 y 9×9).
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
  int _errors = 0;
  int _flash = -1;
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

  void _newBoard() {
    if (!mounted) {
      return;
    }
    final SudokuBoard b = SudokuBoard.generate(_rng, widget.launch.band, _engine.level);
    final String que = b.usesEmoji ? 'cada dibujo' : 'cada número';
    setState(() {
      _board = b;
      _selected = -1;
      _errors = 0;
      _instruction = 'Completa el tablero: $que debe aparecer una sola vez en cada fila, cada columna y cada región.';
    });
    _engine.startRound();
    _engine.say(_instruction);
  }

  void _selectCell(int i) {
    final SudokuBoard? b = _board;
    if (b == null || b.isGiven(i) || _engine.busy) {
      return;
    }
    unawaited(AppScope.read(context).sfx.play(SfxId.tap));
    setState(() => _selected = _selected == i ? -1 : i);
  }

  void _place(int value) {
    final SudokuBoard? b = _board;
    if (b == null || _selected < 0 || _engine.busy) {
      return;
    }
    final Services s = AppScope.read(context);
    if (value == 0) {
      setState(() => b.cells[_selected] = 0);
      return;
    }
    if (b.conflicts(_selected, value)) {
      _errors += 1;
      final String lugar = b.conflictPlace(_selected, value);
      unawaited(s.sfx.play(SfxId.hint));
      s.voice.sayLater(b.usesEmoji ? 'Ese ya está en esta $lugar. Busca otro.' : 'El $value ya está en esta $lugar. Busca otro.');
      setState(() => _flash = _selected);
      _flashTimer?.cancel();
      _flashTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() => _flash = -1);
        }
      });
      return;
    }
    unawaited(s.sfx.play(SfxId.pop));
    setState(() {
      b.cells[_selected] = value;
      _selected = -1;
    });
    if (b.complete) {
      final bool ok = _errors <= 2;
      _engine.finishBoard(
        success: ok,
        message: ok ? '¡Completaste el sudoku!' : '¡Lo completaste! Antes de poner uno, revisa la fila, la columna y la región.',
      );
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
      child: b == null
          ? const SizedBox.shrink()
          : LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
              final bool wide = c.maxWidth > c.maxHeight * 1.1;
              final Widget grid = Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: PilasColors.tinta, width: 3),
                    ),
                    child: Column(
                      children: <Widget>[
                        for (int r = 0; r < b.size; r++)
                          Expanded(
                            child: Row(
                              children: <Widget>[
                                for (int col = 0; col < b.size; col++) Expanded(child: _cell(b, r, col)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
              final Widget palette = _Palette(board: b, onPick: _place, enabled: _selected >= 0, vertical: wide);
              if (wide) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: <Widget>[Expanded(child: grid), const SizedBox(width: 12), palette]),
                );
              }
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: <Widget>[Expanded(child: grid), const SizedBox(height: 12), palette]),
              );
            }),
    );
  }

  Widget _cell(SudokuBoard b, int r, int col) {
    final int i = b.index(r, col);
    final int v = b.cells[i];
    final bool given = b.isGiven(i);
    final bool selected = i == _selected;
    final bool sameValue = _selected >= 0 && v != 0 && v == b.cells[_selected] && !selected;
    final bool flash = i == _flash;
    const BorderSide thin = BorderSide(color: PilasColors.borde, width: 1);
    const BorderSide thick = BorderSide(color: PilasColors.tinta, width: 2.5);
    return GestureDetector(
      onTap: () => _selectCell(i),
      child: Semantics(
        button: !given,
        label: v == 0 ? 'Casilla vacía' : (b.usesEmoji ? 'Casilla con dibujo' : 'Casilla con $v'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: flash
                ? PilasColors.rojoSuave
                : (selected ? PilasColors.amarillo.withValues(alpha: 0.5) : (sameValue ? PilasColors.azulClaro : (given ? PilasColors.fondo : Colors.white))),
            border: Border(
              right: (col + 1) % b.boxCols == 0 && col != b.size - 1 ? thick : thin,
              bottom: (r + 1) % b.boxRows == 0 && r != b.size - 1 ? thick : thin,
            ),
          ),
          child: Center(
            child: v == 0
                ? null
                : (b.usesEmoji
                    ? Padding(padding: const EdgeInsets.all(4), child: LayoutBuilder(builder: (BuildContext c2, BoxConstraints k) => EmojiImage(b.label(v), size: k.maxWidth < k.maxHeight ? k.maxWidth : k.maxHeight)))
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Text(b.label(v), style: TextStyle(fontSize: b.size == 9 ? 22 : 30, fontWeight: given ? FontWeight.w800 : FontWeight.w500, color: given ? PilasColors.tinta : PilasColors.azul)),
                        ),
                      )),
          ),
        ),
      ),
    );
  }
}

class _Palette extends StatelessWidget {
  const _Palette({required this.board, required this.onPick, required this.enabled, required this.vertical});

  final SudokuBoard board;
  final void Function(int value) onPick;
  final bool enabled;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = <Widget>[
      for (int v = 1; v <= board.size; v++)
        _PaletteButton(
          enabled: enabled,
          onTap: () => onPick(v),
          label: board.usesEmoji ? 'dibujo $v' : '$v',
          child: board.usesEmoji ? EmojiImage(board.label(v), size: 34) : Text('$v', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: PilasColors.tinta)),
        ),
      _PaletteButton(
        enabled: enabled,
        onTap: () => onPick(0),
        label: 'borrar',
        child: const Icon(Icons.backspace_outlined, color: PilasColors.tintaSuave),
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Dim.radio), border: Border.all(color: PilasColors.borde, width: 2)),
      child: vertical
          ? SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: items))
          : Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: items),
    );
  }
}

class _PaletteButton extends StatelessWidget {
  const _PaletteButton({required this.enabled, required this.onTap, required this.label, required this.child});

  final bool enabled;
  final VoidCallback onTap;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: enabled ? PilasColors.fondo : PilasColors.fondo.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled ? onTap : null,
            child: Opacity(
              opacity: enabled ? 1 : 0.45,
              child: SizedBox(width: 50, height: 50, child: Center(child: child)),
            ),
          ),
        ),
      ),
    );
  }
}
