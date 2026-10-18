import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/app_state.dart';
import 'package:sello/core/storage.dart';
import 'package:sello/model/models.dart';
import 'package:sello/stamp/composer.dart';

import 'support/fakes.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sello_storage');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  File inStore(String rel) => File('${tmp.path}/sello/$rel');

  List<String> leftovers() => Directory('${tmp.path}/sello').listSync(recursive: true).whereType<File>().map((File f) => f.path).where((String p) => p.contains('.tmp-')).toList();

  group('Índice de fotos (B3)', () {
    test('Cincuenta guardados simultáneos no pierden ninguna ficha', () async {
      final AppState st = await testState(tmp);
      await Future.wait(<Future<void>>[
        for (int i = 0; i < 50; i++) st.addPhoto(PhotoRecord(id: 'f$i', projectId: 'general', originalFile: 'photos/general/f$i-orig.jpg', stampedFile: 'photos/general/f$i.jpg', takenAt: DateTime.utc(2026, 3, 9, 12, i))),
      ]);
      expect(st.photos.length, 50);
      final AppState again = await testState(tmp);
      expect(again.photos.length, 50);
      expect(again.notices, isEmpty);
      expect(leftovers(), isEmpty);
    });

    test('Escrituras seguidas quedan en orden y la última gana', () async {
      final JsonStore store = JsonStore(root: tmp);
      await Future.wait(<Future<void>>[
        for (int i = 0; i < 30; i++) store.writeJson('x.json', <String, dynamic>{'n': i}),
      ]);
      expect((await store.readJson('x.json'))!['n'], 29);
      // La copia anterior queda como .bak.
      expect(jsonDecode(inStore('x.json.bak').readAsStringSync())['n'], 28);
      expect(leftovers(), isEmpty);
    });

    test('Un índice dañado se recupera de la copia anterior y se aparta', () async {
      final JsonStore store = JsonStore(root: tmp);
      await store.writeJson('photos.json', <String, dynamic>{'photos': <dynamic>[]});
      await store.writeJson('photos.json', <String, dynamic>{
        'photos': <dynamic>[PhotoRecord(id: 'a', projectId: 'general', originalFile: 'o', stampedFile: 's', takenAt: DateTime.utc(2026)).toJson()],
      });
      // Corte de energía a mitad de escritura (sin escritura atómica podía pasar).
      inStore('photos.json').writeAsStringSync('{"photos": [{"id": "a", "proj');
      final JsonRead r = await store.readJsonChecked('photos.json');
      expect(r.outcome, ReadOutcome.fromBackup);
      expect(r.data!['photos'], isEmpty);
      // El archivo dañado no se borra: se aparta para poder revisarlo.
      final List<String> names = Directory('${tmp.path}/sello').listSync().map((FileSystemEntity e) => e.uri.pathSegments.last).toList();
      expect(names.any((String n) => n.startsWith('photos.json.danado-')), isTrue);
    });

    test('Sin índice ni copia: aviso y fotos recuperadas de la carpeta con su EXIF', () async {
      final JsonStore store = JsonStore(root: tmp);
      // Una foto sellada por Sello (con su EXIF) y su original.
      final File orig = inStore('photos/general/Obra_20260309_140507_k7f3a1-orig.jpg')..createSync(recursive: true);
      orig.writeAsBytesSync(syntheticJpeg(64, 48));
      composeStampedSync(ComposeJob(
        originalPath: orig.path,
        outputPath: inStore('photos/general/Obra_20260309_140507_k7f3a1.jpg').path,
        quality: 90,
        latitude: 4.711,
        longitude: -74.0721,
        altitudeMsl: 2600,
        heading: 135,
        takenAt: DateTime.utc(2026, 3, 9, 19, 5, 7),
        utcOffsetMinutes: -300,
        description: 'Obra | Columna C-3',
      ));
      // Un original suelto de una foto que no alcanzó a sellarse.
      inStore('photos/general/Obra_20260309_141000_q9z8y7-orig.jpg').writeAsBytesSync(syntheticJpeg(64, 48));
      // Un temporal de una escritura interrumpida.
      inStore('photos/general/x.jpg.tmp-123').writeAsBytesSync(<int>[1, 2, 3]);
      inStore('photos.json').writeAsStringSync('basura');
      final AppState st = AppState(store);
      await st.load();
      expect(st.notices.map((LoadNotice n) => n.kind), containsAll(<LoadNoticeKind>[LoadNoticeKind.photosLost, LoadNoticeKind.photosRecovered]));
      expect(st.notices.firstWhere((LoadNotice n) => n.kind == LoadNoticeKind.photosRecovered).count, 2);
      final PhotoRecord a = st.photoById('k7f3a1')!;
      expect(a.status, PhotoStatus.ok);
      expect(a.latitude, closeTo(4.711, 1e-6));
      expect(a.longitude, closeTo(-74.0721, 1e-6));
      expect(a.altitudeMsl, closeTo(2600, 0.01));
      expect(a.takenAt, DateTime.utc(2026, 3, 9, 19, 5, 7));
      expect(a.utcOffsetMinutes, -300);
      expect(a.description, 'Obra | Columna C-3');
      expect(a.originalFile, 'photos/general/Obra_20260309_140507_k7f3a1-orig.jpg');
      final PhotoRecord b = st.photoById('q9z8y7')!;
      expect(b.status, PhotoStatus.failed);
      expect(b.error, AppState.kErrorRecoveredOriginal);
      expect(inStore('photos/general/x.jpg.tmp-123').existsSync(), isFalse);
      // El índice reconstruido queda guardado.
      final AppState again = await testState(tmp);
      expect(again.photos.length, 2);
      expect(again.notices, isEmpty);
    });

    test('Borrar quita primero los archivos: el reindexado no las resucita', () async {
      final AppState st = await testState(tmp);
      await st.store.writeBytes('photos/general/a_1-orig.jpg', syntheticJpeg(16, 16));
      await st.store.writeBytes('photos/general/a_1.jpg', syntheticJpeg(16, 16));
      await st.addPhoto(PhotoRecord(id: '1', projectId: 'general', originalFile: 'photos/general/a_1-orig.jpg', stampedFile: 'photos/general/a_1.jpg', takenAt: DateTime.utc(2026)));
      await st.deletePhotos(st.photos.toList());
      final AppState again = await testState(tmp);
      expect(again.photos, isEmpty);
      expect(inStore('photos/general/a_1.jpg').existsSync(), isFalse);
    });

    test('Proyectos dañados: se usan los de la copia', () async {
      final AppState st = await testState(tmp);
      await st.addProject('Obra 1');
      await st.addProject('Obra 2');
      inStore('projects.json').writeAsStringSync('{');
      final AppState again = await testState(tmp);
      expect(again.notices.map((LoadNotice n) => n.kind), contains(LoadNoticeKind.projectsFromBackup));
      expect(again.projects.map((Project p) => p.name), contains('Obra 1'));
    });

    test('Un índice con tipos inesperados no impide abrir la app (M10)', () async {
      // JSON válido pero tocado a mano (en iOS la carpeta se ve en Archivos).
      Directory('${tmp.path}/sello').createSync(recursive: true);
      inStore('photos.json').writeAsStringSync(jsonEncode(<String, Object?>{
        'photos': <Object?>[
          <String, Object?>{
            'id': 'ok1',
            'projectId': 'general',
            'originalFile': 'photos/general/a-orig.jpg',
            'stampedFile': 'photos/general/a.jpg',
            'takenAt': '2026-03-09T19:05:00.000Z',
            'latitude': '4.7',
            'longitude': -74.07,
            'tags': 'muro',
            'fields': <int>[1, 2],
            'width': 'ancho',
            'status': 7,
            'heading': 'norte',
          },
          <String, Object?>{'id': 5, 'originalFile': 'photos/general/b-orig.jpg'},
          'basura',
          <String, Object?>{'id': 'ok1', 'originalFile': 'photos/general/repetida-orig.jpg'},
          <String, Object?>{'id': 'sin-archivo'},
        ],
      }));
      inStore('projects.json').writeAsStringSync(jsonEncode(<String, Object?>{
        'projects': <Object?>[
          <String, Object?>{'id': 'general', 'name': 'General', 'fields': 'ninguno', 'counter': 'mucho', 'templateId': 3},
          <String, Object?>{'id': 'general', 'name': 'Repetido'},
          42,
        ],
        'templates': <Object?>[
          <String, Object?>{'id': 'x', 'name': 'Mía', 'items': 'todo', 'textScale': 'grande', 'backgroundOpacity': 7, 'textColor': 'blanco'},
        ],
      }));
      final AppState st = await testState(tmp);
      expect(st.loaded, isTrue);
      expect(st.photos.map((PhotoRecord p) => p.id), <String>['ok1']);
      final PhotoRecord p = st.photos.single;
      expect(p.originalFile, 'photos/general/a-orig.jpg');
      expect(p.latitude, isNull);
      expect(p.longitude, isNull);
      expect(p.heading, isNull);
      expect(p.tags, isEmpty);
      expect(p.fields, isEmpty);
      expect(p.width, 0);
      expect(p.status, PhotoStatus.ok);
      expect(st.projects.map((Project x) => x.name), <String>['General']);
      final Project g = st.projects.single;
      expect(g.fields, isEmpty);
      expect(g.photoCounter, 0);
      expect(g.templateId, 'default');
      final StampTemplate t = st.templates.firstWhere((StampTemplate x) => x.id == 'x');
      expect(t.items, isEmpty);
      expect(t.textScale, 1.0);
      expect(t.backgroundOpacity, 1.0);
      expect(t.textColor, 0xFFFFFFFF);
      expect(st.templates.first.id, 'default');
      // Guardar después no reescribe la basura: queda un índice limpio.
      await st.savePhotos();
      final AppState again = await testState(tmp);
      expect(again.photos.map((PhotoRecord x) => x.id), <String>['ok1']);
    });
  });
}
