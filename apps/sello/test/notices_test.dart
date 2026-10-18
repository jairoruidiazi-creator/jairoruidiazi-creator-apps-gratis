import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/app.dart';
import 'package:sello/core/app_scope.dart';
import 'package:sello/core/app_state.dart';
import 'package:sello/core/settings.dart';
import 'package:sello/geo/heading.dart';
import 'package:sello/geo/location_service.dart';
import 'package:sello/model/models.dart';
import 'package:sello/stamp/capture_pipeline.dart';
import 'package:sello/ui/map/map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// Avisos visibles: un sellado que falla (G1) y un índice recuperado (B3).
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sello_notices');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    MapScreen.tilesEnabled = false;
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Services servicesFor(AppState state, AppSettings settings, CapturePipeline pipeline) =>
      Services(settings: settings, state: state, store: state.store, location: LocationService(backend: FakeLocationBackend()), heading: HeadingService(useSystemHeading: false), pipeline: pipeline);

  testWidgets('Si una foto no se puede sellar, se avisa y se puede ir a ella', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    late Services services;
    late RecordingPipeline pipeline;
    await tester.runAsync(() async {
      final AppSettings settings = await testSettings();
      final AppState state = await testState(tmp);
      await state.addPhoto(PhotoRecord(id: 'p1', projectId: 'general', originalFile: 'photos/general/p1-orig.jpg', stampedFile: 'photos/general/p1.jpg', takenAt: DateTime.utc(2026, 3, 9, 19), status: PhotoStatus.pending));
      pipeline = RecordingPipeline(store: state.store, state: state, settings: settings)..onStamp = (PhotoRecord p) async => throw const StampException(StampException.missingOriginal);
      services = servicesFor(state, settings, pipeline);
    });
    await tester.pumpWidget(SelloApp(services: services, cameraEnabled: false));
    await tester.pump();
    services.queue.resumePending();
    await waitReal(tester, () => find.textContaining('no se pudo sellar').evaluate().isNotEmpty);
    expect(find.textContaining('no se pudo sellar'), findsOneWidget);
    expect(services.state.photoById('p1')!.status, PhotoStatus.failed);
    // "Ver" abre la foto, con su aviso y el botón para reintentar.
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Ver'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Reintentar'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Al abrir con el índice dañado se dice qué se recuperó', (WidgetTester tester) async {
    late Services services;
    await tester.runAsync(() async {
      final AppSettings settings = await testSettings();
      final AppState first = await testState(tmp);
      await first.addPhoto(PhotoRecord(id: 'a', projectId: 'general', originalFile: 'o', stampedFile: 's', takenAt: DateTime.utc(2026)));
      await first.addPhoto(PhotoRecord(id: 'b', projectId: 'general', originalFile: 'o2', stampedFile: 's2', takenAt: DateTime.utc(2026)));
      File('${tmp.path}/sello/photos.json').writeAsStringSync('{"photos": [');
      final AppState state = await testState(tmp);
      services = servicesFor(state, settings, RecordingPipeline(store: state.store, state: state, settings: settings));
    });
    expect(services.state.notices.map((LoadNotice n) => n.kind), contains(LoadNoticeKind.photosFromBackup));
    await tester.pumpWidget(SelloApp(services: services, cameraEnabled: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('se recuperó de la copia anterior'), findsOneWidget);
    // La copia anterior tenía la primera foto.
    expect(services.state.photoById('a'), isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 7));
  });
}
