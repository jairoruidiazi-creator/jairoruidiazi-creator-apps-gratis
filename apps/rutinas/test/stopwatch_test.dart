import 'package:flutter_test/flutter_test.dart';
import 'package:rutinas/core/dates.dart';
import 'package:rutinas/logic/stopwatch.dart';

final DateTime t0 = DateTime(2026, 10, 14, 7);

DateTime at(double seconds) => t0.add(Duration(milliseconds: (seconds * 1000).round()));

void main() {
  test('cuenta desde el arranque y la pausa congela el tiempo', () {
    final StopwatchState sw = StopwatchState();
    expect(sw.isZero, isTrue);
    sw.start(at(0));
    expect(sw.running, isTrue);
    expect(sw.elapsedMs(at(5)), 5000);
    // Arrancar de nuevo mientras corre no lo reinicia.
    sw.start(at(3));
    expect(sw.elapsedMs(at(5)), 5000);
    sw.pause(at(20));
    expect(sw.running, isFalse);
    expect(sw.elapsedMs(at(90)), 20000);
    sw.start(at(30));
    expect(sw.elapsedMs(at(31.5)), 21500);
    // Un reloj que va hacia atrás no resta tiempo.
    expect(sw.elapsedMs(at(29)), 20000);
  });

  test('vueltas con la más rápida y la más lenta', () {
    final StopwatchState sw = StopwatchState()..start(at(0));
    sw.lap(at(5));
    sw.lap(at(12));
    sw.lap(at(15));
    expect(sw.laps, <int>[5000, 12000, 15000]);
    expect(sw.lapDurations(), <int>[5000, 7000, 3000]);
    expect(sw.bestLap, 2);
    expect(sw.worstLap, 1);
    expect(sw.currentLapMs(at(16.25)), 1250);
    // En pausa no se marcan vueltas.
    sw.pause(at(17));
    sw.lap(at(18));
    expect(sw.laps, hasLength(3));
  });

  test('sin resaltar con una sola vuelta o con todas iguales', () {
    final StopwatchState one = StopwatchState()..start(at(0));
    one.lap(at(4));
    expect(one.bestLap, isNull);
    expect(one.worstLap, isNull);
    final StopwatchState same = StopwatchState()..start(at(0));
    same.lap(at(4));
    same.lap(at(8));
    expect(same.bestLap, isNull);
    expect(same.worstLap, isNull);
  });

  test('reiniciar lo deja en cero y viaja en JSON', () {
    final StopwatchState sw = StopwatchState()..start(at(0));
    sw.lap(at(61.37));
    final StopwatchState back = StopwatchState.fromJson(sw.toJson());
    expect(back.running, isTrue);
    expect(back.laps, <int>[61370]);
    expect(back.elapsedMs(at(70)), 70000);
    expect(formatStopwatch(back.laps.single), '1:01.37');
    sw.reset();
    expect(sw.isZero, isTrue);
    expect(StopwatchState.fromJson(sw.toJson()).isZero, isTrue);
  });

  test('formato del cronómetro', () {
    expect(formatStopwatch(0), '0:00.00');
    expect(formatStopwatch(65370), '1:05.37');
    expect(formatStopwatch(3725010), '1:02:05.01');
  });
}
