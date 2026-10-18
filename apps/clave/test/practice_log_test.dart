// Registro de práctica (B3, M12, G10): intervalos por herramienta con reloj
// simulado, unión de herramientas, medianoche, racha y guardado.

import 'dart:io';

import 'package:clave/core/practice_log.dart';
import 'package:clave/core/storage.dart';
import 'package:clave/model/models.dart';
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('clave_practice');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {
      // Una escritura en curso de una prueba con tiempo simulado.
    }
  });

  PracticeLog newLog() => PracticeLog(JsonStore(root: tmp));

  test('El metrónomo cuenta mientras corre, aunque no se toque la pantalla (B3)', () {
    fakeAsync((FakeAsync async) {
      final PracticeLog log = newLog();
      final DateTime t0 = clock.now();
      log.start('metronomo', 'guitarra');
      async.elapse(const Duration(minutes: 10));
      expect(log.secondsBetween(t0, clock.now()), 600, reason: 'en curso también cuenta');
      log.stop('metronomo');
      async.elapse(const Duration(minutes: 3));
      expect(log.secondsBetween(t0, clock.now()), 600);
      expect(log.secondsByTool(from: t0)['metronomo'], 600);
      expect(log.secondsOn(t0), 600);
      log.dispose();
    }, initialTime: DateTime(2026, 10, 18, 10));
  });

  test('Dos herramientas a la vez no cuentan doble; cada una suma su tiempo', () {
    fakeAsync((FakeAsync async) {
      final PracticeLog log = newLog();
      final DateTime t0 = clock.now();
      log.start('metronomo', 'guitarra');
      async.elapse(const Duration(minutes: 5));
      log.start('tono', 'guitarra');
      async.elapse(const Duration(minutes: 5));
      log.stop('metronomo');
      async.elapse(const Duration(minutes: 2));
      log.stop('tono');
      expect(log.secondsBetween(t0, clock.now()), 12 * 60);
      final Map<String, int> byTool = log.secondsByTool(from: t0);
      expect(byTool['metronomo'], 600);
      expect(byTool['tono'], 420);
      expect(log.secondsByInstrument(from: t0)['guitarra'], 720);
      log.dispose();
    }, initialTime: DateTime(2026, 10, 18, 10));
  });

  test('Las notas cortas del teclado se unen en un intervalo', () {
    fakeAsync((FakeAsync async) {
      final PracticeLog log = newLog();
      final DateTime t0 = clock.now();
      for (int i = 0; i < 30; i++) {
        log.start('tono', 'piano');
        async.elapse(const Duration(milliseconds: 700));
        log.stop('tono');
        async.elapse(const Duration(milliseconds: 500));
      }
      // 30 notas de 0,7 s con pausas de 0,5 s: 35,5 s seguidos.
      expect(log.sessions.where((PracticeSession s) => s.tool == 'tono'), hasLength(1));
      expect(log.secondsBetween(t0, clock.now()), 35);
      log.dispose();
    }, initialTime: DateTime(2026, 10, 18, 10));
  });

  test('El afinador cuenta mientras oye tonos estables y se corta sin ellos', () {
    fakeAsync((FakeAsync async) {
      final PracticeLog log = newLog();
      final DateTime t0 = clock.now();
      // 20 s afinando (un análisis cada 60 ms), 10 s en silencio, 5 s más.
      for (int i = 0; i < 20000 ~/ 60; i++) {
        log.ping('afinador', 'violin');
        async.elapse(const Duration(milliseconds: 60));
      }
      async.elapse(const Duration(seconds: 10));
      expect(log.isActive('afinador'), isFalse);
      for (int i = 0; i < 5000 ~/ 60; i++) {
        log.ping('afinador', 'violin');
        async.elapse(const Duration(milliseconds: 60));
      }
      async.elapse(const Duration(seconds: 3));
      final int total = log.secondsBetween(t0, clock.now());
      expect(total, inInclusiveRange(24, 25));
      expect(log.recentGroups().first.tool, 'afinador');
      log.dispose();
    }, initialTime: DateTime(2026, 10, 18, 10));
  });

  test('Cambiar de instrumento con una herramienta en marcha parte el intervalo', () {
    fakeAsync((FakeAsync async) {
      final PracticeLog log = newLog();
      final DateTime t0 = clock.now();
      log.start('metronomo', 'guitarra');
      async.elapse(const Duration(minutes: 4));
      log.changeInstrument('tiple');
      async.elapse(const Duration(minutes: 6));
      log.stop('metronomo');
      final Map<String, int> byInstrument = log.secondsByInstrument(from: t0);
      expect(byInstrument['guitarra'], 240);
      expect(byInstrument['tiple'], 360);
      log.dispose();
    }, initialTime: DateTime(2026, 10, 18, 10));
  });

  test('Un intervalo que cruza la medianoche se reparte entre los dos días (M12)', () {
    fakeAsync((FakeAsync async) {
      final PracticeLog log = newLog();
      log.start('metronomo', 'guitarra');
      async.elapse(const Duration(minutes: 20));
      log.stop('metronomo');
      final Map<DateTime, int> daily = log.dailySeconds();
      expect(daily[DateTime(2026, 10, 17)], 600);
      expect(daily[DateTime(2026, 10, 18)], 600);
      expect(log.secondsOn(DateTime(2026, 10, 18, 15)), 600);
      log.dispose();
    }, initialTime: DateTime(2026, 10, 17, 23, 50));
  });

  group('Racha', () {
    PracticeSession day(int back, {int minutes = 10, DateTime? today}) {
      final DateTime t = today ?? DateTime(2026, 10, 18);
      final DateTime start = DateTime(t.year, t.month, t.day - back, 18);
      return PracticeSession(id: 's$back', start: start, end: start.add(Duration(minutes: minutes)), tool: 'metronomo', instrumentId: 'guitarra');
    }

    int streakWith(List<int> practicedBack, {List<int> shortBack = const <int>[]}) {
      return withClock(Clock.fixed(DateTime(2026, 10, 18, 20)), () {
        final PracticeLog log = newLog();
        log.sessions.addAll(<PracticeSession>[for (final int b in practicedBack) day(b), for (final int b in shortBack) day(b, minutes: 3)]);
        log.sessions.sort((PracticeSession a, PracticeSession b) => a.start.compareTo(b.start));
        final int s = log.streak();
        log.dispose();
        return s;
      });
    }

    test('Cuenta días con al menos 5 minutos; hoy todavía no la rompe', () {
      expect(streakWith(<int>[0, 1, 2]), 3);
      expect(streakWith(<int>[1, 2, 3]), 3);
      expect(streakWith(<int>[0, 1], shortBack: <int>[2]), 2);
      expect(streakWith(<int>[]), 0);
    });

    test('Se puede descansar un día de cada siete sin perder la racha', () {
      // Descansos hace 2 y hace 9 días (siete días entre ellos).
      expect(streakWith(<int>[0, 1, 3, 4, 5, 6, 7, 8, 10]), 9);
      // Dos días seguidos de descanso la cortan.
      expect(streakWith(<int>[0, 1, 4, 5]), 2);
      // Dos descansos con menos de siete días entre ellos: el segundo la corta.
      expect(streakWith(<int>[0, 2, 3, 5, 6]), 3);
    });
  });

  test('Lo abierto se guarda cada cierto tiempo y sobrevive a un cierre de golpe', () async {
    DateTime now = DateTime(2026, 10, 18, 9);
    await withClock(Clock(() => now), () async {
      final JsonStore store = JsonStore(root: tmp);
      final PracticeLog log = PracticeLog(store);
      log.start('grabadora', 'voz');
      now = now.add(const Duration(minutes: 5));
      await log.checkpoint();
      await store.flush();
      // La app muere sin cerrar el intervalo: lo guardado llega hasta el último punto.
      final PracticeLog again = PracticeLog(JsonStore(root: tmp));
      await again.load();
      expect(again.secondsOn(now), 300);
      expect(again.sessions.single.tool, 'grabadora');
      // Al cerrar normalmente queda el intervalo completo.
      now = now.add(const Duration(minutes: 1));
      await log.closeAll();
      await store.flush();
      final PracticeLog third = PracticeLog(JsonStore(root: tmp));
      await third.load();
      expect(third.secondsOn(now), 360);
      log.dispose();
      again.dispose();
      third.dispose();
    });
  });
}
