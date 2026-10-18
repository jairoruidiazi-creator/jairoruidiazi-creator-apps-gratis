import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/rng.dart';
import '../../core/sfx.dart';
import '../../engine/game_def.dart';
import '../../engine/round_engine.dart';
import '../../model/age_band.dart';
import '../choice/choice_body.dart';
import 'game_frame.dart';
import 'tile_order_board.dart';

/// Una ronda de ordenar fichas.
class OrderRound {
  const OrderRound({
    required this.instruction,
    required this.hint,
    required this.explain,
    required this.ordered,
    required this.shuffled,
    this.alternatives = const <List<String>>[],
    this.spoken,
    this.praise,
    this.prompt,
    this.tileSize = 64,
    this.slotLabels,
    this.separator,
    this.sayOnPlaced,
  });

  /// Texto que se muestra en la barra de instrucción.
  final String instruction;

  /// Lo que dice la voz (si es distinto de lo escrito, por ejemplo para no
  /// mostrar la palabra que hay que armar).
  final String? spoken;
  final String hint;
  final String explain;
  final String? praise;
  final WidgetBuilder? prompt;

  /// Fichas en el orden que se muestra al explicar.
  final List<OrderTile> ordered;

  /// Otros órdenes que también son correctos, como listas de valores.
  final List<List<String>> alternatives;
  final List<OrderTile> shuffled;
  final double tileSize;
  final List<String>? slotLabels;
  final Widget? separator;

  /// Qué decir al colocar cada ficha (por defecto, su etiqueta).
  final String Function(OrderTile tile, int index)? sayOnPlaced;

  /// Todos los órdenes válidos (el principal primero).
  List<List<String>> get validOrders => <List<String>>[
        <String>[for (final OrderTile t in ordered) t.value],
        ...alternatives,
      ];
}

typedef OrderRoundBuilder = OrderRound Function(Rng rng, AgeBand band, int level);

/// Pantalla genérica de los juegos de ordenar: arma la palabra, ordena la
/// oración y el tablero de rutinas.
class OrderGameScreen extends StatefulWidget {
  const OrderGameScreen({super.key, required this.launch, required this.builder});

  final GameLaunch launch;
  final OrderRoundBuilder builder;

  @override
  State<OrderGameScreen> createState() => _OrderGameScreenState();
}

class _OrderGameScreenState extends State<OrderGameScreen> {
  late final RoundEngine _engine;
  final Rng _rng = Rng();
  OrderRound? _round;
  bool _started = false;

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
    final OrderRound r = widget.builder(_rng, widget.launch.band, _engine.level);
    setState(() => _round = r);
    _engine.startRound();
    _engine.say(r.spoken ?? r.instruction);
  }

  void _onPlaced(OrderTile tile, int index) {
    final Services s = AppScope.read(context);
    unawaited(s.sfx.play(SfxId.tap));
    final OrderRound? r = _round;
    if (r == null) {
      return;
    }
    final String text = r.sayOnPlaced != null ? r.sayOnPlaced!(tile, index) : tile.label;
    if (text.isNotEmpty) {
      s.voice.sayLater(text);
    }
  }

  void _onWrong(OrderTile tapped, int errors) {
    final OrderRound? r = _round;
    if (r == null) {
      return;
    }
    unawaited(_engine.wrong(hint: r.hint, explain: r.explain));
  }

  void _onComplete(int errors) {
    final OrderRound? r = _round;
    if (r == null) {
      return;
    }
    unawaited(_engine.correct(praise: r.praise));
  }

  @override
  void dispose() {
    _engine.removeListener(_refresh);
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OrderRound? r = _round;
    return GameFrame(
      launch: widget.launch,
      engine: _engine,
      instruction: r?.instruction ?? '',
      onRepeat: r == null ? null : () => AppScope.read(context).voice.sayLater(r.spoken ?? r.instruction),
      child: r == null
          ? const SizedBox.shrink()
          : LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
              final Widget board = TileOrderBoard(
                key: ValueKey<int>(_engine.roundNumber),
                validOrders: r.validOrders,
                shuffled: r.shuffled,
                tileSize: r.tileSize,
                slotLabels: r.slotLabels,
                separator: r.separator,
                enabled: !_engine.busy,
                onPlaced: _onPlaced,
                onWrong: _onWrong,
                onComplete: _onComplete,
              );
              if (r.prompt == null) {
                return board;
              }
              final bool wide = c.maxWidth > c.maxHeight * 1.3;
              if (wide) {
                return Row(
                  children: <Widget>[
                    SizedBox(
                      width: c.maxWidth * 0.28,
                      child: Padding(padding: const EdgeInsets.fromLTRB(12, 4, 0, 12), child: Center(child: FitPrompt(builder: r.prompt!))),
                    ),
                    Expanded(child: board),
                  ],
                );
              }
              return Column(
                children: <Widget>[
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: c.maxHeight * 0.3),
                    child: Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: Center(child: FitPrompt(builder: r.prompt!))),
                  ),
                  Expanded(child: board),
                ],
              );
            }),
    );
  }
}
