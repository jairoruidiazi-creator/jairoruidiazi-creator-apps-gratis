// Grabadora (M7): duración real sin pausas, tomas que se cortan solas,
// números de toma que no se repiten y rescate tras un cierre de golpe.

import 'dart:async';
import 'dart:io';

import 'package:clave/audio/take_recorder.dart';
import 'package:clave/audio/tuner.dart';
import 'package:clave/core/app_state.dart';
import 'package:clave/core/storage.dart';
import 'package:clave/model/models.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('clave_rec');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('La toma mide lo grabado y deja un marcador mientras graba', () async {
    DateTime now = DateTime(2026, 10, 18, 9);
    await withClock(Clock(() => now), () async {
      final JsonStore store = JsonStore(root: tmp);
      final FakeFileCapture cap = FakeFileCapture();
      final TakeRecorder rec = TakeRecorder(store: store, capture: cap);
      await rec.start(format: 'flac', folder: 'Ensayo', instrumentId: 'tiple', bpm: 96);
      expect(rec.recording, isTrue);
      expect(await store.readJson(TakeRecorder.pendingFile), isNotNull);
      now = now.add(const Duration(seconds: 12));
      expect(rec.elapsed, const Duration(seconds: 12));
      final TakeResult? r = await rec.stop();
      expect(r, isNotNull);
      expect(r!.durationMs, 12000);
      expect(r.format, 'flac');
      expect(r.file, endsWith('.flac'));
      expect(r.folder, 'Ensayo');
      expect(r.instrumentId, 'tiple');
      expect(r.bpm, 96);
      expect(r.startedAt, DateTime(2026, 10, 18, 9));
      expect(await store.exists(r.file), isTrue);
      expect(await store.exists(TakeRecorder.pendingFile), isFalse);
      expect(await rec.stop(), isNull);
      rec.dispose();
    });
  });

  test('Una llamada corta la toma y la guarda con lo grabado hasta ahí', () async {
    DateTime now = DateTime(2026, 10, 18, 9);
    await withClock(Clock(() => now), () async {
      final JsonStore store = JsonStore(root: tmp);
      final FakeFileCapture cap = FakeFileCapture();
      final TakeRecorder rec = TakeRecorder(store: store, capture: cap);
      TakeResult? got;
      TakeStopReason? why;
      final Completer<void> stopped = Completer<void>();
      rec.onAutoStop = (TakeResult? r, TakeStopReason reason) {
        got = r;
        why = reason;
        if (!stopped.isCompleted) {
          stopped.complete();
        }
      };
      await rec.start(format: 'aac');
      now = now.add(const Duration(seconds: 7));
      cap.systemPause();
      await stopped.future.timeout(const Duration(seconds: 10));
      expect(rec.recording, isFalse);
      expect(why, TakeStopReason.interruption);
      expect(got?.durationMs, 7000);
      // Al salir de la app en Android, igual.
      await rec.start(format: 'wav');
      now = now.add(const Duration(seconds: 3));
      await rec.stopForBackground();
      expect(why, TakeStopReason.background);
      expect(got?.durationMs, 3000);
      expect(got?.format, 'wav');
      rec.dispose();
    });
  });

  test('"Toma N" no repite números aunque se borren tomas, y sobrevive al reinicio', () async {
    final JsonStore store = JsonStore(root: tmp);
    final AppState st = AppState(store);
    await st.load();
    int minute = 0;
    TakeResult take(String name) => TakeResult(file: 'recordings/$name.m4a', format: 'aac', durationMs: 1000, startedAt: DateTime(2026, 10, 18, 9, minute++));
    await store.writeBytes('recordings/a.m4a', <int>[1, 2]);
    await store.writeBytes('recordings/b.m4a', <int>[1, 2]);
    final Recording a = await st.addTake(take('a'), takeWord: 'Toma');
    final Recording b = await st.addTake(take('b'), takeWord: 'Toma');
    expect(a.name, 'Toma 1');
    expect(b.name, 'Toma 2');
    await st.deleteRecording(b);
    expect(await store.exists('recordings/b.m4a'), isFalse);
    await store.writeBytes('recordings/c.m4a', <int>[1, 2]);
    final Recording c = await st.addTake(take('c'), takeWord: 'Take');
    expect(c.name, 'Take 3');
    await store.flush();
    final AppState again = AppState(JsonStore(root: tmp));
    await again.load();
    expect(again.nextTake, 4);
    expect(again.recordings.map((Recording r) => r.name), <String>['Take 3', 'Toma 1']);
  });

  test('Al abrir se rescatan la toma a medias y los archivos sueltos; los vacíos se borran', () async {
    final JsonStore store = JsonStore(root: tmp);
    final AppState st = AppState(store);
    await st.load();
    await store.writeBytes('recordings/1760000000000.m4a', <int>[1, 2, 3]);
    await st.addTake(TakeResult(file: 'recordings/1760000000000.m4a', format: 'aac', durationMs: 5000, startedAt: DateTime(2026, 10, 1)), takeWord: 'Toma');
    // La app murió grabando: queda el marcador y el archivo.
    await store.writeBytes('recordings/1760100000000.wav', List<int>.filled(64, 1));
    await store.writeJson(TakeRecorder.pendingFile, <String, dynamic>{
      'file': 'recordings/1760100000000.wav',
      'format': 'wav',
      'startedAt': '2026-10-10T18:00:00.000',
      'folder': 'Ideas',
      'instrumentId': 'violin',
    });
    // Un archivo que no está en la lista y otro vacío.
    await store.writeBytes('recordings/1760200000000.flac', List<int>.filled(16, 1));
    await store.writeBytes('recordings/1760300000000.m4a', <int>[]);
    await store.flush();
    final AppState again = AppState(JsonStore(root: tmp));
    await again.load();
    final int n = await again.recoverTakes(takeWord: 'Toma', instrumentId: 'guitarra');
    expect(n, 2);
    expect(again.recoveredTakes, 2);
    final Recording pending = again.recordings.firstWhere((Recording r) => r.file.endsWith('.wav'));
    expect(pending.recovered, isTrue);
    expect(pending.folder, 'Ideas');
    expect(pending.instrumentId, 'violin');
    expect(pending.createdAt, DateTime(2026, 10, 10, 18));
    expect(pending.durationMs, 0);
    final Recording loose = again.recordings.firstWhere((Recording r) => r.file.endsWith('.flac'));
    expect(loose.instrumentId, 'guitarra');
    expect(loose.createdAt, DateTime.fromMillisecondsSinceEpoch(1760200000000));
    expect(<String>{for (final Recording r in again.recordings) r.name}.length, again.recordings.length, reason: 'sin nombres repetidos');
    expect(await again.store.exists('recordings/1760300000000.m4a'), isFalse);
    expect(await again.store.exists(TakeRecorder.pendingFile), isFalse);
    // La lista sigue ordenada de la más nueva a la más vieja.
    final List<DateTime> dates = again.recordings.map((Recording r) => r.createdAt).toList();
    expect(dates, List<DateTime>.from(dates)..sort((DateTime x, DateTime y) => y.compareTo(x)));
    // Abrir otra vez no duplica nada.
    expect(await again.recoverTakes(takeWord: 'Toma'), 0);
  });

  test('Mientras se graba, el afinador suelta el micrófono y la grabadora cuenta como práctica', () async {
    DateTime now = DateTime(2026, 10, 18, 9);
    await withClock(Clock(() => now), () async {
      final TestServices t = TestServices();
      t.services.tuner.setActive(true);
      await t.services.tuner.settle();
      expect(t.mic.open, isTrue);
      await t.services.recorder.start(format: 'aac');
      await t.services.tuner.settle();
      expect(t.mic.open, isFalse);
      expect(t.services.tuner.status, MicStatus.busy);
      expect(t.services.practice.isActive('grabadora'), isTrue);
      now = now.add(const Duration(minutes: 2));
      final TakeResult? r = await t.services.recorder.stop();
      await t.services.state.addTake(r!, takeWord: 'Toma');
      await t.services.tuner.settle();
      expect(t.mic.open, isTrue, reason: 'el afinador vuelve al terminar la toma');
      expect(t.services.practice.secondsOn(now), 120);
      t.services.tuner.setActive(false);
      await t.services.tuner.settle();
      await t.services.practice.closeAll();
      await t.services.store.flush();
      t.dispose();
    });
  });
}
