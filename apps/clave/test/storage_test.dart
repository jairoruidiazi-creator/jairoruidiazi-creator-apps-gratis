// Almacén JSON (M8), validación de lo que llega de archivos (G11) e
// importación de preajustes.

import 'dart:convert';
import 'dart:io';

import 'package:clave/audio/sequencer.dart';
import 'package:clave/core/app_state.dart';
import 'package:clave/core/storage.dart';
import 'package:clave/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('clave_store');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  String pathOf(String rel) => '${tmp.path}${Platform.pathSeparator}clave${Platform.pathSeparator}$rel';

  group('JsonStore (M8)', () {
    test('Escrituras seguidas de la misma ruta quedan en orden y sin temporales', () async {
      final JsonStore store = JsonStore(root: tmp);
      final List<Future<void>> writes = <Future<void>>[
        for (int i = 0; i < 40; i++) store.writeJson('datos.json', <String, dynamic>{'n': i}),
      ];
      await Future.wait(writes);
      await store.flush();
      final Map<String, dynamic>? back = await store.readJson('datos.json');
      expect(back?['n'], 39);
      final List<String> names = Directory('${tmp.path}${Platform.pathSeparator}clave').listSync().map((FileSystemEntity e) => e.uri.pathSegments.last).toList();
      expect(names.where((String n) => n.endsWith('.tmp')), isEmpty);
      // El respaldo es la versión anterior.
      final Map<String, dynamic> bak = jsonDecode(File('${pathOf('datos.json')}.bak').readAsStringSync()) as Map<String, dynamic>;
      expect(bak['n'], 38);
    });

    test('Un archivo dañado se aparta y se recupera la copia anterior, con aviso', () async {
      final JsonStore store = JsonStore(root: tmp);
      await store.writeJson('presets.json', <String, dynamic>{'v': 1});
      await store.writeJson('presets.json', <String, dynamic>{'v': 2});
      await store.flush();
      File(pathOf('presets.json')).writeAsStringSync('{"v": 3, "corta'); // se cortó a medias
      final JsonStore again = JsonStore(root: tmp);
      final Map<String, dynamic>? data = await again.readJson('presets.json');
      expect(data?['v'], 1);
      expect(again.notices, hasLength(1));
      expect(again.notices.single.recovered, isTrue);
      expect(again.notices.single.keptAs, startsWith('presets.json.danado-'));
      // El dañado quedó apartado (no se pisó) y el principal volvió a ser válido.
      final List<String> names = Directory('${tmp.path}${Platform.pathSeparator}clave').listSync().map((FileSystemEntity e) => e.uri.pathSegments.last).toList();
      expect(names.any((String n) => n.startsWith('presets.json.danado-')), isTrue);
      expect(jsonDecode(File(pathOf('presets.json')).readAsStringSync()), <String, dynamic>{'v': 1});
    });

    test('Sin copia anterior, el dañado se aparta y se avisa que no se recuperó', () async {
      Directory('${tmp.path}${Platform.pathSeparator}clave').createSync(recursive: true);
      File(pathOf('practice.json')).writeAsStringSync('no es json');
      final JsonStore store = JsonStore(root: tmp);
      expect(await store.readJson('practice.json'), isNull);
      expect(store.notices.single.recovered, isFalse);
      expect(File(pathOf('practice.json')).existsSync(), isFalse);
      // Un archivo que no existe no es un error.
      expect(await store.readJson('otro.json'), isNull);
      expect(store.notices, hasLength(1));
    });

    test('Un JSON que no es un objeto cuenta como dañado', () async {
      Directory('${tmp.path}${Platform.pathSeparator}clave').createSync(recursive: true);
      File(pathOf('recordings.json')).writeAsStringSync('[1, 2, 3]');
      final JsonStore store = JsonStore(root: tmp);
      expect(await store.readJson('recordings.json'), isNull);
      expect(store.notices.single.file, 'recordings.json');
    });

    test('Bytes, borrado, tamaño y listado', () async {
      final JsonStore store = JsonStore(root: tmp);
      await store.writeBytes('recordings/a.wav', <int>[1, 2, 3]);
      await store.writeBytes('recordings/b.m4a', <int>[1]);
      expect(await store.size('recordings/a.wav'), 3);
      expect(await store.list('recordings'), <String>['recordings/a.wav', 'recordings/b.m4a']);
      expect(await store.list('recordings', extension: '.wav'), <String>['recordings/a.wav']);
      await store.delete('recordings/a.wav');
      expect(await store.exists('recordings/a.wav'), isFalse);
      expect(await store.clear('recordings'), 1);
      expect(await store.list('recordings'), isEmpty);
    });
  });

  group('Lo que llega de un archivo se valida (G11)', () {
    test('Preajuste y setlist con valores hostiles', () {
      final Preset p = Preset.fromJson(<String, dynamic>{
        'id': '../../etc',
        'name': 'x' * 5000,
        'rhythm': <String, dynamic>{'bpm': -1, 'beatsPerBar': 'tres'},
        'notes': 42,
        'createdAt': 'ayer',
      });
      expect(p.id, isNot('../../etc'));
      expect(RegExp(r'^[A-Za-z0-9_\-]+$').hasMatch(p.id), isTrue);
      expect(p.name.length, Preset.maxName);
      expect(p.rhythm.bpm, RhythmConfig.minBpm);
      expect(p.rhythm.beatsPerBar, 4);
      expect(p.notes, '');
      final Setlist s = Setlist.fromJson(<String, dynamic>{
        'id': 'ok_1',
        'name': null,
        'presetIds': <Object?>['a', 3, null, '../b', 'c' * 100, 'd-2'],
      });
      expect(s.id, 'ok_1');
      expect(s.name, '');
      expect(s.presetIds, <String>['a', 'd-2']);
    });

    test('Una grabación que apunta fuera de su carpeta se descarta', () {
      expect(Recording.fromJson(<String, dynamic>{'file': '../../secreto.m4a'}), isNull);
      expect(Recording.fromJson(<String, dynamic>{'file': 'recordings/../x.m4a'}), isNull);
      expect(Recording.fromJson(<String, dynamic>{'file': '/data/x.m4a'}), isNull);
      expect(Recording.fromJson(<String, dynamic>{'file': 'recordings/x.exe'}), isNull);
      final Recording? r = Recording.fromJson(<String, dynamic>{
        'file': 'recordings/123.wav',
        'format': 'mp3',
        'durationMs': -5,
        'bpm': double.infinity,
        'name': 7,
      });
      expect(r, isNotNull);
      expect(r!.format, 'aac');
      expect(r.durationMs, 0);
      expect(r.bpm, isNull);
      expect(r.name, '');
    });

    test('Un intervalo de práctica imposible se descarta o se acota', () {
      expect(PracticeSession.fromJson(<String, dynamic>{'start': '2026-10-18T10:00:00', 'end': '2026-10-18T09:00:00', 'tool': 'metronomo'}), isNull);
      expect(PracticeSession.fromJson(<String, dynamic>{'start': '2026-10-18T10:00:00', 'end': '2026-10-18T11:00:00', 'tool': 'cohete'}), isNull);
      expect(PracticeSession.fromJson(<String, dynamic>{'start': 5, 'end': '2026-10-18T11:00:00', 'tool': 'afinador'}), isNull);
      final PracticeSession? long = PracticeSession.fromJson(<String, dynamic>{'start': '2026-10-01T10:00:00', 'end': '2026-10-18T11:00:00', 'tool': 'tono'});
      expect(long!.end.difference(long.start), const Duration(hours: 24));
    });

    test('Importar preajustes valida, no duplica y rechaza lo que no es de Clave', () async {
      final AppState st = AppState(JsonStore(root: tmp));
      await st.addPreset(Preset(id: 'p1', name: 'Cumbia', rhythm: const RhythmConfig(bpm: 92, beatsPerBar: 2)));
      final ImportResult r = await st.importPresets(<String, dynamic>{
        'presets': <Object?>[
          <String, dynamic>{'id': 'p1', 'name': 'Repetido'},
          <String, dynamic>{'id': 'p2', 'name': 'Bambuco', 'rhythm': <String, dynamic>{'bpm': 96, 'beatsPerBar': 3}},
          'basura',
          <String, dynamic>{'id': 'p3', 'name': 'Raro', 'rhythm': <String, dynamic>{'bpm': 'NaN', 'beatsPerBar': 99}},
        ],
        'setlists': <Object?>[
          <String, dynamic>{'id': 's1', 'name': 'Ensayo', 'presetIds': <Object?>['p2', 'no-existe', 'p1']},
        ],
      });
      expect(r.presets, 2);
      expect(r.setlists, 1);
      expect(st.presets.map((Preset p) => p.name), containsAll(<String>['Cumbia', 'Bambuco', 'Raro']));
      expect(st.presetById('p3')!.rhythm.beatsPerBar, RhythmConfig.maxBeats);
      expect(st.setlistById('s1')!.presetIds, <String>['p2', 'p1']);
      await expectLater(st.importPresets(<String, dynamic>{'otra': 'app'}), throwsFormatException);
      // Lo exportado se vuelve a importar sin duplicar nada.
      final ImportResult again = await st.importPresets(st.exportPresets());
      expect(again.presets, 0);
      expect(again.setlists, 0);
      await st.store.flush();
      final AppState reloaded = AppState(JsonStore(root: tmp));
      await reloaded.load();
      expect(reloaded.presets.length, 3);
      expect(reloaded.setlistById('s1')!.presetIds, <String>['p2', 'p1']);
    });
  });
}
