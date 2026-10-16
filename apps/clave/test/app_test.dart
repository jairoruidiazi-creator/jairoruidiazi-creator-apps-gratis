import 'dart:io';

import 'package:clave/app.dart';
import 'package:clave/audio/audio_engine.dart';
import 'package:clave/audio/metronome.dart';
import 'package:clave/audio/sequencer.dart';
import 'package:clave/audio/tuner.dart';
import 'package:clave/core/app_scope.dart';
import 'package:clave/core/app_state.dart';
import 'package:clave/core/settings.dart';
import 'package:clave/core/storage.dart';
import 'package:clave/model/models.dart';
import 'package:clave/ui/metronome/presets_screen.dart';
import 'package:clave/ui/settings/settings_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late Services services;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('clave_test');
    final AppSettings settings = AppSettings();
    final JsonStore store = JsonStore(root: tmp);
    final AppState state = AppState(store);
    await state.load();
    final AudioEngine engine = SilentEngine();
    services = Services(settings: settings, state: state, store: store, engine: engine, metronome: Metronome(engine), tuner: Tuner(microphoneEnabled: false));
  });

  tearDown(() async {
    services.metronome.dispose();
    await tmp.delete(recursive: true);
  });

  test('Los preajustes y setlists se guardan, exportan e importan', () async {
    final AppState st = services.state;
    final Preset p = await st.addPreset(Preset(id: newId(), name: 'Cumbia', rhythm: const RhythmConfig(bpm: 92, beatsPerBar: 2)));
    final Setlist sl = await st.addSetlist('Ensayo');
    sl.presetIds.add(p.id);
    await st.savePresets();
    final AppState again = AppState(JsonStore(root: tmp));
    await again.load();
    expect(again.presets.single.name, 'Cumbia');
    expect(again.presets.single.rhythm.bpm, 92);
    expect(again.setlists.single.presetIds, <String>[p.id]);
    // Importar lo mismo no duplica.
    final int n = await again.importPresets(st.exportPresets());
    expect(n, 0);
    expect(again.presets.length, 1);
    await st.deletePreset(p.id);
    expect(st.setlists.single.presetIds, isEmpty);
  });

  test('El registro de práctica suma por día y calcula la racha', () async {
    final AppState st = services.state;
    final DateTime now = DateTime.now();
    st.sessions.add(PracticeSession(id: '1', start: now.subtract(const Duration(minutes: 30)), end: now.subtract(const Duration(minutes: 10)), tool: 'metronomo', instrumentId: 'guitarra'));
    st.sessions.add(PracticeSession(id: '2', start: now.subtract(const Duration(days: 1, minutes: 20)), end: now.subtract(const Duration(days: 1)), tool: 'afinador', instrumentId: 'guitarra'));
    st.sessions.add(PracticeSession(id: '3', start: now.subtract(const Duration(days: 2, minutes: 2)), end: now.subtract(const Duration(days: 2)), tool: 'afinador', instrumentId: 'violin'));
    expect(st.secondsOn(now), 1200);
    expect(st.streak(), 2); // hoy y ayer (anteayer solo 2 minutos)
    expect(st.secondsByInstrument(days: 7)['guitarra'], 2400);
    expect(st.secondsByTool(days: 7)['afinador'], 1320);
    await st.savePractice();
    final AppState again = AppState(JsonStore(root: tmp));
    await again.load();
    expect(again.sessions.length, 3);
  });

  test('touchPractice abre una sesión y la cierra al terminar', () async {
    final AppState st = services.state;
    st.touchPractice('afinador', 'guitarra');
    expect(st.secondsOn(DateTime.now()), 0);
    st.endPractice();
    // Menos de 10 segundos: no se guarda.
    expect(st.sessions, isEmpty);
  });

  test('El metrónomo arranca y para con el motor mudo', () async {
    final Metronome m = services.metronome;
    expect(m.running, isFalse);
    await m.start();
    expect(m.running, isTrue);
    m.setBpm(140);
    expect(m.config.bpm, 140);
    expect(m.tap(), isNull);
    await m.stop();
    expect(m.running, isFalse);
    expect(m.state.running, isFalse);
  });

  testWidgets('La app abre las cinco pestañas y los ajustes sin excepciones', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
    final FlutterExceptionHandler? previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);
    String report() => errors.map((FlutterErrorDetails d) => d.toString()).join('\n----\n');
    await tester.pumpWidget(ClaveApp(services: services));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(errors, isEmpty, reason: 'inicio: ${report()}');
    expect(find.text('Afinador'), findsWidgets);
    for (final String tab in <String>['Metrónomo', 'Tono', 'Grabar', 'Práctica']) {
      await tester.tap(find.widgetWithText(NavigationDestination, tab));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(errors, isEmpty, reason: '$tab: ${report()}');
    }
    // Metrónomo: iniciar y parar.
    await tester.tap(find.widgetWithText(NavigationDestination, 'Metrónomo'));
    await tester.pump();
    await tester.tap(find.text('Iniciar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(services.metronome.running, isTrue);
    expect(find.text('Parar'), findsOneWidget);
    await tester.tap(find.text('Parar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(services.metronome.running, isFalse);
    expect(errors, isEmpty, reason: report());
    // Ajustes.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pump();
    expect(find.text('Settings'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(errors, isEmpty, reason: report());
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    FlutterError.onError = previous;
  });

  testWidgets('La pantalla de preajustes guarda el ritmo actual', (WidgetTester tester) async {
    await tester.pumpWidget(AppScope(services: services, child: const MaterialApp(home: PresetsScreen())));
    await tester.pump();
    expect(find.textContaining('Aún no hay preajustes'), findsOneWidget);
    await tester.tap(find.text('Guardar el actual'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bambuco');
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    // La escritura en disco es asíncrona real: se le da tiempo.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();
    expect(services.state.presets.single.name, 'Bambuco');
    expect(find.text('Bambuco'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Deja que se liberen los controladores del diálogo.
    await tester.pump(const Duration(seconds: 2));
  });
}
