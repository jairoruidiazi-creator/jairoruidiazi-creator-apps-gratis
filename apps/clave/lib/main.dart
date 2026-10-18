import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'audio/audio_engine.dart';
import 'audio/metronome.dart';
import 'audio/tuner.dart';
import 'core/app_scope.dart';
import 'core/app_state.dart';
import 'core/settings.dart';
import 'core/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Los signos musicales y las flechas vienen de un subconjunto de DejaVu
  // Sans: su licencia aparece en Licencias de código abierto.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(<String>['DejaVu Sans (Simbolos)'], await rootBundle.loadString('assets/legal/LICENSE-DejaVu.txt'));
  });
  final AppSettings settings = AppSettings();
  await settings.load();
  final JsonStore store = JsonStore();
  // Lo exportado ya se compartió: la copia de la app se borra al abrirla de nuevo.
  await store.clear('export');
  final AppState state = AppState(store);
  await state.load();
  final AudioEngine engine = SoLoudEngine();
  final Metronome metronome = Metronome(engine)
    ..hapticsEnabled = settings.haptics
    ..flashEnabled = settings.flash
    ..visualOffsetMs = settings.visualOffsetMs
    ..volume = settings.metronomeVolume;
  final Tuner tuner = Tuner()
    ..settings = settings.pitch
    ..toleranceCents = settings.toleranceCents
    ..damping = settings.damping;
  runApp(ClaveApp(services: Services(settings: settings, state: state, store: store, engine: engine, metronome: metronome, tuner: tuner)));
  WidgetsBinding.instance.addPostFrameCallback((_) => lockPhonePortrait());
  // El motor arranca después del primer cuadro para no retrasar la pantalla.
  Future<void>.microtask(engine.init);
}

/// Los teléfonos van en vertical; las tabletas (lado corto de 600 dp o más)
/// giran libremente. En iPhone lo mismo lo fija el Info.plist.
void lockPhonePortrait() {
  final FlutterView? view = WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view == null || view.devicePixelRatio <= 0) {
    return;
  }
  final double shortest = view.physicalSize.shortestSide / view.devicePixelRatio;
  if (shortest > 0 && shortest < 600) {
    unawaited(SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]));
  }
}
