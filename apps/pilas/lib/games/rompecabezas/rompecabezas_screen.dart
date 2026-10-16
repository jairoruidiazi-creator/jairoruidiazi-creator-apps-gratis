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

/// Pieza de encajar: una figura con color y tamaño.
class EncajePiece {
  const EncajePiece(this.id, this.kind, this.color, this.scale, this.nombre);

  final String id;
  final ShapeKind kind;
  final NamedColor color;
  final double scale;
  final String nombre;
}

/// Ronda de encajar: siluetas (en orden) y piezas en la bandeja (con distractores).
class EncajeRound {
  const EncajeRound({required this.targets, required this.tray, required this.descripcion});

  final List<EncajePiece> targets;
  final List<EncajePiece> tray;
  final String descripcion;

  static const List<ShapeKind> kinds = <ShapeKind>[ShapeKind.circle, ShapeKind.square, ShapeKind.triangle, ShapeKind.star, ShapeKind.heart, ShapeKind.hexagon, ShapeKind.rectangle, ShapeKind.oval];

  static EncajeRound generate(Rng rng, AgeBand band, int level) {
    // 3-4: 2, 3, 3, 4 piezas; 5-6: 4, 5, 5, 6, con distractores desde el nivel 2.
    final int n = band == AgeBand.b3a4 ? <int>[2, 3, 3, 4][level - 1] : <int>[4, 5, 5, 6][level - 1];
    final int distractores = band == AgeBand.b3a4 ? (level >= 3 ? 1 : 0) : (level >= 2 ? 2 : 1);
    final bool porTamano = band != AgeBand.b3a4 && level >= 3;
    final List<ShapeKind> ks = rng.sample(kinds, porTamano ? (n / 2).ceil() : n + distractores);
    final List<EncajePiece> targets = <EncajePiece>[];
    final List<EncajePiece> extra = <EncajePiece>[];
    if (porTamano) {
      // La misma figura en dos tamaños: hay que fijarse en el tamaño.
      int i = 0;
      for (final ShapeKind k in ks) {
        for (final double sc in <double>[1.0, 0.62]) {
          if (targets.length < n) {
            final NamedColor c = rng.pick(NamedColor.basicos);
            targets.add(EncajePiece('t$i', k, c, sc, '${nombreForma(k)} ${sc < 1 ? 'pequeño' : 'grande'}'));
            i += 1;
          }
        }
      }
      for (int d = 0; d < distractores; d++) {
        final ShapeKind k = rng.pick(kinds.where((ShapeKind x) => !ks.contains(x)).toList());
        extra.add(EncajePiece('d$d', k, rng.pick(NamedColor.basicos), 1.0, nombreForma(k)));
      }
    } else {
      for (int i = 0; i < n; i++) {
        final ShapeKind k = ks[i];
        targets.add(EncajePiece('t$i', k, rng.pick(NamedColor.basicos), 1.0, nombreForma(k)));
      }
      for (int d = 0; d < distractores; d++) {
        final ShapeKind k = ks[n + d];
        extra.add(EncajePiece('d$d', k, rng.pick(NamedColor.basicos), 1.0, nombreForma(k)));
      }
    }
    final List<EncajePiece> tray = <EncajePiece>[...targets, ...extra];
    rng.shuffle(tray);
    return EncajeRound(targets: targets, tray: tray, descripcion: 'Arrastra cada figura hasta su silueta.');
  }
}

/// Rompecabezas de imagen: fichas de una imagen que se intercambian tocando dos.
class SwapPuzzle {
  SwapPuzzle({required this.n, required this.emoji, required this.nombre, required this.order});

  final int n;
  final String emoji;
  final String nombre;

  /// order[pos] = índice de la ficha que está en esa posición.
  final List<int> order;
  int swaps = 0;

  bool get solved {
    for (int i = 0; i < order.length; i++) {
      if (order[i] != i) {
        return false;
      }
    }
    return true;
  }

  static const List<List<String>> imagenes = <List<String>>[
    <String>['1f3de', 'un parque'],
    <String>['1f305', 'un amanecer'],
    <String>['1f3d6', 'una playa'],
    <String>['1f30b', 'un volcán'],
    <String>['1f3a1', 'una rueda de Chicago'],
    <String>['1f6a2', 'un barco'],
    <String>['1f981', 'un león'],
    <String>['1f98b', 'una mariposa'],
    <String>['1f33b', 'un girasol'],
    <String>['1f308', 'un arcoíris'],
    <String>['1f3e0', 'una casa'],
    <String>['1f69c', 'un tractor'],
    <String>['1f419', 'un pulpo'],
    <String>['1f99c', 'una guacamaya'],
    <String>['1f3af', 'una diana'],
    <String>['1f682', 'un tren'],
  ];

  static int sizeFor(AgeBand band, int level) {
    if (band == AgeBand.b7a8) {
      return level <= 2 ? 3 : 4;
    }
    return level == 1 ? 3 : (level <= 3 ? 4 : 5);
  }

  static SwapPuzzle generate(Rng rng, AgeBand band, int level) {
    final int n = sizeFor(band, level);
    final List<String> img = rng.pick(imagenes);
    final List<int> order = <int>[for (int i = 0; i < n * n; i++) i];
    // Mezcla con un número limitado de intercambios para que sea resoluble en pocos pasos.
    final int mezclas = level <= 1 ? n + 1 : n * 2 + level;
    for (int k = 0; k < mezclas; k++) {
      final int a = rng.nextInt(order.length);
      final int b = rng.nextInt(order.length);
      final int t = order[a];
      order[a] = order[b];
      order[b] = t;
    }
    if (order.every((int v) => order.indexOf(v) == v)) {
      final int t = order[0];
      order[0] = order[1];
      order[1] = t;
    }
    return SwapPuzzle(n: n, emoji: img[0], nombre: img[1], order: order);
  }

  /// Intercambios mínimos: n − ciclos de la permutación.
  int get minSwaps {
    final List<bool> seen = List<bool>.filled(order.length, false);
    int cycles = 0;
    for (int i = 0; i < order.length; i++) {
      if (seen[i]) {
        continue;
      }
      cycles += 1;
      int j = i;
      while (!seen[j]) {
        seen[j] = true;
        j = order[j];
      }
    }
    return order.length - cycles;
  }
}

/// Tangram y rompecabezas: encajar siluetas (3 a 6 años) y armar imágenes
/// intercambiando fichas (primaria).
class RompecabezasScreen extends StatefulWidget {
  const RompecabezasScreen({super.key, required this.launch});

  final GameLaunch launch;

  @override
  State<RompecabezasScreen> createState() => _RompecabezasScreenState();
}

class _RompecabezasScreenState extends State<RompecabezasScreen> {
  late final RoundEngine _engine;
  final Rng _rng = Rng();
  EncajeRound? _encaje;
  SwapPuzzle? _puzzle;
  final Set<String> _placed = <String>{};
  int _errors = 0;
  int _selected = -1;
  bool _started = false;
  String _instruction = '';

  bool get _modoEncaje => widget.launch.band == AgeBand.b3a4 || widget.launch.band == AgeBand.b5a6;

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
    setState(() {
      _placed.clear();
      _errors = 0;
      _selected = -1;
      if (_modoEncaje) {
        _encaje = EncajeRound.generate(_rng, widget.launch.band, _engine.level);
        _puzzle = null;
        _instruction = _encaje!.descripcion;
      } else {
        _puzzle = SwapPuzzle.generate(_rng, widget.launch.band, _engine.level);
        _encaje = null;
        _instruction = 'Arma la imagen de ${_puzzle!.nombre}: toca dos fichas para intercambiarlas.';
      }
    });
    _engine.startRound();
    _engine.say(_instruction);
  }

  // ------------------------------------------------------------ encajar

  void _drop(EncajePiece target, EncajePiece piece) {
    final Services s = AppScope.read(context);
    final bool ok = piece.kind == target.kind && piece.scale == target.scale;
    if (!ok) {
      _errors += 1;
      unawaited(s.sfx.play(SfxId.hint));
      final String porque = piece.kind == target.kind ? 'Es la misma figura pero de otro tamaño.' : 'Mira los lados y las puntas: esa silueta es de ${target.nombre}.';
      s.voice.sayLater('Ahí no encaja. $porque');
      return;
    }
    unawaited(s.sfx.play(SfxId.pop));
    s.voice.sayLater('${_cap(piece.nombre)}.');
    setState(() => _placed.add(piece.id));
    if (_placed.length == _encaje!.targets.length) {
      final bool bien = _errors <= 1;
      _engine.finishBoard(success: bien, message: bien ? '¡Todas las figuras en su lugar!' : '¡Lo lograste! Fíjate en las puntas y los lados antes de soltar la pieza.');
    }
  }

  String _cap(String t) => t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);

  Widget _buildEncaje(EncajeRound r) {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final int n = r.targets.length;
      final double maxW = (c.maxWidth - 32) / (n <= 3 ? n : ((n + 1) ~/ 2));
      final double size = maxW.clamp(64.0, 120.0).toDouble();
      return Column(
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Dim.radio), border: Border.all(color: PilasColors.borde, width: 2)),
              child: Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 14,
                  runSpacing: 14,
                  children: <Widget>[
                    for (final EncajePiece t in r.targets)
                      DragTarget<EncajePiece>(
                        onWillAcceptWithDetails: (DragTargetDetails<EncajePiece> d) => !_placed.contains(t.id),
                        onAcceptWithDetails: (DragTargetDetails<EncajePiece> d) => _drop(t, d.data),
                        builder: (BuildContext context, List<EncajePiece?> cand, List<dynamic> rej) {
                          final bool done = _placed.contains(t.id);
                          return Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              color: cand.isNotEmpty ? PilasColors.amarillo.withValues(alpha: 0.25) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: done
                                  ? ShapeIcon(kind: t.kind, color: t.color.color, size: size * 0.85 * t.scale)
                                  : ShapeIcon(kind: t.kind, color: const Color(0xFFCFCAC0), size: size * 0.85 * t.scale),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    for (final EncajePiece p in r.tray)
                      if (!_placed.contains(p.id))
                        Draggable<EncajePiece>(
                          data: p,
                          maxSimultaneousDrags: _engine.busy ? 0 : 1,
                          feedback: ShapeIcon(kind: p.kind, color: p.color.color, size: size * 0.85 * p.scale),
                          childWhenDragging: Opacity(opacity: 0.25, child: ShapeIcon(kind: p.kind, color: p.color.color, size: size * 0.85 * p.scale)),
                          child: Semantics(
                            label: p.nombre,
                            child: SizedBox(
                              width: size * 0.9,
                              height: size * 0.9,
                              child: Center(child: ShapeIcon(kind: p.kind, color: p.color.color, size: size * 0.85 * p.scale)),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  // ------------------------------------------------------------ intercambio

  void _tapTile(int pos) {
    final SwapPuzzle? p = _puzzle;
    if (p == null || _engine.busy) {
      return;
    }
    final Services s = AppScope.read(context);
    if (_selected < 0) {
      unawaited(s.sfx.play(SfxId.tap));
      setState(() => _selected = pos);
      return;
    }
    if (_selected == pos) {
      setState(() => _selected = -1);
      return;
    }
    unawaited(s.sfx.play(SfxId.pop));
    setState(() {
      final int t = p.order[pos];
      p.order[pos] = p.order[_selected];
      p.order[_selected] = t;
      p.swaps += 1;
      _selected = -1;
    });
    if (p.solved) {
      final bool bien = p.swaps <= p.n * p.n;
      _engine.finishBoard(success: bien, message: bien ? '¡Armaste ${p.nombre}!' : '¡Lo armaste! Antes de mover una ficha, piensa dónde debería quedar.');
    }
  }

  Widget _buildPuzzle(SwapPuzzle p) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: <Widget>[
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
                  final double side = c.maxWidth;
                  final double tile = side / p.n;
                  return Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: PilasColors.tinta, width: 3)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Stack(
                        children: <Widget>[
                          for (int pos = 0; pos < p.order.length; pos++)
                            Positioned(
                              left: (pos % p.n) * tile,
                              top: (pos ~/ p.n) * tile,
                              width: tile,
                              height: tile,
                              child: GestureDetector(
                                onTap: () => _tapTile(pos),
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: _selected == pos ? PilasColors.naranja : PilasColors.borde, width: _selected == pos ? 4 : 1),
                                    color: _selected == pos ? PilasColors.amarillo.withValues(alpha: 0.3) : Colors.white,
                                  ),
                                  child: ClipRect(
                                    child: Align(
                                      alignment: Alignment(p.n == 1 ? 0 : -1 + 2 * (p.order[pos] % p.n) / (p.n - 1), p.n == 1 ? 0 : -1 + 2 * (p.order[pos] ~/ p.n) / (p.n - 1)),
                                      widthFactor: 1 / p.n,
                                      heightFactor: 1 / p.n,
                                      child: EmojiImage(p.emoji, size: side - 8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
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
              EmojiImage(p.emoji, size: 44),
              const SizedBox(width: 12),
              Text('${p.swaps} cambios', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: PilasColors.tintaSuave)),
              if (widget.launch.band == AgeBand.b9a11) ...<Widget>[
                const SizedBox(width: 12),
                Text('Faltan al menos ${p.minSwaps}', style: const TextStyle(fontSize: 16, color: PilasColors.tintaSuave)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _engine.removeListener(_refresh);
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameFrame(
      launch: widget.launch,
      engine: _engine,
      instruction: _instruction,
      child: _encaje != null ? _buildEncaje(_encaje!) : (_puzzle != null ? _buildPuzzle(_puzzle!) : const SizedBox.shrink()),
    );
  }
}
