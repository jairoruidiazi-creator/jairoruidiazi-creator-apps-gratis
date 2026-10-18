import 'package:flutter/widgets.dart';

import '../../core/es.dart';
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
    this.optionAspect = 1.0,
    this.spoken,
  });

  final String instruction;
  final List<ChoiceOption> options;
  final String correctId;
  final String hint;
  final String explain;

  /// Estímulo grande arriba de las opciones (una secuencia, una cara, una letra).
  final WidgetBuilder? prompt;
  final String? praise;

  /// Columnas de la cuadrícula; 0 = automático según el espacio.
  final int columns;

  /// Si la voz debe leer también las opciones (para los que no leen).
  final bool readOptionsAloud;

  /// Tamaño máximo de los dibujos dentro de cada opción.
  final double optionSize;

  /// Proporción preferida de cada casilla (ancho / alto): 1 para dibujos, más
  /// para frases.
  final double optionAspect;

  /// Lo que dice la voz si es distinto de lo escrito.
  final String? spoken;

  /// Con dos opciones no hay segunda oportunidad: se muestra la respuesta.
  bool get allowRetry => options.length >= 3;

  String get spokenInstruction {
    final String base = spoken ?? instruction;
    if (!readOptionsAloud) {
      return base;
    }
    return '$base ${Es.cap(listaDeOpciones(options.map((ChoiceOption o) => o.label).toList()))}';
  }

  /// "gato, perro o vaca." (con "u" delante de una palabra que suena con o).
  static String listaDeOpciones(List<String> labels) {
    if (labels.isEmpty) {
      return '';
    }
    if (labels.length == 1) {
      return '${labels.first}.';
    }
    final List<String> rest = List<String>.from(labels);
    final String last = rest.removeLast();
    return '${rest.join(', ')} ${Es.o(last)} $last.';
  }
}

/// Genera rondas para un tramo y un nivel.
abstract class ChoiceGenerator {
  ChoiceRound next(Rng rng, AgeBand band, int level);
}
