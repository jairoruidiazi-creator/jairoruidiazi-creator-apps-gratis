import 'package:flutter/material.dart';

import '../shell/widgets.dart';
import 'choice_round.dart';

typedef StatusOf = TileStatus Function(ChoiceOption option);
typedef OnOption = void Function(ChoiceOption option);

/// Cuerpo de una ronda de elegir: estímulo arriba y cuadrícula de opciones.
class ChoiceRoundBody extends StatelessWidget {
  const ChoiceRoundBody({super.key, required this.round, required this.statusOf, required this.onTap});

  final ChoiceRound round;
  final StatusOf statusOf;
  final OnOption onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
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
        final List<Widget> tiles = round.options.map((ChoiceOption o) {
          return OptionTile(
            status: statusOf(o),
            semanticsLabel: o.label,
            onTap: () => onTap(o),
            child: o.build(context, round.optionSize),
          );
        }).toList();
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
                child: GridView.count(
                  crossAxisCount: cols,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: _aspect(n, cols, c),
                  physics: const ClampingScrollPhysics(),
                  children: tiles,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  double _aspect(int n, int cols, BoxConstraints c) {
    final int rows = (n / cols).ceil();
    final double promptSpace = round.prompt == null ? 0 : 150;
    final double h = (c.maxHeight - promptSpace - 40) / rows - 14;
    final double w = (c.maxWidth - 32) / cols - 14;
    if (h <= 0 || w <= 0) {
      return 1;
    }
    final double a = w / h;
    return a.clamp(0.6, 2.4).toDouble();
  }
}
