@Tags(<String>['screenshots'])
library;

// Capturas de tienda de Sello: fotos libres selladas con la tubería real de la
// app (test/store/sello_demo.dart), la galería, el detalle con todos los
// datos, la plantilla, el mapa con teselas guardadas y la exportación, en
// teléfono y tableta de Android y en iPhone y iPad, en español e inglés.
// Se ejecutan con `flutter test --tags screenshots`.

import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/app.dart';
import 'package:sello/core/app_scope.dart';
import 'package:sello/core/app_state.dart';
import 'package:sello/core/settings.dart';
import 'package:sello/core/storage.dart';
import 'package:sello/geo/heading.dart';
import 'package:sello/geo/location_service.dart';
import 'package:sello/ui/map/map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'store/sello_demo.dart';
import 'store/store_shots.dart';

/// Teselas guardadas en test/store/tiles (ver tiles/CREDITOS.md). Una tesela
/// que falte se dibuja gris para que se note en la revisión.
class _FixtureTiles extends TileProvider {
  _FixtureTiles(this.root);

  final String root;

  static final Uint8List _gray = Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 120, 218, 99, 56, 115, 230, 12, 0, 4, 204, 2, 101, 7, 103, 182, 128, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final File f = File('$root/${coordinates.z}/${coordinates.x}/${coordinates.y}.png');
    return f.existsSync() ? FileImage(f) : MemoryImage(_gray);
  }
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));

/// Deja correr E/S real (lectura de imágenes y teselas) entre cuadros.
Future<void> _realTime(WidgetTester tester, {int rounds = 6}) async {
  for (int i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _goTab(WidgetTester tester, String label) async {
  Finder f = find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
  if (f.evaluate().isEmpty) {
    f = find.descendant(of: find.byType(NavigationRail), matching: find.text(label));
  }
  await tester.tap(f.first);
  await _settle(tester);
}

void main() {
  for (final StoreDevice device in StoreDevice.all) {
    for (final String lang in storeLanguages) {
      testWidgets('Capturas de Sello en ${device.id} ($lang)', (WidgetTester tester) async {
        final bool es = lang == 'es';
        String tr(String a, String b) => es ? a : b;
        // Los errores se guardan como texto al momento: describirlos después,
        // con el árbol ya desmontado, falla en el inspector de widgets.
        final List<String> errors = <String>[];
        final FlutterExceptionHandler? previous = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails d) {
          errors.add(d.toString());
          previous?.call(d);
        };
        addTearDown(() => FlutterError.onError = previous);
        // Hora fija de la demostración (después de la última foto del día), para
        // que la vista previa de la plantilla no muestre la hora de la CI.
        final DateTime today = DateTime.now();
        final DateTime demoNow = DateTime(today.year, today.month, today.day, 10, 5, 12);
        await withClock(Clock.fixed(demoNow), () async {
          device.apply(tester);
          await loadStoreFonts(tester);
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final Directory dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('sello_shots')))!;
          final Directory scratch = (await tester.runAsync(() => Directory.systemTemp.createTemp('sello_scratch')))!;
          final AppSettings settings = AppSettings();
          final JsonStore store = JsonStore(root: dir);
          final AppState state = AppState(store);
          await tester.runAsync(() async {
            await state.load();
            await seedSelloDemo(state: state, store: store, settings: settings, spanish: es, now: demoNow, photosDir: 'test/store/photos', scratchDir: scratch.path);
          });
          MapScreen.tileProviderOverride = _FixtureTiles('test/store/tiles');
          addTearDown(() => MapScreen.tileProviderOverride = null);
          final Services s = Services(settings: settings, state: state, store: store, location: LocationService(), heading: HeadingService());

          await tester.pumpWidget(storeShotRoot(SelloApp(services: s, cameraEnabled: false)));
          await _settle(tester);

          // 4. Galería con los dos proyectos.
          await _goTab(tester, tr('Galería', 'Gallery'));
          await _realTime(tester);
          await takeStoreShot(tester, device, lang, '04-galeria');

          // 6. Exportar: CSV, KML, KMZ, ZIP e informe PDF.
          await tester.tap(find.text(tr('Exportar', 'Export')));
          await _settle(tester);
          await takeStoreShot(tester, device, lang, '06-exportar');
          await tester.tapAt(const Offset(20, 120));
          await _settle(tester);

          // 1 y 2. Detalle de la foto principal: la imagen sellada y sus datos.
          final Finder tile = find.descendant(of: find.byType(SliverGrid), matching: find.byType(GestureDetector)).first;
          await tester.tap(tile);
          await _settle(tester);
          await _realTime(tester);
          await takeStoreShot(tester, device, lang, '01-foto');
          final Finder data = find.text(tr('Rumbo', 'Heading'));
          await tester.scrollUntilVisible(data, 300, scrollable: find.byType(Scrollable).first);
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -220));
          await _settle(tester);
          await takeStoreShot(tester, device, lang, '02-datos');
          await tester.tap(find.byType(BackButton));
          await _settle(tester);

          // 5. Mapa con las fotos de los dos proyectos.
          await _goTab(tester, tr('Mapa', 'Map'));
          await _realTime(tester, rounds: 12);
          await takeStoreShot(tester, device, lang, '05-mapa');

          // 3. Plantilla del sello con vista previa.
          await _goTab(tester, tr('Proyectos', 'Projects'));
          final Finder tpl = find.widgetWithText(ListTile, tr('Interventoría', 'Site supervision'));
          await tester.scrollUntilVisible(tpl, 200, scrollable: find.byType(Scrollable).first);
          await tester.tap(tpl);
          await _settle(tester);
          await _realTime(tester);
          await takeStoreShot(tester, device, lang, '03-plantilla');
          await tester.tap(find.byType(BackButton));
          await _settle(tester);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 2));
          await tester.runAsync(() async {
            await dir.delete(recursive: true);
            await scratch.delete(recursive: true);
          });
        });
        expect(errors, isEmpty, reason: errors.join('\n----\n'));
      }, variant: TargetPlatformVariant.only(device.platform), timeout: const Timeout(Duration(minutes: 6)));
    }
  }
}
