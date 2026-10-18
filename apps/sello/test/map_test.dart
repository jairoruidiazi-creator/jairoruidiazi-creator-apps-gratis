import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show HitTestEntry, HitTestResult;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/app.dart';
import 'package:sello/core/app_scope.dart';
import 'package:sello/core/app_state.dart';
import 'package:sello/core/settings.dart';
import 'package:sello/geo/heading.dart';
import 'package:sello/geo/location_service.dart';
import 'package:sello/ui/map/map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// Teselas en blanco: ninguna prueba descarga nada de OpenStreetMap.
class _BlankTiles extends TileProvider {
  _BlankTiles();

  int requests = 0;

  static final Uint8List _png = Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 120, 218, 99, 56, 115, 230, 12, 0, 4, 204, 2, 101, 7, 103, 182, 128, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    requests++;
    return MemoryImage(_png);
  }
}

void main() {
  late Directory tmp;
  late Services services;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sello_map');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppSettings settings = await testSettings();
    final AppState state = await testState(tmp);
    services = Services(settings: settings, state: state, store: state.store, location: LocationService(backend: FakeLocationBackend()), heading: HeadingService(useSystemHeading: false));
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  /// El texto se ve y lo que esté en su centro es él (nada lo tapa).
  void expectVisible(WidgetTester tester, Finder f) {
    expect(f, findsOneWidget);
    final Rect r = tester.getRect(f);
    final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(r.top, greaterThanOrEqualTo(0));
    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.bottom, lessThanOrEqualTo(screen.height));
    expect(r.right, lessThanOrEqualTo(screen.width));
    final HitTestResult hit = tester.hitTestOnBinding(r.center);
    final RenderObject target = tester.renderObject(f);
    expect(hit.path.any((HitTestEntry e) => identical(e.target, target)), isTrue, reason: 'algo tapa la atribución');
  }

  testWidgets('El mapa no se crea ni pide teselas hasta abrir su pestaña; la atribución se ve siempre (G11)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final _BlankTiles tiles = _BlankTiles();
    MapScreen.tilesEnabled = true;
    MapScreen.tileProviderOverride = tiles;
    addTearDown(() => MapScreen.tileProviderOverride = null);
    await tester.pumpWidget(SelloApp(services: services, cameraEnabled: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MapScreen), findsNothing);
    expect(find.byType(FlutterMap), findsNothing);
    expect(tiles.requests, 0);
    // Otras pestañas tampoco lo crean.
    await tester.tap(find.widgetWithText(NavigationDestination, 'Galería'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FlutterMap), findsNothing);
    expect(tiles.requests, 0);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Mapa'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(tiles.requests, greaterThan(0));
    // Texto de atribución a la vista, sin tocar nada, aunque la galería esté vacía (la tarjeta de aviso está abajo).
    expectVisible(tester, find.text('© colaboradores de OpenStreetMap'));
    // Con la letra al doble sigue a la vista.
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expectVisible(tester, find.text('© colaboradores de OpenStreetMap'));
    // Sin mapa en línea no hay teselas ni atribución.
    services.settings.mapTiles = false;
    services.settings.refresh();
    await tester.pump();
    expect(find.byType(TileLayer), findsNothing);
    expect(find.text('© colaboradores de OpenStreetMap'), findsNothing);
    // Y al volver a encenderlo, las teselas cargan de nuevo.
    final int before = tiles.requests;
    services.settings.mapTiles = true;
    services.settings.refresh();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TileLayer), findsOneWidget);
    expect(tiles.requests, greaterThan(before));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
