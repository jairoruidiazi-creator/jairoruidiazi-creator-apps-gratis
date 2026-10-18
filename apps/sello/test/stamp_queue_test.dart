import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/app_state.dart';
import 'package:sello/core/settings.dart';
import 'package:sello/geo/location_service.dart';
import 'package:sello/model/models.dart';
import 'package:sello/stamp/capture_pipeline.dart';
import 'package:sello/stamp/composer.dart';
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
      expect(out.removed, isFalse);
      expect(out.record.status, PhotoStatus.ok);
      expect(out.record.width, 64);
      expect(out.record.height, 48);
      expect(out.record.version, 1);
      expect(File(await state.store.absolutePath(r.stampedFile)).existsSync(), isTrue);
      // Sin original no hay cómo sellar: excepción con su código y la ficha intacta.
      await state.store.delete(r.originalFile);
      await expectLater(pipeline.stamp(r), throwsA(isA<StampException>().having((StampException e) => e.code, 'code', StampException.missingOriginal)));
      expect(r.status, PhotoStatus.ok);
      expect(r.version, 1);
    });
  });

  group('El borrado gana siempre (G1)', () {
    /// Tubería real con la composición detenida hasta abrir [gate] y la
    /// fototeca simulada.
    CapturePipeline gated({required Completer<void> gate, required List<String> composing, required List<String> library, bool composeFirst = false}) {
      settings.saveToGallery = true;
      return CapturePipeline(
        store: state.store,
        state: state,
        settings: settings,
        compose: (ComposeJob job) async {
          composing.add(job.outputPath);
          if (composeFirst) {
            // El archivo sellado ya quedó escrito cuando llega el borrado.
            final ComposeResult r = composeStampedSync(job);
            await gate.future;
            return r;
          }
          await gate.future;
          return composeStampedSync(job);
        },
        toPhotoLibrary: (String path) async => library.add(path),
      );
    }

    Future<void> waitFor(bool Function() done) async {
      for (int i = 0; i < 200 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    for (final bool composeFirst in <bool>[false, true]) {
      test(composeFirst ? 'Borrada después de componer: se descarta la copia escrita' : 'Borrada antes de que se lea el original: no queda nada', () async {
        final Completer<void> gate = Completer<void>();
        final List<String> composing = <String>[];
        final List<String> library = <String>[];
        final CapturePipeline pipeline = gated(gate: gate, composing: composing, library: library, composeFirst: composeFirst);
        final StampQueue queue = StampQueue(pipeline: pipeline);
        final List<StampEvent> events = <StampEvent>[];
        final StreamSubscription<StampEvent> sub = queue.events.listen(events.add);
        final PhotoRecord first = await shoot(pipeline);
        final PhotoRecord second = await shoot(pipeline, n: 1);
        queue.enqueue(first.id);
        queue.enqueue(second.id);
        await waitFor(() => composing.isNotEmpty);
        expect(queue.currentId, first.id);
        // Se borran las dos: la que se está sellando y la que espera.
        await state.deletePhotos(<PhotoRecord>[first, second]);
        await pumpEventQueue();
        // La que esperaba salió de la fila sin sellarse.
        expect(queue.contains(second.id), isFalse);
        gate.complete();
        await queue.idle();
        await pumpEventQueue();
        expect(composing, hasLength(1));
        // Ni copia sellada en la carpeta, ni copia en la fototeca, ni aviso.
        expect(File(await state.store.absolutePath(first.stampedFile)).existsSync(), isFalse);
        expect(File(await state.store.absolutePath(first.originalFile)).existsSync(), isFalse);
        expect(library, isEmpty);
        expect(events, isEmpty);
        expect(state.photos, isEmpty);
        // Al abrir de nuevo no se "resucita" nada de la carpeta.
        final AppState reopened = await testState(tmp);
        expect(reopened.photos, isEmpty);
        expect(reopened.notices, isEmpty);
        await sub.cancel();
        queue.dispose();
      });
    }

    test('Sin borrar, la misma tubería sella y copia a la fototeca', () async {
      final Completer<void> gate = Completer<void>()..complete();
      final List<String> composing = <String>[];
      final List<String> library = <String>[];
      final CapturePipeline pipeline = gated(gate: gate, composing: composing, library: library);
      final StampQueue queue = StampQueue(pipeline: pipeline);
      final PhotoRecord r = await shoot(pipeline);
      queue.enqueue(r.id);
      await queue.idle();
      expect(state.photoById(r.id)!.status, PhotoStatus.ok);
      expect(library, <String>[await state.store.absolutePath(r.stampedFile)]);
      queue.dispose();
    });
  });

  test('El número {n} del nombre de archivo no se repite al borrar fotos (M8)', () async {
    final RecordingPipeline pipeline = RecordingPipeline(store: state.store, state: state, settings: settings);
    final Project p = state.projectById('general')..fileNamePattern = '{proyecto}_{n}';
    final PhotoRecord a = await shoot(pipeline);
    final PhotoRecord b = await shoot(pipeline, n: 1);
    expect(a.originalFile, contains('_0001_'));
    expect(b.originalFile, contains('_0002_'));
    await state.deletePhotos(<PhotoRecord>[b]);
    final PhotoRecord c = await shoot(pipeline, n: 2);
    expect(c.originalFile, contains('_0003_'));
    // El contador queda guardado con el proyecto.
    final AppState reopened = await testState(tmp);
    expect(reopened.projectById(p.id).photoCounter, 3);
    expect(reopened.nextNumber(p.id), 4);
  });
}
