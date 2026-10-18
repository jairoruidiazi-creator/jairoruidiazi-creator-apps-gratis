import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/core/app_state.dart';
import 'package:pilas/core/storage.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/model/profile.dart';

/// Guardado atómico, en cola y con recuperación (auditoría G3).
void main() {
  late Directory tmp;
  late JsonStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pilas_storage');
    store = JsonStore(root: tmp);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<File> archivo(String rel) async => File(await store.absolutePath(rel));

  test('Muchas escrituras seguidas del mismo archivo no se pisan ni dejan temporales', () async {
    final List<Future<void>> todas = <Future<void>>[
      for (int i = 0; i < 60; i++) store.writeJson('progress/a.json', <String, dynamic>{'n': i, 'relleno': 'x' * (i * 50)}),
    ];
    await Future.wait(todas);
    final Map<String, dynamic>? data = await store.readJson('progress/a.json');
    expect(data?['n'], 59);
    final List<String> sobrantes = (await (await archivo('progress/a.json')).parent.list().toList()).map((FileSystemEntity e) => e.path).where((String p) => p.endsWith('.tmp')).toList();
    expect(sobrantes, isEmpty);
  });

  test('Si el archivo se daña, se recupera la copia y el dañado queda aparte', () async {
    await store.writeJson('perfiles.json', <String, dynamic>{'v': 1});
    await store.writeJson('perfiles.json', <String, dynamic>{'v': 2});
    // La copia .bak guarda la versión anterior, sana.
    final File f = await archivo('perfiles.json');
    await f.writeAsString('{"v": 2, "cortado');
    final JsonRead r = await store.readJsonSafe('perfiles.json');
    expect(r.outcome, ReadOutcome.recovered);
    expect(r.data?['v'], 1);
    expect(r.asidePath, isNotNull);
    expect(r.asidePath, contains('.corrupto-'));
    expect(File(r.asidePath!).existsSync(), isTrue);
    // El archivo principal quedó sano otra vez.
    expect((await store.readJsonSafe('perfiles.json')).outcome, ReadOutcome.ok);
  });

  test('Si el archivo y su copia están dañados, se apartan y se avisa (nunca se pisan en silencio)', () async {
    await store.writeJson('x.json', <String, dynamic>{'v': 1});
    await store.writeJson('x.json', <String, dynamic>{'v': 2});
    final File f = await archivo('x.json');
    await f.writeAsBytes(<int>[0xff, 0xfe, 0x00, 0x7b]); // ni siquiera es UTF-8
    await File('${f.path}.bak').writeAsString('[1, 2');
    final JsonRead r = await store.readJsonSafe('x.json');
    expect(r.outcome, ReadOutcome.corrupt);
    expect(r.data, isNull);
    expect(File(r.asidePath!).existsSync(), isTrue);
    expect(f.existsSync(), isFalse);
  });

  test('Un avance dañado no borra a los demás niños y deja un aviso; la app arranca igual', () async {
    final AppState a = AppState(store);
    await a.load();
    final Profile ana = await a.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1, bandOverride: AgeBand.b5a6);
    final Profile beto = await a.addProfile(nombre: 'Beto', avatar: '1f436', birthYear: 2019, birthMonth: 1, bandOverride: AgeBand.b5a6);
    await a.selectProfile(ana);
    await a.recordRound(GameRegistry.byId('patrones')!, AgeBand.b5a6, true);
    await a.selectProfile(beto);
    await a.recordRound(GameRegistry.byId('patrones')!, AgeBand.b5a6, true);
    await a.selectProfile(null);
    a.dispose();
    // Se daña el avance de Beto (archivo y copia).
    final File f = await archivo('progress/${beto.id}.json');
    await f.writeAsString('{"mastery": {');
    final File bak = File('${f.path}.bak');
    if (bak.existsSync()) {
      await bak.writeAsString('nada');
    }
    final AppState b = AppState(store);
    await b.load();
    expect(b.loaded, isTrue);
    expect(b.profiles.length, 2);
    expect(b.progressOf(ana.id).masteryIfAny('patrones', AgeBand.b5a6)?.roundsPlayed, 1);
    expect(b.notices, isNotEmpty);
    expect(b.notices.first.texto, contains('Beto'));
    b.dispose();
  });

  test('Un JSON válido pero con otro formato se aparta tal cual y se avisa', () async {
    final AppState a = AppState(store);
    await a.load();
    final Profile ana = await a.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1);
    a.dispose();
    await store.writeJson('progress/${ana.id}.json', <String, dynamic>{'mastery': 'no es un mapa'});
    final AppState b = AppState(store);
    await b.load();
    expect(b.notices.any((StorageNotice n) => n.texto.contains('aparte')), isTrue);
    final List<String> apartados = (await (await archivo('progress/x')).parent.list().toList()).map((FileSystemEntity e) => e.path).where((String p) => p.contains('.corrupto-')).toList();
    expect(apartados, isNotEmpty);
    expect(jsonDecode(await File(apartados.first).readAsString()), isA<Map<String, dynamic>>());
    b.dispose();
  });
}
