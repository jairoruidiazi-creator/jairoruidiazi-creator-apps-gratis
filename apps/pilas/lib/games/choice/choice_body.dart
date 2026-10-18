import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../shell/widgets.dart';
import 'choice_round.dart';

typedef StatusOf = TileStatus Function(ChoiceOption option);
typedef OnOption = void Function(ChoiceOption option);

/// Cómo se reparten [count] opciones en un espacio: columnas, filas y tamaño
/// de cada casilla.
class OptionGridSpec {
  const OptionGridSpec({required this.cols, required this.rows, required this.tileWidth, required this.tileHeight});

  final int cols;
  final int rows;
  final double tileWidth;
  final double tileHeight;

  static const double gap = 12;

  /// Lado útil máximo de una casilla. Más grande no ayuda (el dibujo o el
  /// número no crecen) y en una tableta deja casillas enormes y huecos.
  static const double maxUseful = 260;

  /// Elige la cuadrícula que deja las casillas más grandes en [width] ×
  /// [height], con casillas de [maxUseful] como mucho. Una fila incompleta
  /// (por ejemplo 2 + 1 con tres opciones) solo se usa si es claramente
  /// mejor: deja huecos grandes. A igual tamaño gana la cuadrícula más pareja
  /// (2 × 2 antes que 1 × 4).
  static OptionGridSpec compute(int count, double width, double height, {double aspect = 1.0, int columns = 0}) {
    final int n = math.max(1, count);
    OptionGridSpec? best;
    double bestScore = -1;
    int bestShape = 1 << 30;
    for (int cols = 1; cols <= n; cols++) {
      if (columns > 0 && cols != columns) {
        continue;
      }
      final int rows = (n / cols).ceil();
      // Medio punto de margen: los redondeos no deben desbordar la fila.
      final double tw = (width - gap * (cols - 1)) / cols - 0.5;
      final double th = (height - gap * (rows - 1)) / rows - 0.5;
      if (tw <= 0 || th <= 0) {
        continue;
      }
      final double sinTope = math.min(tw / aspect, th);
      final double useful = math.min(sinTope, maxUseful);
      final int empty = rows * cols - n;
      final double score = useful * (empty == 0 ? 1.0 : 0.7);
      final int shape = (cols - rows).abs();
      if (score > bestScore + 0.5 || (score > bestScore - 0.5 && shape < bestShape)) {
        bestScore = math.max(score, bestScore);
        bestShape = shape;
        // Casillas no más altas de lo que su contenido aprovecha y, si se
        // llegó al tope, tampoco más anchas.
        final double h = math.min(th, math.max(Dim.tapMin, useful * 1.25 + 16));
        final double w = sinTope > maxUseful ? math.min(tw, math.max(Dim.tapMin, maxUseful * aspect * 1.25 + 16)) : tw;
        best = OptionGridSpec(cols: cols, rows: rows, tileWidth: w, tileHeight: h);
      }
    }
    return best ?? OptionGridSpec(cols: 1, rows: n, tileWidth: math.max(1, width), tileHeight: math.max(1, (height - gap * (n - 1)) / n));
  }
}

/// Envuelve un contenido para que nunca se salga de su casilla: se parte al
/// ancho disponible y, si aun así no cabe a lo alto, se achica.
class SafeFit extends StatelessWidget {
  const SafeFit({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      if (!c.hasBoundedWidth || !c.hasBoundedHeight) {
        return child;
      }
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: c.maxWidth), child: child),
      );
    });
  }
}

/// Estímulo que se achica para caber en el alto disponible sin salirse a lo
/// ancho.
class FitPrompt extends StatelessWidget {
  const FitPrompt({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final Widget child = builder(context);
      if (!c.hasBoundedWidth) {
        return child;
      }
      return FittedBox(fit: BoxFit.scaleDown, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: c.maxWidth), child: child));
    });
  }
}

/// Cuadrícula de opciones que llena exactamente su espacio: todas se ven y
/// se pueden tocar sin desplazarse.
class OptionGrid extends StatelessWidget {
  const OptionGrid({super.key, required this.round, required this.statusOf, required this.onTap});

  final ChoiceRound round;
  final StatusOf statusOf;
  final OnOption onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final List<ChoiceOption> options = round.options;
      final OptionGridSpec spec = OptionGridSpec.compute(options.length, c.maxWidth, c.maxHeight, aspect: round.optionAspect, columns: round.columns);
      final double content = math.max(24, math.min(round.optionSize, math.min(spec.tileWidth, spec.tileHeight) - 28));
      final List<Widget> rows = <Widget>[];
      for (int r = 0; r < spec.rows; r++) {
        final List<Widget> cells = <Widget>[];
        for (int col = 0; col < spec.cols; col++) {
          final int i = r * spec.cols + col;
          if (i >= options.length) {
            break;
          }
          final ChoiceOption o = options[i];
          if (cells.isNotEmpty) {
            cells.add(const SizedBox(width: OptionGridSpec.gap));
          }
          cells.add(SizedBox(
            width: spec.tileWidth,
            height: spec.tileHeight,
            child: OptionTile(
              key: ValueKey<String>('opcion-${o.id}'),
              status: statusOf(o),
              semanticsLabel: o.label,
              onTap: () => onTap(o),
              minHeight: 0,
              minWidth: 0,
              padding: EdgeInsets.all(spec.tileHeight < 90 ? 6 : 12),
              child: SafeFit(child: o.build(context, content)),
            ),
          ));
        }
        if (rows.isNotEmpty) {
          rows.add(const SizedBox(height: OptionGridSpec.gap));
        }
        rows.add(Row(mainAxisAlignment: MainAxisAlignment.center, children: cells));
      }
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: rows);
    });
  }
}

/// Cuerpo de una ronda de elegir: estímulo arriba (a la izquierda en apaisado)
/// y las opciones en el espacio que queda.
class ChoiceRoundBody extends StatelessWidget {
  const ChoiceRoundBody({super.key, required this.round, required this.statusOf, required this.onTap, this.footer});

  final ChoiceRound round;
  final StatusOf statusOf;
  final OnOption onTap;

  /// Algo debajo de las opciones (por ejemplo, el marcador de la carrera).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final Widget grid = OptionGrid(round: round, statusOf: statusOf, onTap: onTap);
        final bool wide = c.maxWidth > c.maxHeight * 1.15;
        final WidgetBuilder? prompt = round.prompt;
        Widget body;
        if (prompt != null && wide) {
          // Apaisado: la pregunta a la izquierda (achicada si no cabe) y las
          // opciones a la derecha.
          final double pw = (c.maxWidth - 36) * 0.45;
          body = Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: <Widget>[
                SizedBox(width: pw, child: Center(child: FitPrompt(builder: prompt))),
                const SizedBox(width: 12),
                Expanded(child: grid),
              ],
            ),
          );
        } else if (prompt != null) {
          // La pregunta usa lo que necesita, hasta casi la mitad del alto; las
          // opciones, el resto.
          final double maxPrompt = math.max(80, c.maxHeight * (round.options.length > 4 ? 0.42 : 0.48));
          body = Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Column(
              children: <Widget>[
                ConstrainedBox(constraints: BoxConstraints(maxHeight: maxPrompt), child: FitPrompt(builder: prompt)),
                const SizedBox(height: 12),
                Expanded(child: grid),
              ],
            ),
          );
        } else {
          body = Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 12), child: grid);
        }
        if (footer == null) {
          return body;
        }
        return Column(children: <Widget>[Expanded(child: body), footer!]);
      },
    );
  }
}
