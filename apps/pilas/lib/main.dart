import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/app_scope.dart';
import 'core/app_state.dart';
import 'core/licenses.dart';
import 'core/settings.dart';
import 'core/sfx.dart';
import 'core/share.dart';
import 'core/speech.dart';
import 'core/storage.dart';

/// Arranca siempre: si algo no se puede leer, la app abre igual y el panel
/// de adultos muestra el aviso.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledLicenses();
  final AppSettings settings = AppSettings();
  try {
    await settings.load();
  } catch (e) {
    debugPrint('No se pudieron leer los ajustes: $e');
  }
  final JsonStore store = JsonStore();
  // Lo exportado ya se compartió: las copias de la app se borran al abrirla
  // de nuevo (también la que deja la hoja de compartir de Android).
  try {
    await store.clear('export');
  } catch (e) {
    debugPrint('No se pudo limpiar la carpeta de exportación: $e');
  }
  unawaited(Sharer.clearShareCache());
  final AppState state = AppState(store);
  try {
    await state.load();
  } catch (e) {
    debugPrint('No se pudo cargar el estado: $e');
    state.loaded = true;
  }
  final Voice voice = Voice(settings);
  final Sfx sfx = Sfx(settings);
  final Services services = Services(settings: settings, voice: voice, sfx: sfx, store: store, state: state);
  runApp(PilasApp(services: services));
  // La voz y el sonido se preparan después de pintar la primera pantalla.
  unawaited(Future<void>.microtask(() async {
    await voice.init();
    await sfx.init();
  }));
}
