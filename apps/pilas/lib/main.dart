import 'package:flutter/material.dart';

import 'app.dart';
import 'core/app_scope.dart';
import 'core/app_state.dart';
import 'core/licenses.dart';
import 'core/settings.dart';
import 'core/sfx.dart';
import 'core/speech.dart';
import 'core/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledLicenses();
  final AppSettings settings = AppSettings();
  await settings.load();
  final JsonStore store = JsonStore();
  // Lo exportado ya se compartió: la copia de la app se borra al abrirla de nuevo.
  await store.clear('export');
  final AppState state = AppState(store);
  await state.load();
  final Voice voice = Voice(settings);
  final Sfx sfx = Sfx(settings);
  final Services services = Services(settings: settings, voice: voice, sfx: sfx, store: store, state: state);
  runApp(PilasApp(services: services));
  // La voz y el sonido se preparan después de pintar la primera pantalla.
  Future<void>.microtask(() async {
    await voice.init();
    await sfx.init();
  });
}
