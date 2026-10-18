import 'dart:async';
import 'dart:ui' show FlutterView, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/app_scope.dart';
import 'core/backup_io.dart';
import 'core/cues.dart';
import 'core/notifications.dart';
import 'core/settings.dart';
import 'core/storage.dart';
import 'state/timer_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Las flechas y marcas vienen de un subconjunto de DejaVu Sans: su licencia
  // aparece en Licencias de código abierto.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(<String>['DejaVu Sans (Simbolos)'], await rootBundle.loadString('assets/legal/LICENSE-DejaVu.txt'));
  });
  // Idioma inicial: el del teléfono (español si está en español; si no, inglés).
  final AppSettings settings = AppSettings(deviceLanguage: PlatformDispatcher.instance.locale.languageCode);
  await settings.load();
  final JsonStore store = JsonStore();
  await store.root();
  // Las copias exportadas ya se compartieron: la de la app se borra al abrirla.
  await store.clear('exports');
  final Services services = Services.create(
    settings: settings,
    store: store,
    gateway: LocalNotificationGateway(),
    cues: DeviceCuePlayer(settings),
    screen: DeviceScreenWake(),
    io: DeviceBackupIO(),
  );
  runApp(RutinasApp(services: services));
  WidgetsBinding.instance.addPostFrameCallback((_) => lockPhonePortrait());
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
