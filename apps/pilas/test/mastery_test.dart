import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/engine/mastery.dart';
import 'package:pilas/ui/parent/family_guide_screen.dart';

void main() {
  group('Regla de elegir: 5 de 6 al primer intento', () {
    const MasteryRule r = MasteryRule.eleccion;

    test('cinco aciertos de seis suben de nivel', () {
      final MasteryState m = MasteryState();
      for (final bool ok in <bool>[true, true, false, true, true]) {
        expect(m.record(ok, 4, rule: r), MasteryEvent.none);
      }
      expect(m.record(true, 4, rule: r), MasteryEvent.levelUp);
      expect(m.level, 2);
      expect(m.recent, isEmpty);
      expect(m.levelsCompleted, 1);
    });

    test('cuatro de seis mantienen el nivel', () {
      final MasteryState m = MasteryState(level: 2);
      for (final bool ok in <bool>[true, false, true, true, false]) {
        m.record(ok, 4, rule: r);
      }
      expect(m.record(true, 4, rule: r), MasteryEvent.levelKept);
      expect(m.level, 2);
      expect(m.failStreak, 0);
    });

    test('dos ventanas seguidas con menos de tres aciertos bajan un nivel', () {
      final MasteryState m = MasteryState(level: 3);
      for (int i = 0; i < 5; i++) {
        m.record(false, 4, rule: r);
      }
      expect(m.record(true, 4, rule: r), MasteryEvent.levelKept);
      expect(m.failStreak, 1);
      for (int i = 0; i < 5; i++) {
        m.record(i == 0, 4, rule: r);
      }
      expect(m.record(false, 4, rule: r), MasteryEvent.levelDown);
      expect(m.level, 2);
    });

    test('no baja del nivel 1 ni sube del máximo', () {
      final MasteryState m = MasteryState();
      for (int i = 0; i < 18; i++) {
        m.record(false, 4, rule: r);
      }
      expect(m.level, 1);
      final MasteryState top = MasteryState(level: 4);
      for (int i = 0; i < 5; i++) {
        top.record(true, 4, rule: r);
      }
      expect(top.record(true, 4, rule: r), MasteryEvent.levelMastered);
      expect(top.level, 4);
      expect(MasteryEvent.levelMastered.completedLevel, isTrue);
      expect(MasteryEvent.levelKept.completedLevel, isFalse);
    });
  });

  test('Regla de ordenar y trazar: 4 de 5', () {
    final MasteryState m = MasteryState();
    for (final bool ok in <bool>[true, false, true, true]) {
      expect(m.record(ok, 4, rule: MasteryRule.ordenar), MasteryEvent.none);
    }
    expect(m.record(true, 4, rule: MasteryRule.ordenar), MasteryEvent.levelUp);
  });

  test('Regla de tableros: 2 de 3 resueltos con eficiencia', () {
    final MasteryState m = MasteryState();
    expect(m.record(true, 1, rule: MasteryRule.tablero), MasteryEvent.none);
    expect(m.record(false, 1, rule: MasteryRule.tablero), MasteryEvent.none);
    // Con un solo nivel, dominarlo es lograr la habilidad.
    expect(m.record(true, 1, rule: MasteryRule.tablero), MasteryEvent.levelMastered);
  });

  test('se guarda y se lee igual', () {
    final MasteryState m = MasteryState(level: 3, recent: <bool>[true, false], failStreak: 1, roundsPlayed: 20, roundsCorrect: 14, maxLevelReached: 3, levelsCompleted: 2);
    final MasteryState back = MasteryState.fromJson(m.toJson());
    expect(back.level, 3);
    expect(back.recent, <bool>[true, false]);
    expect(back.failStreak, 1);
    expect(back.roundsPlayed, 20);
    expect(back.roundsCorrect, 14);
    expect(back.levelsCompleted, 2);
  });

  test('La guía para familias explica las mismas reglas que usa la app', () {
    final String guia = FamilyGuideScreen.secciones.expand((GuideSection g) => g.parrafos).join(' ');
    expect(guia, contains('${MasteryRule.eleccion.toAdvance} aciertos al primer intento en ${MasteryRule.eleccion.window} rondas'));
    expect(guia, contains('${MasteryRule.ordenar.toAdvance} rondas sin errores de ${MasteryRule.ordenar.window}'));
    expect(guia, contains('${MasteryRule.tablero.toAdvance} tableros resueltos con eficiencia de ${MasteryRule.tablero.window}'));
    expect(guia, contains('descanso de 10 minutos'));
  });
}
