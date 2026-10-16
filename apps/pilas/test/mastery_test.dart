import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/engine/mastery.dart';

void main() {
  group('MasteryState', () {
    test('tres aciertos de cuatro suben de nivel', () {
      final MasteryState m = MasteryState();
      expect(m.record(true, 4), MasteryEvent.none);
      expect(m.record(true, 4), MasteryEvent.none);
      expect(m.record(false, 4), MasteryEvent.none);
      expect(m.record(true, 4), MasteryEvent.levelUp);
      expect(m.level, 2);
      expect(m.recent, isEmpty);
      expect(m.levelsCompleted, 1);
    });

    test('dos aciertos mantienen el nivel', () {
      final MasteryState m = MasteryState(level: 2);
      m.record(true, 4);
      m.record(false, 4);
      m.record(true, 4);
      expect(m.record(false, 4), MasteryEvent.levelKept);
      expect(m.level, 2);
      expect(m.failStreak, 0);
    });

    test('dos ventanas seguidas con un acierto o menos bajan un nivel', () {
      final MasteryState m = MasteryState(level: 3);
      for (int i = 0; i < 3; i++) {
        m.record(false, 4);
      }
      expect(m.record(true, 4), MasteryEvent.levelKept);
      expect(m.failStreak, 1);
      for (int i = 0; i < 3; i++) {
        m.record(false, 4);
      }
      expect(m.record(false, 4), MasteryEvent.levelDown);
      expect(m.level, 2);
    });

    test('no baja del nivel 1 ni sube del máximo', () {
      final MasteryState m = MasteryState();
      for (int i = 0; i < 8; i++) {
        m.record(false, 4);
      }
      expect(m.level, 1);
      final MasteryState top = MasteryState(level: 4);
      for (int i = 0; i < 3; i++) {
        top.record(true, 4);
      }
      expect(top.record(true, 4), MasteryEvent.levelMastered);
      expect(top.level, 4);
      expect(MasteryEvent.levelMastered.completedLevel, isTrue);
      expect(MasteryEvent.levelKept.completedLevel, isFalse);
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
  });
}
