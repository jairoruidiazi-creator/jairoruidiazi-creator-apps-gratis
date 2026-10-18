import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutinas/core/cues.dart';
import 'package:rutinas/core/dates.dart';
import 'package:rutinas/core/settings.dart';
import 'package:rutinas/core/storage.dart';
import 'package:rutinas/logic/templates.dart';
import 'package:rutinas/logic/timer_engine.dart';
import 'package:rutinas/model/habit.dart';
import 'package:rutinas/model/workout.dart';
import 'package:rutinas/state/habit_store.dart';
import 'package:rutinas/state/timer_controller.dart';
import 'package:rutinas/state/timer_store.dart';

import 'support/test_clock.dart';

final DateTime t0 = DateTime(2026, 10, 14, 7);

/// Sentadillas 10 s, descanso 5 s y flexiones 20 s: 35 s en total.
Workout sample() => Workout(
      id: 'w',
      name: 'Prueba',
      createdAt: t0,
      nodes: <TimerNode>[
        IntervalStep(name: 'Sentadillas', seconds: 10),
        IntervalStep(name: 'Descanso', seconds: 5, kind: StepKind.rest),
        IntervalStep(name: 'Flexiones', seconds: 20),
      ],
    );

class Rig {
  Rig(Directory dir) : store = JsonStore(root: dir) {
    habits = HabitStore(store)..load();
    timers = TimerStore(store)..load();
    controller = TimerController(store: timers, cues: cues, settings: settings, habits: habits, screen: screen);
  }

  final JsonStore store;
  final AppSettings settings = AppSettings();
  final SilentCuePlayer cues = SilentCuePlayer();
  final FakeScreenWake screen = FakeScreenWake();
  late final HabitStore habits;
  late final TimerStore timers;
  late final TimerController controller;

  void dispose() {
    controller.dispose();
    habits.dispose();
    timers.dispose();
  }
}

/// Prepara todo sobre una carpeta temporal, corre la prueba con el reloj
/// simulado desde [t0] y deja todo limpio (sin temporizadores pendientes).
Future<void> run(WidgetTester tester, Future<void> Function(Rig rig) body) async {
  final Directory dir = Directory.systemTemp.createTempSync('rutinas_timer');
  await withTestClock(t0, () async {
    final Rig rig = Rig(dir);
    try {
      await body(rig);
    } finally {
      rig.dispose();
    }
  });
  dir.deleteSync(recursive: true);
}

void main() {
  testWidgets('entrenamiento completo: voz, sonidos, vibración y registro', (WidgetTester tester) async {
    await run(tester, (Rig rig) async {
      expect(rig.controller.startWorkout(sample()), isTrue);
      expect(rig.screen.on, isTrue);
      await tester.pump(const Duration(seconds: 36));
      expect(rig.cues.log, <String>[
        'sound:beep', 'vibrate', 'speak:Sentadillas',
        'speak:3', 'speak:2', 'speak:1',
        'sound:bell', 'vibrate', 'speak:Descanso',
        'speak:3', 'speak:2', 'speak:1',
        'sound:beep', 'vibrate', 'speak:Último: Flexiones',
        'speak:3', 'speak:2', 'speak:1',
        'sound:gong', 'vibrate:strong', 'speak:¡Terminaste! Buen trabajo.',
      ]);
      expect(rig.controller.run, isNull);
      expect(rig.controller.finished!.seconds, 35);
      expect(rig.screen.on, isFalse);
      final WorkoutSession s = rig.timers.sessions.single;
      expect(s.completed, isTrue);
      expect(s.activeSeconds, 35);
      expect(s.workoutId, 'w');
      expect(s.endedAt, t0.add(const Duration(seconds: 35)));
    });
  });

  testWidgets('sin cuenta hablada suenan pitidos', (WidgetTester tester) async {
    await run(tester, (Rig rig) async {
      rig.settings.voiceCountdown = false;
      rig.controller.startWorkout(sample());
      await tester.pump(const Duration(seconds: 10));
      expect(rig.cues.log.where((String e) => e == 'pip'), hasLength(3));
      rig.controller.stop();
    });
  });

  testWidgets('la pausa congela el tiempo y apaga la pantalla', (WidgetTester tester) async {
    await run(tester, (Rig rig) async {
      rig.controller.startWorkout(sample());
      await tester.pump(const Duration(seconds: 3));
      rig.controller.pause();
      expect(rig.screen.on, isFalse);
      final int before = rig.cues.log.length;
      await tester.pump(const Duration(seconds: 60));
      expect(rig.cues.log.length, before);
      expect(rig.controller.snapshot!.elapsedMs, 3000);
      expect(rig.controller.snapshot!.paused, isTrue);
      rig.controller.resume();
      expect(rig.screen.on, isTrue);
      await tester.pump(const Duration(seconds: 33));
      final WorkoutSession s = rig.timers.sessions.single;
      expect(s.activeSeconds, 35);
      expect(s.endedAt, t0.add(const Duration(seconds: 95)));
    });
  });

  testWidgets('en segundo plano no suena nada y al volver no hay avisos atrasados', (WidgetTester tester) async {
    await run(tester, (Rig rig) async {
      rig.controller.startWorkout(sample());
      await tester.pump(const Duration(seconds: 1));
      rig.controller.setForeground(false);
      expect(rig.screen.on, isFalse);
      final int before = rig.cues.log.length;
      await tester.pump(const Duration(seconds: 20));
      expect(rig.cues.log.length, before);
      rig.controller.setForeground(true);
      expect(rig.screen.on, isTrue);
      expect(rig.controller.snapshot!.index, 2);
      await tester.pump(const Duration(milliseconds: 500));
      expect(rig.cues.log.length, before);
      // Sigue avisando desde donde va: la cuenta regresiva de las flexiones.
      await tester.pump(const Duration(seconds: 11));
      expect(rig.cues.log.sublist(before), <String>['speak:3']);
      rig.controller.stop();
      expect(rig.timers.sessions.single.completed, isFalse);
    });
  });

  testWidgets('saltar intervalos', (WidgetTester tester) async {
    await run(tester, (Rig rig) async {
      rig.controller.startWorkout(sample());
      await tester.pump(const Duration(seconds: 2));
      rig.controller.next();
      expect(rig.controller.snapshot!.index, 1);
      expect(rig.cues.log.last, 'speak:Descanso');
      rig.controller.previous();
      expect(rig.controller.snapshot!.index, 0);
      rig.controller.next();
      rig.controller.next();
      rig.controller.next();
      // Saltar el último lo termina.
      expect(rig.controller.run, isNull);
      expect(rig.controller.finished, isNotNull);
    });
  });

  testWidgets('el tiempo de un hábito se suma al día, aunque se detenga antes', (WidgetTester tester) async {
    await run(tester, (Rig rig) async {
      final Habit h = Habit(id: 'med', name: 'Meditar', kind: HabitKind.timed, goal: 600, startDate: t0, createdAt: t0);
      rig.habits.add(h);
      rig.controller.startHabit(h, 600);
      await tester.pump(const Duration(seconds: 601));
      expect(rig.habits.entry('med', t0)!.value, 600);
      expect(rig.cues.log, <String>['sound:bell', 'vibrate:strong', 'speak:Listo.']);
      rig.controller.startHabit(h, 600);
      await tester.pump(const Duration(seconds: 120));
      rig.controller.stop();
      expect(rig.habits.entry('med', t0)!.value, 720);
      expect(rig.timers.sessions, isEmpty);
    });
  });

  testWidgets('cuenta regresiva libre y reemplazo de un entrenamiento en marcha', (WidgetTester tester) async {
    await run(tester, (Rig rig) async {
      rig.controller.startWorkout(WorkoutTemplates.create(WorkoutTemplate.tabata, spanish: true, now: t0));
      await tester.pump(const Duration(seconds: 45));
      rig.controller.startCountdown(name: 'Té', seconds: 240);
      // El Tabata interrumpido queda en el historial con su tiempo.
      final WorkoutSession s = rig.timers.sessions.single;
      expect(s.completed, isFalse);
      expect(s.activeSeconds, 45);
      expect(rig.timers.lastCountdownSeconds, 240);
      rig.cues.log.clear();
      await tester.pump(const Duration(seconds: 241));
      expect(rig.cues.log, <String>['sound:gong', 'vibrate:strong', 'speak:Se acabó el tiempo.']);
      expect(rig.controller.finished!.kind, RunKind.countdown);
      expect(rig.timers.sessions, hasLength(1));
    });
  });

  testWidgets('al abrir la app sigue el temporizador o lo registra si terminó', (WidgetTester tester) async {
    await run(tester, (Rig rig) async {
      final List<TimerSegment> segs = TimerEngine.flatten(sample().nodes);
      // Empezó hace 12 s: va en el descanso.
      rig.timers.run = TimerRun(kind: RunKind.workout, refId: 'w', name: 'Prueba', segments: segs, startedAt: clock.now().subtract(const Duration(seconds: 12)));
      rig.controller.restore();
      expect(rig.controller.snapshot!.index, 1);
      expect(rig.cues.log, isEmpty);
      rig.controller.stop();
      // Terminó hace rato con la app cerrada: se registra a su hora de fin.
      final DateTime started = clock.now().subtract(const Duration(minutes: 5));
      rig.timers.run = TimerRun(kind: RunKind.workout, refId: 'w', name: 'Prueba', segments: segs, startedAt: started);
      rig.controller.restore();
      expect(rig.controller.run, isNull);
      expect(rig.controller.finished, isNotNull);
      final WorkoutSession done = rig.timers.sessions.last;
      expect(done.completed, isTrue);
      expect(done.endedAt, started.add(const Duration(seconds: 35)));
      expect(rig.cues.log, isEmpty);
      expect(dayKey(done.startedAt), '2026-10-14');
    });
  });

  testWidgets('los intervalos sin nombre se anuncian con su tipo, como en la pantalla (M17)', (WidgetTester tester) async {
    await run(tester, (Rig rig) async {
      final Workout w = Workout(id: 'sin', name: 'Sin nombres', createdAt: t0, nodes: <TimerNode>[
        IntervalStep(name: '', seconds: 4),
        IntervalStep(name: ' ', seconds: 4, kind: StepKind.rest),
      ]);
      expect(rig.controller.startWorkout(w), isTrue);
      await tester.pump(const Duration(seconds: 9));
      expect(rig.cues.log, contains('speak:Trabajo'));
      expect(rig.cues.log, contains('speak:Último: Descanso'));
      expect(rig.cues.log.where((String e) => e == 'speak:' || e == 'speak: '), isEmpty);
    });
  });

  testWidgets('la vibración usa el motor del teléfono y respeta el ajuste (M17)', (WidgetTester tester) async {
    final List<MethodCall> calls = <MethodCall>[];
    const MethodChannel channel = MethodChannel('rutinas/vibracion');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final AppSettings settings = AppSettings();
    final DeviceCuePlayer player = DeviceCuePlayer(settings);
    await player.vibrate();
    await player.vibrate(strong: true);
    expect(calls.map((MethodCall c) => c.method), <String>['vibrar', 'vibrar']);
    expect((calls.first.arguments as Map<Object?, Object?>)['ms'], 300);
    expect((calls.last.arguments as Map<Object?, Object?>)['ms'], 700);
    settings.vibration = false;
    await player.vibrate();
    expect(calls, hasLength(2));
  });
}
