import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plata/app.dart';
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
import 'package:plata/model/models.dart';
import 'package:plata/ui/lock_screen.dart';
import 'package:plata/ui/widgets/amount_keypad.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// pumpAndSettle con un tope corto: si algo anima sin parar, la prueba falla
/// en segundos (con su pila) en vez de colgarse diez minutos.
Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 15));

/// Espera (con tiempo real) a que termine una escritura en disco y la
/// interfaz la refleje.
Future<void> waitFor(WidgetTester tester, bool Function() done, {int maxTenths = 50}) async {
  for (int i = 0; i < maxTenths && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
  await settle(tester);
}

/// Deja que el guardado diferido del libro escriba en disco de verdad.
Future<void> syncLedger(WidgetTester tester, Services s) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.runAsync(() => s.ledger.flush());
  await tester.pump();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.descendant(of: find.byType(AmountKeypad), matching: find.text(key)).last);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late Services services;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('plata_app_test');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppSettings settings = AppSettings();
    await settings.load();
    final JsonStore store = JsonStore(root: tmp);
    final MemoryKeyStore keys = MemoryKeyStore();
    final CryptoBox box = await CryptoBox.fromKeyStore(keys);
    final Ledger ledger = Ledger(EncryptedStore(store, box), clock: () => DateTime(2026, 10, 16, 12));
    await ledger.load();
    final AppLock lock = AppLock(keys, biometricsAvailable: false);
    await lock.load();
    services = Services(
      settings: settings,
      ledger: ledger,
      store: store,
      keys: keys,
      lock: lock,
      notifier: NoopNotifier(),
      rates: RateService(client: MockClient((http.Request r) async => http.Response('no', 503))),
      notices: NoticeService(bridge: FakeNoticeBridge(supported: false), ledger: ledger, settings: settings),
      backups: BackupManager(store: store, ledger: ledger, settings: settings),
    );
  });

  tearDown(() async {
    services.ledger.dispose();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('Inicio, nuevo gasto, movimientos, presupuesto, informes y cuentas sin errores', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
    final FlutterExceptionHandler? previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails d) {
      errors.add(d);
      previous?.call(d);
    };
    addTearDown(() => FlutterError.onError = previous);
    String report() => errors.map((FlutterErrorDetails d) => d.toString()).join('\n----\n');

    debugPrint('[prueba] inicio');
    await tester.pumpWidget(PlataApp(services: services, startup: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(errors, isEmpty, reason: 'inicio: ${report()}');
    expect(find.text('Plata'), findsOneWidget);
    expect(find.text('Patrimonio neto'), findsOneWidget);
    expect(find.text('¡Bienvenido a Plata!'), findsOneWidget);
    await tester.tap(find.text('Entendido'));
    await settle(tester);
    expect(find.text('¡Bienvenido a Plata!'), findsNothing);
    expect(services.settings.onboarded, isTrue);

    debugPrint('[prueba] nuevo gasto');
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    expect(find.text('Nuevo movimiento'), findsOneWidget);
    expect(find.byType(AmountKeypad), findsOneWidget);
    for (final String k in <String>['1', '5', '0', '0', '0']) {
      await tapKey(tester, k);
    }
    expect(find.text(r'$ 15.000'), findsOneWidget);
    await tester.tap(find.text('Listo'));
    await settle(tester);
    await tester.tap(find.text('Categoría'));
    await settle(tester);
    expect(find.text('Categoría del gasto'), findsOneWidget);
    await tester.tap(find.text('Alimentación').last);
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Descripción'), 'Almuerzo corrientazo');
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await settle(tester);
    expect(find.text('Nuevo movimiento'), findsNothing);
    expect(services.ledger.txs.length, 1);
    expect(services.ledger.txs.single.amountMinor, 1500000);
    expect(services.ledger.txs.single.categoryId, 'c_food');
    await syncLedger(tester, services);
    expect(find.textContaining('15.000'), findsWidgets);
    expect(errors, isEmpty, reason: 'nuevo gasto: ${report()}');

    debugPrint('[prueba] movimientos');
    await tester.tap(find.widgetWithText(NavigationDestination, 'Movimientos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Almuerzo corrientazo'), findsOneWidget);
    await tester.tap(find.text('Almuerzo corrientazo'));
    await settle(tester);
    expect(find.text('Editar movimiento'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    // Calendario.
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await settle(tester);
    expect(find.byIcon(Icons.view_list_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.view_list_outlined));
    await settle(tester);
    // Filtros.
    await tester.tap(find.byIcon(Icons.tune));
    await settle(tester);
    expect(find.text('Filtros'), findsWidgets);
    await tester.tap(find.text('Aplicar'));
    await settle(tester);
    expect(errors, isEmpty, reason: 'movimientos: ${report()}');

    debugPrint('[prueba] presupuesto');
    await tester.tap(find.widgetWithText(NavigationDestination, 'Presupuestos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Presupuesto'));
    await settle(tester);
    expect(find.text('Nuevo presupuesto'), findsOneWidget);
    await tester.tap(find.text('Tope por periodo'));
    await settle(tester);
    for (final String k in <String>['5', '0', '0', '0', '0', '0']) {
      await tapKey(tester, k);
    }
    await tester.tap(find.text('Listo'));
    await settle(tester);
    expect(find.text(r'$ 500.000'), findsOneWidget);
    await tester.scrollUntilVisible(find.widgetWithText(FilterChip, 'Alimentación'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.widgetWithText(FilterChip, 'Alimentación'));
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await settle(tester);
    expect(services.ledger.budgets.length, 1);
    expect(find.text('Alimentación'), findsWidgets);
    expect(find.text('disponible'), findsOneWidget);
    await syncLedger(tester, services);
    expect(errors, isEmpty, reason: 'presupuesto: ${report()}');

    debugPrint('[prueba] informes');
    await tester.tap(find.widgetWithText(NavigationDestination, 'Informes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Alimentación'), findsWidgets);
    await tester.tap(find.text('Tendencia'));
    await settle(tester);
    expect(find.text('Neto por periodo'), findsOneWidget);
    await tester.tap(find.text('Cuentas').first);
    await settle(tester);
    expect(find.text('Efectivo'), findsWidgets);
    await tester.tap(find.text('Categorías').first);
    await settle(tester);
    expect(errors, isEmpty, reason: 'informes: ${report()}');

    debugPrint('[prueba] cuentas');
    await tester.tap(find.widgetWithText(NavigationDestination, 'Más'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(ListTile, 'Cuentas'));
    await settle(tester);
    expect(find.text('Efectivo'), findsWidgets);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Cuenta'));
    await settle(tester);
    expect(find.text('¿Qué tipo de cuenta?'), findsOneWidget);
    await tester.tap(find.text('Nequi'));
    await settle(tester);
    expect(find.text('Nueva cuenta'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await settle(tester);
    expect(services.ledger.accounts.any((Account a) => a.name == 'Nequi' && a.bank == 'nequi'), isTrue);
    expect(find.text('Nequi'), findsWidgets);
    await syncLedger(tester, services);
    await tester.tap(find.byType(BackButton));
    await settle(tester);

    debugPrint('[prueba] programado y tarjetas');
    await tester.tap(find.widgetWithText(ListTile, 'Programados'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Programado'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Arriendo');
    await tester.tap(find.text('Monto'));
    await settle(tester);
    for (final String k in <String>['1', '2', '0', '0', '0', '0', '0']) {
      await tapKey(tester, k);
    }
    await tester.tap(find.text('Listo'));
    await settle(tester);
    await tester.tap(find.text('Guardar'));
    await settle(tester);
    expect(services.ledger.scheduled.single.name, 'Arriendo');
    expect(services.ledger.scheduled.single.amountMinor, 120000000);
    expect(find.text('Arriendo'), findsWidgets);
    await syncLedger(tester, services);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Tarjetas de crédito'));
    await settle(tester);
    expect(find.textContaining('Tarjeta de crédito'), findsWidgets);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(errors, isEmpty, reason: 'programado: ${report()}');

    debugPrint('[prueba] ajustes, guía y copias');
    await tester.tap(find.widgetWithText(ListTile, 'Ajustes'));
    await settle(tester);
    expect(find.text('Moneda base'), findsOneWidget);
    await tester.tap(find.text('Cómo cuentas el mes'));
    await settle(tester);
    await tester.tap(find.text('Quincenal'));
    await tester.pump();
    await tester.tap(find.text('Aceptar'));
    await settle(tester);
    expect(services.ledger.periodSpec.mode.name, 'quincena');
    await syncLedger(tester, services);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Guía y acerca de'));
    await settle(tester);
    expect(find.text('Acerca de Plata'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.scrollUntilVisible(find.widgetWithText(ListTile, 'Copias de seguridad'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.widgetWithText(ListTile, 'Copias de seguridad'));
    await settle(tester);
    expect(find.text('Exportar copia cifrada'), findsOneWidget);
    await tester.tap(find.text('Hacer copia local ahora'));
    await waitFor(tester, () => find.textContaining('.json.enc').evaluate().isNotEmpty, maxTenths: 80);
    expect(find.textContaining('plata-'), findsWidgets);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(errors, isEmpty, reason: 'ajustes: ${report()}');

    debugPrint('[prueba] inicio con datos');
    await tester.tap(find.widgetWithText(NavigationDestination, 'Inicio'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Próximos pagos'), findsOneWidget);
    expect(find.text('Arriendo'), findsWidgets);
    expect(find.text('Nequi'), findsWidgets);
    await syncLedger(tester, services);
    expect(errors, isEmpty, reason: 'final: ${report()}');
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('La pantalla de bloqueo pide la clave y abre con la correcta', (WidgetTester tester) async {
    await tester.runAsync(() => services.lock.setPasscode('2468'));
    services.lock.lockNow();
    await tester.pumpWidget(PlataApp(services: services, startup: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.text('Escribe tu clave'), findsOneWidget);
    for (final String k in <String>['1', '1', '1', '1']) {
      await tester.tap(find.descendant(of: find.byType(LockScreen), matching: find.text(k)));
      await tester.pump();
    }
    for (int i = 0; i < 300 && find.text('Clave incorrecta').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Clave incorrecta'), findsOneWidget);
    expect(services.lock.locked, isTrue);
    for (final String k in <String>['2', '4', '6', '8']) {
      await tester.tap(find.descendant(of: find.byType(LockScreen), matching: find.text(k)));
      await tester.pump();
    }
    for (int i = 0; i < 300 && services.lock.locked; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(services.lock.locked, isFalse);
    await settle(tester);
    expect(find.byType(LockScreen), findsNothing);
    expect(find.text('Patrimonio neto'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
