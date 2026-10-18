@Tags(<String>['screenshots'])
library;

// Capturas de tienda de Plata: pantallas reales con los datos de ejemplo de
// test/store/plata_demo.dart, en teléfono y tableta de Android y en iPhone y
// iPad, en español e inglés. Se ejecutan con `flutter test --tags screenshots`.

import 'dart:io';

import 'package:clock/clock.dart';
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
import 'package:plata/ui/widgets/adaptive.dart';
import 'package:plata/ui/widgets/amount_keypad.dart';
import 'package:plata/ui/widgets/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'store/plata_demo.dart';
import 'store/store_shots.dart';

Future<Services> _demoServices(String lang, Directory dir, {required bool notices}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'language': lang,
    'onboarded': true,
    'defaultAccountId': 'billetera',
    'noticesEnabled': notices,
  });
  final AppSettings settings = AppSettings();
  await settings.load();
  final JsonStore store = JsonStore(root: dir);
  final MemoryKeyStore keys = MemoryKeyStore();
  final CryptoBox box = await CryptoBox.fromKeyStore(keys);
  final Ledger ledger = Ledger(EncryptedStore(store, box), spanish: lang == 'es', clock: () => demoNow);
  await ledger.load();
  await seedDemo(ledger, spanish: lang == 'es', withNotices: notices);
  await ledger.flush();
  final AppLock lock = AppLock(keys, biometricsAvailable: false);
  await lock.load();
  return Services(
    settings: settings,
    ledger: ledger,
    store: store,
    keys: keys,
    lock: lock,
    notifier: NoopNotifier(),
    rates: RateService(client: MockClient((http.Request r) async => http.Response('sin red en las capturas', 503))),
    notices: NoticeService(bridge: FakeNoticeBridge(supported: notices, enabled: notices), ledger: ledger, settings: settings),
    backups: BackupManager(store: store, ledger: ledger, settings: settings),
  );
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));

/// Cambia de pestaña con la barra inferior (teléfono) o el menú lateral (tableta).
Future<void> _goTab(WidgetTester tester, String label) async {
  Finder f = find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
  if (f.evaluate().isEmpty) {
    f = find.descendant(of: find.byType(NavigationRail), matching: find.text(label));
  }
  await tester.tap(f.first);
  await _settle(tester);
}

Future<void> _openMore(WidgetTester tester, String title) async {
  final Finder tile = find.widgetWithText(ListTile, title);
  await tester.scrollUntilVisible(tile, 150, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(tile);
  await tester.pump();
  await tester.tap(tile);
  await _settle(tester);
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton).last);
  await _settle(tester);
}

Future<void> _key(WidgetTester tester, String key) async {
  await tester.tap(find.descendant(of: find.byType(AmountKeypad), matching: find.text(key)).last);
  await tester.pump();
}

void main() {
  for (final StoreDevice device in StoreDevice.all) {
    for (final String lang in storeLanguages) {
      testWidgets('Capturas de Plata en ${device.id} ($lang)', (WidgetTester tester) async {
        final bool es = lang == 'es';
        String tr(String a, String b) => es ? a : b;
        final List<String> errors = <String>[];
        final FlutterExceptionHandler? previous = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails d) {
          errors.add(d.toString());
          previous?.call(d);
        };
        addTearDown(() => FlutterError.onError = previous);

        await withClock(Clock.fixed(demoNow), () async {
          device.apply(tester);
          await loadStoreFonts(tester);
          final Directory dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('plata_shots')))!;
          final Services s = (await tester.runAsync(() => _demoServices(lang, dir, notices: !device.isIOS)))!;
          await tester.pumpWidget(storeShotRoot(PlataApp(services: s, startup: false)));
          await _settle(tester);

          // 1. Inicio: patrimonio, cuentas, el mes, presupuestos y próximos pagos.
          // El botón + taparía la acción de la derecha del primer aviso: en
          // esta escena se esconde (la 02 muestra cómo se anota).
          hideFloatingButtons.value = true;
          await _settle(tester);
          await takeStoreShot(tester, device, lang, '01-inicio');
          hideFloatingButtons.value = false;
          await _settle(tester);

          // 2. Anotar un gasto con la calculadora y las sugerencias.
          await tester.tap(find.byTooltip(tr('Anotar movimiento', 'Log transaction')).first);
          await _settle(tester);
          for (final String k in <String>['1', '8', '5', '0', '0']) {
            await _key(tester, k);
          }
          await tester.tap(find.descendant(of: find.byType(AmountKeypad), matching: find.text(tr('Listo', 'Done'))));
          await _settle(tester);
          await tester.enterText(find.widgetWithText(TextField, tr('Descripción', 'Description')), tr('Alm', 'Set'));
          await tester.pump();
          await tester.tap(find.widgetWithText(ActionChip, tr('Almuerzo ejecutivo', 'Set lunch')).first);
          await tester.pump();
          FocusManager.instance.primaryFocus?.unfocus();
          await _settle(tester);
          await tester.tap(find.byType(AmountTile));
          await _settle(tester);
          await takeStoreShot(tester, device, lang, '02-anotar');
          await _back(tester);

          // 3. Informes: en qué se va la plata.
          await _goTab(tester, tr('Informes', 'Reports'));
          await takeStoreShot(tester, device, lang, '03-informes');

          // 4. Presupuestos.
          await _goTab(tester, tr('Presupuestos', 'Budgets'));
          hideFloatingButtons.value = true;
          await _settle(tester);
          await takeStoreShot(tester, device, lang, '04-presupuestos');
          hideFloatingButtons.value = false;
          await _settle(tester);

          // 5. Movimientos en calendario.
          await _goTab(tester, tr('Movimientos', 'Transactions'));
          await tester.tap(find.byIcon(Icons.calendar_month_outlined));
          await _settle(tester);
          await takeStoreShot(tester, device, lang, '05-calendario');

          // 6. Tarjeta de crédito: estado de cuenta, cuotas y próximo pago.
          await _goTab(tester, tr('Más', 'More'));
          await _openMore(tester, tr('Tarjetas de crédito', 'Credit cards'));
          await takeStoreShot(tester, device, lang, '06-tarjeta');
          await _back(tester);

          // 7. Avisos bancarios (solo Android).
          if (!device.isIOS) {
            await _openMore(tester, tr('Avisos bancarios', 'Bank notices'));
            // La bandeja arriba: es lo que promete el titular (los avisos que
            // se vuelven movimientos), no el texto que explica cómo funciona.
            final Finder tray = find.textContaining(tr('Por confirmar', 'To confirm')).first;
            await tester.scrollUntilVisible(tray, 200, scrollable: find.byType(Scrollable).first);
            // Empieza en «Anotar sin preguntar», sin renglones cortados arriba.
            await tester.ensureVisible(find.text(tr('Anotar sin preguntar', 'Log without asking')).first);
            await _settle(tester);
            await takeStoreShot(tester, device, lang, '07-avisos');
            await _back(tester);
          }

          // Cierre. Cancelar la suscripción de avisos devuelve un futuro de la
          // zona raíz: esperarlo en la zona de tiempo falso reanuda la prueba
          // fuera de su control y el siguiente pump no termina nunca. Por eso
          // va dentro de runAsync. El guardado diferido se dispara con el reloj
          // falso y escribe con tiempo real: se le dan turnos hasta que acaba.
          await tester.runAsync(() => s.notices.stop());
          await tester.pump(const Duration(milliseconds: 500));
          for (int i = 0; i < 50 && s.ledger.busy; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
            await tester.pump();
          }
          expect(s.ledger.busy, isFalse, reason: 'el guardado diferido no terminó');
          await tester.pumpWidget(const SizedBox.shrink());
          s.ledger.dispose();
          await tester.runAsync(() => dir.delete(recursive: true));
        });
        expect(errors, isEmpty, reason: errors.join('\n----\n'));
      }, variant: TargetPlatformVariant.only(device.platform), timeout: const Timeout(Duration(minutes: 3)));
    }
  }
}
