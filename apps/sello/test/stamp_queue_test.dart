import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/app_state.dart';
import 'package:sello/core/settings.dart';
import 'package:sello/geo/location_service.dart';
import 'package:sello/model/models.dart';
import 'package:sello/stamp/capture_pipeline.dart';
import 'package:sello/stamp/stamp_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late AppSettings settings;
  late AppState state;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sello_queue');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    settings = await testSettings();
    state = await testState(tmp);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<PhotoRecord> shoot(CapturePipeline pipeline, {int n = 0}) async {
    final File f = File('${tmp.path}/camara_$n.jpg')..writeAsBytesSync(syntheticJpeg(64, 48));
    return pipeline.saveCapture(
      jpegPath: f.path,
      project: state.projectById('general'),
      fix: Fix(latitude: 4.711, longitude: -74.0721, time: DateTime.utc(2026, 3, 9, 19, 5), accuracy: 4),
      now: DateTime.utc(2026, 3, 9, 19, 5, n),
    );
  }

  group('Cola de sellado (G1)', () {
    test('La ficha queda guardada como pendiente antes de sellar', () async {
      final RecordingPipeline pipeline = RecordingPipeline(store: state.store, state: state, settings: settings);
      final PhotoRecord rec = await shoot(pipeline);
      expect(rec.status, PhotoStatus.pending);
      // Ya está en el índice en disco, con el original guardado y el temporal de la cámara borrado.
      final Map<String, dynamic> onDisk = jsonDecode(File('${tmp.path}/sello/photos.json').readAsStringSync()) as Map<String, dynamic>;
      final Map<String, dynamic> j = (onDisk['photos'] as List<dynamic>).single as Map<String, dynamic>;
      expect(j['status'], 'pending');
      expect(j['latitude'], 4.711);
      expect(File(await state.store.absolutePath(rec.originalFile)).existsSync(), isTrue);
      expect(File('${tmp.path}/camara_0.jpg').existsSync(), isFalse);
      // Si la app se cerró aquí, al abrir se reanuda.
      final AppState reopened = await testState(tmp);
      final RecordingPipeline again = RecordingPipeline(store: reopened.store, state: reopened, settings: settings);
      final StampQueue queue = StampQueue(pipeline: again);
      expect(queue.resumePending(), 1);
      await queue.idle();
      expect(again.stamped, <String>[rec.id]);
      expect(reopened.photoById(rec.id)!.status, PhotoStatus.ok);
      queue.dispose();
    });

    test('Sella de a una foto aunque se dispare seguido', () async {
      final RecordingPipeline pipeline = RecordingPipeline(store: state.store, state: state, settings: settings)
        ..onStamp = (PhotoRecord p) => Future<void>.delayed(const Duration(milliseconds: 20));
      final StampQueue queue = StampQueue(pipeline: pipeline);
      final List<String> ids = <String>[];
      for (int i = 0; i < 5; i++) {
        final PhotoRecord r = await shoot(pipeline, n: i);
        ids.add(r.id);
        queue.enqueue(r.id);
      }
      expect(queue.pendingCount, greaterThan(0));
      await queue.idle();
      expect(pipeline.maxRunning, 1);
      expect(pipeline.stamped, ids);
      expect(queue.pendingCount, 0);
      expect(state.photos.every((PhotoRecord p) => p.status == PhotoStatus.ok), isTrue);
      queue.dispose();
    });

    test('Un fallo deja la foto como fallida, lo anuncia y se puede reintentar', () async {
      final RecordingPipeline pipeline = RecordingPipeline(store: state.store, state: state, settings: settings);
      final StampQueue queue = StampQueue(pipeline: pipeline);
      final List<StampEvent> events = <StampEvent>[];
      final StreamSubscription<StampEvent> sub = queue.events.listen(events.add);
      final PhotoRecord r = await shoot(pipeline);
      pipeline.onStamp = (PhotoRecord p) async => throw const StampException(StampException.unreadable);
      queue.enqueue(r.id);
      await queue.idle();
      await pumpEventQueue();
      expect(events.single.kind, StampEventKind.failed);
      expect(events.single.detail, StampException.unreadable);
      final PhotoRecord failed = state.photoById(r.id)!;
      expect(failed.status, PhotoStatus.failed);
      expect(failed.error, StampException.unreadable);
      // Persistido: al reabrir sigue marcada como fallida (no se pierde ni se da por sellada).
      expect((await testState(tmp)).photoById(r.id)!.status, PhotoStatus.failed);
      // Reintentar funciona cuando la causa desaparece.
      pipeline.onStamp = null;
      expect(await queue.restamp(r.id), isTrue);
      expect(state.photoById(r.id)!.status, PhotoStatus.ok);
      await pumpEventQueue();
      expect(events.last.kind, StampEventKind.stamped);
      await sub.cancel();
      queue.dispose();
    });

    test('El sellado real escribe la copia, actualiza la ficha y avisa si falta el original', () async {
      final CapturePipeline pipeline = CapturePipeline(store: state.store, state: state, settings: settings);
      final PhotoRecord r = await shoot(pipeline);
      final StampOutcome out = await pipeline.stamp(r);
      expect(out.record.status, PhotoStatus.ok);
      expect(out.record.width, 64);
      expect(out.record.height, 48);
      expect(out.record.version, 1);
      expect(File(await state.store.absolutePath(r.stampedFile)).existsSync(), isTrue);
      // Sin original no hay cómo sellar: excepción con su código y la ficha intacta.
      await state.store.delete(r.originalFile);
      final PhotoRecord copy = PhotoRecord.fromJson(r.toJson());
      await expectLater(pipeline.stamp(copy), throwsA(isA<StampException>().having((StampException e) => e.code, 'code', StampException.missingOriginal)));
    });
  });
}
