// Séptima ronda de la auditoría, en la interfaz: Atrás en «¿Ya lo pagaste?»
// no cambia nada (G1), el pago registrado desde la fila queda vinculado y la
// fila lo dice (M1), los botones dicen de qué extracto son (M4), y la
// respuesta de la notificación espera a la clave con el ciclo de vida real
// (M2): dentro de los segundos de gracia y al abrir la app en frío.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plata/app.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/core/lock.dart';
import 'package:plata/core/notifications.dart';
import 'package:plata/model/models.dart';
import 'package:plata/ui/more/cards_screen.dart';

import 'support/env.dart';

Future<TestEnv> start(WidgetTester tester, {bool startup = false, Future<void> Function(TestEnv env)? before}) async {
  final TestEnv env = (await tester.runAsync(() async {
    final TestEnv e = await makeEnv();
    await before?.call(e);
    return e;
  }))!;
  addTearDown(env.dispose);
  await tester.pumpWidget(PlataApp(services: env.services, startup: startup));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return env;
}

Future<void> syncLedger(WidgetTester tester, TestEnv env) async {
  await tester.pump(const Duration(milliseconds: 500));
  await waitFor(tester, () => !env.services.ledger.busy);
}

/// Tarjeta con corte el 30 y pago el 15, una compra del 20 sep y un mínimo
/// de $80.000 del extracto del 30 sep, que vencía el jue 15 oct; "hoy" es el
/// 16. Hay una cuenta de ahorros para pagarla.
Future<Account> seedCard(Ledger l) async {
  await l.addAccount(Account(id: 'ah', name: 'Ahorros', type: AccountType.bank, initialMinor: 500000000));
  final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, icon: 'card', cutDay: 30, payDay: 15));
  await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 100000000, accountId: 'tc', categoryId: 'c_food', date: DateTime(2026, 9, 20, 12)));
  l.setStatementMinimum(tc, DateTime(2026, 9, 30), 8000000);
  return tc;
}

final DateTime cut = DateTime(2026, 9, 30);
const NotifierResponse paidResponse = NotifierResponse(payload: 'o:tc:2026-09-30', actionId: Notifier.paidAction);

Future<void> lifecycle(WidgetTester tester, List<AppLifecycleState> states) async {
  for (final AppLifecycleState s in states) {
    tester.binding.handleAppLifecycleStateChanged(s);
    await tester.pump();
  }
}

const List<AppLifecycleState> toBackground = <AppLifecycleState>[AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused];
const List<AppLifecycleState> toForeground = <AppLifecycleState>[AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed];

void main() {
  testWidgets('G1: Atrás no cierra «¿Ya lo pagaste?» ni cambia la marca', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      late Account tc;
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        tc = await seedCard(e.services.ledger);
        e.services.ledger.markStatementPaid(tc, cut);
      });
      final Ledger l = env.services.ledger;
      await goTab(tester, 'Más');
      await openMore(tester, 'Tarjetas de crédito');
      await tester.tap(find.text('Cambiar'));
      await settle(tester);
      await tester.tap(find.text('Listo'));
      await settle(tester);
      expect(find.text('¿Ya lo pagaste?'), findsOneWidget);
      // El botón Atrás de Android (o el gesto): el diálogo sigue abierto.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('¿Ya lo pagaste?'), findsOneWidget);
      expect(l.isStatementPaid(tc, cut), isTrue);
      expect(find.byType(OverdueBanner), findsNothing);
      await tester.tap(find.text('Sí, ya lo pagué'));
      await settle(tester);
      expect(l.isStatementPaid(tc, cut), isTrue);
      expect(find.byType(OverdueBanner), findsNothing);
      await syncLedger(tester, env);
      await finish(tester);
    });
  });

  testWidgets('M1: el pago registrado desde la fila queda vinculado, la fila lo dice y no ofrece registrarlo otra vez', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final SemanticsHandle semantics = tester.ensureSemantics();
      late Account tc;
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        tc = await seedCard(e.services.ledger);
        e.services.ledger.markStatementPaid(tc, cut);
      });
      final Ledger l = env.services.ledger;
      final int before = l.statement(tc, date: DateTime(2026, 10, 30)).dueMinor;
      await goTab(tester, 'Más');
      await openMore(tester, 'Tarjetas de crédito');
      // Cada botón dice de qué extracto es.
      expect(find.bySemanticsLabel('Registrar el pago del extracto del 30 sep'), findsOneWidget);
      expect(find.bySemanticsLabel('Desmarcar el extracto del 30 sep'), findsOneWidget);
      // El botón de abajo ya no se llama casi igual.
      expect(find.text('Pagar el próximo pago'), findsOneWidget);
      final Finder log = find.text('Registrar el pago');
      await tester.scrollUntilVisible(log, 150, scrollable: find.byType(Scrollable).first);
      await tester.tap(log);
      await settle(tester);
      // El formulario explica el vínculo y qué hacer si se pagó desde otra entidad.
      expect(find.textContaining('Queda asociado al extracto del 30 sep'), findsOneWidget);
      expect(find.textContaining('basta con la marca «Ya lo pagué»'), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      await syncLedger(tester, env);
      final Tx paid = l.txs.firstWhere((Tx t) => t.kind == TxKind.transfer && t.toAccountId == 'tc');
      expect(paid.statementOf, '2026-09-30');
      expect(dateOnly(paid.date), DateTime(2026, 10, 15));
      expect(l.statement(tc, date: DateTime(2026, 10, 30)).dueMinor, before);
      final Finder row = find.textContaining('Extracto del 30 sep pagado con el movimiento del 15 oct');
      await tester.scrollUntilVisible(row, 150, scrollable: find.byType(Scrollable).first);
      expect(row, findsOneWidget);
      expect(find.text('Registrar el pago'), findsNothing);
      // Borrar el movimiento deja la marca como estaba: no aparece la mora.
      await tester.runAsync(() => l.deleteTx(paid.id));
      await settle(tester);
      expect(find.text('Registrar el pago'), findsOneWidget);
      expect(find.byType(OverdueBanner), findsNothing);
      await syncLedger(tester, env);
      await finish(tester);
      semantics.dispose();
    });
  });

  testWidgets('M2: dentro de los 60 s de gracia, «Ya lo pagué» de la notificación espera a la clave', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      late Account tc;
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        tc = await seedCard(e.services.ledger);
        await e.services.lock.setPasscode('2468');
      });
      final Ledger l = env.services.ledger;
      final AppLock lock = env.services.lock;
      await lifecycle(tester, <AppLifecycleState>[AppLifecycleState.resumed]);
      expect(lock.locked, isFalse);
      expect(lock.lockAfterSeconds, 60);
      // La persona sale de la app y, segundos después, toca el botón de la
      // notificación: la respuesta entra antes de que la app vuelva
      // (onNewIntent antes de onResume).
      await lifecycle(tester, toBackground);
      expect(lock.locked, isFalse);
      env.notifier.respond(paidResponse);
      await tester.pump();
      expect(l.isStatementPaid(tc, cut), isFalse);
      await lifecycle(tester, toForeground);
      await tester.pump(const Duration(milliseconds: 300));
      // Vuelve dentro de la gracia, pero tiene que poner la clave.
      expect(lock.locked, isTrue);
      expect(l.isStatementPaid(tc, cut), isFalse);
      expect(find.textContaining('Marcado como pagado'), findsNothing);
      await tester.runAsync(() => lock.verify('2468'));
      await settle(tester);
      expect(l.isStatementPaid(tc, cut), isTrue);
      expect(find.textContaining('Marcado como pagado'), findsOneWidget);
      await syncLedger(tester, env);
      await finish(tester);
    });
  });

  testWidgets('M2: con la app en primer plano y desbloqueada, el botón actúa enseguida', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      late Account tc;
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        tc = await seedCard(e.services.ledger);
        await e.services.lock.setPasscode('2468');
      });
      await lifecycle(tester, <AppLifecycleState>[AppLifecycleState.resumed]);
      env.notifier.respond(paidResponse);
      await settle(tester);
      expect(env.services.ledger.isStatementPaid(tc, cut), isTrue);
      expect(env.services.lock.locked, isFalse);
      await syncLedger(tester, env);
      await finish(tester);
    });
  });

  testWidgets('M2: al abrir la app en frío desde la notificación, con clave, espera a desbloquear', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      late Account tc;
      final TestEnv env = await start(tester, startup: true, before: (TestEnv e) async {
        tc = await seedCard(e.services.ledger);
        await e.services.lock.setPasscode('2468');
        // Arranque: el candado se lee bloqueado.
        await e.services.lock.load();
        e.services.settings.autoBackup = false;
        e.notifier.launch = paidResponse;
      });
      final Ledger l = env.services.ledger;
      await tester.pump(const Duration(milliseconds: 500));
      expect(env.services.lock.locked, isTrue);
      expect(l.isStatementPaid(tc, cut), isFalse);
      await tester.runAsync(() => env.services.lock.verify('2468'));
      await waitFor(tester, () => l.isStatementPaid(tc, cut));
      expect(l.isStatementPaid(tc, cut), isTrue);
      await syncLedger(tester, env);
      await finish(tester);
    });
  });
}
