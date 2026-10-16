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
import 'memoria_board.dart';

/// Parejas y memoria.
class MemoriaScreen extends StatefulWidget {
  const MemoriaScreen({super.key, required this.launch});

  final GameLaunch launch;

  @override
  State<MemoriaScreen> createState() => _MemoriaScreenState();
}

class _MemoriaScreenState extends State<MemoriaScreen> {
  late final RoundEngine _engine;
  final Rng _rng = Rng();
  MemoryBoard? _board;
  MemoryCard? _first;
  bool _locked = false;
  bool _started = false;
  Timer? _timer;

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
    _timer?.cancel();
    final MemoryBoard board = MemoryBoard.generate(_rng, widget.launch.band, _engine.level);
    setState(() {
      _board = board;
      _first = null;
      _locked = board.previewSeconds > 0;
    });
    _engine.startRound();
    _engine.say(board.descripcion);
    if (board.previewSeconds > 0) {
      for (final MemoryCard c in board.cards) {
        c.faceUp = true;
      }
      _timer = Timer(Duration(seconds: board.previewSeconds), () {
        if (!mounted) {
          return;
        }
        setState(() {
          for (final MemoryCard c in board.cards) {
            c.faceUp = false;
          }
          _locked = false;
        });
      });
    }
  }

  void _tap(MemoryCard card) {
    final MemoryBoard? board = _board;
    if (board == null || _locked || card.faceUp || card.matched || _engine.busy) {
      return;
    }
    final Services s = AppScope.read(context);
    unawaited(s.sfx.play(SfxId.tap));
    setState(() {
      card.faceUp = true;
      board.flips += 1;
    });
    if (_first == null) {
      _first = card;
      s.voice.sayLater(card.label);
      return;
    }
    final MemoryCard a = _first!;
    _first = null;
    if (a.pairId == card.pairId) {
      setState(() {
        a.matched = true;
        card.matched = true;
      });
      unawaited(s.sfx.play(SfxId.pop));
      s.voice.sayLater('${card.label}. ¡Pareja!');
      if (board.done) {
        final bool ok = board.efficient;
        _engine.finishBoard(
          success: ok,
          message: ok ? '¡Encontraste todas las parejas!' : 'Encontraste todas. La próxima vez intenta recordar dónde estaba cada carta.',
        );
      }
    } else {
      board.mismatches += 1;
      s.voice.sayLater(card.label);
      _locked = true;
      _timer = Timer(const Duration(milliseconds: 900), () {
        if (!mounted) {
          return;
        }
        setState(() {
          a.faceUp = false;
          card.faceUp = false;
          _locked = false;
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _engine.removeListener(_refresh);
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MemoryBoard? board = _board;
    return GameFrame(
      launch: widget.launch,
      engine: _engine,
      instruction: board?.descripcion ?? '',
      child: board == null
          ? const SizedBox.shrink()
          : LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) {
                final int cols = c.maxWidth > c.maxHeight && board.cards.length > 6 ? (board.cards.length / 2).ceil().clamp(3, 6).toInt() : board.columns;
                final int rows = (board.cards.length / cols).ceil();
                final double w = (c.maxWidth - 32 - (cols - 1) * 10) / cols;
                final double h = (c.maxHeight - 32 - (rows - 1) * 10) / rows;
                final double aspect = (w / h).clamp(0.6, 1.6).toDouble();
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: GridView.count(
                    crossAxisCount: cols,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: aspect,
                    physics: const ClampingScrollPhysics(),
                    children: <Widget>[
                      for (final MemoryCard card in board.cards) _CardView(card: card, onTap: () => _tap(card)),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _CardView extends StatelessWidget {
  const _CardView({required this.card, required this.onTap});

  final MemoryCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool up = card.faceUp || card.matched;
    return Semantics(
      button: true,
      label: up ? card.label : 'Carta boca abajo',
      child: GestureDetector(
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: up ? 1 : 0),
          duration: const Duration(milliseconds: 260),
          builder: (BuildContext context, double t, Widget? _) {
            final bool showFront = t > 0.5;
            final double angle = t * 3.14159;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(angle),
              child: showFront
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(3.14159),
                      child: _front(),
                    )
                  : _back(),
            );
          },
        ),
      ),
    );
  }

  Widget _back() {
    return Container(
      decoration: BoxDecoration(
        color: PilasColors.azul,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: const Center(child: Opacity(opacity: 0.9, child: Mascot(size: 36))),
    );
  }

  Widget _front() {
    return Container(
      decoration: BoxDecoration(
        color: card.matched ? PilasColors.verdeClaro : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: card.matched ? PilasColors.verde : PilasColors.borde, width: 3),
      ),
      padding: const EdgeInsets.all(8),
      child: Center(
        child: card.emoji != null
            ? LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
                final double s = (c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight) * 0.8;
                return EmojiImage(card.emoji!, size: s, semanticsLabel: card.label);
              })
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(card.text ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: PilasColors.tinta)),
              ),
      ),
    );
  }
}
