import 'package:flutter_test/flutter_test.dart';
import 'package:rutinas/logic/templates.dart';
import 'package:rutinas/logic/timer_engine.dart';
import 'package:rutinas/model/workout.dart';
import 'package:rutinas/ui/timer/timer_texts.dart';

final DateTime t0 = DateTime(2026, 10, 14, 7);

DateTime at(double seconds) => t0.add(Duration(milliseconds: (seconds * 1000).round()));

IntervalStep step(String name, int seconds, [StepKind kind = StepKind.work]) => IntervalStep(name: name, seconds: seconds, kind: kind);

TimerRun simple() => TimerRun(
      kind: RunKind.workout,
      name: 'Prueba',
      segments: TimerEngine.flatten(<TimerNode>[step('A', 10), step('B', 5, StepKind.rest), step('C', 20)]),
      startedAt: t0,
    );

void main() {
  group('Despliegue de bloques', () {
    test('las plantillas duran lo que dicen', () {
      final List<TimerSegment> hiit = TimerEngine.flatten(WorkoutTemplates.create(WorkoutTemplate.hiit, spanish: true, now: t0).nodes);
      expect(hiit.length, 22);
      expect(TimerEngine.totalSeconds(hiit), 940);
      final List<TimerSegment> tabata = TimerEngine.flatten(WorkoutTemplates.create(WorkoutTemplate.tabata, spanish: true, now: t0).nodes);
      expect(tabata.length, 64);
      expect(TimerEngine.totalSeconds(tabata), 1110);
      final List<TimerSegment> circuit = TimerEngine.flatten(WorkoutTemplates.create(WorkoutTemplate.circuit, spanish: false, now: t0).nodes);
      expect(circuit.length, 24);
      expect(TimerEngine.totalSeconds(circuit), 805);
      expect(circuit[1].name, 'Squats');
      final List<TimerSegment> custom = TimerEngine.flatten(WorkoutTemplates.create(WorkoutTemplate.custom, spanish: true, now: t0).nodes);
      expect(custom.map((TimerSegment s) => s.name).toList(), <String>['Prepárate', 'Trabajo']);
    });

    test('bloques anidados: series de rondas con su número', () {
      final Workout w = WorkoutTemplates.create(WorkoutTemplate.tabata, spanish: true, now: t0);
      expect(TimerEngine.depth(w.nodes), 2);
      final List<TimerSegment> segs = TimerEngine.flatten(w.nodes);
      // Segunda serie, tercera ronda, trabajo: prepárate (1) + serie 1 (16) + 4 intervalos.
      final TimerSegment s = segs[1 + 16 + 4];
      expect(s.kind, StepKind.work);
      expect(s.rounds.length, 2);
      expect(s.rounds[0].index, 2);
      expect(s.rounds[0].total, 4);
      expect(s.rounds[1].index, 3);
      expect(s.rounds[1].total, 8);
      expect(TimerTexts.rounds(s.rounds, true), 'Ronda 3 de 8 · Serie 2 de 4');
      expect(TimerTexts.rounds(s.rounds, false), 'Round 3 of 8 · Set 2 of 4');
      // La última ronda de cada serie no tiene su descanso corto: sigue el de 1 min.
      final TimerSegment lastWork = segs[1 + 14];
      expect(lastWork.kind, StepKind.work);
      expect(segs[1 + 15].seconds, 60);
      // El entrenamiento termina con trabajo, sin descansos al final.
      expect(segs.last.kind, StepKind.work);
    });

    test('omitir el último descanso se puede apagar', () {
      final List<TimerSegment> keep = TimerEngine.flatten(<TimerNode>[
        RepeatBlock(repeats: 3, skipLastRest: false, children: <TimerNode>[step('T', 20), step('D', 10, StepKind.rest)]),
      ]);
      expect(keep.length, 6);
      expect(keep.last.kind, StepKind.rest);
      final List<TimerSegment> skip = TimerEngine.flatten(<TimerNode>[
        RepeatBlock(repeats: 3, children: <TimerNode>[step('T', 20), step('D', 10, StepKind.rest)]),
      ]);
      expect(skip.length, 5);
      expect(TimerEngine.totalSeconds(skip), 80);
    });

    test('tres niveles de bloques y nombres propios de las vueltas', () {
      final List<TimerSegment> segs = TimerEngine.flatten(<TimerNode>[
        RepeatBlock(name: 'Bloque', repeats: 2, skipLastRest: false, children: <TimerNode>[
          RepeatBlock(repeats: 2, skipLastRest: false, children: <TimerNode>[
            RepeatBlock(name: 'Golpe', repeats: 3, skipLastRest: false, children: <TimerNode>[step('Golpe', 5)]),
          ]),
        ]),
      ]);
      expect(segs.length, 12);
      expect(segs.last.rounds.map((RoundInfo r) => r.index).toList(), <int>[2, 2, 3]);
      expect(TimerTexts.rounds(segs.last.rounds, true), 'Golpe 3 de 3 · Serie 2 de 2 · Bloque 2 de 2');
    });

    test('colores y sonidos por tipo cuando no se eligen', () {
      final List<TimerSegment> segs = TimerEngine.flatten(<TimerNode>[step('T', 10), step('D', 10, StepKind.rest), IntervalStep(name: 'X', seconds: 5, color: 0xFF6A1B9A, sound: CueSound.horn)]);
      expect(segs[0].color, defaultStepColor(StepKind.work));
      expect(segs[0].sound, CueSound.beep);
      expect(segs[1].sound, CueSound.bell);
      expect(segs[2].color, 0xFF6A1B9A);
      expect(segs[2].sound, CueSound.horn);
    });

    test('el entrenamiento viaja en JSON con sus bloques', () {
      final Workout w = WorkoutTemplates.create(WorkoutTemplate.tabata, spanish: true, now: t0)..finishSound = CueSound.bell;
      final Workout back = Workout.fromJson(w.toJson());
      expect(back.name, w.name);
      expect(back.finishSound, CueSound.bell);
      expect(TimerEngine.totalSeconds(TimerEngine.flatten(back.nodes)), 1110);
    });
  });

  group('Estado con el reloj', () {
    test('el intervalo sale del tiempo transcurrido', () {
      final TimerRun r = simple();
      RunSnapshot s = r.snapshot(t0);
      expect(s.index, 0);
      expect(s.segmentRemainingSeconds, 10);
      s = r.snapshot(at(9.5));
      expect(s.index, 0);
      expect(s.segmentRemainingSeconds, 1);
      s = r.snapshot(at(10));
      expect(s.index, 1);
      expect(s.segmentElapsedMs, 0);
      expect(s.totalRemainingSeconds, 25);
      s = r.snapshot(at(34.9));
      expect(s.index, 2);
      expect(s.finished, isFalse);
      s = r.snapshot(at(35));
      expect(s.finished, isTrue);
      expect(r.snapshot(at(1000)).finished, isTrue);
    });

    test('la pausa congela el tiempo y al seguir no se pierde nada', () {
      final TimerRun r = simple();
      r.pause(at(12));
      final RunSnapshot paused = r.snapshot(at(60));
      expect(paused.paused, isTrue);
      expect(paused.elapsedMs, 12000);
      expect(paused.index, 1);
      r.resume(at(60));
      expect(r.pausedMs, 48000);
      final RunSnapshot s = r.snapshot(at(63));
      expect(s.index, 2);
      expect(s.elapsedMs, 15000);
      expect(r.activeMs(at(63)), 15000);
      // Hora real a la que termina: inicio + 35 s + 48 s de pausa.
      expect(r.wallTimeOf(r.totalMs), at(83));
    });

    test('saltar al siguiente y volver al anterior', () {
      final TimerRun r = simple();
      r.next(at(3));
      expect(r.snapshot(at(3)).index, 1);
      expect(r.snapshot(at(3)).segmentElapsedMs, 0);
      // Recién empezado (menos de 2 s): vuelve al anterior.
      r.previous(at(4));
      expect(r.snapshot(at(4)).index, 0);
      expect(r.snapshot(at(4)).segmentElapsedMs, 0);
      // Ya avanzado: vuelve al inicio del actual.
      final RunSnapshot mid = r.snapshot(at(7));
      expect(mid.index, 0);
      r.previous(at(7));
      expect(r.snapshot(at(7)).segmentElapsedMs, 0);
      // El tiempo real en marcha no cambia con los saltos.
      expect(r.activeMs(at(7)), 7000);
    });

    test('saltar el último intervalo lo termina', () {
      final TimerRun r = simple();
      r.next(at(16)); // de C al final
      expect(r.snapshot(at(16)).finished, isTrue);
    });

    test('viaja en JSON', () {
      final TimerRun r = simple()
        ..pausedMs = 1500
        ..offsetMs = 2000;
      r.pause(at(20));
      final TimerRun back = TimerRun.fromJson(r.toJson())!;
      expect(back.segments.length, 3);
      expect(back.pausedMs, 1500);
      expect(back.offsetMs, 2000);
      expect(back.paused, isTrue);
      expect(back.snapshot(at(99)).elapsedMs, r.snapshot(at(99)).elapsedMs);
      expect(TimerRun.fromJson(<String, dynamic>{'segments': <dynamic>[]}), isNull);
    });
  });

  group('Avisos de voz y sonido', () {
    test('anuncia cada intervalo y cuenta 3, 2, 1 en los de 5 s o más', () {
      final TimerRun r = simple();
      final CueTracker c = CueTracker();
      final List<String> events = <String>[];
      for (double s = 0; s <= 36; s += 0.1) {
        events.addAll(c.update(r.snapshot(at(s))).map((CueEvent e) => e.toString()));
      }
      expect(events, <String>[
        'segmentStart:0:0',
        'countdown:0:3',
        'countdown:0:2',
        'countdown:0:1',
        'segmentStart:1:0',
        'countdown:1:3',
        'countdown:1:2',
        'countdown:1:1',
        'segmentStart:2:0',
        'countdown:2:3',
        'countdown:2:2',
        'countdown:2:1',
        'finished:0:0',
      ]);
    });

    test('los intervalos de menos de 5 s no tienen cuenta regresiva', () {
      final TimerRun r = TimerRun(kind: RunKind.workout, name: 'Corto', segments: TimerEngine.flatten(<TimerNode>[step('A', 4), step('B', 3)]), startedAt: t0);
      final CueTracker c = CueTracker();
      final List<CueType> types = <CueType>[];
      for (double s = 0; s <= 8; s += 0.1) {
        types.addAll(c.update(r.snapshot(at(s))).map((CueEvent e) => e.type));
      }
      expect(types, <CueType>[CueType.segmentStart, CueType.segmentStart, CueType.finished]);
    });

    test('al volver de segundo plano no suelta avisos atrasados', () {
      final TimerRun r = simple();
      final CueTracker c = CueTracker();
      c.update(r.snapshot(at(0)));
      // La app estuvo congelada del segundo 1 al 22.
      c.sync(r.snapshot(at(22)));
      expect(c.update(r.snapshot(at(22.1))), isEmpty);
      // Si se congela y el temporizador termina, tampoco anuncia el final.
      c.sync(r.snapshot(at(40)));
      expect(c.update(r.snapshot(at(40.1))), isEmpty);
    });

    test('en pausa no cuenta regresiva', () {
      final TimerRun r = simple();
      final CueTracker c = CueTracker();
      c.update(r.snapshot(at(0)));
      r.pause(at(7.5));
      expect(c.update(r.snapshot(at(30))).where((CueEvent e) => e.type == CueType.countdown), isEmpty);
    });
  });
}
