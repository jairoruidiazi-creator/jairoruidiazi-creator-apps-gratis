import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/app_scope.dart';
import 'package:sello/core/app_state.dart';
import 'package:sello/core/backup.dart';
import 'package:sello/core/device_files.dart';
import 'package:sello/core/exports.dart';
import 'package:sello/core/settings.dart';
import 'package:sello/core/sharing.dart';
import 'package:sello/geo/heading.dart';
import 'package:sello/geo/location_service.dart';
import 'package:sello/model/models.dart';
import 'package:sello/stamp/composer.dart';
import 'package:sello/ui/gallery/gallery_screen.dart';
import 'package:sello/ui/gallery/photo_detail_screen.dart';
import 'package:sello/ui/settings/settings_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// B1: en iOS (Xcode 26) la hoja de compartir falla sin un origen no vacío,
/// también en iPhone. Estas pruebas exigen que cada salida pase el rectángulo
/// del botón pulsado.
void main() {
  late Directory tmp;
  late Services services;
  late FakeDeviceFiles files;
  final List<ShareParams> shared = <ShareParams>[];
  // Si los archivos existían mientras la hoja de compartir estaba abierta.
  final List<bool> existedWhileSharing = <bool>[];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sello_share');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppSettings settings = await testSettings();
    final AppState state = await testState(tmp);
    await state.store.writeBytes('photos/general/a_a-orig.jpg', syntheticJpeg(64, 48, orientation: 6, make: 'Acme'));
    composeStampedSync(ComposeJob(
      originalPath: await state.store.absolutePath('photos/general/a_a-orig.jpg'),
      outputPath: await state.store.absolutePath('photos/general/a_a.jpg'),
      quality: 85,
      latitude: 4.711,
      longitude: -74.0721,
      takenAt: DateTime.utc(2026, 3, 9, 19, 5),
    ));
    await state.addPhoto(PhotoRecord(id: 'a', projectId: 'general', originalFile: 'photos/general/a_a-orig.jpg', stampedFile: 'photos/general/a_a.jpg', takenAt: DateTime.utc(2026, 3, 9, 19, 5), latitude: 4.711, longitude: -74.0721, width: 48, height: 64, description: 'Sello de prueba'));
    files = FakeDeviceFiles(picker: false);
    services = Services(settings: settings, state: state, store: state.store, location: LocationService(backend: FakeLocationBackend()), heading: HeadingService(useSystemHeading: false), files: files);
    shared.clear();
    existedWhileSharing.clear();
    shareSheet = (ShareParams p) async {
      existedWhileSharing.add((p.files ?? <XFile>[]).every((XFile f) => File(f.path).existsSync()));
      shared.add(p);
      return const ShareResult('ok', ShareResultStatus.success);
    };
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Widget app(Widget home) => AppScope(services: services, child: MaterialApp(home: home));

  void expectAnchoredOn(WidgetTester tester, Finder button) {
    expect(shared, isNotEmpty);
    final Rect? origin = shared.last.sharePositionOrigin;
    expect(origin, isNotNull);
    expect(origin!.isEmpty, isFalse);
    expect(origin.contains(tester.getCenter(button)), isTrue, reason: 'origen $origin, botón ${tester.getRect(button)}');
  }

  testWidgets('Detalle: compartir y compartir sin EXIF', (WidgetTester tester) async {
    await tester.pumpWidget(app(const PhotoDetailScreen(photoId: 'a')));
    await tester.pump();
    final Finder share = find.byTooltip('Compartir');
    await tester.tap(share);
    await waitReal(tester, () => shared.isNotEmpty);
    expectAnchoredOn(tester, share);
    expect(shared.last.files!.single.path, endsWith('a_a.jpg'));
    expect(shared.last.text, contains('Sello de prueba'));

    final Finder menu = find.byTooltip('Más opciones');
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compartir sin EXIF'));
    await waitReal(tester, () => shared.length == 2);
    expectAnchoredOn(tester, menu);
    final String path = shared.last.files!.single.path;
    expect(path, endsWith('a_a_sin_exif.jpg'));
    final StampExif clean = readStampExif(File(path).readAsBytesSync());
    expect(clean.latitude, isNull);
    expect(clean.takenAt, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('El detalle no decodifica la foto entera; con zoom, más detalle pero con tope (M3 de la ronda 3)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const PhotoDetailScreen(photoId: 'a')));
    await tester.pump();
    await waitReal(tester, () => find.byType(InteractiveViewer).evaluate().isNotEmpty);
    ResizeImage shown() => tester.widget<Image>(find.descendant(of: find.byType(InteractiveViewer), matching: find.byType(Image))).image as ResizeImage;
    expect(shown().policy, ResizeImagePolicy.fit);
    expect(shown().width, lessThanOrEqualTo(4096));
    expect(shown().height, shown().width);
    final InteractiveViewer viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    viewer.transformationController!.value = Matrix4.diagonal3Values(3, 3, 1);
    await tester.pump();
    expect(shown().width, kDetailZoomBox);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Galería: compartir lo seleccionado y exportar', (WidgetTester tester) async {
    await tester.pumpWidget(app(const GalleryScreen()));
    await tester.pump();
    await tester.longPress(find.descendant(of: find.byType(SliverGrid), matching: find.byType(GestureDetector)).first);
    await tester.pump();
    final Finder share = find.byTooltip('Compartir');
    await tester.tap(share);
    await waitReal(tester, () => shared.isNotEmpty);
    expectAnchoredOn(tester, share);
    await tester.tap(find.byTooltip('Cancelar selección'));
    await tester.pump();

    final Finder export = find.text('Exportar');
    await tester.tap(export);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CSV'));
    await waitReal(tester, () => shared.length == 2);
    expectAnchoredOn(tester, find.byType(FloatingActionButton));
    final File csv = File(shared.last.files!.single.path);
    expect(csv.readAsBytesSync().sublist(0, 3), <int>[0xEF, 0xBB, 0xBF]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Ajustes: la copia completa se comparte anclada en su botón', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const SettingsScreen()));
    await tester.pump();
    final Finder button = find.text('Crear copia completa');
    await tester.scrollUntilVisible(button, 300, scrollable: find.byType(Scrollable).first);
    await tester.pump();
    await tester.tap(button);
    await waitReal(tester, () => find.text('Crear').evaluate().isNotEmpty);
    await tester.tap(find.text('Crear'));
    await waitReal(tester, () => shared.isNotEmpty, maxTenths: 150);
    expectAnchoredOn(tester, button);
    final String zip = shared.last.files!.single.path;
    expect(zip, endsWith('.zip'));
    // La hoja de compartir la tuvo; al cerrarse, la copia de la app se borra
    // (en iPhone quedaba en Documents/sello/exports: M2 de la ronda 5).
    expect(existedWhileSharing.last, isTrue);
    await waitReal(tester, () => !File(zip).existsSync());
    expect(File(zip).existsSync(), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Las salidas selladas no llevan originales a escondidas (M3)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      // Una foto que todavía se está sellando: solo tiene el original.
      await services.store.writeBytes('photos/general/b_b-orig.jpg', syntheticJpeg(64, 48));
      await services.state.addPhoto(PhotoRecord(id: 'b', projectId: 'general', originalFile: 'photos/general/b_b-orig.jpg', stampedFile: 'photos/general/b_b.jpg', takenAt: DateTime.utc(2026, 3, 9, 19, 6), status: PhotoStatus.pending, latitude: 4.712, longitude: -74.072, description: 'Pendiente'));
    });
    // La miniatura de la pendiente gira sin parar: nada de pumpAndSettle.
    Future<void> pumpABit() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    await tester.pumpWidget(app(const GalleryScreen()));
    await tester.pump();
    // Compartir las fotos selladas: se avisa y va solo la sellada.
    await tester.tap(find.text('Exportar'));
    await pumpABit();
    await tester.tap(find.text('Fotos selladas'));
    await waitReal(tester, () => find.text('Algunas fotos quedan fuera').evaluate().isNotEmpty);
    expect(find.textContaining('1 de las 2 fotos todavía no están selladas'), findsOneWidget);
    await tester.tap(find.text('Seguir con 1'));
    await waitReal(tester, () => shared.isNotEmpty);
    expect(shared.single.files!.map((XFile f) => f.path.split('/').last), <String>['a_a.jpg']);
    // KMZ: el mismo aviso, y dentro ni la foto ni el punto de la pendiente.
    await tester.tap(find.text('Exportar'));
    await pumpABit();
    await tester.tap(find.text('KMZ'));
    await waitReal(tester, () => find.text('Algunas fotos quedan fuera').evaluate().isNotEmpty);
    await tester.tap(find.text('Seguir con 1'));
    await waitReal(tester, () => shared.length == 2, maxTenths: 150);
    final Archive kmz = ZipDecoder().decodeBytes(File(shared.last.files!.single.path).readAsBytesSync());
    final List<String> names = kmz.files.map((ArchiveFile f) => f.name).toList();
    expect(names.where((String n) => n.endsWith('.jpg')), hasLength(1));
    expect(names.any((String n) => n.contains('b_b')), isFalse);
    final String doc = utf8.decode(kmz.findFile('doc.kml')!.content);
    expect(doc.contains('Pendiente'), isFalse);
    // Cancelar el aviso no exporta nada.
    await tester.tap(find.text('Exportar'));
    await pumpABit();
    await tester.tap(find.text('Informe PDF'));
    await waitReal(tester, () => find.text('Algunas fotos quedan fuera').evaluate().isNotEmpty);
    await tester.tap(find.text('Cancelar'));
    await pumpABit();
    expect(shared, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('Copia completa en Android, sin pasar entera por la memoria (G2)', () {
    Future<void> openSettings(WidgetTester tester, String buttonText) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const SettingsScreen()));
      await tester.pump();
      final Finder button = find.text(buttonText);
      await tester.scrollUntilVisible(button, 300, scrollable: find.byType(Scrollable).first);
      await tester.pump();
      await tester.tap(button);
    }

    testWidgets('Dice cuánto ocupa, la guarda donde se elija y borra la de la app', (WidgetTester tester) async {
      files
        ..picker = true
        ..free = 8 * 1024 * 1024 * 1024;
      await openSettings(tester, 'Crear copia completa');
      await waitReal(tester, () => find.text('Crear').evaluate().isNotEmpty);
      // El tamaño y el espacio libre se ven antes de crearla.
      expect(find.textContaining('hay 8,0 GB'), findsOneWidget);
      expect(find.textContaining('ocupará otro tanto'), findsOneWidget);
      await tester.tap(find.text('Crear'));
      await waitReal(tester, () => files.saved.isNotEmpty, maxTenths: 150);
      await waitReal(tester, () => find.text('Copia guardada.').evaluate().isNotEmpty);
      // Al selector del sistema le llega un ZIP ya escrito en disco (no bytes).
      expect(files.saved.single, endsWith('.zip'));
      expect(files.savedSizes.single, greaterThan(1000));
      // Sin hoja de compartir (que la volvía a copiar a su caché).
      expect(shared, isEmpty);
      // La copia de la app ya sobra.
      await waitReal(tester, () => !File(files.saved.single).existsSync());
      expect(File(files.saved.single).existsSync(), isFalse);
      expect(find.text('Copia guardada.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Sin espacio suficiente no deja crearla', (WidgetTester tester) async {
      files
        ..picker = true
        ..free = 1024;
      await openSettings(tester, 'Crear copia completa');
      await waitReal(tester, () => find.text('Cancelar').evaluate().isNotEmpty);
      expect(find.textContaining('No hay espacio suficiente'), findsOneWidget);
      expect(find.text('Crear'), findsNothing);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(files.saved, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Restaurar copia el documento a un archivo, restaura desde él y lo borra', (WidgetTester tester) async {
      final String zip = '${tmp.path}/copia.zip';
      await tester.runAsync(() async {
        await writeZipFile(zip, await Backup.entries(services.state));
        await services.state.deletePhotos(services.state.photos.toList());
      });
      expect(services.state.photos, isEmpty);
      files
        ..picker = true
        ..free = 8 * 1024 * 1024 * 1024
        ..toOpen = zip;
      await openSettings(tester, 'Restaurar una copia');
      await waitReal(tester, () => find.text('Restaurar').evaluate().isNotEmpty);
      // Antes de copiar nada: el peso, lo que hace falta y lo que hay.
      expect(files.copies, 0);
      expect(find.textContaining('La copia pesa'), findsOneWidget);
      expect(find.textContaining('hacen falta unos'), findsOneWidget);
      expect(find.textContaining('Hay 8,0 GB libres'), findsOneWidget);
      await tester.tap(find.text('Restaurar'));
      await waitReal(tester, () => services.state.photos.isNotEmpty, maxTenths: 150);
      await waitReal(tester, () => find.textContaining('Copia restaurada').evaluate().isNotEmpty);
      expect(services.state.photos.single.id, 'a');
      expect(find.textContaining('Copia restaurada: 1 fotos'), findsOneWidget);
      // Se avisó el avance de la copia hasta el final.
      expect(files.progress, isNotEmpty);
      expect(files.progress.last, File(zip).lengthSync());
      final String brought = (await tester.runAsync(() => services.store.absolutePath('exports/restaurar_copia.zip')))!;
      await waitReal(tester, () => !File(brought).existsSync());
      expect(File(brought).existsSync(), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('iPhone: la copia que deja el selector en tmp/…-Inbox se borra al terminar, al fallar o al cancelar (M1 de la ronda 5)', (WidgetTester tester) async {
      final String zip = '${tmp.path}/copia.zip';
      await tester.runAsync(() async {
        await writeZipFile(zip, await Backup.entries(services.state));
        await services.state.deletePhotos(services.state.photos.toList());
      });
      // Como en el teléfono: TMPDIR del contenedor y Library/Caches.
      final String inbox = '${tmp.path}/tmp/co.appsgratis.sello-Inbox';
      Directory(inbox).createSync(recursive: true);
      files
        ..picker = false
        ..free = 8 * 1024 * 1024 * 1024
        ..tempDirs = <String>['${tmp.path}/tmp/', '${tmp.path}/Library/Caches'];
      Future<void> restore(String picked, String expected, {bool cancel = false}) async {
        files.toPickCopy = picked;
        await openSettings(tester, 'Restaurar una copia');
        if (cancel) {
          await waitReal(tester, () => find.text('Cancelar').evaluate().isNotEmpty);
          await tester.tap(find.text('Cancelar'));
          await waitReal(tester, () => !File(picked).existsSync());
        } else {
          await waitReal(tester, () => find.text('Restaurar').evaluate().isNotEmpty);
          await tester.tap(find.text('Restaurar'));
          await waitReal(tester, () => find.textContaining(expected).evaluate().isNotEmpty, maxTenths: 150);
          await waitReal(tester, () => !File(picked).existsSync());
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }

      // Con éxito.
      final String ok = '$inbox/copia.zip';
      File(zip).copySync(ok);
      await restore(ok, 'Copia restaurada');
      expect(File(ok).existsSync(), isFalse);
      // La carpeta del selector quedó vacía y también se borró.
      await waitReal(tester, () => !Directory(inbox).existsSync());
      expect(Directory(inbox).existsSync(), isFalse);
      // Un archivo que no es una copia: falla y la copia igual se borra.
      Directory(inbox).createSync(recursive: true);
      final String bad = '$inbox/otro.zip';
      await tester.runAsync(() => writeZipFile(bad, <ArchiveEntry>[const ArchiveEntry.bytes('hola.txt', <int>[104, 111, 108, 97])]));
      await restore(bad, 'no es una copia de Sello');
      expect(File(bad).existsSync(), isFalse);
      // Cancelar en el diálogo.
      Directory(inbox).createSync(recursive: true);
      final String third = '$inbox/tercera.zip';
      File(zip).copySync(third);
      await restore(third, '', cancel: true);
      expect(File(third).existsSync(), isFalse);
      // Un archivo fuera de las carpetas temporales nunca se borra.
      final String mine = '${tmp.path}/Documents/mia.zip';
      File(mine).parent.createSync(recursive: true);
      File(zip).copySync(mine);
      files.toPickCopy = mine;
      await openSettings(tester, 'Restaurar una copia');
      await waitReal(tester, () => find.text('Cancelar').evaluate().isNotEmpty);
      await tester.tap(find.text('Cancelar'));
      await waitReal(tester, () => false, maxTenths: 5);
      expect(File(mine).existsSync(), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    test('Qué cuenta como copia del selector: rutas reales de iOS (M1 de la ronda 5)', () {
      const String container = '/private/var/mobile/Containers/Data/Application/6F1B2C3D-0000-4E5F-9A8B-1234567890AB';
      // Directory.systemTemp (TMPDIR) y getTemporaryDirectory() (Library/Caches) en un iPhone.
      const List<String> dirs = <String>['$container/tmp/', '/var/mobile/Containers/Data/Application/6F1B2C3D-0000-4E5F-9A8B-1234567890AB/Library/Caches'];
      expect(isPickerCopy('$container/tmp/co.appsgratis.sello-Inbox/sello_copia_20261018_1005.zip', dirs), isTrue);
      // La misma ruta sin /private delante.
      expect(isPickerCopy('/var/mobile/Containers/Data/Application/6F1B2C3D-0000-4E5F-9A8B-1234567890AB/tmp/co.appsgratis.sello-Inbox/copia.zip', dirs), isTrue);
      expect(isPickerCopy('$container/Library/Caches/copia.zip', dirs), isTrue);
      // Lo que no es temporal: Documents de la app, iCloud Drive, otra app, la carpeta misma, rutas con "..".
      expect(isPickerCopy('$container/Documents/sello/photos/general/a.jpg', dirs), isFalse);
      expect(isPickerCopy('/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/copia.zip', dirs), isFalse);
      expect(isPickerCopy('/private/var/mobile/Containers/Data/Application/OTRA/tmp/copia.zip', dirs), isFalse);
      expect(isPickerCopy('$container/tmp', dirs), isFalse);
      expect(isPickerCopy('$container/tmp/../Documents/copia.zip', dirs), isFalse);
      // Sin carpetas temporales no se borra nada.
      expect(isPickerCopy('$container/tmp/x.zip', const <String>[]), isFalse);
      expect(isPickerCopy('/x.zip', const <String>['/']), isFalse);
    });

    Future<String> backupWithoutPhotos(WidgetTester tester) async {
      final String zip = '${tmp.path}/copia.zip';
      await tester.runAsync(() async {
        await writeZipFile(zip, await Backup.entries(services.state));
        await services.state.deletePhotos(services.state.photos.toList());
      });
      return zip;
    }

    testWidgets('Restaurar sin espacio para traer la copia y agregar sus fotos: no copia nada (M5 de la ronda 3)', (WidgetTester tester) async {
      final String zip = await backupWithoutPhotos(tester);
      final int size = File(zip).lengthSync();
      files
        ..picker = true
        // Alcanza para la copia, no para la copia y sus fotos.
        ..free = size + kBackupSpareBytes
        ..toOpen = zip;
      await openSettings(tester, 'Restaurar una copia');
      await waitReal(tester, () => find.text('Cancelar').evaluate().isNotEmpty);
      expect(find.textContaining('No hay espacio suficiente'), findsOneWidget);
      expect(find.text('Restaurar'), findsNothing);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(files.copies, 0);
      expect(services.state.photos, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final bool noSpace in <bool>[false, true]) {
      testWidgets(noSpace ? 'Si el teléfono se llena al traer la copia se dice claro y no queda nada a medias' : 'Cancelar mientras se trae la copia no deja nada a medias', (WidgetTester tester) async {
        final String zip = await backupWithoutPhotos(tester);
        files
          ..picker = true
          ..free = 8 * 1024 * 1024 * 1024
          ..toOpen = zip;
        if (noSpace) {
          files.noSpaceWhileCopying = true;
        } else {
          files.cancelAt = 1024;
        }
        await openSettings(tester, 'Restaurar una copia');
        await waitReal(tester, () => find.text('Restaurar').evaluate().isNotEmpty);
        await tester.tap(find.text('Restaurar'));
        final String expected = noSpace ? 'se quedó sin espacio al traer la copia' : 'Se canceló la restauración';
        await waitReal(tester, () => find.textContaining(expected).evaluate().isNotEmpty, maxTenths: 150);
        expect(find.textContaining(expected), findsOneWidget);
        expect(find.textContaining('ENOSPC'), findsNothing);
        expect(services.state.photos, isEmpty);
        final String brought = (await tester.runAsync(() => services.store.absolutePath('exports/restaurar_copia.zip')))!;
        expect(File(brought).existsSync(), isFalse);
        expect(File('$brought.tmp-open').existsSync(), isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });

  testWidgets('El origen nunca es un rectángulo vacío', (WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (BuildContext c) {
      captured = c;
      return const SizedBox(width: 10, height: 10);
    })));
    expect(shareOriginOf(captured).isEmpty, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    // Con el botón ya fuera de pantalla se usa un punto, nunca {0, 0, 0, 0}.
    expect(shareOriginOf(captured).isEmpty, isFalse);
    await shareFiles(<String>['/x.jpg'], origin: const Rect.fromLTWH(1, 2, 3, 4), text: '  ');
    expect(shared.single.sharePositionOrigin, const Rect.fromLTWH(1, 2, 3, 4));
    expect(shared.single.text, isNull);
  });

  test('share_plus con el arreglo del origen en iOS (13.3.1 o posterior)', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch m = RegExp(r'^\s*share_plus:\s*\^(\d+)\.(\d+)\.(\d+)', multiLine: true).firstMatch(pubspec)!;
    final List<int> v = <int>[for (int i = 1; i <= 3; i++) int.parse(m.group(i)!)];
    expect(v[0] * 10000 + v[1] * 100 + v[2], greaterThanOrEqualTo(130301));
  });
}
