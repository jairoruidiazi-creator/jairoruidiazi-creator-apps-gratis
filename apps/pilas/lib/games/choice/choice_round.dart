import 'package:flutter/widgets.dart';

import '../../core/rng.dart';
import '../../model/age_band.dart';

typedef OptionBuilder = Widget Function(BuildContext context, double size);

/// Una opción para elegir: lo que se dibuja y cómo se nombra en voz alta.
class ChoiceOption {
  const ChoiceOption({required this.id, required this.label, required this.build});

  final String id;

  /// Nombre para la voz y la accesibilidad.
  final String label;
  final OptionBuilder build;
}

/// Una ronda de "elige la respuesta": instrucción, un estímulo opcional y
/// las opciones, con la pista y la explicación que usa el motor.
class ChoiceRound {
  const ChoiceRound({
    required this.instruction,
    required this.options,
    required this.correctId,
    required this.hint,
    required this.explain,
    this.prompt,
    this.praise,
    this.columns = 0,
    this.readOptionsAloud = false,
    this.optionSize = 96,
  });

  final String instruction;
  final List<ChoiceOption> options;
  final String correctId;
  final String hint;
  final String explain;

  /// Estímulo grande arriba de las opciones (una secuencia, una cara, una letra).
  final WidgetBuilder? prompt;
  final String? praise;

  /// Columnas de la cuadrícula; 0 = automático según el número de opciones.
  final int columns;

  /// Si la voz debe leer también las opciones (para los que no leen).
  final bool readOptionsAloud;

  /// Tamaño sugerido de los dibujos dentro de cada opción.
  final double optionSize;

  String get spokenInstruction {
    if (!readOptionsAloud) {
      return instruction;
    }
    final List<String> labels = options.map((ChoiceOption o) => o.label).toList();
    if (labels.isEmpty) {
      return instruction;
    }
    if (labels.length == 1) {
      return '$instruction ${labels.first}.';
    }
    final String last = labels.removeLast();
    return '$instruction ${labels.join(', ')} o $last.';
  }
}

/// Genera rondas para un tramo y un nivel.
abstract class ChoiceGenerator {
  ChoiceRound next(Rng rng, AgeBand band, int level);
}
