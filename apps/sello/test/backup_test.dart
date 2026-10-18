import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/app_state.dart';
import 'package:sello/core/backup.dart';
import 'package:sello/core/exports.dart';
import 'package:sello/model/models.dart';

import 'support/fakes.dart';

/// M21: los datos se pueden pasar a otro teléfono con una copia completa.
void main() {
  late Directory a;
  late Directory b;

  setUp(() async {
    a = await Directory.systemTemp.createTemp('sello_backup_a');
    b = await Directory.systemTemp.createTemp('sello_backup_b');
  });

  tearDown(() async {
    await a.delete(recursive: true);
    await b.delete(recursive: true);
  });

  test('La copia completa lleva fotos, fichas, proyectos, plantillas y logos, y restaurar no duplica', () async {
    final AppState source = await testState(a);
    final Project obra = await source.addProject('Obra');
    obra.fields.add(const FieldDef('k1', 'Lote'));
    final StampTemplate tpl = await source.addTemplate('Con logo', copyOf: source.templateById('default'));
    await source.store.writeBytes('logos/logo.png', <int>[1, 2, 3, 4]);
    tpl.logoPath = 'logos/logo.png';
    obra.templateId = tpl.id;
    await source.saveProjects();
    for (final String id in <String>['f1', 'f2']) {
      await source.store.writeBytes('photos/${obra.id}/x_$id-orig.jpg', syntheticJpeg(32, 24));
      await source.store.writeBytes('photos/${obra.id}/x_$id.jpg', syntheticJpeg(32, 24));
      await source.addPhoto(PhotoRecord(
        id: id,
        projectId: obra.id,
        originalFile: 'photos/${obra.id}/x_$id-orig.jpg',
        stampedFile: 'photos/${obra.id}/x_$id.jpg',
        takenAt: DateTime.utc(2026, 3, 9, 19, id == 'f1' ? 1 : 2),
        utcOffsetMinutes: -300,
        latitude: 4.711,
        longitude: -74.0721,
        fields: <String, String>{'k1': '12'},
        fieldLabels: <String, String>{'k1': 'Lote'},
        notes: 'Nota $id',
      ));
    }
    final String zip = '${a.path}/copia.zip';
    await writeZipFile(zip, await Backup.entries(source));

    final AppState target = await testState(b);
    final RestoreSummary r = await Backup.restore(zip, target);
    expect(r.photos, 2);
    expect(r.projects, 1);
    expect(r.templates, 1);
    expect(r.files, 5);
    expect(target.photoById('f1')!.notes, 'Nota f1');
    expect(target.photoById('f2')!.labelFor('k1'), 'Lote');
    expect(target.projectById(obra.id).fields.single.label, 'Lote');
    expect(target.templateForProject(target.projectById(obra.id)).logoPath, 'logos/logo.png');
    expect(await target.logoFile(target.templateById(tpl.id)), isNotNull);
    expect(File(await target.store.absolutePath('photos/${obra.id}/x_f2.jpg')).existsSync(), isTrue);
    // Persistido y sin duplicar al restaurar otra vez.
    final AppState reopened = await testState(b);
    expect(reopened.photos.length, 2);
    final RestoreSummary again = await Backup.restore(zip, reopened);
    expect(again.photos, 0);
    expect(again.files, 0);
    expect(reopened.photos.length, 2);
  });

  test('Restaurar avisa el avance y cancelar no agrega nada (M5 de la ronda 3)', () async {
    final AppState source = await testState(a);
    for (final String id in <String>['f1', 'f2', 'f3']) {
      await source.store.writeBytes('photos/general/x_$id.jpg', syntheticJpeg(32, 24));
      await source.addPhoto(PhotoRecord(id: id, projectId: 'general', originalFile: '', stampedFile: 'photos/general/x_$id.jpg', takenAt: DateTime.utc(2026, 3, 9)));
    }
    final String zip = '${a.path}/copia.zip';
    await writeZipFile(zip, await Backup.entries(source));

    // Cancelada: ni fichas ni archivos (que el reindexado "recuperaría").
    final AppState cancelled = await testState(b);
    final ExportCancel cancel = ExportCancel()..cancel();
    await expectLater(Backup.restore(zip, cancelled, cancel: cancel), throwsA(isA<ExportCancelled>()));
    expect(cancelled.photos, isEmpty);
    expect(Directory('${b.path}/sello/photos').existsSync() ? Directory('${b.path}/sello/photos').listSync(recursive: true).whereType<File>() : <File>[], isEmpty);
    expect((await testState(b)).photos, isEmpty);
    expect(File('${b.path}/sello/exports/.cancelar-restaurar').existsSync(), isFalse);

    // Completa: el avance llega hasta el total.
    final List<List<int>> progress = <List<int>>[];
    final RestoreSummary r = await Backup.restore(zip, cancelled, onProgress: (int d, int t) => progress.add(<int>[d, t]));
    expect(r.photos, 3);
    expect(progress, isNotEmpty);
    expect(progress.last[0], progress.last[1]);
    expect(progress.last[1], greaterThanOrEqualTo(5));
  });

  test('Un ZIP cualquiera no se toma por una copia', () async {
    final String zip = '${a.path}/otro.zip';
    await writeZipFile(zip, <ArchiveEntry>[const ArchiveEntry.bytes('hola.txt', <int>[104, 111, 108, 97])]);
    final AppState target = await testState(b);
    await expectLater(Backup.restore(zip, target), throwsA(isA<NotABackup>()));
  });

  test('Rutas peligrosas dentro de la copia se ignoran', () async {
    final AppState target = await testState(b);
    final String zip = '${a.path}/mala.zip';
    await writeZipFile(zip, <ArchiveEntry>[
      ArchiveEntry.bytes(Backup.manifestName, '{"app": "Sello", "format": 1}'.codeUnits),
      const ArchiveEntry.bytes('../fuera.txt', <int>[1]),
      const ArchiveEntry.bytes('photos/../../fuera.jpg', <int>[1]),
      const ArchiveEntry.bytes('settings.json', <int>[1]),
    ]);
    final RestoreSummary r = await Backup.restore(zip, target);
    expect(r.files, 0);
    expect(File('${b.path}/fuera.txt').existsSync(), isFalse);
    expect(File('${b.path}/fuera.jpg').existsSync(), isFalse);
  });
}
