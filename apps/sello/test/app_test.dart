import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/app.dart';
import 'package:sello/core/app_scope.dart';
import 'package:sello/core/app_state.dart';
import 'package:sello/core/settings.dart';
import 'package:sello/core/storage.dart';
import 'package:sello/geo/heading.dart';
import 'package:sello/geo/location_service.dart';
import 'package:sello/model/models.dart';
import 'package:sello/ui/gallery/gallery_screen.dart';
import 'package:sello/ui/gallery/photo_detail_screen.dart';
import 'package:sello/ui/map/map_screen.dart';
import 'package:sello/ui/projects/project_editor.dart';
import 'package:sello/ui/projects/projects_screen.dart';
import 'package:sello/ui/projects/template_editor.dart';
import 'package:sello/ui/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// pumpAndSettle con un tope corto: si algo anima sin parar, la prueba falla
/// en segundos (con su pila) en vez de colgarse diez minutos.
Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 15));

/// Espera (con tiempo real) a que termine una escritura en disco y la
/// interfaz la refleje.
Future<void> waitFor(WidgetTester tester, bool Function() done, {int maxTenths = 50}) async {
  for (int i = 0; i < maxTenths && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
  await settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late Services services;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sello_app_test');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppSettings settings = AppSettings();
    await settings.load();
    final JsonStore store = JsonStore(root: tmp);
    final AppState state = AppState(store);
    await state.load();
    services = Services(settings: settings, state: state, store: store, location: LocationService(), heading: HeadingService());
    MapScreen.tilesEnabled = false;
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  testWidgets('La app recorre sus pestañas, crea un proyecto y edita la plantilla sin errores', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
    final FlutterExceptionHandler? previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails d) {
      errors.add(d);
      previous?.call(d);
    };
    addTearDown(() => FlutterError.onError = previous);
    String report() => errors.map((FlutterErrorDetails d) => d.toString()).join('\n----\n');

    debugPrint('[prueba] inicio');
    await tester.pumpWidget(SelloApp(services: services, cameraEnabled: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(errors, isEmpty, reason: 'inicio: ${report()}');
    expect(find.text('Cámara'), findsWidgets);

    debugPrint('[prueba] hoja de datos');
    // Hoja de datos de la foto (proyecto, notas, etiquetas) desde la cámara.
    await tester.tap(find.text('General').first);
    await settle(tester);
    expect(find.text('Notas para el sello'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Ej.: Fisura en muro norte, nivel 2'), 'Muro norte');
    await tester.tap(find.text('Listo'));
    await settle(tester);
    expect(errors, isEmpty, reason: 'hoja de datos: ${report()}');

    debugPrint('[prueba] hoja GPS');
    // Hoja de GPS y brújula.
    await tester.tap(find.byIcon(Icons.gps_fixed).first);
    await settle(tester);
    expect(find.text('GPS apagado'), findsOneWidget);
    expect(find.text('Posición manual'), findsOneWidget);
    await tester.tap(find.text('Posición manual'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(0), '4.711');
    await tester.enterText(find.byType(TextField).at(1), '-74.0721');
    await tester.tap(find.text('Fijar'));
    await settle(tester);
    expect(services.location.fix?.latitude, 4.711);
    expect(services.location.locked, isTrue);
    expect(find.text('18NXL0291020787'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Liberar posición'), 150, scrollable: find.byType(Scrollable).last);
    await tester.ensureVisible(find.text('Liberar posición'));
    await tester.pump();
    await tester.tap(find.text('Liberar posición'));
    await tester.pump();
    expect(services.location.locked, isFalse);
    // Cerrar la hoja.
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(errors, isEmpty, reason: 'hoja GPS: ${report()}');

    debugPrint('[prueba] pestañas');
    // Galería vacía, mapa y proyectos.
    await tester.tap(find.widgetWithText(NavigationDestination, 'Galería'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Aún no hay fotos'), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Mapa'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MapScreen), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Proyectos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Proyectos y sellos'), findsOneWidget);
    expect(errors, isEmpty, reason: 'pestañas: ${report()}');

    debugPrint('[prueba] nuevo proyecto');
    // Nuevo proyecto con un campo.
    await tester.tap(find.text('Nuevo'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Obra Calle 80');
    await tester.tap(find.text('Aceptar'));
    await waitFor(tester, () => find.byType(ProjectEditor).evaluate().isNotEmpty);
    expect(find.byType(ProjectEditor), findsOneWidget);
    expect(services.state.projects.length, 2);
    expect(services.settings.currentProjectId, services.state.projects.last.id);
    await tester.tap(find.text('Añadir'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Lote');
    await tester.tap(find.text('Aceptar'));
    await settle(tester);
    expect(find.text('Lote'), findsOneWidget);
    // El texto dice lo que la app hace (G8): no se piden antes de cada foto.
    expect(find.textContaining('se llenan en la cámara'), findsOneWidget);
    expect(find.textContaining('antes de cada foto'), findsNothing);
    // Hasta guardar, el proyecto vivo no cambia (M21).
    expect(services.state.projects.last.fields, isEmpty);
    await tester.tap(find.text('Guardar'));
    await waitFor(tester, () => find.byType(ProjectEditor).evaluate().isEmpty);
    expect(find.byType(ProjectEditor), findsNothing);
    expect(services.state.projects.last.fields.single.label, 'Lote');
    // Lectura real de disco: dentro de runAsync para que el tiempo simulado no la congele.
    final AppState reloaded = AppState(services.store);
    await tester.runAsync(() => reloaded.load());
    expect(reloaded.projects.last.name, 'Obra Calle 80');
    expect(errors, isEmpty, reason: 'proyecto: ${report()}');

    debugPrint('[prueba] plantilla');
    // Editor de plantilla con vista previa.
    await tester.tap(find.text('Estándar'));
    await settle(tester);
    expect(find.byType(TemplateEditor), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Rosa de los vientos'), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Rosa de los vientos'));
    await settle(tester);
    await tester.tap(find.text('Rosa de los vientos'));
    await tester.pump();
    expect(services.state.templateById('default').items, contains(StampItem.compass));
    await tester.scrollUntilVisible(find.text('Franja inferior'), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Franja inferior').first);
    await settle(tester);
    await tester.tap(find.text('Franja inferior').first);
    await tester.pump();
    expect(services.state.templateById('default').position, StampPosition.bottomBar);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(find.byType(TemplateEditor), findsNothing);
    // Deja terminar el guardado de la plantilla (E/S real) antes de seguir.
    await waitFor(tester, () => false, maxTenths: 10);
    expect(services.state.templateById('default').position, StampPosition.bottomBar);
    expect(errors, isEmpty, reason: 'plantilla: ${report()}');

    debugPrint('[prueba] ajustes');
    // Ajustes e idioma.
    await tester.tap(find.byIcon(Icons.settings_outlined).last);
    await settle(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Settings'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(find.text('Projects'), findsWidgets);
    expect(errors, isEmpty, reason: 'ajustes: ${report()}');

    // Deja terminar cualquier E/S pendiente antes de desmontar y borrar la carpeta temporal.
    await waitFor(tester, () => false, maxTenths: 10);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    FlutterError.onError = previous;
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('La galería muestra una foto guardada y abre su detalle', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Una foto mínima (PNG de 1×1 sirve para Image.file).
    const List<int> png = <int>[137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 207, 192, 240, 31, 0, 5, 0, 1, 255, 95, 92, 56, 137, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130];
    await tester.runAsync(() async {
      await services.store.writeBytes('photos/general/a.jpg', png);
      await services.state.addPhoto(PhotoRecord(
        id: 'a',
        projectId: 'general',
        originalFile: 'photos/general/a-orig.jpg',
        stampedFile: 'photos/general/a.jpg',
        takenAt: DateTime(2026, 3, 9, 14, 5),
        latitude: 4.711,
        longitude: -74.0721,
        accuracy: 4.2,
        altitude: 2601,
        heading: 135,
        address: 'Cra 7, Bogotá',
        notes: 'Columna C-3',
        tags: <String>['muro'],
        description: 'desc',
        width: 4,
        height: 3,
      ));
    });
    debugPrint('[prueba] galería: montar');
    await tester.pumpWidget(SelloApp(services: services, cameraEnabled: false));
    await tester.pump();
    await tester.tap(find.widgetWithText(NavigationDestination, 'Galería'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    debugPrint('[prueba] galería: con foto');
    expect(find.text('#muro'), findsOneWidget);
    expect(find.text('Exportar'), findsOneWidget);
    debugPrint('[prueba] galería: buscar');
    // Buscar filtra.
    await tester.enterText(find.byType(TextField), 'nada');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Ninguna foto coincide'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'columna');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    debugPrint('[prueba] galería: desenfocar');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    debugPrint('[prueba] galería: abrir detalle');
    // Abrir el detalle.
    final Finder tile = find.descendant(of: find.byType(SliverGrid), matching: find.byType(GestureDetector)).first;
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    debugPrint('[prueba] galería: detalle abierto');
    expect(find.text('Columna C-3'), findsWidgets);
    await tester.scrollUntilVisible(find.text('67P7PW6H+C5'), 200, scrollable: find.byType(Scrollable).first);
    await tester.pump();
    expect(find.text('18NXL0291020787'), findsOneWidget);
    expect(find.text('67P7PW6H+C5'), findsOneWidget);
    // La etiqueta y el valor nunca quedan pegados, aunque la etiqueta sea larga.
    expect(tester.getTopLeft(find.text('67P7PW6H+C5')).dx - tester.getTopRight(find.text('Plus Code')).dx, greaterThanOrEqualTo(8));
    debugPrint('[prueba] galería: volver');
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    await waitFor(tester, () => false, maxTenths: 10);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('Volver a sellar olvida también las miniaturas en caché (M11)', (WidgetTester tester) async {
    final File file = File('${tmp.path}/m11.jpg')..writeAsBytesSync(syntheticJpeg(64, 48));
    final List<Object> keys = <Object>[];
    await tester.runAsync(() async {
      // Las miniaturas usan cacheWidth: otra clave de caché que la imagen completa.
      for (final ImageProvider<Object> provider in <ImageProvider<Object>>[FileImage(file), for (final int w in kThumbWidths) ResizeImage(FileImage(file), width: w)]) {
        keys.add(await provider.obtainKey(ImageConfiguration.empty));
        final Completer<void> loaded = Completer<void>();
        final ImageStream stream = provider.resolve(ImageConfiguration.empty);
        final ImageStreamListener listener = ImageStreamListener((ImageInfo info, bool sync) => loaded.complete(), onError: (Object e, StackTrace? s) => loaded.completeError(e, s));
        stream.addListener(listener);
        await loaded.future;
        stream.removeListener(listener);
      }
    });
    expect(keys.length, 1 + kThumbWidths.length);
    expect(keys.every(imageCache.containsKey), isTrue);
    await tester.runAsync(() => evictPhotoImages(file));
    expect(keys.any(imageCache.containsKey), isFalse);
  });

  testWidgets('La plantilla de fábrica se nombra en el idioma de la app (M7)', (WidgetTester tester) async {
    services.settings.language = 'en';
    await tester.pumpWidget(AppScope(services: services, child: const MaterialApp(home: ProjectsScreen())));
    await tester.pump();
    expect(find.textContaining('stamp: Standard'), findsOneWidget);
    expect(find.textContaining('Estándar'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Editar datos: al cambiar de proyecto se llenan y guardan los campos del nuevo (M18)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Project b;
    late PhotoRecord p;
    await tester.runAsync(() async {
      final Project a = services.state.projectById('general');
      a.fields.add(const FieldDef('k1', 'Lote', defaultValue: '1'));
      b = await services.state.addProject('Obra B');
      b.fields.add(const FieldDef('k2', 'Inspector', defaultValue: 'Ana'));
      await services.state.saveProjects();
      await services.store.writeBytes('photos/general/a.jpg', syntheticJpeg(32, 24));
      p = PhotoRecord(id: 'a', projectId: 'general', originalFile: '', stampedFile: 'photos/general/a.jpg', takenAt: DateTime.utc(2026, 3, 9, 19, 5), fields: <String, String>{'k1': '7'}, fieldLabels: <String, String>{'k1': 'Lote'}, width: 32, height: 24);
      await services.state.addPhoto(p);
    });
    await tester.pumpWidget(AppScope(services: services, child: const MaterialApp(home: PhotoDetailScreen(photoId: 'a'))));
    await tester.pump();
    await tester.tap(find.byTooltip('Más opciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar datos'));
    await tester.pumpAndSettle();
    // Con el proyecto de la foto se ve su campo con lo que la foto tenía.
    expect(find.byKey(const ValueKey<String>('campo-k1')), findsOneWidget);
    expect(find.widgetWithText(TextField, '7'), findsOneWidget);
    await tester.tap(find.byWidgetPredicate((Widget w) => w is DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Obra B').last);
    await tester.pumpAndSettle();
    // Aparecen los del nuevo proyecto, con su valor inicial.
    expect(find.byKey(const ValueKey<String>('campo-k1')), findsNothing);
    final Finder inspector = find.byKey(const ValueKey<String>('campo-k2'));
    expect(inspector, findsOneWidget);
    expect(find.descendant(of: inspector, matching: find.text('Ana')), findsOneWidget);
    await tester.enterText(inspector, 'Luis');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    expect(p.projectId, b.id);
    expect(p.fields['k2'], 'Luis');
    expect(p.fieldLabels['k2'], 'Inspector');
    // Lo del proyecto anterior queda como dato de la foto, con su rótulo.
    expect(p.fields['k1'], '7');
    expect(p.fieldLabels['k1'], 'Lote');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  for (final Locale device in const <Locale>[Locale('en', 'US'), Locale('es', 'CO'), Locale('es', 'MX'), Locale('pt', 'BR')]) {
    testWidgets('Sin idioma elegido, la app usa el del teléfono: $device (G1 de la ronda 4)', (WidgetTester tester) async {
      tester.platformDispatcher.localeTestValue = device;
      tester.platformDispatcher.localesTestValue = <Locale>[device];
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final AppSettings settings = AppSettings.forDevice();
      await settings.load();
      final bool es = device.languageCode == 'es';
      expect(settings.language, es ? 'es' : 'en');
      // El geocodificador (dirección aproximada) arranca en el mismo idioma.
      expect(settings.geocoderLocale, es ? 'es_CO' : 'en_US');
      final Services s = Services(settings: settings, state: services.state, store: services.store, location: LocationService(), heading: HeadingService());
      await tester.pumpWidget(SelloApp(services: s, cameraEnabled: false));
      await tester.pump();
      expect(find.widgetWithText(NavigationDestination, es ? 'Cámara' : 'Camera'), findsOneWidget);
      expect(find.widgetWithText(NavigationDestination, es ? 'Galería' : 'Gallery'), findsOneWidget);
      // Guardar otro ajuste no fija el idioma: si el teléfono cambia, la app lo sigue.
      settings.grid = false;
      await settings.save();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('language'), isNull);
      // Elegirlo en Ajustes sí lo guarda y manda sobre el del teléfono.
      settings.language = es ? 'en' : 'es';
      await settings.save();
      final AppSettings again = AppSettings.forDevice();
      await again.load();
      expect(again.language, es ? 'en' : 'es');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('Con la app abierta sigue el cambio de idioma del teléfono, y «Idioma del teléfono» vuelve a seguirlo (M3 de la ronda 5)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
    tester.platformDispatcher.localesTestValue = const <Locale>[Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppSettings settings = AppSettings.forDevice();
    await settings.load();
    final LocationService location = LocationService();
    final Services s = Services(settings: settings, state: services.state, store: services.store, location: location, heading: HeadingService());
    await tester.pumpWidget(SelloApp(services: s, cameraEnabled: false));
    await tester.pump();
    expect(find.widgetWithText(NavigationDestination, 'Gallery'), findsOneWidget);
    // El usuario pone el teléfono en español sin cerrar la app (Android no la reinicia).
    tester.platformDispatcher.localeTestValue = const Locale('es', 'CO');
    tester.platformDispatcher.localesTestValue = const <Locale>[Locale('es', 'CO')];
    await tester.pump();
    expect(find.widgetWithText(NavigationDestination, 'Galería'), findsOneWidget);
    expect(location.localeIdentifier, 'es_CO');
    // Elige inglés en Ajustes: queda fijo aunque el teléfono siga en español.
    await tester.tap(find.widgetWithText(NavigationDestination, 'Galería'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.byTooltip('Ajustes')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(settings.language, 'en');
    expect(settings.followsDeviceLanguage, isFalse);
    expect((await SharedPreferences.getInstance()).getString('language'), 'en');
    tester.platformDispatcher.localeTestValue = const Locale('es', 'MX');
    await tester.pump();
    expect(settings.language, 'en');
    // «Idioma del teléfono»: vuelve a seguirlo y se borra lo elegido.
    await tester.tap(find.text('Phone language'));
    await tester.pumpAndSettle();
    expect(settings.followsDeviceLanguage, isTrue);
    expect(settings.language, 'es');
    expect(location.localeIdentifier, 'es_CO');
    expect(find.text('Idioma del teléfono'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('language'), isNull);
    final AppSettings again = AppSettings.forDevice();
    await again.load();
    expect(again.followsDeviceLanguage, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  test('Los ajustes se guardan en preferencias', () async {
    final AppSettings s = services.settings;
    // Sin ajuste guardado, la resolución máxima (M15).
    expect(s.resolution, 'max');
    s.language = 'en';
    s.jpegQuality = 80;
    s.autoDeclination = false;
    s.declination = -8.5;
    await s.save();
    final AppSettings again = AppSettings();
    await again.load();
    expect(again.language, 'en');
    expect(again.spanish, isFalse);
    expect(again.jpegQuality, 80);
    expect(again.autoDeclination, isFalse);
    expect(again.declination, -8.5);
  });
}
