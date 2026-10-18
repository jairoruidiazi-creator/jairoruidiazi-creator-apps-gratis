import 'package:flutter/material.dart';

import '../../content/vocab.dart';
import '../../core/theme.dart';
import '../shell/widgets.dart';
import 'choice_round.dart';

/// Fábricas de opciones comunes. Todas se acomodan a la casilla que les toca:
/// el texto se parte al ancho y, si no cabe a lo alto, se achica.
class Opt {
  Opt._();

  static Widget _fitInTile(Widget content) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final Widget sized = c.hasBoundedWidth ? SizedBox(width: c.maxWidth, child: content) : content;
        return FittedBox(fit: BoxFit.scaleDown, child: sized);
      },
    );
  }

  static ChoiceOption emoji(String id, String code, String label, {bool showLabel = false}) {
    return ChoiceOption(
      id: id,
      label: label,
      build: (BuildContext context, double size) {
        if (!showLabel) {
          return EmojiImage(code, size: size, semanticsLabel: label);
        }
        final PilasPalette pal = PilasPalette.of(context);
        return _fitInTile(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              EmojiImage(code, size: size * 0.8, semanticsLabel: label),
              const SizedBox(height: 6),
              Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: pal.tinta)),
            ],
          ),
        );
      },
    );
  }

  static ChoiceOption vocab(VocabItem v, {bool showLabel = false, String? idPrefix}) {
    return emoji('${idPrefix ?? ''}${v.id}', v.emoji, v.nombre, showLabel: showLabel);
  }

  /// Figura de color. En alto contraste lleva la marca de su color, para no
  /// depender solo del color.
  static ChoiceOption shape(String id, ShapeKind kind, NamedColor color, String label) {
    return ChoiceOption(
      id: id,
      label: label,
      build: (BuildContext context, double size) => ShapeIcon(kind: kind, color: color.color, size: size, mark: color.mark),
    );
  }

  static ChoiceOption text(String id, String text, {double fontSize = 36, String? label}) {
    return ChoiceOption(
      id: id,
      label: label ?? text,
      build: (BuildContext context, double size) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: PilasPalette.of(context).tinta)),
        ),
      ),
    );
  }

  static ChoiceOption number(int n) => text('n$n', '$n', label: '$n');

  /// Texto largo que puede ocupar varias líneas (opciones de una frase).
  static ChoiceOption sentence(String id, String text, {double fontSize = 18}) {
    return ChoiceOption(
      id: id,
      label: text,
      build: (BuildContext context, double size) => _fitInTile(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: PilasPalette.of(context).tinta, height: 1.25)),
        ),
      ),
    );
  }

  static ChoiceOption color(NamedColor c) {
    return ChoiceOption(
      id: 'color_${c.id}',
      label: c.nombre,
      build: (BuildContext context, double size) => ShapeIcon(kind: ShapeKind.circle, color: c.color, size: size, mark: c.mark),
    );
  }

  /// Texto con un pictograma al lado (para los que leen poco).
  static ChoiceOption textWithEmoji(String id, String text, String code, {double fontSize = 17}) {
    return ChoiceOption(
      id: id,
      label: text,
      build: (BuildContext context, double size) => _fitInTile(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            EmojiImage(code, size: size * 0.7, semanticsLabel: text),
            const SizedBox(height: 6),
            Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: PilasPalette.of(context).tinta, height: 1.2)),
          ],
        ),
      ),
    );
  }
}

/// Fila de pictogramas o figuras para mostrar una secuencia como estímulo.
class PromptRow extends StatelessWidget {
  const PromptRow({super.key, required this.children, this.size = 56, this.semanticsLabel});

  final List<Widget> children;
  final double size;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: semanticsLabel != null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: pal.tarjeta,
          borderRadius: BorderRadius.circular(Dim.radio),
          border: Border.all(color: pal.altoContraste ? pal.bordeFuerte : pal.borde, width: 2),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int i = 0; i < children.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 10),
                SizedBox(width: size, height: size, child: Center(child: children[i])),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Casilla con signo de interrogación para el elemento que falta.
class QuestionSlot extends StatelessWidget {
  const QuestionSlot({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: pal.pistaClaro,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pal.pista, width: 2),
      ),
      child: Center(child: Text('?', style: TextStyle(fontSize: size * 0.6, fontWeight: FontWeight.w800, color: pal.pista))),
    );
  }
}

/// Estímulo grande centrado (una cara, una letra, un número).
class BigPrompt extends StatelessWidget {
  const BigPrompt({super.key, required this.child, this.caption});

  final Widget child;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pal.tarjeta,
        borderRadius: BorderRadius.circular(Dim.radio),
        border: Border.all(color: pal.altoContraste ? pal.bordeFuerte : pal.borde, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Lo que no cabe a lo ancho se achica en lugar de desbordar; los
          // Wrap ya se acomodan solos en varias líneas.
          if (child is Wrap) child else FittedBox(fit: BoxFit.scaleDown, child: child),
          if (caption != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(caption!, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: pal.tinta)),
          ],
        ],
      ),
    );
  }
}
