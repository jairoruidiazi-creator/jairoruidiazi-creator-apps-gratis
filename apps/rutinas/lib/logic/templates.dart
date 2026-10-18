import '../core/ids.dart';
import '../model/workout.dart';

/// Entrenamientos de partida: HIIT, Tabata, circuito y uno propio. Se crean
/// en el idioma de la app y luego se editan como cualquier otro.
class WorkoutTemplates {
  WorkoutTemplates._();

  static Workout create(WorkoutTemplate template, {required bool spanish, required DateTime now}) {
    String tr(String es, String en) => spanish ? es : en;
    IntervalStep step(String es, String en, int seconds, StepKind kind) => IntervalStep(name: tr(es, en), seconds: seconds, kind: kind);
    final IntervalStep prepare = step('Prepárate', 'Get ready', 10, StepKind.prepare);
    switch (template) {
      case WorkoutTemplate.hiit:
        return Workout(
          id: newId(),
          name: tr('HIIT 30/30', 'HIIT 30/30'),
          template: template,
          createdAt: now,
          nodes: <TimerNode>[
            prepare,
            step('Calentamiento', 'Warm-up', 180, StepKind.warmup),
            RepeatBlock(repeats: 10, children: <TimerNode>[
              step('Trabajo', 'Work', 30, StepKind.work),
              step('Descanso', 'Rest', 30, StepKind.rest),
            ]),
            step('Enfriamiento', 'Cool-down', 180, StepKind.cooldown),
          ],
        );
      case WorkoutTemplate.tabata:
        return Workout(
          id: newId(),
          name: tr('Tabata de 4 series', 'Tabata, 4 sets'),
          template: template,
          createdAt: now,
          nodes: <TimerNode>[
            prepare,
            RepeatBlock(repeats: 4, children: <TimerNode>[
              RepeatBlock(repeats: 8, children: <TimerNode>[
                step('Trabajo', 'Work', 20, StepKind.work),
                step('Descanso', 'Rest', 10, StepKind.rest),
              ]),
              step('Descanso entre series', 'Rest between sets', 60, StepKind.rest),
            ]),
          ],
        );
      case WorkoutTemplate.circuit:
        return Workout(
          id: newId(),
          name: tr('Circuito de 4 ejercicios', '4-exercise circuit'),
          template: template,
          createdAt: now,
          nodes: <TimerNode>[
            prepare,
            RepeatBlock(repeats: 3, children: <TimerNode>[
              step('Sentadillas', 'Squats', 45, StepKind.work),
              step('Descanso', 'Rest', 15, StepKind.rest),
              step('Flexiones', 'Push-ups', 45, StepKind.work),
              step('Descanso', 'Rest', 15, StepKind.rest),
              step('Zancadas', 'Lunges', 45, StepKind.work),
              step('Descanso', 'Rest', 15, StepKind.rest),
              step('Plancha', 'Plank', 45, StepKind.work),
              step('Descanso entre rondas', 'Rest between rounds', 60, StepKind.rest),
            ]),
          ],
        );
      case WorkoutTemplate.custom:
        return Workout(
          id: newId(),
          name: tr('Mi entrenamiento', 'My workout'),
          template: template,
          createdAt: now,
          nodes: <TimerNode>[
            prepare,
            step('Trabajo', 'Work', 60, StepKind.work),
          ],
        );
    }
  }
}
