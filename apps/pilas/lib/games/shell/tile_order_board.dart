import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Una ficha que hay que colocar en orden.
class OrderTile {
  OrderTile({required this.id, required this.label, required this.build, String? value}) : value = value ?? id;

  final String id;

  /// Valor que se compara al colocar: dos fichas con la misma letra son
  /// intercambiables aunque tengan ids distintos.
  final String value;

  /// Nombre para la voz y la accesibilidad.
  final String label;
  final Widget Function(BuildContext context, double size) build;
  bool placed = false;
}

/// Tablero para ordenar fichas: letras de una palabra, palabras de una oración
/// o pasos de una rutina. Arriba están las casillas vacías y abajo las fichas
/// revueltas; el niño toca la ficha que va en la siguiente casilla.
///
/// Si toca la ficha equivocada, esta se sacude y se cuenta un error; el padre
/// decide qué pista dar a través de [onWrong]. Al completar, llama a
/// [onComplete] con el número de errores.
class TileOrderBoard extends StatefulWidget {
  const TileOrderBoard({
    super.key,
    required this.ordered,
    required this.shuffled,
    required this.onComplete,
    required this.onWrong,
    required this.onPlaced,
    this.tileSize = 64,
    this.slotLabels,
    this.separator,
    this.enabled = true,
  });

  /// Fichas en el orden correcto.
  final List<OrderTile> ordered;

  /// Las mismas fichas (más distractores si los hay) en el orden en que se muestran.
  final List<OrderTile> shuffled;
  final void Function(int errors) onComplete;
  final void Function(OrderTile tapped, OrderTile expected, int errors) onWrong;
  final void Function(OrderTile placed, int index) onPlaced;
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
  int _next = 0;
  int _errors = 0;
  String? _shaking;
  Timer? _shakeTimer;

  @override
  void didUpdateWidget(covariant TileOrderBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.ordered, widget.ordered)) {
      _next = 0;
      _errors = 0;
      _shaking = null;
    }
  }

  @override
  void dispose() {
    _shakeTimer?.cancel();
    super.dispose();
  }

  void _tap(OrderTile tile) {
    if (!widget.enabled || tile.placed || _next >= widget.ordered.length) {
      return;
    }
    final OrderTile expected = widget.ordered[_next];
    if (tile.value == expected.value) {
      setState(() {
        tile.placed = true;
        _next += 1;
      });
      widget.onPlaced(tile, _next - 1);
      if (_next >= widget.ordered.length) {
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
    widget.onWrong(tile, expected, _errors);
  }

  @override
  Widget build(BuildContext context) {
    final double s = widget.tileSize;
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      return SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          children: <Widget>[
            // Casillas
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Dim.radio),
                border: Border.all(color: PilasColors.borde, width: 2),
              ),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 8,
                children: <Widget>[
                  for (int i = 0; i < widget.ordered.length; i++) ...<Widget>[
                    if (i > 0 && widget.separator != null) widget.separator!,
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _Slot(
                          size: s,
                          active: i == _next,
                          child: i < _next ? widget.ordered[i].build(context, s * 0.8) : null,
                        ),
                        if (widget.slotLabels != null && i < widget.slotLabels!.length)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(widget.slotLabels![i], style: const TextStyle(fontSize: 12, color: PilasColors.tintaSuave, fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Fichas
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                for (final OrderTile t in widget.shuffled)
                  _Tile(
                    key: ValueKey<String>(t.id),
                    size: s,
                    placed: t.placed,
                    shaking: _shaking == t.id,
                    label: t.label,
                    onTap: () => _tap(t),
                    child: t.build(context, s * 0.8),
                  ),
              ],
            ),
          ],
        ),
      );
    });
  }
}

class _Slot extends StatelessWidget {
  const _Slot({required this.size, required this.active, this.child});

  final double size;
  final bool active;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: child != null ? PilasColors.verdeClaro : (active ? PilasColors.amarillo.withValues(alpha: 0.3) : PilasColors.fondo),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: child != null ? PilasColors.verde : (active ? PilasColors.naranja : PilasColors.borde), width: active ? 3 : 2),
      ),
      child: Center(child: child ?? (active ? Text('?', style: TextStyle(fontSize: size * 0.4, color: PilasColors.naranja, fontWeight: FontWeight.w800)) : null)),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.size, required this.placed, required this.shaking, required this.label, required this.onTap, required this.child});

  final double size;
  final bool placed;
  final bool shaking;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: !placed,
      label: label,
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
            color: placed ? PilasColors.fondo : Colors.white,
            borderRadius: BorderRadius.circular(16),
            elevation: placed ? 0 : 2,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: placed ? null : onTap,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: shaking ? PilasColors.rosa : PilasColors.borde, width: 2),
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
Widget textTile(String text, {double fontSize = 30, Color? color}) {
  return FittedBox(
    fit: BoxFit.scaleDown,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(text, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: color ?? PilasColors.tinta, fontFamily: 'Andika')),
    ),
  );
}
