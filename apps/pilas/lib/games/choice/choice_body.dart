import 'package:flutter/material.dart';

import '../shell/widgets.dart';
import 'choice_round.dart';

typedef StatusOf = TileStatus Function(ChoiceOption option);
typedef OnOption = void Function(ChoiceOption option);

/// Cuerpo de una ronda de elegir: estímulo arriba (a la izquierda en apaisado)
/// y cuadrícula de opciones.
class ChoiceRoundBody extends StatelessWidget {
  const ChoiceRoundBody({super.key, required this.round, required this.statusOf, required this.onTap});

  final ChoiceRound round;
  final StatusOf statusOf;
  final OnOption onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final List<Widget> tiles = round.options.map((ChoiceOption o) {
          return OptionTile(
            status: statusOf(o),
            semanticsLabel: o.label,
            onTap: () => onTap(o),
            child: o.build(context, round.optionSize),
          );
        }).toList();
        final bool wide = c.maxWidth > c.maxHeight * 1.15;
        if (wide && round.prompt != null) {
          // Apaisado: la tarjeta de la pregunta a la izquierda (achicada si no
          // cabe a lo alto) y las opciones a la derecha, sin apretujarse.
          return Row(
            children: <Widget>[
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 16),
                  child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: round.prompt!(context))),
                ),
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 16, 16),
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints g) => _grid(tiles, g),
                  ),
                ),
              ),
            ],
          );
        }
        return Column(
          children: <Widget>[
            if (round.prompt != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: round.prompt!(context),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints g) => _grid(tiles, g),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Cuadrícula de opciones que llena el espacio que le queda.
  Widget _grid(List<Widget> tiles, BoxConstraints c) {
    final int n = round.options.length;
    int cols = round.columns;
    if (cols == 0) {
      if (c.maxWidth > c.maxHeight) {
        cols = n <= 4 ? n : (n <= 6 ? 3 : 4);
      } else {
        cols = n <= 4 ? 2 : (n <= 6 ? 2 : 3);
        if (n == 3 && c.maxWidth > 520) {
          cols = 3;
        }
      }
    }
    return GridView.count(
      crossAxisCount: cols,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: _aspect(n, cols, c),
      physics: const ClampingScrollPhysics(),
      children: tiles,
    );
  }

  /// Proporción de cada casilla para que todas quepan en [c] sin desplazarse.
  double _aspect(int n, int cols, BoxConstraints c) {
    final int rows = (n / cols).ceil();
    final double h = c.maxHeight / rows - 14;
    final double w = c.maxWidth / cols - 14;
    if (h <= 0 || w <= 0) {
      return 1;
    }
    final double a = w / h;
    return a.clamp(0.6, 2.4).toDouble();
  }
}
