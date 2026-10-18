import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/app_scope.dart';
import 'package:sello/core/app_state.dart';
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
  final List<ShareParams> shared = <ShareParams>[];

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
    services = Services(settings: settings, state: state, store: state.store, location: LocationService(backend: FakeLocationBackend()), heading: HeadingService(useSystemHeading: false));
    shared.clear();
    shareSheet = (ShareParams p) async {
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
    await waitReal(tester, () => shared.isNotEmpty, maxTenths: 150);
    expectAnchoredOn(tester, button);
    expect(shared.last.files!.single.path, endsWith('.zip'));
    await tester.pumpWidget(const SizedBox.shrink());
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
