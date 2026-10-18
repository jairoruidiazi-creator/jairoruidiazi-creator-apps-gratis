import 'dart:math';

import 'package:clock/clock.dart';

final Random _random = Random();
int _counter = 0;

/// Identificador corto y único: hora en base 36, un contador y algo de azar
/// (dos objetos creados en el mismo microsegundo no chocan).
String newId() {
  _counter = (_counter + 1) % 1296;
  final String time = clock.now().microsecondsSinceEpoch.toRadixString(36);
  final String count = _counter.toRadixString(36).padLeft(2, '0');
  final String noise = _random.nextInt(1 << 20).toRadixString(36).padLeft(4, '0');
  return '$time$count$noise';
}
