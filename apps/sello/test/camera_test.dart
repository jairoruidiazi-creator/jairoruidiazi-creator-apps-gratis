import 'dart:async';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/app.dart';
import 'package:sello/core/app_scope.dart';
import 'package:sello/core/app_state.dart';
import 'package:sello/core/settings.dart';
import 'package:sello/geo/heading.dart';
import 'package:sello/geo/location_service.dart';
import 'package:sello/model/models.dart';
import 'package:sello/stamp/stamp_painter.dart';
import 'package:sello/ui/camera/camera_screen.dart';
import 'package:sello/ui/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  late Directory tmp;
  late FakeCameraPlatform camera;
  late FakeLocationBackend backend;
  late StreamController<List<double>> acc;
  late StreamController<List<double>> mag;
  late RecordingPipeline pipeline;
  late Services services;
  late FakeKeepAwake keepAwake;
  final List<String> log = <String>[];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sello_camera');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    log.clear();
    final AppSettings settings = await testSettings();
    final AppState state = await testState(tmp);
    backend = FakeLocationBackend(log: log);
    camera = FakeCameraPlatform(directory: tmp, picture: (DeviceOrientation? o) => syntheticJpeg(64, 48), log: log);
    CameraPlatform.instance = camera;
    acc = StreamController<List<double>>.broadcast();
    mag = StreamController<List<double>>.broadcast();
    final HeadingService heading = HeadingService(useSystemHeading: false, accelerometer: () => acc.stream, magnetometer: () => mag.stream);
    pipeline = RecordingPipeline(store: state.store, state: state, settings: settings);
    keepAwake = FakeKeepAwake();
    services = Services(
      settings: settings,
      state: state,
      store: state.store,
      location: LocationService(backend: backend, systemAltitudeIsMsl: false, undulation: (double a, double b) => 20),
      heading: heading,
      pipeline: pipeline,
      keepAwake: keepAwake,
    );
  });

  tearDown(() async {
    await acc.close();
    await mag.close();
    await tmp.delete(recursive: true);
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpMany(WidgetTester tester, [int n = 10]) async {
    for (int i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Widget cameraApp() => AppScope(services: services, child: const MaterialApp(home: CameraScreen()));

  Finder labeled(String label) => find.byWidgetPredicate((Widget w) => w is Semantics && w.properties.label == label);

  /// El teléfono se sostiene así: la gravedad (medida hacia arriba) en ejes del teléfono.
  Future<void> hold(WidgetTester tester, List<double> gravity, {List<double> field = const <double>[0, -30, -20]}) async {
    for (int i = 0; i < 40; i++) {
      acc.add(gravity);
      mag.add(field);
    }
    await tester.pump();
  }

  RotatedBox stampBox(WidgetTester tester) => tester.widget<RotatedBox>(find.byWidgetPredicate((Widget w) => w is RotatedBox && w.child is CustomPaint && (w.child! as CustomPaint).painter is StampPainter));

  /// Dispara y espera a que la foto quede guardada y en la cola (la cámara
  /// queda libre para la siguiente).
  Future<void> shoot(WidgetTester tester, int expected) async {
    await tester.tap(labeled('Tomar foto'));
    await tester.pump();
    await waitReal(tester, () => pipeline.stamped.length >= expected);
    await pumpMany(tester, 3);
    expect(pipeline.stamped.length, expected);
  }

  /// Transiciones del ciclo de vida de una en una, como las entrega el sistema.
  void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
    for (final AppLifecycleState s in states) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
  }

  testWidgets('Cada foto se toma con la orientación física del teléfono (B2, Android)', (WidgetTester tester) async {
    phone(tester);
    await tester.pumpWidget(cameraApp());
    await pumpMany(tester);
    expect(camera.created, 1);
    // En Android la captura no se fija al abrir la cámara.
    expect(camera.calls.where((String c) => c.startsWith('lock:')), isEmpty);

    // Teléfono en horizontal, con el borde superior a la izquierda.
    await hold(tester, <double>[9.81, 0, 0]);
    expect(services.heading.physicalOrientation, DeviceOrientation.landscapeLeft);
    // El sello de la vista previa y los íconos giran con el teléfono.
    expect(stampBox(tester).quarterTurns, 1);
    await shoot(tester, 1);
    final int take1 = camera.calls.indexOf('take');
    expect(camera.calls[take1 - 1], 'lock:landscapeLeft');

    // Ahora en vertical: la siguiente foto vuelve a ser vertical.
    await hold(tester, <double>[0, 9.81, 0]);
    expect(services.heading.physicalOrientation, DeviceOrientation.portraitUp);
    expect(stampBox(tester).quarterTurns, 0);
    await shoot(tester, 2);
    final int take2 = camera.calls.lastIndexOf('take');
    expect(take2, greaterThan(take1));
    expect(camera.calls[take2 - 1], 'lock:portraitUp');

    // Al otro lado.
    await hold(tester, <double>[-9.81, 0, 0]);
    await shoot(tester, 3);
    expect(camera.calls[camera.calls.lastIndexOf('take') - 1], 'lock:landscapeRight');
    // Las fotos se guardaron y la cola las selló (una a la vez).
    await waitReal(tester, () => pipeline.stamped.length == 3);
    expect(pipeline.maxRunning, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpMany(tester);
  });

  testWidgets('En iPhone la vista previa queda vertical y cada foto se gira al dispararla (B2, iOS)', (WidgetTester tester) async {
    phone(tester);
    await tester.pumpWidget(cameraApp());
    await pumpMany(tester);
    // La captura (que en iOS también gira el video) arranca fija en vertical.
    expect(camera.calls, contains('lock:portraitUp'));
    await hold(tester, <double>[9.81, 0, 0]);
    final int before = camera.calls.length;
    await shoot(tester, 1);
    final List<String> shot = camera.calls.sublist(before);
    expect(shot, containsAllInOrder(<String>['pause', 'lock:landscapeLeft', 'take', 'lock:portraitUp', 'resume']));
    // En vertical no hace falta congelar la vista previa.
    await hold(tester, <double>[0, 9.81, 0]);
    final int before2 = camera.calls.length;
    await shoot(tester, 2);
    expect(camera.calls.sublist(before2), isNot(contains('pause')));
    expect(camera.calls.sublist(before2), contains('take'));
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpMany(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Cámara frontal: rumbo opuesto y marcada en la ficha (M3); rumbo sin GPS, magnético (M1)', (WidgetTester tester) async {
    phone(tester);
    await tester.pumpWidget(cameraApp());
    await pumpMany(tester);
    await hold(tester, <double>[0, 9.81, 0]);
    // Trasera mirando al norte (magnético: todavía no hay posición para la declinación).
    await shoot(tester, 1);
    final PhotoRecord back = services.state.photos.first;
    expect(back.heading, closeTo(0, 0.5));
    expect(back.headingTrue, isFalse);
    expect(back.frontCamera, isFalse);
    await tester.tap(find.byTooltip('Cambiar cámara'));
    await pumpMany(tester);
    expect(camera.calls.where((String c) => c.startsWith('create:frontal')), hasLength(1));
    await hold(tester, <double>[0, 9.81, 0]);
    await shoot(tester, 2);
    final PhotoRecord front = services.state.photos.first;
    expect(front.frontCamera, isTrue);
    expect(front.heading, closeTo(180, 0.5));
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpMany(tester);
  });

  testWidgets('Primero el permiso de cámara y después el de ubicación (G13)', (WidgetTester tester) async {
    phone(tester);
    camera.initGate = Completer<void>();
    await tester.pumpWidget(cameraApp());
    await pumpMany(tester);
    // Mientras el sistema muestra el permiso de cámara no se pide otro.
    expect(log, contains('camera:init'));
    expect(log, isNot(contains('location:request')));
    camera.initGate!.complete();
    await pumpMany(tester);
    expect(log, contains('location:request'));
    expect(log.indexOf('location:request'), greaterThan(log.indexOf('camera:initialized')));
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpMany(tester);
  });

  testWidgets('Cambiar la resolución vuelve a abrir la cámara con la nueva (G7)', (WidgetTester tester) async {
    phone(tester);
    await tester.pumpWidget(cameraApp());
    await pumpMany(tester);
    // Por defecto, la máxima: todo el campo del sensor, sin recorte (M15).
    expect(camera.presets, <ResolutionPreset?>[ResolutionPreset.max]);
    services.settings.resolution = 'ultraHigh';
    await services.settings.save();
    await pumpMany(tester);
    expect(camera.disposed, 1);
    expect(camera.presets, <ResolutionPreset?>[ResolutionPreset.max, ResolutionPreset.ultraHigh]);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpMany(tester);
  });

  testWidgets('Controles con nombre y de 48 dp, también con letra al doble (G14)', (WidgetTester tester) async {
    phone(tester);
    final SemanticsHandle handle = tester.ensureSemantics();
    final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
    final FlutterExceptionHandler? previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);
    await tester.pumpWidget(cameraApp());
    await pumpMany(tester);
    expect(find.bySemanticsLabel('Tomar foto'), findsOneWidget);
    expect(find.bySemanticsLabel('Rejilla'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Flash')), findsOneWidget);
    expect(find.bySemanticsLabel('Zoom 2x'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpMany(tester, 3);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    FlutterError.onError = previous;
    expect(errors.map((FlutterErrorDetails d) => d.toString()), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpMany(tester);
    handle.dispose();
  });

  testWidgets('Fuera de su pestaña, tapada por otra pantalla o en segundo plano, la cámara se libera del todo (G3, M12, M5)', (WidgetTester tester) async {
    phone(tester);
    await tester.pumpWidget(SelloApp(services: services));
    await pumpMany(tester);
    bool locating() => backend.positionsCtrl.hasListener;
    expect(camera.created, 1);
    expect(services.heading.running, isTrue);
    expect(locating(), isTrue);
    expect(keepAwake.on, isTrue);
    // Linterna encendida (apagado → automático → siempre → linterna).
    for (int i = 0; i < 3; i++) {
      await tester.tap(find.byWidgetPredicate((Widget w) => w is Semantics && (w.properties.label ?? '').startsWith('Flash')).first);
      await pumpMany(tester, 2);
    }
    expect(camera.calls.last, 'flash:torch');

    // Otra pestaña: la cámara se cierra (no basta pausarla), la linterna se
    // apaga con ella, y se detienen la brújula y la ubicación.
    await tester.tap(find.widgetWithText(NavigationDestination, 'Galería'));
    await pumpMany(tester);
    expect(camera.disposed, 1);
    expect(camera.calls, isNot(contains('pause')));
    expect(services.heading.running, isFalse);
    expect(locating(), isFalse);
    expect(keepAwake.on, isFalse);
    // En segundo plano y de vuelta, con la galería a la vista: nada se abre.
    lifecycle(tester, <AppLifecycleState>[AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]);
    await pumpMany(tester);
    lifecycle(tester, <AppLifecycleState>[AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]);
    await pumpMany(tester);
    expect(camera.created, 1);
    expect(services.heading.running, isFalse);
    expect(locating(), isFalse);

    // De vuelta a la cámara: todo se abre otra vez, con la linterna apagada.
    await tester.tap(find.widgetWithText(NavigationDestination, 'Cámara'));
    await pumpMany(tester);
    expect(camera.created, 2);
    expect(services.heading.running, isTrue);
    expect(locating(), isTrue);
    expect(keepAwake.on, isTrue);
    expect(camera.calls.where((String c) => c.startsWith('flash:')).last, 'flash:off');

    // Ajustes encima de la cámara: se libera mientras están abiertos.
    await tester.tap(find.byTooltip('Ajustes'));
    await pumpMany(tester, 30);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(camera.disposed, 2);
    expect(services.heading.running, isFalse);
    expect(locating(), isFalse);
    expect(keepAwake.on, isFalse);
    await tester.tap(find.byType(BackButton));
    await pumpMany(tester, 30);
    expect(camera.created, 3);
    expect(locating(), isTrue);
    expect(keepAwake.on, isTrue);

    // En segundo plano la ubicación se detiene (M5) y al volver se retoma.
    lifecycle(tester, <AppLifecycleState>[AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]);
    await pumpMany(tester);
    expect(camera.disposed, 3);
    expect(locating(), isFalse);
    lifecycle(tester, <AppLifecycleState>[AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]);
    await pumpMany(tester);
    expect(camera.created, 4);
    expect(locating(), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpMany(tester);
  });

  testWidgets('Si la cámara deja de responder se dice y se puede reintentar (M19)', (WidgetTester tester) async {
    phone(tester);
    await tester.pumpWidget(cameraApp());
    await pumpMany(tester);
    expect(camera.created, 1);
    // Otra app toma la cámara (pantalla dividida): el complemento avisa el error.
    camera.emitError('The camera was already in use, possibly by a higher-priority camera client.');
    await pumpMany(tester);
    expect(camera.disposed, 1);
    expect(find.textContaining('dejó de responder'), findsOneWidget);
    expect(find.textContaining('already in use'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
    await pumpMany(tester);
    expect(camera.created, 2);
    expect(find.textContaining('dejó de responder'), findsNothing);
    expect(labeled('Tomar foto'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpMany(tester);
  });

  testWidgets('El temporizador se cancela tocando el obturador (M21)', (WidgetTester tester) async {
    phone(tester);
    services.settings.timerSeconds = 3;
    await tester.pumpWidget(cameraApp());
    await pumpMany(tester);
    await tester.tap(labeled('Tomar foto'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(labeled('Cancelar el temporizador'), findsOneWidget);
    await tester.tap(labeled('Cancelar el temporizador'));
    await tester.pump(const Duration(seconds: 4));
    expect(camera.calls, isNot(contains('take')));
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpMany(tester);
  });
}
