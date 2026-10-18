// Segunda ronda de la auditoría, en la interfaz: el candado al terminar la
// espera (G1), el permiso de notificaciones (G2), el pago vencido (G3), Atrás
// con el candado puesto (M8) y el ajuste de saldo en débito y en una tarjeta
// con saldo a favor (M9, M25).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plata/app.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/core/lock.dart';
import 'package:plata/model/models.dart';
import 'package:plata/ui/lock_screen.dart';
import 'package:plata/ui/more/cards_screen.dart';

import 'support/env.dart';

Future<TestEnv> start(WidgetTester tester, {bool? notificationsGranted = true, bool grantOnRequest = true}) async {
  final TestEnv env = (await tester.runAsync(() => makeEnv(notificationsGranted: notificationsGranted, grantOnRequest: grantOnRequest)))!;
  addTearDown(env.dispose);
  await tester.pumpWidget(PlataApp(services: env.services, startup: false));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return env;
}

/// La app sale al fondo y vuelve (así se vuelve a comprobar el permiso).
Future<void> leaveAndCome(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
  await settle(tester);
}

/// El botón o gesto Atrás del sistema.
Future<void> systemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')), (_) {});
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> typeCode(WidgetTester tester, String code) async {
  for (final String k in code.split('')) {
    await tester.tap(find.descendant(of: find.byType(LockScreen), matching: find.text(k)));
    await tester.pump();
  }
}

/// Da tiempo real a la clave (se calcula en otro hilo) sin mover el reloj de
/// la prueba.
Future<void> untilReal(WidgetTester tester, bool Function() done) async {
  for (int i = 0; i < 120 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
}

void main() {
  testWidgets('G1: al terminar la espera el candado vuelve a dejar escribir, sin tocar nada', (WidgetTester tester) async {
    // Sin reloj fijo: el de la prueba avanza con cada pump, como el del
    // teléfono, y la espera tiene que terminar sola.
    usePhone(tester);
    final TestEnv env = await start(tester);
    final AppLock lock = env.services.lock;
    await tester.runAsync(() => lock.setPasscode('2468'));
    lock.lockNow();
    await tester.pump();
    expect(find.byType(LockScreen), findsOneWidget);
    FilledButton key(String k) => tester.widget<FilledButton>(find.ancestor(of: find.descendant(of: find.byType(LockScreen), matching: find.text(k)), matching: find.byType(FilledButton)));
    for (int i = 0; i < 2; i++) {
      await typeCode(tester, '1111');
      await untilReal(tester, () => find.text('Clave incorrecta').evaluate().isNotEmpty);
      expect(find.text('Clave incorrecta'), findsOneWidget);
    }
    await typeCode(tester, '1111');
    await untilReal(tester, () => lock.waitSeconds > 0);
    await tester.pump();
    expect(find.text('Espera 30 s para intentar de nuevo'), findsOneWidget);
    expect(key('2').onPressed, isNull);
    await tester.pump(const Duration(seconds: 29));
    expect(find.text('Espera 1 s para intentar de nuevo'), findsOneWidget);
    expect(key('2').onPressed, isNull);
    // Justo después del final de la espera, sin ningún toque.
    await tester.pump(const Duration(seconds: 1, milliseconds: 5));
    expect(find.textContaining('Espera'), findsNothing);
    expect(key('2').onPressed, isNotNull);
    // Y se puede escribir la clave buena.
    await typeCode(tester, '2468');
    await untilReal(tester, () => !lock.locked);
    await tester.pump();
    expect(lock.locked, isFalse);
    expect(find.byType(LockScreen), findsNothing);
    await finish(tester);
  });

  testWidgets('G2: una tarjeta con día de pago pide el permiso una vez, con su motivo; después solo se avisa', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester, notificationsGranted: false, grantOnRequest: false);
      Future<void> newCard() async {
        await tester.tap(find.widgetWithText(FloatingActionButton, 'Cuenta'));
        await settle(tester);
        await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.widgetWithText(ListTile, 'Tarjeta de crédito')).first);
        await settle(tester);
        await tester.tap(find.text('Guardar'));
        await settle(tester);
      }

      await goTab(tester, 'Más');
      await openMore(tester, 'Cuentas');
      await newCard();
      expect(find.text('Activar las notificaciones'), findsOneWidget);
      expect(find.textContaining('fecha límite de pago de Tarjeta de crédito'), findsOneWidget);
      await tester.tap(find.text('Permitir'));
      await settle(tester);
      expect(env.notifier.requests, 1);
      expect(find.textContaining('Las notificaciones están apagadas'), findsOneWidget);
      // La segunda tarjeta ya no vuelve a preguntar: solo lo recuerda.
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).clearSnackBars();
      await settle(tester);
      await newCard();
      expect(find.text('Activar las notificaciones'), findsNothing);
      expect(env.notifier.requests, 1);
      expect(find.textContaining('Las notificaciones están apagadas'), findsOneWidget);
      expect(env.services.ledger.accounts.where((Account a) => a.isCredit), hasLength(2));
      await syncLedger(tester, env);
      await finish(tester);
    });
  });

  testWidgets('G2: Inicio y Ajustes muestran el permiso real, dejan darlo y lo vuelven a comprobar al volver', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester, notificationsGranted: false);
      await tester.runAsync(() => env.services.ledger.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, icon: 'card', cutDay: 15, payDay: 5)));
      await leaveAndCome(tester);
      expect(env.services.settings.notificationsAllowed, isFalse);
      expect(find.text('Tus recordatorios no aparecerán'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Activar'));
      await settle(tester);
      await tester.tap(find.text('Permitir'));
      await settle(tester);
      expect(env.notifier.requests, 1);
      expect(find.text('Tus recordatorios no aparecerán'), findsNothing);
      // En Ajustes: concedido. Si se quita desde el sistema, al volver se ve.
      await goTab(tester, 'Más');
      await openMore(tester, 'Ajustes');
      final Finder tile = find.text('Permiso de notificaciones');
      await tester.scrollUntilVisible(tile, 150, scrollable: find.byType(Scrollable).first);
      expect(find.text('Concedido: los recordatorios aparecen.'), findsOneWidget);
      env.notifier.granted = false;
      env.notifier.grantOnRequest = false;
      await leaveAndCome(tester);
      expect(find.text('Sin permiso: los recordatorios no aparecen.'), findsOneWidget);
      // Negado antes: el sistema ya no pregunta, así que se abren sus ajustes.
      await tester.tap(find.widgetWithText(TextButton, 'Dar permiso'));
      await settle(tester);
      expect(env.notifier.settingsOpened, 1);
      env.notifier.granted = true;
      await leaveAndCome(tester);
      expect(find.text('Concedido: los recordatorios aparecen.'), findsOneWidget);
      await finish(tester);
    });
  });

  testWidgets('G3: un día después de la fecha límite, Inicio y Tarjetas dicen «Vencido desde el …»', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester);
      // Corte el 30 y pago el 15: la compra del 20 de septiembre vencía el 15
      // de octubre, y "hoy" es el 16.
      await tester.runAsync(() async {
        await env.services.ledger.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, icon: 'card', cutDay: 30, payDay: 15));
        await env.services.ledger.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 100000000, accountId: 'tc', categoryId: 'c_food', date: DateTime(2026, 9, 20, 12)));
      });
      await settle(tester);
      expect(find.text('Vencido desde el 15 oct · capital estimado'), findsOneWidget);
      expect(find.text('Vencido desde el 15 oct'), findsOneWidget); // la tarjeta de la cuenta
      await goTab(tester, 'Más');
      await openMore(tester, 'Tarjetas de crédito');
      expect(find.byType(OverdueBanner), findsOneWidget);
      expect(find.text(r'Vencido desde el 15 oct: $ 1.000.000'), findsOneWidget);
      // El próximo pago (el del ciclo en curso) trae lo vencido como saldo anterior.
      expect(find.text('Incluye lo vencido'), findsOneWidget);
      await syncLedger(tester, env);
      await finish(tester);
    });
  });

  testWidgets('M8: Atrás con el candado puesto no cierra lo que hay detrás', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      expect(find.text('Nuevo movimiento'), findsOneWidget);
      await tester.runAsync(() => env.services.lock.setPasscode('2468'));
      env.services.lock.lockNow();
      await tester.pump();
      await systemBack(tester);
      await systemBack(tester);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('Nuevo movimiento'), findsOneWidget);
      await typeCode(tester, '2468');
      await untilReal(tester, () => !env.services.lock.locked);
      await settle(tester);
      expect(find.text('Nuevo movimiento'), findsOneWidget);
      // Ya abierta, Atrás vuelve a funcionar.
      await systemBack(tester);
      await settle(tester);
      expect(find.text('Nuevo movimiento'), findsNothing);
      await finish(tester);
    });
  });

  testWidgets('M9 y M25: el ajuste no se ofrece en una débito y respeta el saldo a favor de una tarjeta', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester);
      final Ledger l = env.services.ledger;
      await tester.runAsync(() async {
        await l.addAccount(Account(id: 'bank', name: 'Ahorros', type: AccountType.bank, icon: 'bank', initialMinor: 100000000));
        await l.addAccount(Account(id: 'deb', name: 'Débito', type: AccountType.debit, icon: 'card', linkedAccountId: 'bank'));
        await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, icon: 'card', cutDay: 15, payDay: 5));
        // Una devolución deja la tarjeta con $ 50.000 a favor.
        await l.addTx(Tx(id: 'dev', kind: TxKind.income, amountMinor: 5000000, accountId: 'tc', categoryId: 'c_food', date: DateTime(2026, 10, 10, 12)));
      });
      await goTab(tester, 'Más');
      await openMore(tester, 'Cuentas');
      // Saldo a favor: en positivo, sin "−", y dicho.
      expect(find.textContaining('saldo a favor'), findsOneWidget);
      expect(find.textContaining('−\$ 50.000'), findsNothing);
      await tester.longPress(find.text('Débito'));
      await settle(tester);
      await tester.tap(find.byWidgetPredicate((Widget w) => w is PopupMenuButton<String>));
      await settle(tester);
      expect(find.text('Ajustar saldo real…'), findsNothing);
      await tester.tapAt(const Offset(10, 400));
      await settle(tester);
      await back(tester);
      await tester.longPress(find.text('Visa'));
      await settle(tester);
      await tester.tap(find.byWidgetPredicate((Widget w) => w is PopupMenuButton<String>));
      await settle(tester);
      await tester.tap(find.text('Ajustar saldo real…'));
      await settle(tester);
      await tester.tap(find.text('Tengo saldo a favor'));
      await settle(tester);
      // Parte del saldo a favor de hoy; aceptarlo no cambia nada (antes lo
      // guardaba como deuda).
      await tester.tap(find.text('Listo'));
      await settle(tester);
      expect(find.text('El saldo ya coincidía.'), findsOneWidget);
      expect(l.balanceMinor('tc'), 5000000);
      expect(l.txs, hasLength(1));
      await back(tester);
      await syncLedger(tester, env);
      await finish(tester);
    });
  });
}

/// Lleva el libro al disco con tiempo real (el guardado diferido usa el reloj falso).
Future<void> syncLedger(WidgetTester tester, TestEnv env) async {
  await tester.pump(const Duration(milliseconds: 500));
  await waitFor(tester, () => !env.services.ledger.busy);
}
