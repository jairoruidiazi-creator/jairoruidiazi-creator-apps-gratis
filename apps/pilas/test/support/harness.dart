import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pilas/core/app_scope.dart';
import 'package:pilas/core/app_state.dart';
import 'package:pilas/core/settings.dart';
import 'package:pilas/core/sfx.dart';
import 'package:pilas/core/share.dart';
import 'package:pilas/core/speech.dart';
import 'package:pilas/core/storage.dart';
import 'package:pilas/core/theme.dart';

/// Voz de mentiras: anota lo que se dice y cuántas veces se calló.
class FakeVoice extends Voice {
  FakeVoice(super.settings);

  final List<String> dicho = <String>[];
  int paradas = 0;

  @override
  Future<void> say(String text) async => dicho.add(text);

  @override
  void sayLater(String text) => dicho.add(text);

  @override
  Future<void> stop() async => paradas += 1;

  /// Avisa a la pantalla que cambió el estado de la voz (como al terminar de
  /// cargarla).
  void avisar() => notifyListeners();
}

/// Servicios de prueba sobre una carpeta temporal.
class Harness {
  Harness._(this.dir, this.services, this.voice);

  final Directory dir;
  final Services services;
  final FakeVoice voice;

  AppState get state => services.state;

  static Future<Harness> create({int limite = 0, Sharer? sharer}) async {
    final Directory dir = await Directory.systemTemp.createTemp('pilas_ui');
    final AppSettings settings = AppSettings()
      ..voiceEnabled = false
      ..sfxEnabled = false
      ..sessionLimitMinutes = limite;
    final JsonStore store = JsonStore(root: dir);
    final AppState state = AppState(store)..sessionLimitMinutes = () => limite;
    await state.load();
    final FakeVoice voice = FakeVoice(settings);
    final Services services = Services(settings: settings, voice: voice, sfx: Sfx(settings), store: store, state: state, sharer: sharer);
    return Harness._(dir, services, voice);
  }

  /// La app de prueba con [home] como pantalla inicial.
  Widget app(Widget home, {bool highContrast = false, GlobalKey<NavigatorState>? navigatorKey, double textScale = 1.0}) {
    return AppScope(
      services: services,
      state: services.state,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: PilasTheme.light(highContrast: highContrast),
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox.shrink(),
        ),
        home: home,
      ),
    );
  }

  Future<void> dispose() async {
    state.dispose();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}
