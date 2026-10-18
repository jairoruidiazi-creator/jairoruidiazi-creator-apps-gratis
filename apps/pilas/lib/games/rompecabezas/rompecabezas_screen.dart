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
import '../shell/game_frame.dart';
import '../shell/widgets.dart';

/// Pieza de encajar: una figura con color y tamaño.
class EncajePiece {
  const EncajePiece(this.id, this.kind, this.color, this.scale);

  final String id;
  final ShapeKind kind;
  final NamedColor color;
  final double scale;

  bool get pequena => scale < 1;

  /// "estrella pequeña", "círculo grande", "cuadrado".
  String nombre({bool conTamano = false}) {
    if (!conTamano) {
      return nombreForma(kind);
    }
    final bool f = generoForma(kind) == 'f';
    return '${nombreForma(kind)} ${pequena ? (f ? 'pequeña' : 'pequeño') : 'grande'}';
  }
}

/// Ronda de encajar: siluetas (en orden) y piezas en la bandeja (con distractores).
class EncajeRound {
  const EncajeRound({required this.targets, required this.tray, required this.descripcion, required this.porTamano});

  final List<EncajePiece> targets;
  final List<EncajePiece> tray;
  final String descripcion;

  /// Si hay figuras iguales en dos tamaños (hay que fijarse en el tamaño).
  final bool porTamano;

  /// Errores con los que el tablero todavía cuenta como bien resuelto.
  static const int erroresPermitidos = 1;

  /// Si [pieza] encaja en la silueta [silueta].
  static bool encaja(EncajePiece pieza, EncajePiece silueta) => pieza.kind == silueta.kind && pieza.scale == silueta.scale;

  static const List<ShapeKind> kinds = <ShapeKind>[ShapeKind.circle, ShapeKind.square, ShapeKind.triangle, ShapeKind.star, ShapeKind.heart, ShapeKind.hexagon, ShapeKind.rectangle, ShapeKind.oval];

  static EncajeRound generate(Rng rng, AgeBand band, int level) {
    // 3-4: 3, 4, 4 y 5 piezas; 5-6: 4, 5, 5 y 6. Siempre sobra alguna pieza
    // que no encaja: con dos piezas y sin sobrantes, tocar al azar daba el
    // tablero bien resuelto (un error como mucho) tres de cada cuatro veces.
    // Así, al azar se logra en menos del 6 % de los tableros y la regla de
    // dominio casi nunca sube de nivel (test/random_player_test.dart).
    final int n = band == AgeBand.b3a4 ? <int>[3, 4, 4, 5][level - 1] : <int>[4, 5, 5, 6][level - 1];
    final int distractores = band == AgeBand.b3a4 ? <int>[2, 1, 2, 2][level - 1] : (level >= 2 ? 2 : 1);
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
            targets.add(EncajePiece('t$i', k, rng.pick(NamedColor.basicos), sc));
            i += 1;
          }
        }
      }
      for (int d = 0; d < distractores; d++) {
        final ShapeKind k = rng.pick(kinds.where((ShapeKind x) => !ks.contains(x)).toList());
        extra.add(EncajePiece('d$d', k, rng.pick(NamedColor.basicos), 1.0));
      }
    } else {
      for (int i = 0; i < n; i++) {
        targets.add(EncajePiece('t$i', ks[i], rng.pick(NamedColor.basicos), 1.0));
      }
      for (int d = 0; d < distractores; d++) {
        extra.add(EncajePiece('d$d', ks[n + d], rng.pick(NamedColor.basicos), 1.0));
      }
    }
    final List<EncajePiece> tray = <EncajePiece>[...targets, ...extra];
    rng.shuffle(tray);
    return EncajeRound(targets: targets, tray: tray, porTamano: porTamano, descripcion: 'Pon cada figura en su silueta: tócala y luego toca la silueta, o arrástrala.');
  }
}

/// Una imagen para armar y los tamaños de rompecabezas en los que todas sus
/// fichas se ven distintas (revisado con test/rompecabezas_test.dart: ninguna
/// ficha vacía o igual a otra, para que no se vea armada sin estarlo).
class ImagenPuzzle {
  const ImagenPuzzle(this.emoji, this.nombre, this.tamanos);

  final String emoji;

  /// Con artículo: "un parque", "el planeta Tierra".
  final String nombre;
  final List<int> tamanos;
}

/// Rompecabezas de imagen: fichas de una imagen que se intercambian tocando dos.
class SwapPuzzle {
  SwapPuzzle({required this.n, required this.imagen, required this.order}) : minInicial = _minSwaps(order);

  final int n;
  final ImagenPuzzle imagen;

  /// order[pos] = índice de la ficha que está en esa posición.
  final List<int> order;

  /// Intercambios mínimos al empezar.
  final int minInicial;
  int swaps = 0;

  String get emoji => imagen.emoji;

  String get nombre => imagen.nombre;

  bool get solved {
    for (int i = 0; i < order.length; i++) {
      if (order[i] != i) {
        return false;
      }
    }
    return true;
  }

  /// Se resolvió con pocos movimientos de más.
  bool get eficiente => swaps <= minInicial + n;

  static const List<ImagenPuzzle> imagenes = <ImagenPuzzle>[
    ImagenPuzzle('1f3de', 'un parque', <int>[3, 4]),
    ImagenPuzzle('1f3a1', 'una rueda de Chicago', <int>[3, 4]),
    ImagenPuzzle('1f98b', 'una mariposa', <int>[3, 4, 5]),
    ImagenPuzzle('1f33b', 'un girasol', <int>[3, 4]),
    ImagenPuzzle('1f3af', 'un tiro al blanco', <int>[3, 4, 5]),
    ImagenPuzzle('1f682', 'una locomotora', <int>[3, 4]),
    ImagenPuzzle('1f304', 'un amanecer en las montañas', <int>[3, 4]),
    ImagenPuzzle('1f303', 'una noche estrellada', <int>[3, 4]),
    ImagenPuzzle('1f306', 'una ciudad al atardecer', <int>[3]),
    ImagenPuzzle('1f307', 'un atardecer en la ciudad', <int>[3, 4, 5]),
    ImagenPuzzle('1f309', 'un puente de noche', <int>[3, 4]),
    ImagenPuzzle('1f3dd', 'una isla', <int>[3]),
    ImagenPuzzle('1f3d5', 'un campamento', <int>[3, 4]),
    ImagenPuzzle('1f3df', 'un estadio', <int>[3, 4]),
    ImagenPuzzle('1f3e1', 'una casa con jardín', <int>[3, 4]),
    ImagenPuzzle('1f5fa', 'un mapa del mundo', <int>[3, 4]),
    ImagenPuzzle('1f3a8', 'una paleta de pintor', <int>[3, 4]),
    ImagenPuzzle('1f382', 'una torta de cumpleaños', <int>[3]),
    ImagenPuzzle('1f35f', 'unas papas fritas', <int>[3, 4]),
    ImagenPuzzle('1f30d', 'el planeta Tierra', <int>[3, 4]),
    ImagenPuzzle('1f31e', 'un sol sonriente', <int>[3, 4]),
    ImagenPuzzle('1f31d', 'una luna llena sonriente', <int>[3]),
    ImagenPuzzle('1f369', 'una dona', <int>[3, 4]),
    ImagenPuzzle('1f391', 'una noche de luna', <int>[3, 4]),
    ImagenPuzzle('1f3eb', 'un colegio', <int>[3, 4, 5]),
    ImagenPuzzle('1f3b2', 'un dado', <int>[3, 4]),
    ImagenPuzzle('26bd', 'un balón', <int>[3, 4, 5]),
    ImagenPuzzle('1f3d0', 'un balón de voleibol', <int>[3, 4]),
  ];

  static int sizeFor(AgeBand band, int level) {
    if (band == AgeBand.b7a8) {
      return level <= 2 ? 3 : 4;
    }
    return level == 1 ? 3 : (level <= 3 ? 4 : 5);
  }

  static SwapPuzzle generate(Rng rng, AgeBand band, int level) {
    final int n = sizeFor(band, level);
    final ImagenPuzzle img = rng.pick(imagenes.where((ImagenPuzzle i) => i.tamanos.contains(n)).toList());
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
    if (_minSwaps(order) == 0) {
      final int t = order[0];
      order[0] = order[1];
      order[1] = t;
    }
    return SwapPuzzle(n: n, imagen: img, order: order);
  }

  /// Intercambios mínimos: fichas − ciclos de la permutación.
  static int _minSwaps(List<int> order) {
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

  int get minSwaps => _minSwaps(order);
}

/// Rompecabezas: encajar siluetas (3 a 6 años) y armar imágenes
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
  String? _pieceSelected;
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
      _pieceSelected = null;
      _errors = 0;
      _selected = -1;
      if (_modoEncaje) {
        _encaje = EncajeRound.generate(_rng, widget.launch.band, _engine.level);
        _puzzle = null;
        _instruction = _encaje!.descripcion;
      } else {
        _puzzle = SwapPuzzle.generate(_rng, widget.launch.band, _engine.level);
        _encaje = null;
        _instruction = Es.contraer('Arma la imagen de ${_puzzle!.nombre}: toca dos fichas para intercambiarlas.');
      }
    });
    _engine.startRound();
    _engine.say(_instruction);
  }

  // ------------------------------------------------------------ encajar

  void _drop(EncajePiece target, EncajePiece piece) {
    final EncajeRound? r = _encaje;
    if (r == null || _placed.contains(target.id) || _engine.busy) {
      return;
    }
    final Services s = AppScope.read(context);
    final bool ok = EncajeRound.encaja(piece, target);
    setState(() => _pieceSelected = null);
    if (!ok) {
      _errors += 1;
      unawaited(s.sfx.play(SfxId.hint));
      final String porque = piece.kind == target.kind
          ? 'Es la misma figura, pero de otro tamaño.'
          : 'Mira los lados y las puntas: esa silueta es de ${Es.con(generoForma(target.kind), nombreForma(target.kind), definido: false)}.';
      s.voice.sayLater('Ahí no encaja. $porque');
      return;
    }
    unawaited(s.sfx.play(SfxId.pop));
    s.voice.sayLater('${Es.cap(piece.nombre(conTamano: r.porTamano))}.');
    setState(() => _placed.add(target.id));
    if (_placed.length == r.targets.length) {
      final bool bien = _errors <= EncajeRound.erroresPermitidos;
      unawaited(_engine.finishBoard(success: bien, message: bien ? '¡Todas las figuras en su lugar!' : '¡Lo lograste! Fíjate en las puntas, los lados y el tamaño antes de soltar la pieza.'));
    }
  }

  void _tapPiece(EncajePiece p) {
    if (_engine.busy) {
      return;
    }
    unawaited(AppScope.read(context).sfx.play(SfxId.tap));
    setState(() => _pieceSelected = _pieceSelected == p.id ? null : p.id);
    AppScope.read(context).voice.sayLater(p.nombre(conTamano: _encaje?.porTamano ?? false));
  }

  void _tapSilhouette(EncajePiece target) {
    final EncajeRound? r = _encaje;
    final String? sel = _pieceSelected;
    if (r == null || sel == null) {
      return;
    }
    final EncajePiece piece = r.tray.firstWhere((EncajePiece p) => p.id == sel);
    _drop(target, piece);
  }

  bool _pieceUsed(EncajeRound r, EncajePiece p) {
    // Una pieza queda usada si su silueta (la que encaja) ya está llena con
    // ella: las piezas de la bandeja y las siluetas se emparejan por forma y tamaño.
    for (final EncajePiece t in r.targets) {
      if (_placed.contains(t.id) && t.kind == p.kind && t.scale == p.scale) {
        final int usadas = r.targets.where((EncajePiece x) => _placed.contains(x.id) && x.kind == p.kind && x.scale == p.scale).length;
        final List<EncajePiece> iguales = r.tray.where((EncajePiece x) => x.kind == p.kind && x.scale == p.scale).toList();
        return iguales.indexOf(p) < usadas;
      }
    }
    return false;
  }

  Widget _buildEncaje(EncajeRound r) {
    final PilasPalette pal = PilasPalette.of(context);
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final bool wide = c.maxWidth > c.maxHeight * 1.2;
      final int n = r.targets.length;
      final double areaW = wide ? c.maxWidth * 0.55 : c.maxWidth;
      final double areaH = wide ? c.maxHeight : c.maxHeight * 0.55;
      final int perRow = n <= 3 ? n : ((n + 1) ~/ 2);
      final int rows = (n / perRow).ceil();
      final double size = math.min((areaW - 48 - (perRow - 1) * 14) / perRow, (areaH - 48 - (rows - 1) * 14) / rows).clamp(56.0, 130.0).toDouble();
      final Widget siluetas = Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: pal.tarjeta, borderRadius: BorderRadius.circular(Dim.radio), border: Border.all(color: pal.altoContraste ? pal.bordeFuerte : pal.borde, width: 2)),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: perRow * size + (perRow - 1) * 14,
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
                        return Semantics(
                          button: !done,
                          label: done ? '${t.nombre(conTamano: r.porTamano)}, en su lugar' : 'Silueta de ${Es.articulo(generoForma(t.kind), definido: false)} ${t.nombre(conTamano: r.porTamano)}',
                          excludeSemantics: true,
                          child: GestureDetector(
                            onTap: () => _tapSilhouette(t),
                            child: Container(
                              width: size,
                              height: size,
                              decoration: BoxDecoration(
                                color: cand.isNotEmpty || (_pieceSelected != null && !done) ? pal.pistaClaro : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: done
                                    ? ShapeIcon(kind: t.kind, color: t.color.color, size: size * 0.85 * t.scale, mark: t.color.mark)
                                    : CustomPaint(size: Size.square(size * 0.85 * t.scale), painter: ShapePainter(t.kind, pal.silueta, edge: pal.silueta)),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      final Widget bandeja = Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: math.max(areaW - 24, size),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  for (final EncajePiece p in r.tray)
                    if (!_pieceUsed(r, p))
                      Draggable<EncajePiece>(
                        data: p,
                        maxSimultaneousDrags: _engine.busy ? 0 : 1,
                        feedback: ShapeIcon(kind: p.kind, color: p.color.color, size: size * 0.85 * p.scale, mark: p.color.mark),
                        childWhenDragging: Opacity(opacity: 0.25, child: ShapeIcon(kind: p.kind, color: p.color.color, size: size * 0.85 * p.scale, mark: p.color.mark)),
                        child: Semantics(
                          button: true,
                          selected: _pieceSelected == p.id,
                          label: 'Pieza: ${p.nombre(conTamano: r.porTamano)}',
                          excludeSemantics: true,
                          child: GestureDetector(
                            onTap: () => _tapPiece(p),
                            child: Container(
                              width: math.max(size * 0.95, 56),
                              height: math.max(size * 0.95, 56),
                              decoration: BoxDecoration(
                                color: _pieceSelected == p.id ? pal.acentoClaro : Colors.transparent,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: _pieceSelected == p.id ? pal.acento : Colors.transparent, width: 3),
                              ),
                              child: Center(child: ShapeIcon(kind: p.kind, color: p.color.color, size: size * 0.85 * p.scale, mark: p.color.mark)),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      );
      if (wide) {
        return Row(children: <Widget>[Expanded(flex: 11, child: siluetas), Expanded(flex: 9, child: bandeja)]);
      }
      return Column(children: <Widget>[Expanded(flex: 11, child: siluetas), Expanded(flex: 9, child: bandeja)]);
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
      final bool bien = p.eficiente;
      unawaited(_engine.finishBoard(success: bien, message: bien ? Es.contraer('¡Armaste la imagen de ${p.nombre}!') : '¡Lo armaste! Antes de mover una ficha, piensa dónde debería quedar.'));
    }
  }

  Widget _buildPuzzle(SwapPuzzle p) {
    final PilasPalette pal = PilasPalette.of(context);
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final bool mostrarPie = c.maxHeight > 380;
      final double side = math.min(c.maxWidth - 24, c.maxHeight - 24 - (mostrarPie ? 56 : 0));
      final double tile = side / p.n;
      final Widget tablero = Container(
        key: ValueKey<String>('tablero-${p.n}x${p.n}'),
        width: side,
        height: side,
        decoration: BoxDecoration(color: pal.tarjeta, borderRadius: BorderRadius.circular(12), border: Border.all(color: pal.tinta, width: 3)),
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
                  child: Semantics(
                    button: true,
                    selected: _selected == pos,
                    label: 'Ficha en la fila ${pos ~/ p.n + 1}, columna ${pos % p.n + 1}${p.order[pos] == pos ? ', en su lugar' : ''}',
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () => _tapTile(pos),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: _selected == pos ? pal.acento : pal.borde, width: _selected == pos ? 4 : 1),
                          color: _selected == pos ? pal.acentoClaro : Colors.white,
                        ),
                        child: ClipRect(
                          child: Align(
                            alignment: Alignment(p.n == 1 ? 0 : -1 + 2 * (p.order[pos] % p.n) / (p.n - 1), p.n == 1 ? 0 : -1 + 2 * (p.order[pos] ~/ p.n) / (p.n - 1)),
                            widthFactor: 1 / p.n,
                            heightFactor: 1 / p.n,
                            child: EmojiImage(p.emoji, size: side > 8 ? side - 8 : 1),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            Expanded(child: Center(child: tablero)),
            if (mostrarPie) ...<Widget>[
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      EmojiImage(p.emoji, size: 44, semanticsLabel: 'Modelo: ${p.nombre}'),
                      const SizedBox(width: 12),
                      Text(p.swaps == 1 ? '1 cambio' : '${p.swaps} cambios', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.tintaSuave)),
                      if (widget.launch.band == AgeBand.b9a11) ...<Widget>[
                        const SizedBox(width: 12),
                        Text('Faltan al menos ${p.minSwaps}', style: TextStyle(fontSize: 16, color: pal.tintaSuave)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    });
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
