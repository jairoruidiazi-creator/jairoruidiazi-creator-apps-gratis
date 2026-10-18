// Pruebas de interfaz de los hallazgos del informe de auditoría: B2, B3,
// G10, G11, G17 y los menores M1, M2, M9, M10 y M17.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plata/app.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/core/settings.dart';
import 'package:plata/model/models.dart';
import 'package:plata/ui/lock_screen.dart';
import 'package:plata/ui/transactions/tx_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'store/plata_demo.dart';
import 'store/store_shots.dart';
import 'support/env.dart';

Future<TestEnv> start(WidgetTester tester, {String language = 'es', bool onboarded = true, bool demo = false}) async {
  final TestEnv env = (await tester.runAsync(() => makeEnv(language: language, onboarded: onboarded, demo: demo)))!;
  addTearDown(env.dispose);
  await tester.pumpWidget(PlataApp(services: env.services, startup: false));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return env;
}

/// Lleva el libro al disco con tiempo real (el guardado diferido usa el reloj falso).
Future<void> syncLedger(WidgetTester tester, TestEnv env) async {
  await tester.pump(const Duration(milliseconds: 500));
  await waitFor(tester, () => !env.services.ledger.busy);
}

void main() {
  testWidgets('B3: el editor guarda la suma aunque no se pulse "="', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      for (final String k in <String>['5', '0', '0', '0', '0', '+', '2', '0', '0', '0', '0']) {
        await tapKey(tester, k);
      }
      await tester.tap(find.text('Listo'));
      await settle(tester);
      expect(find.text(r'$ 70.000'), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      expect(env.services.ledger.txs.single.amountMinor, 7000000);
      await syncLedger(tester, env);
      // Inicio ya cuenta los 70.000 (patrimonio y saldo del efectivo).
      expect(find.textContaining('70.000'), findsWidgets);
      await finish(tester);
    });
  });

  testWidgets('B2: la deuda inicial de una tarjeta se guarda como deuda', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester);
      await goTab(tester, 'Más');
      await openMore(tester, 'Cuentas');
      await tester.tap(find.widgetWithText(FloatingActionButton, 'Cuenta'));
      await settle(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Tarjeta de crédito').first);
      await settle(tester);
      await tester.tap(find.text('Deuda inicial (lo que ya debes)'));
      await settle(tester);
      for (final String k in <String>['1', '0', '0', '0', '0', '0', '0']) {
        await tapKey(tester, k);
      }
      await tester.tap(find.text('Listo'));
      await settle(tester);
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      final Ledger l = env.services.ledger;
      final Account card = l.accounts.firstWhere((Account a) => a.isCredit);
      expect(card.initialMinor, -100000000);
      expect(l.debtMinor(), 100000000);
      expect(l.netWorthMinor(), -100000000);
      expect(find.textContaining(r'Deudas: $ 1.000.000'), findsOneWidget);
      await syncLedger(tester, env);
      await finish(tester);
    });
  });

  group('G10: el candado tapa lo que hay detrás', () {
    testWidgets('lo de atrás no se lee, no recibe foco ni toques', (WidgetTester tester) async {
      await atTestTime(() async {
        usePhone(tester);
        await loadStoreFonts(tester);
        final SemanticsHandle semantics = tester.ensureSemantics();
        final TestEnv env = await start(tester);
        expect(find.semantics.byLabel(RegExp('Patrimonio neto')), findsOneWidget);
        await tester.runAsync(() => env.services.lock.setPasscode('2468'));
        env.services.lock.lockNow();
        await tester.pump();
        expect(find.byType(LockScreen), findsOneWidget);
        expect(env.window.secure, isTrue); // FLAG_SECURE en Android, cubierta en iOS
        expect(find.semantics.byLabel(RegExp('Escribe tu clave')), findsWidgets);
        expect(find.semantics.byLabel(RegExp('Patrimonio neto')), findsNothing);
        expect(find.semantics.byLabel(RegExp('Anotar movimiento')), findsNothing);
        // El botón de anotar sigue en el árbol, pero no puede tomar el foco ni
        // recibe toques: un toque en su lugar no llega a él.
        final Finder fabFinder = find.byType(FloatingActionButton);
        final FocusNode fab = Focus.of(tester.element(find.descendant(of: fabFinder, matching: find.byType(Icon))));
        expect(fab.canRequestFocus, isFalse);
        final RenderObject fabBox = tester.renderObject(fabFinder);
        final HitTestResult hit = tester.hitTestOnBinding(tester.getCenter(fabFinder));
        expect(hit.path.any((HitTestEntry e) => e.target == fabBox), isFalse);
        // Las teclas del candado sí se leen con nombre.
        expect(find.semantics.byLabel('Borrar'), findsOneWidget);
        for (final String k in <String>['2', '4', '6', '8']) {
          await tester.tap(find.descendant(of: find.byType(LockScreen), matching: find.text(k)));
          await tester.pump();
        }
        await waitFor(tester, () => !env.services.lock.locked);
        expect(find.byType(LockScreen), findsNothing);
        expect(fab.canRequestFocus, isTrue);
        expect(tester.hitTestOnBinding(tester.getCenter(fabFinder)).path.any((HitTestEntry e) => e.target == fabBox), isTrue);
        expect(find.semantics.byLabel(RegExp('Patrimonio neto')), findsOneWidget);
        await finish(tester);
        semantics.dispose();
      });
    });

    testWidgets('en iOS se tapa al dejar de estar activa y se destapa al volver', (WidgetTester tester) async {
      await atTestTime(() async {
        usePhone(tester);
        final SemanticsHandle semantics = tester.ensureSemantics();
        final TestEnv env = await start(tester);
        await tester.runAsync(() => env.services.lock.setPasscode('2468'));
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump();
        expect(find.byType(PrivacyCover), findsOneWidget);
        expect(find.semantics.byLabel(RegExp('Patrimonio neto')), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(find.byType(PrivacyCover), findsNothing);
        expect(find.byType(LockScreen), findsNothing);
        // Con "bloquear de inmediato", al irse al fondo queda bloqueada.
        await tester.runAsync(() => env.services.lock.setLockAfter(0));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(find.byType(LockScreen), findsOneWidget);
        await finish(tester);
        semantics.dispose();
      });
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    test('M14: el desbloqueo con huella o rostro no acepta el PIN del teléfono', () {
      // Las pruebas corren en la carpeta de la app.
      expect(File('lib/core/lock.dart').readAsStringSync(), contains('biometricOnly: true'));
    });
  });

  testWidgets('G11: "¿Olvidaste la clave?" borra todo y deja usar la app', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      await loadStoreFonts(tester);
      final TestEnv env = await start(tester);
      final Ledger l = env.services.ledger;
      await tester.runAsync(() async {
        await l.addTx(Tx(id: 't1', kind: TxKind.expense, amountMinor: 100, accountId: 'a_cash', date: DateTime(2026, 10, 10)));
        await l.flush();
        await env.services.lock.setPasscode('2468');
      });
      env.services.lock.lockNow();
      await tester.pump();
      expect(find.byType(LockScreen), findsOneWidget);
      await tester.tap(find.text('¿Olvidaste la clave?'));
      await settle(tester);
      final Finder erase = find.widgetWithText(FilledButton, 'Borrar todo');
      expect(tester.widget<FilledButton>(erase).onPressed, isNull); // primero hay que confirmar
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(tester.widget<FilledButton>(erase).onPressed, isNotNull);
      await tester.tap(erase);
      await tester.pump();
      await waitFor(tester, () => !env.services.lock.enabled && find.byType(LockScreen).evaluate().isEmpty);
      expect(find.byType(LockScreen), findsNothing);
      expect(env.services.lock.enabled, isFalse);
      expect(l.txs, isEmpty);
      expect(env.window.secure, isFalse);
      expect(find.text('¡Bienvenido a Plata!'), findsOneWidget);
      await finish(tester);
    });
  });

  group('G17: idioma', () {
    test('el primer arranque toma el idioma del teléfono', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final AppSettings en = AppSettings();
      await en.load(deviceLocales: const <ui.Locale>[ui.Locale('en', 'US')]);
      expect(en.language, 'en');
      final AppSettings es = AppSettings();
      await es.load(deviceLocales: const <ui.Locale>[ui.Locale('fr', 'FR'), ui.Locale('es', 'CO')]);
      expect(es.language, 'es');
      final AppSettings other = AppSettings();
      await other.load(deviceLocales: const <ui.Locale>[ui.Locale('pt', 'BR')]);
      expect(other.language, 'en');
      SharedPreferences.setMockInitialValues(<String, Object>{'language': 'es'});
      final AppSettings saved = AppSettings();
      await saved.load(deviceLocales: const <ui.Locale>[ui.Locale('en', 'US')]);
      expect(saved.language, 'es');
    });

    testWidgets('cambiar de idioma traduce la app y las categorías de fábrica, no las renombradas', (WidgetTester tester) async {
      await atTestTime(() async {
        usePhone(tester);
        final TestEnv env = await start(tester);
        final Ledger l = env.services.ledger;
        l.category('c_transport')!.name = 'Buses';
        await goTab(tester, 'Más');
        await openMore(tester, 'Ajustes');
        await tester.scrollUntilVisible(find.text('English'), 200, scrollable: find.byType(Scrollable).first);
        await tester.tap(find.text('English'));
        await settle(tester);
        await back(tester);
        await goTab(tester, 'Home');
        expect(find.text('Net worth'), findsOneWidget);
        expect(l.category('c_food')!.name, 'Food');
        expect(l.category('c_transport')!.name, 'Buses');
        expect(l.account('a_cash')!.name, 'Cash');
        await syncLedger(tester, env);
        await finish(tester);
      });
    });

    testWidgets('M1: en inglés no queda texto en español ni "TxSplit"', (WidgetTester tester) async {
      await atTestTime(() async {
        usePhone(tester);
        final TestEnv env = await start(tester, language: 'en');
        final Ledger l = env.services.ledger;
        await tester.runAsync(() => l.addTx(Tx(id: 's', kind: TxKind.expense, amountMinor: 5000000, accountId: 'a_cash', date: DateTime(2026, 10, 10), splits: <TxSplit>[const TxSplit(categoryId: 'c_food', amountMinor: 3000000), const TxSplit(categoryId: 'c_transport', amountMinor: 2000000)])));
        await tester.pump();
        expect(find.text('Net worth'), findsOneWidget);
        await goTab(tester, 'Transactions');
        expect(find.descendant(of: find.byType(TxTile), matching: find.text('Split')), findsOneWidget);
        expect(find.textContaining('TxSplit'), findsNothing);
        expect(find.textContaining(' mil'), findsNothing);
        await syncLedger(tester, env);
        await finish(tester);
      });
    });
  });

  for (final double scale in <double>[1.3, 2.0]) {
    testWidgets('M2: con texto a ${scale}x nada se desborda en las pantallas principales', (WidgetTester tester) async {
      usePhone(tester, textScale: scale);
      final List<String> errors = collectErrors();
      await withClock(Clock.fixed(demoNow), () async {
        // Con las fuentes reales: la de pruebas dibuja cada letra como un cuadro
        // mucho más ancho y daría desbordes que en el teléfono no existen.
        await loadStoreFonts(tester);
        final TestEnv env = await start(tester, demo: true);
        debugPrint('[M2 $scale] inicio');
        expect(find.text('Patrimonio neto'), findsOneWidget);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
        await settle(tester);
        debugPrint('[M2 $scale] editor');
        await tester.tap(find.byType(FloatingActionButton));
        await settle(tester);
        await tapKey(tester, '5');
        await back(tester);
        debugPrint('[M2 $scale] movimientos');
        await goTab(tester, 'Movimientos');
        await tester.tap(find.byIcon(Icons.calendar_month_outlined));
        await settle(tester);
        await tester.drag(find.byType(GridView), const Offset(0, -800));
        await settle(tester);
        await tester.tap(find.byIcon(Icons.view_list_outlined));
        await settle(tester);
        debugPrint('[M2 $scale] presupuestos e informes');
        await goTab(tester, 'Presupuestos');
        await goTab(tester, 'Informes');
        for (final String chip in <String>['Tendencia', 'Presupuestos', 'Cuentas', 'Categorías']) {
          await tester.tap(find.widgetWithText(ChoiceChip, chip));
          await settle(tester);
        }
        await goTab(tester, 'Más');
        for (final String entry in <String>['Cuentas', 'Tarjetas de crédito', 'Programados', 'Monedas', 'Seguridad', 'Copias de seguridad', 'Ajustes']) {
          debugPrint('[M2 $scale] $entry');
          await openMore(tester, entry);
          await back(tester);
        }
        debugPrint('[M2 $scale] candado');
        await tester.runAsync(() => env.services.lock.setPasscode('2468'));
        env.services.lock.lockNow();
        await tester.pump();
        expect(find.byType(LockScreen), findsOneWidget);
        await tester.tap(find.text('¿Olvidaste la clave?'));
        await settle(tester);
        await finish(tester);
      });
      expect(errors, isEmpty, reason: errors.join('\n----\n'));
    }, timeout: const Timeout(Duration(minutes: 3)));
  }

  testWidgets('M2: las gráficas se describen para el lector de pantalla', (WidgetTester tester) async {
    usePhone(tester);
    final SemanticsHandle semantics = tester.ensureSemantics();
    await withClock(Clock.fixed(demoNow), () async {
      await start(tester, demo: true);
      await goTab(tester, 'Informes');
      expect(find.semantics.byLabel(RegExp(r'^Gastos: \$')), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Tendencia'));
      await settle(tester);
      expect(find.semantics.byLabel(RegExp('^Ingresos y gastos por periodo. .*ingresos')), findsOneWidget);
      expect(find.semantics.byLabel(RegExp('^Neto por periodo. ')), findsOneWidget);
      await finish(tester);
    });
    semantics.dispose();
  });

  testWidgets('M9: la pantalla de monedas atribuye las tasas de ExchangeRate-API', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester);
      final Ledger l = env.services.ledger;
      l.rates.rates['PEN'] = 1100;
      l.rates.origins['PEN'] = RateOrigin.erApi;
      env.services.settings.extraCurrencies = <String>['PEN'];
      await goTab(tester, 'Más');
      await openMore(tester, 'Monedas');
      await tester.scrollUntilVisible(find.textContaining('Rates By Exchange Rate API'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('Rates By Exchange Rate API'), findsWidgets);
      await finish(tester);
    });
  });

  testWidgets('M10: la contraseña de la copia va oculta, no se aprende y se confirma', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      await start(tester);
      await goTab(tester, 'Más');
      await openMore(tester, 'Copias de seguridad');
      await tester.tap(find.text('Exportar copia cifrada'));
      await settle(tester);
      final Finder inputs = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
      final List<TextField> fields = tester.widgetList<TextField>(inputs).toList();
      expect(fields.length, 2);
      for (final TextField f in fields) {
        expect(f.obscureText, isTrue);
        expect(f.autocorrect, isFalse);
        expect(f.enableSuggestions, isFalse);
        expect(f.enableIMEPersonalizedLearning, isFalse);
      }
      await tester.enterText(inputs.first, 'corta');
      await tester.enterText(inputs.last, 'corta');
      await tester.tap(find.text('Aceptar'));
      await tester.pump();
      expect(find.text('Usa al menos 8 caracteres.'), findsOneWidget);
      await tester.enterText(inputs.first, 'una clave larga');
      await tester.enterText(inputs.last, 'otra clave larga');
      await tester.tap(find.text('Aceptar'));
      await tester.pump();
      expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      await finish(tester);
    });
  });

  testWidgets('M17: si los datos no se pueden abrir, la app solo deja restaurar o empezar de cero', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = (await tester.runAsync(() => makeEnv()))!;
      addTearDown(env.dispose);
      final Ledger l = env.services.ledger;
      l.recoveryReason = RecoveryReason.unreadable;
      l.readOnly = true;
      await tester.pumpWidget(PlataApp(services: env.services, startup: false));
      await tester.pump();
      expect(find.text('Recuperar tus datos'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Exportar copia cifrada'), findsNothing);
      await tester.tap(find.text('Empezar de cero'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Empezar de cero'));
      await tester.pump();
      await waitFor(tester, () => !l.readOnly);
      expect(find.text('Patrimonio neto'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      await finish(tester);
    });
  });
}
