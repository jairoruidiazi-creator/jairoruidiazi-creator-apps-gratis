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
        unawaited(_engine.finishBoard(
          success: ok,
          message: ok ? '¡Encontraste todas las parejas!' : 'Encontraste todas. La próxima vez intenta recordar dónde estaba cada carta.',
        ));
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

  /// Columnas que dejan las cartas más grandes en el espacio disponible.
  static int columnsFor(int n, double w, double h) {
    int best = 2;
    double bestSide = 0;
    for (int cols = 2; cols <= math.min(n, 8); cols++) {
      final int rows = (n / cols).ceil();
      final double cw = (w - (cols - 1) * 10) / cols;
      final double ch = (h - (rows - 1) * 10) / rows;
      final double side = math.min(cw, ch * 1.2);
      if (side > bestSide) {
        bestSide = side;
        best = cols;
      }
    }
    return best;
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
          : Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints c) {
                  final int n = board.cards.length;
                  final int cols = columnsFor(n, c.maxWidth, c.maxHeight);
                  final int rows = (n / cols).ceil();
                  final double cw = (c.maxWidth - (cols - 1) * 10) / cols - 0.5;
                  final double ch = math.min((c.maxHeight - (rows - 1) * 10) / rows - 0.5, cw * 1.35);
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      for (int r = 0; r < rows; r++) ...<Widget>[
                        if (r > 0) const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            for (int col = 0; col < cols && r * cols + col < n; col++) ...<Widget>[
                              if (col > 0) const SizedBox(width: 10),
                              SizedBox(
                                width: cw,
                                height: ch,
                                child: _CardView(
                                  key: ValueKey<String>('carta-${board.cards[r * cols + col].id}'),
                                  card: board.cards[r * cols + col],
                                  position: r * cols + col + 1,
                                  onTap: () => _tap(board.cards[r * cols + col]),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
    );
  }
}

class _CardView extends StatelessWidget {
  const _CardView({super.key, required this.card, required this.position, required this.onTap});

  final MemoryCard card;
  final int position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    final bool up = card.faceUp || card.matched;
    return Semantics(
      button: !card.matched,
      label: up ? 'Carta $position: ${card.label}${card.matched ? ', pareja encontrada' : ''}' : 'Carta $position, boca abajo',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: up ? 1 : 0),
          duration: const Duration(milliseconds: 260),
          builder: (BuildContext context, double t, Widget? _) {
            final bool showFront = t > 0.5;
            final double angle = t * math.pi;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(angle),
              child: showFront
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(math.pi),
                      child: _front(pal),
                    )
                  : _back(pal),
            );
          },
        ),
      ),
    );
  }

  Widget _back(PilasPalette pal) {
    return Container(
      decoration: BoxDecoration(
        color: pal.acento,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: pal.altoContraste ? pal.tinta : Colors.white, width: 3),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: const Center(child: FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: EdgeInsets.all(4), child: Mascot(size: 36)))),
    );
  }

  Widget _front(PilasPalette pal) {
    return Container(
      decoration: BoxDecoration(
        color: card.matched ? pal.correctoClaro : pal.tarjeta,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: card.matched ? pal.correcto : pal.bordeFuerte, width: 3),
      ),
      padding: const EdgeInsets.all(6),
      child: Center(
        child: card.emoji != null
            ? LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
                final double s = (c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight) * 0.85;
                return EmojiImage(card.emoji!, size: s, semanticsLabel: card.label);
              })
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(card.text ?? '', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: pal.tinta)),
              ),
      ),
    );
  }
}
