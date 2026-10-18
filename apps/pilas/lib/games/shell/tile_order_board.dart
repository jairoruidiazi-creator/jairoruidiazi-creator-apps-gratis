import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Una ficha que hay que colocar en orden.
class OrderTile {
  OrderTile({required this.id, required this.label, required this.build, String? value, this.widthFactor = 1.0}) : value = value ?? id;

  final String id;

  /// Valor que se compara al colocar: dos fichas con el mismo valor (la misma
  /// letra) son intercambiables aunque tengan ids distintos.
  final String value;

  /// Nombre para la voz y la accesibilidad.
  final String label;
  final Widget Function(BuildContext context, double size) build;

  /// Ancho de la ficha respecto a su alto (una palabra larga es más ancha).
  final double widthFactor;
}

/// Qué valores pueden ir en la siguiente casilla, según los órdenes válidos y
/// lo que ya se colocó. Una oración o una rutina puede tener más de un orden
/// correcto; las letras repetidas de una palabra son intercambiables.
Set<String> allowedNextValues(List<List<String>> validOrders, List<String> placed) {
  final Set<String> out = <String>{};
  for (final List<String> order in validOrders) {
    if (order.length <= placed.length) {
      continue;
    }
    bool prefix = true;
    for (int i = 0; i < placed.length; i++) {
      if (order[i] != placed[i]) {
        prefix = false;
        break;
      }
    }
    if (prefix) {
      out.add(order[placed.length]);
    }
  }
  return out;
}

/// Tablero para ordenar fichas: letras de una palabra, palabras de una oración
/// o pasos de una rutina. Arriba están las casillas y abajo las fichas
/// revueltas; el niño toca la ficha que va en la siguiente casilla.
///
/// El tamaño de las fichas se calcula para que todo quepa sin desplazarse; si
/// aun así no cabe (texto muy grande en un teléfono acostado), el tablero
/// entero se achica.
class TileOrderBoard extends StatefulWidget {
  const TileOrderBoard({
    super.key,
    required this.validOrders,
    required this.shuffled,
    required this.onComplete,
    required this.onWrong,
    required this.onPlaced,
    this.tileSize = 64,
    this.slotLabels,
    this.separator,
    this.enabled = true,
  });

  /// Órdenes correctos, como listas de valores (el primero es el que se
  /// muestra al explicar).
  final List<List<String>> validOrders;

  /// Las fichas (más distractores si los hay) en el orden en que se muestran.
  final List<OrderTile> shuffled;
  final void Function(int errors) onComplete;
  final void Function(OrderTile tapped, int errors) onWrong;
  final void Function(OrderTile placed, int index) onPlaced;

  /// Alto preferido de las fichas.
  final double tileSize;

  /// Texto pequeño bajo cada casilla (por ejemplo, "1.º", "2.º").
  final List<String>? slotLabels;

  /// Widget entre casillas (por ejemplo una flecha para las rutinas).
  final Widget? separator;
  final bool enabled;

  @override
  State<TileOrderBoard> createState() => _TileOrderBoardState();
}

class _TileOrderBoardState extends State<TileOrderBoard> {
  final List<OrderTile> _slots = <OrderTile>[];
  int _errors = 0;
  String? _shaking;
  Timer? _shakeTimer;

  int get _slotCount => widget.validOrders.isEmpty ? 0 : widget.validOrders.first.length;

  @override
  void didUpdateWidget(covariant TileOrderBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.shuffled, widget.shuffled)) {
      _slots.clear();
      _errors = 0;
      _shaking = null;
    }
  }

  @override
  void dispose() {
    _shakeTimer?.cancel();
    super.dispose();
  }

  bool _isPlaced(OrderTile t) => _slots.any((OrderTile s) => identical(s, t));

  void _tap(OrderTile tile) {
    if (!widget.enabled || _isPlaced(tile) || _slots.length >= _slotCount) {
      return;
    }
    final Set<String> allowed = allowedNextValues(widget.validOrders, _slots.map((OrderTile t) => t.value).toList());
    if (allowed.contains(tile.value)) {
      setState(() => _slots.add(tile));
      widget.onPlaced(tile, _slots.length - 1);
      if (_slots.length >= _slotCount) {
        widget.onComplete(_errors);
      }
      return;
    }
    _errors += 1;
    setState(() => _shaking = tile.id);
    _shakeTimer?.cancel();
    _shakeTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) {
        setState(() => _shaking = null);
      }
    });
    widget.onWrong(tile, _errors);
  }

  double get _maxFactor {
    double f = 1;
    for (final OrderTile t in widget.shuffled) {
      f = math.max(f, t.widthFactor);
    }
    return f;
  }

  /// Alto total que ocupa el tablero con fichas de alto [s] en [width].
  double _heightFor(double s, double width) {
    final double inner = width - 24 - 20;
    final double slotW = s * _maxFactor;
    final double sep = widget.separator == null ? 0 : 26;
    final int perRow = math.max(1, ((inner + 6) / (slotW + 6 + sep)).floor());
    final int slotRows = (_slotCount / perRow).ceil();
    final double label = widget.slotLabels == null ? 0 : 18;
    double x = 0;
    int tileRows = 1;
    for (final OrderTile t in widget.shuffled) {
      final double w = s * t.widthFactor + 10;
      if (x + w > inner + 10 && x > 0) {
        tileRows += 1;
        x = 0;
      }
      x += w;
    }
    return 16 + 20 + slotRows * (s + label + 8) + 16 + tileRows * (s + 10);
  }

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final double width = c.maxWidth;
      final double height = c.hasBoundedHeight ? c.maxHeight : 2000;
      double s = widget.tileSize;
      while (s > 40 && _heightFor(s, width) > height) {
        s -= 2;
      }
      final Set<String> allowed = allowedNextValues(widget.validOrders, _slots.map((OrderTile t) => t.value).toList());
      final int next = _slots.length;
      final Widget board = SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: pal.tarjeta,
                  borderRadius: BorderRadius.circular(Dim.radio),
                  border: Border.all(color: pal.altoContraste ? pal.bordeFuerte : pal.borde, width: 2),
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 8,
                  children: <Widget>[
                    for (int i = 0; i < _slotCount; i++) ...<Widget>[
                      if (i > 0 && widget.separator != null) widget.separator!,
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _Slot(
                            width: s * _maxFactor,
                            height: s,
                            active: i == next,
                            label: i < _slots.length ? 'Casilla ${i + 1}: ${_slots[i].label}' : 'Casilla ${i + 1}, vacía',
                            child: i < _slots.length ? _slots[i].build(context, s * 0.8) : null,
                          ),
                          if (widget.slotLabels != null && i < widget.slotLabels!.length)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(widget.slotLabels![i], style: TextStyle(fontSize: 13, color: pal.tintaSuave, fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  for (final OrderTile t in widget.shuffled)
                    _Tile(
                      key: ValueKey<String>('ficha-${t.id}'),
                      width: s * t.widthFactor,
                      height: s,
                      placed: _isPlaced(t),
                      shaking: _shaking == t.id,
                      label: t.label,
                      onTap: () => _tap(t),
                      child: t.build(context, s * 0.8),
                    ),
                ],
              ),
              // Para lectores de pantalla: cuántas casillas quedan.
              Semantics(
                liveRegion: true,
                label: allowed.isEmpty ? 'Completo' : 'Faltan ${_slotCount - _slots.length}',
                child: const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
      return Center(child: FittedBox(fit: BoxFit.scaleDown, child: board));
    });
  }
}

class _Slot extends StatelessWidget {
  const _Slot({required this.width, required this.height, required this.active, required this.label, this.child});

  final double width;
  final double height;
  final bool active;
  final String label;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    final bool filled = child != null;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: filled ? pal.correctoClaro : (active ? pal.pistaClaro : pal.fondo),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: filled ? pal.correcto : (active ? pal.pista : pal.bordeFuerte), width: active ? 3 : 2),
        ),
        child: Center(child: child ?? (active ? Text('?', style: TextStyle(fontSize: height * 0.4, color: pal.pista, fontWeight: FontWeight.w800)) : null)),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.width, required this.height, required this.placed, required this.shaking, required this.label, required this.onTap, required this.child});

  final double width;
  final double height;
  final bool placed;
  final bool shaking;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    return Semantics(
      button: !placed,
      enabled: !placed,
      label: placed ? '$label, ya colocada' : label,
      excludeSemantics: true,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: placed ? 0.25 : 1,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: shaking ? 1 : 0),
          duration: const Duration(milliseconds: 450),
          builder: (BuildContext context, double t, Widget? c) {
            final double dx = shaking ? (8 * (1 - t) * ((t * 20).floor().isEven ? 1 : -1)) : 0;
            return Transform.translate(offset: Offset(dx, 0), child: c);
          },
          child: Material(
            color: placed ? pal.fondo : pal.tarjeta,
            borderRadius: BorderRadius.circular(16),
            elevation: placed ? 0 : 2,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: placed ? null : onTap,
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: shaking ? pal.error : (pal.altoContraste ? pal.bordeFuerte : pal.borde), width: shaking ? 3 : 2),
                ),
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ficha de texto (una letra o una palabra).
Widget textTile(BuildContext context, String text, {double fontSize = 30, Color? color}) {
  final PilasPalette pal = PilasPalette.of(context);
  return FittedBox(
    fit: BoxFit.scaleDown,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(text, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: color ?? pal.tinta, fontFamily: 'Andika')),
    ),
  );
}

/// Ancho relativo de una ficha con una palabra: aproximadamente lo que ocupa
/// el texto a 0,36 del alto de la ficha.
double wordWidthFactor(String word) => math.max(1.0, 0.36 * 0.62 * word.length + 0.45);
