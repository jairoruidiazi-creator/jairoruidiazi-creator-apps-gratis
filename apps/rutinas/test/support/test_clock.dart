import 'package:clock/clock.dart';

/// Corre [body] con un reloj que empieza en [start] y avanza con el tiempo
/// simulado de testWidgets (cada `tester.pump(duración)` lo adelanta).
Future<T> withTestClock<T>(DateTime start, Future<T> Function() body) {
  final Clock outer = clock;
  final DateTime origin = outer.now();
  return withClock(Clock(() => start.add(outer.now().difference(origin))), body);
}
