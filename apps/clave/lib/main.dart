import 'package:flutter/material.dart';

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
  final AppSettings settings = AppSettings();
  await settings.load();
  final JsonStore store = JsonStore();
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
  // El motor arranca después del primer cuadro para no retrasar la pantalla.
  Future<void>.microtask(engine.init);
}
