// Servicios de prueba para las pruebas de interfaz: libro cifrado en una
// carpeta temporal, llavero en memoria, sin red y sin notificaciones reales.

import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plata/core/app_scope.dart';
import 'package:plata/core/backups.dart';
import 'package:plata/core/crypto_store.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/core/lock.dart';
import 'package:plata/core/notices.dart';
import 'package:plata/core/notifications.dart';
import 'package:plata/core/rates.dart';
import 'package:plata/core/settings.dart';
import 'package:plata/core/storage.dart';
import 'package:plata/ui/widgets/amount_keypad.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../store/plata_demo.dart';

class TestEnv {
  TestEnv._(this.services, this.dir, this.bridge, this.window, this.notifier);

  final Services services;
  final Directory dir;
  final FakeNoticeBridge bridge;
  final MemorySecureWindow window;
  final NoopNotifier notifier;

  Future<void> dispose() async {
    services.ledger.dispose();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}

/// Crea los servicios. Con [demo], el libro trae los seis meses de ejemplo
/// de las capturas de tienda (con "hoy" en [demoNow]).
/// [notificationsGranted] y [grantOnRequest] fijan lo que responde el
/// permiso de notificaciones (por defecto, concedido).
Future<TestEnv> makeEnv({String language = 'es', bool onboarded = true, bool demo = false, bool notices = false, bool? notificationsGranted = true, bool grantOnRequest = true}) async {
  final Directory dir = await Directory.systemTemp.createTemp('plata_ui');
  SharedPreferences.setMockInitialValues(<String, Object>{'language': language, 'onboarded': onboarded, 'noticesEnabled': notices});
  final AppSettings settings = AppSettings();
  await settings.load();
  final JsonStore store = JsonStore(root: dir);
  final MemoryKeyStore keys = MemoryKeyStore();
  final CryptoBox box = await CryptoBox.fromKeyStore(keys);
  final DateTime now = demo ? demoNow : kTestNow;
  final Ledger ledger = Ledger(EncryptedStore(store, box), spanish: language == 'es', clock: () => now);
  await ledger.load();
  if (demo) {
    await seedDemo(ledger, spanish: language == 'es', withNotices: notices);
    await ledger.flush();
  }
  final MemorySecureWindow window = MemorySecureWindow();
  final AppLock lock = AppLock(keys, biometricsAvailable: false, window: window);
  await lock.load();
  final FakeNoticeBridge bridge = FakeNoticeBridge(supported: notices, enabled: notices);
  final NoopNotifier notifier = NoopNotifier(granted: notificationsGranted, grantOnRequest: grantOnRequest);
  final Services services = Services(
    settings: settings,
    ledger: ledger,
    store: store,
    keys: keys,
    lock: lock,
    notifier: notifier,
    rates: RateService(client: MockClient((http.Request r) async => http.Response('sin red en las pruebas', 503))),
    notices: NoticeService(bridge: bridge, ledger: ledger, settings: settings),
    backups: BackupManager(store: store, ledger: ledger, settings: settings),
  );
  return TestEnv._(services, dir, bridge, window, notifier);
}

/// pumpAndSettle con un tope corto: si algo anima sin parar, la prueba falla
/// en segundos en vez de colgarse.
Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 15));

/// Espera (con tiempo real) a que [done] se cumpla: para lo que escribe en
/// disco o deriva llaves mientras la interfaz sigue con el reloj falso.
Future<void> waitFor(WidgetTester tester, bool Function() done, {int maxTenths = 80}) async {
  for (int i = 0; i < maxTenths && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
  await settle(tester);
}

/// Teléfono de 360 × 780 dp con la escala de texto dada.
void usePhone(WidgetTester tester, {double textScale = 1}) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Recoge los errores de Flutter (desbordes incluidos) para revisarlos al
/// final; también los pasa al manejador de la prueba, que la hace fallar con
/// el detalle.
List<String> collectErrors() {
  final List<String> errors = <String>[];
  final FlutterExceptionHandler? previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    errors.add(d.toString());
    previous?.call(d);
  };
  addTearDown(() => FlutterError.onError = previous);
  return errors;
}

/// "Hoy" de las pruebas de interfaz que no usan los datos de ejemplo: el libro
/// y la interfaz ven la misma fecha.
final DateTime kTestNow = DateTime(2026, 10, 16, 12);

/// Corre [body] con el reloj de la app fijo en [kTestNow].
Future<void> atTestTime(Future<void> Function() body) => withClock(Clock.fixed(kTestNow), body);

/// Deja pasar el tiempo para que terminen los temporizadores pendientes (los
/// controladores de texto se liberan un segundo después de cerrar su pantalla).
Future<void> finish(WidgetTester tester) => tester.pump(const Duration(seconds: 2));

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.descendant(of: find.byType(AmountKeypad), matching: find.text(key)).last);
  await tester.pump();
}

/// Abre una entrada de la pestaña Más (desplazando la lista si hace falta).
Future<void> openMore(WidgetTester tester, String title) async {
  final Finder tile = find.widgetWithText(ListTile, title);
  // Vuelve al principio: la lista pudo quedar abajo al volver de otra pantalla.
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
  await settle(tester);
  await tester.scrollUntilVisible(tile, 150, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(tile);
  await tester.pump();
  await tester.tap(tile);
  await settle(tester);
}

/// Cambia de pestaña con la barra inferior.
Future<void> goTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)).first);
  await settle(tester);
}

Future<void> back(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton).last);
  await settle(tester);
}
