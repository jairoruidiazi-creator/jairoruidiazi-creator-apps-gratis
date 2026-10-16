import 'package:flutter/material.dart';

import '../../content/vocab.dart';
import '../../core/theme.dart';
import '../shell/widgets.dart';
import 'choice_round.dart';

/// Fábricas de opciones comunes.
class Opt {
  Opt._();

  static ChoiceOption emoji(String id, String code, String label, {bool showLabel = false}) {
    return ChoiceOption(
      id: id,
      label: label,
      build: (BuildContext context, double size) {
        if (!showLabel) {
          return EmojiImage(code, size: size, semanticsLabel: label);
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            EmojiImage(code, size: size * 0.8, semanticsLabel: label),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        );
      },
    );
  }

  static ChoiceOption vocab(VocabItem v, {bool showLabel = false, String? idPrefix}) {
    return emoji('${idPrefix ?? ''}${v.id}', v.emoji, v.nombre, showLabel: showLabel);
  }

  static ChoiceOption shape(String id, ShapeKind kind, Color color, String label) {
    return ChoiceOption(
      id: id,
      label: label,
      build: (BuildContext context, double size) => ShapeIcon(kind: kind, color: color, size: size),
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
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: PilasColors.tinta)),
        ),
      ),
    );
  }

  static ChoiceOption number(int n) => text('n$n', '$n', label: '$n');

  static ChoiceOption color(NamedColor c) {
    return ChoiceOption(
      id: 'color_${c.id}',
      label: c.nombre,
      build: (BuildContext context, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: c.color, shape: BoxShape.circle, border: Border.all(color: Colors.black.withValues(alpha: 0.2), width: 2)),
      ),
    );
  }

  /// Texto con un pictograma al lado (para los que leen poco).
  static ChoiceOption textWithEmoji(String id, String text, String code) {
    return ChoiceOption(
      id: id,
      label: text,
      build: (BuildContext context, double size) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          EmojiImage(code, size: size * 0.7, semanticsLabel: text),
          const SizedBox(height: 6),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Fila de pictogramas o figuras para mostrar una secuencia como estímulo.
class PromptRow extends StatelessWidget {
  const PromptRow({super.key, required this.children, this.size = 56});

  final List<Widget> children;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Dim.radio),
        border: Border.all(color: PilasColors.borde, width: 2),
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
    );
  }
}

/// Casilla con signo de interrogación para el elemento que falta.
class QuestionSlot extends StatelessWidget {
  const QuestionSlot({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: PilasColors.amarillo.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PilasColors.naranja, width: 2),
      ),
      child: Center(child: Text('?', style: TextStyle(fontSize: size * 0.6, fontWeight: FontWeight.w800, color: PilasColors.naranja))),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Dim.radio),
        border: Border.all(color: PilasColors.borde, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          child,
          if (caption != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(caption!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}
