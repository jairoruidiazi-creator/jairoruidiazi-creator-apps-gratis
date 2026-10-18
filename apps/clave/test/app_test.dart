// La app entera con dobles de prueba: pestañas, idioma (G6), micrófono según
// lo que está a la vista (B2), segundo plano en Android, grabadora (M6, M7)
// y compartir/importar (B4).

import 'dart:convert';
import 'dart:io';

import 'package:clave/app.dart';
import 'package:clave/audio/sequencer.dart';
import 'package:clave/core/app_scope.dart';
import 'package:clave/core/settings.dart';
import 'package:clave/model/models.dart';
import 'package:clave/ui/metronome/metronome_screen.dart';
import 'package:clave/ui/metronome/presets_screen.dart';
import 'package:clave/ui/settings/settings_screen.dart';
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart' show ShareParams;

import 'support/fakes.dart';

/// Deja avanzar las lecturas y escrituras reales de disco, que no avanzan
/// con el tiempo simulado de la prueba.
Future<void> pumpUntil(WidgetTester tester, bool Function() done, {int tries = 60}) async {
  for (int i = 0; i < tries && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
}

Future<void> goTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(NavigationDestination, label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Anota los errores de dibujo (desbordes, etc.) y los sigue entregando al
/// manejador de la prueba.
List<FlutterErrorDetails> watchErrors() {
  final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
  final FlutterExceptionHandler? previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    errors.add(d);
    previous?.call(d);
  };
  addTearDown(() => FlutterError.onError = previous);
  return errors;
}

String report(List<FlutterErrorDetails> errors) => errors.map((FlutterErrorDetails d) => d.toString()).join('\n----\n');

/// Vuelve atrás con la flecha de la barra (pageBack busca el texto "Back"
/// y la app está en español).
Future<void> goBack(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton).last);
  await tester.pumpAndSettle();
}

/// Un teléfono de 432 × 864 dp (con la barra de pestañas abajo).
void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2160);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

Future<void> setLifecycle(WidgetTester tester, List<AppLifecycleState> states) async {
  for (final AppLifecycleState s in states) {
    tester.binding.handleAppLifecycleStateChanged(s);
    await tester.pump();
  }
}

void main() {
  testWidgets('Las cinco pestañas y los ajustes abren sin errores y el idioma cambia toda la app (G6)', (WidgetTester tester) async {
    usePhone(tester);
    final List<FlutterErrorDetails> errors = watchErrors();
    final TestServices t = TestServices();
    seedSample(t);
    await tester.pumpWidget(ClaveApp(services: t.services));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(errors, isEmpty, reason: 'inicio: ${report(errors)}');
    expect(find.text('Afinador'), findsWidgets);
    for (final String tab in <String>['Metrónomo', 'Tono', 'Grabar', 'Práctica']) {
      await goTab(tester, tab);
      expect(errors, isEmpty, reason: '$tab: ${report(errors)}');
    }
    // Metrónomo: iniciar y parar.
    await goTab(tester, 'Metrónomo');
    await tester.tap(find.text('Iniciar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(t.services.metronome.running, isTrue);
    await tester.tap(find.text('Parar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(t.services.metronome.running, isFalse);
    // Ajustes: cambiar a inglés rehace la app entera, también la barra de pestañas.
    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    await goBack(tester);
    expect(find.widgetWithText(NavigationDestination, 'Tuner'), findsOneWidget);
    expect(find.widgetWithText(NavigationDestination, 'Practice'), findsOneWidget);
    expect(find.text('Metronome'), findsWidgets);
    expect(find.text('Metrónomo'), findsNothing);
    expect(errors, isEmpty, reason: report(errors));
    await t.shutdown(tester);
  });

  testWidgets('El micrófono solo se abre con el afinador a la vista y la app al frente (B2)', (WidgetTester tester) async {
    usePhone(tester);
    final TestServices t = TestServices();
    await tester.pumpWidget(ClaveApp(services: t.services));
    await tester.pump();
    expect(t.mic.open, isTrue);
    await goTab(tester, 'Metrónomo');
    expect(t.mic.open, isFalse, reason: 'otra pestaña');
    await goTab(tester, 'Afinador');
    expect(t.mic.open, isTrue);
    // Los ajustes encima lo cierran; al volver se abre otra vez.
    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();
    expect(t.mic.open, isFalse, reason: 'ajustes encima');
    await goBack(tester);
    expect(t.mic.open, isTrue);
    // La hoja de ajustes del afinador también lo tapa.
    await tester.tap(find.text('Ajustar'));
    await tester.pumpAndSettle();
    expect(t.mic.open, isFalse, reason: 'hoja encima');
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(t.mic.open, isTrue);
    // La app pasa al fondo y vuelve.
    for (final AppLifecycleState s in <AppLifecycleState>[AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      await setLifecycle(tester, <AppLifecycleState>[s]);
      expect(t.mic.open, isFalse, reason: s.name);
    }
    await setLifecycle(tester, <AppLifecycleState>[AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]);
    expect(t.mic.open, isTrue);
    // El botón del micrófono.
    await tester.tap(find.byTooltip('Apagar micrófono'));
    await tester.pump();
    expect(t.mic.open, isFalse);
    await tester.tap(find.byTooltip('Encender micrófono'));
    await tester.pump();
    expect(t.mic.open, isTrue);
    await t.shutdown(tester);
  });

  testWidgets('Sin permiso, el afinador explica y ofrece los ajustes del sistema (M6)', (WidgetTester tester) async {
    usePhone(tester);
    final TestServices t = TestServices(micGranted: false);
    t.mic.grantOnRequest = false;
    await tester.pumpWidget(ClaveApp(services: t.services));
    await tester.pump();
    expect(find.text('Permitir micrófono'), findsOneWidget);
    expect(t.mic.requests, 0);
    await tester.tap(find.text('Permitir micrófono'));
    await tester.pump();
    await tester.pump();
    expect(t.mic.requests, 1);
    expect(t.services.settings.micAsked, isTrue);
    expect(find.text('Abrir ajustes'), findsOneWidget);
    await tester.tap(find.text('Abrir ajustes'));
    await tester.pump();
    expect(t.platform.settingsOpened, 1);
    await t.shutdown(tester);
  });

  testWidgets('En Android, al salir de la app se para lo que suena y se avisa al volver', (WidgetTester tester) async {
    usePhone(tester);
    final TestServices t = TestServices();
    await tester.pumpWidget(ClaveApp(services: t.services, initialIndex: 1));
    await tester.pump();
    await tester.tap(find.text('Iniciar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(t.services.metronome.running, isTrue);
    await setLifecycle(tester, <AppLifecycleState>[AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]);
    expect(t.services.metronome.running, isFalse);
    await setLifecycle(tester, <AppLifecycleState>[AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('se detuvieron al salir de la app'), findsOneWidget);
    await t.shutdown(tester);
  });

  testWidgets('La grabadora explica el micrófono, graba, guarda la toma y la comparte con su nombre (M6, M7, B4)', (WidgetTester tester) async {
    usePhone(tester);
    final TestServices t = TestServices(micGranted: false);
    await tester.pumpWidget(ClaveApp(services: t.services, initialIndex: 3));
    await tester.pump();
    await tester.tap(find.byTooltip('Grabar una toma'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Micrófono'), findsOneWidget);
    expect(t.capture.requests, 0, reason: 'primero la explicación');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(t.capture.requests, 1);
    expect(t.services.settings.micAsked, isTrue);
    await pumpUntil(tester, () => t.services.recorder.recording);
    expect(t.services.recorder.recording, isTrue);
    expect(t.mic.open, isFalse);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byTooltip('Detener y guardar la toma'));
    await pumpUntil(tester, () => find.text('Toma guardada').evaluate().isNotEmpty);
    expect(find.text('Toma guardada'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => find.text('Toma 1').evaluate().isNotEmpty);
    expect(find.text('Toma 1'), findsOneWidget);
    expect(t.services.state.recordings.single.durationMs, 2000);
    // Compartir: copia con el nombre de la toma y la hoja sale del botón.
    await tester.tap(find.byTooltip('Opciones de Toma 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compartir'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => t.platform.shared.isNotEmpty);
    final ShareParams p = t.platform.shared.single;
    expect(p.files!.single.path, endsWith('Toma 1.m4a'));
    expect(p.files!.single.mimeType, 'audio/mp4');
    expect(p.sharePositionOrigin, isNotNull);
    expect(File(p.files!.single.path).existsSync(), isTrue);
    // Si la hoja falla, se avisa en vez de romperse.
    t.platform.shareError = Exception('sin hoja de compartir');
    await tester.tap(find.byTooltip('Opciones de Toma 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compartir'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => find.text('No se pudo compartir la toma.').evaluate().isNotEmpty);
    expect(find.text('No se pudo compartir la toma.'), findsOneWidget);
    await t.shutdown(tester);
  });

  testWidgets('Preajustes: exportar comparte el JSON anclado al botón; importar valida y avisa (B4)', (WidgetTester tester) async {
    usePhone(tester);
    final TestServices t = TestServices();
    await tester.runAsync(() => t.services.state.addPreset(Preset(id: 'p1', name: 'Cumbia', rhythm: const RhythmConfig(bpm: 92, beatsPerBar: 2))));
    await tester.pumpWidget(AppScope(services: t.services, child: const MaterialApp(home: PresetsScreen())));
    await tester.pump();
    ScaffoldMessengerState messenger() => tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger));

    await tester.tap(find.byTooltip('Exportar preajustes'));
    await pumpUntil(tester, () => t.platform.shared.isNotEmpty);
    final ShareParams p = t.platform.shared.single;
    expect(p.sharePositionOrigin, isNotNull);
    expect(p.sharePositionOrigin!.width, greaterThan(0));
    expect(p.files!.single.mimeType, 'application/json');
    final Map<String, dynamic> exported = jsonDecode(File(p.files!.single.path).readAsStringSync()) as Map<String, dynamic>;
    expect(exported['app'], 'clave');
    expect((exported['presets'] as List<dynamic>).length, 1);

    t.platform.shareError = Exception('sin hoja de compartir');
    await tester.tap(find.byTooltip('Exportar preajustes'));
    await pumpUntil(tester, () => find.text('No se pudo compartir el archivo.').evaluate().isNotEmpty);
    expect(find.text('No se pudo compartir el archivo.'), findsOneWidget);
    messenger().removeCurrentSnackBar();
    await tester.pump();

    final File good = File('${t.dir.path}${Platform.pathSeparator}bueno.json')
      ..writeAsStringSync(jsonEncode(<String, dynamic>{
        'presets': <Object>[
          <String, dynamic>{'id': 'p2', 'name': 'Pasillo', 'rhythm': <String, dynamic>{'bpm': 126, 'beatsPerBar': 3}},
        ],
      }));
    t.platform.nextPick = XFile(good.path);
    await tester.tap(find.byTooltip('Importar preajustes'));
    await pumpUntil(tester, () => t.services.state.presets.length == 2 && find.text('Pasillo').evaluate().isNotEmpty);
    expect(find.text('Pasillo'), findsOneWidget);
    await pumpUntil(tester, () => find.textContaining('1 preajuste importado').evaluate().isNotEmpty);
    expect(find.textContaining('1 preajuste importado'), findsOneWidget);
    messenger().removeCurrentSnackBar();
    await tester.pump();

    final File bad = File('${t.dir.path}${Platform.pathSeparator}malo.json')..writeAsStringSync('[1, 2, 3]');
    t.platform.nextPick = XFile(bad.path);
    await tester.tap(find.byTooltip('Importar preajustes'));
    await pumpUntil(tester, () => find.textContaining('no es un archivo de preajustes').evaluate().isNotEmpty);
    expect(find.textContaining('no es un archivo de preajustes'), findsOneWidget);
    expect(t.services.state.presets.length, 2);
    messenger().removeCurrentSnackBar();
    await tester.pump();

    // El selector de archivos falla: también se avisa.
    t.platform.pickError = Exception('sin selector');
    await tester.tap(find.byTooltip('Importar preajustes'));
    await pumpUntil(tester, () => find.textContaining('no es un archivo de preajustes').evaluate().isNotEmpty);
    expect(find.textContaining('no es un archivo de preajustes'), findsOneWidget);
    expect(t.platform.picks, 3);
    await t.shutdown(tester);
  });

  testWidgets('Los números en pantalla siguen el idioma: swing y La4 (M15)', (WidgetTester tester) async {
    usePhone(tester);
    for (final bool spanish in <bool>[true, false]) {
      final TestServices t = TestServices(settings: AppSettings(deviceLocale: spanish ? null : const Locale('en')));
      t.services.metronome.setConfig(const RhythmConfig(subdivision: 2, swing: 0.3));
      await tester.pumpWidget(ClaveApp(services: t.services, initialIndex: 1));
      await tester.pump();
      final Finder swing = find.text(spanish ? 'Corcheas · swing 30\u00a0%' : 'Eighths · swing 30%');
      await tester.scrollUntilVisible(swing, 200, scrollable: find.descendant(of: find.byType(MetronomeScreen), matching: find.byType(Scrollable)).first);
      expect(swing, findsOneWidget);
      await goTab(tester, spanish ? 'Afinador' : 'Tuner');
      await tester.tap(find.text(spanish ? 'Ajustar' : 'Adjust'));
      await tester.pumpAndSettle();
      expect(find.text(spanish ? '440,0 Hz' : '440.0 Hz'), findsOneWidget);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await t.shutdown(tester);
    }
  });

  testWidgets('Guardar el ritmo actual como preajuste', (WidgetTester tester) async {
    usePhone(tester);
    final TestServices t = TestServices();
    await tester.pumpWidget(AppScope(services: t.services, child: const MaterialApp(home: PresetsScreen())));
    await tester.pump();
    expect(find.textContaining('Aún no hay preajustes'), findsOneWidget);
    await tester.tap(find.text('Guardar el actual'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bambuco');
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => find.text('Bambuco').evaluate().isNotEmpty);
    expect(t.services.state.presets.single.name, 'Bambuco');
    expect(find.text('Bambuco'), findsOneWidget);
    // Deja que se liberen los controladores del diálogo.
    await tester.pump(const Duration(seconds: 2));
    await t.shutdown(tester);
  });

  testWidgets('Borrar un preajuste o una setlist se puede deshacer', (WidgetTester tester) async {
    usePhone(tester);
    final TestServices t = TestServices();
    late Setlist sl;
    await tester.runAsync(() async {
      await t.services.state.addPreset(Preset(id: 'p2', name: 'Pasillo', rhythm: const RhythmConfig(bpm: 126, beatsPerBar: 3)));
      await t.services.state.addPreset(Preset(id: 'p1', name: 'Cumbia', rhythm: const RhythmConfig(bpm: 92, beatsPerBar: 2)));
      sl = await t.services.state.addSetlist('Ensayo');
      sl.presetIds.addAll(<String>['p1', 'p2']);
      await t.services.state.savePresets();
    });
    await tester.pumpWidget(AppScope(services: t.services, child: const MaterialApp(home: PresetsScreen())));
    await tester.pump();

    await tester.tap(find.byTooltip('Opciones de Cumbia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar'));
    await pumpUntil(tester, () => find.text('Se borró «Cumbia»').evaluate().isNotEmpty);
    expect(find.text('Se borró «Cumbia»'), findsOneWidget);
    expect(find.text('Cumbia'), findsNothing);
    expect(sl.presetIds, <String>['p2']);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deshacer'));
    await pumpUntil(tester, () => find.text('Cumbia').evaluate().isNotEmpty);
    expect(t.services.state.presets.map((Preset p) => p.id), <String>['p1', 'p2']);
    expect(sl.presetIds, <String>['p1', 'p2']);
    await tester.pumpAndSettle();

    // La setlist que usa el metrónomo: al deshacer vuelve a quedar activa.
    t.services.settings
      ..activeSetlistId = sl.id
      ..activeSetlistIndex = 1;
    await tester.tap(find.text('Ensayo (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Borrar setlist'));
    await pumpUntil(tester, () => find.text('Se borró la setlist «Ensayo»').evaluate().isNotEmpty);
    expect(find.text('Se borró la setlist «Ensayo»'), findsOneWidget);
    expect(t.services.state.setlists, isEmpty);
    expect(t.services.settings.activeSetlistId, '');
    expect(find.text('Ensayo (2)'), findsNothing);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deshacer'));
    await pumpUntil(tester, () => find.text('Ensayo (2)').evaluate().isNotEmpty);
    expect(t.services.state.setlists.single.presetIds, <String>['p1', 'p2']);
    expect(t.services.settings.activeSetlistId, sl.id);
    expect(t.services.settings.activeSetlistIndex, 1);
    await tester.pumpAndSettle();
    await t.shutdown(tester);
  });
}
