// Quinta ronda de la auditoría, en la interfaz: «¿Ya lo pagaste?» al anotar
// un mínimo (G1), los botones del aviso informativo, «Ya lo pagué» desde la
// notificación, la fecha límite corrida (M2), los nombres de las copias
// (M3), el selector de restaurar ocupado (M4 de la ronda 4) y los tooltips
// que faltaba probar (M5).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plata/app.dart';
import 'package:plata/core/backup_picker.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/core/notifications.dart';
import 'package:plata/model/models.dart';
import 'package:plata/ui/budgets/budgets_screen.dart';
import 'package:plata/ui/more/cards_screen.dart';
import 'package:plata/ui/more/scheduled_screen.dart';

import 'support/env.dart';

Future<TestEnv> start(WidgetTester tester) async {
  final TestEnv env = (await tester.runAsync(() => makeEnv()))!;
  addTearDown(env.dispose);
  await tester.pumpWidget(PlataApp(services: env.services, startup: false));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return env;
}

Future<void> open(WidgetTester tester, Widget page) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute<void>(builder: (_) => page));
  await settle(tester);
}

Future<void> typeAmount(WidgetTester tester, String digits) async {
  for (final String k in digits.split('')) {
    await tapKey(tester, k);
  }
  await tester.tap(find.text('Listo'));
  await settle(tester);
}

Future<void> syncLedger(WidgetTester tester, TestEnv env) async {
  await tester.pump(const Duration(milliseconds: 500));
  await waitFor(tester, () => !env.services.ledger.busy);
}

/// Tarjeta con corte el 30 y pago el 15, y una compra que vencía el 15 de
/// octubre de 2026 (un jueves); "hoy" es el 16.
Future<Account> cardWithPastStatement(WidgetTester tester, Ledger l) async {
  late Account tc;
  await tester.runAsync(() async {
    tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, icon: 'card', cutDay: 30, payDay: 15));
    await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 100000000, accountId: 'tc', categoryId: 'c_food', date: DateTime(2026, 9, 20, 12)));
  });
  return tc;
}

void main() {
  testWidgets('G1: al crear la tarjeta después de pagar, «Sí, ya lo pagué» deja el extracto en cero', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester);
      await goTab(tester, 'Más');
      await openMore(tester, 'Cuentas');
      await tester.tap(find.widgetWithText(FloatingActionButton, 'Cuenta'));
      await settle(tester);
      await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.widgetWithText(ListTile, 'Tarjeta de crédito')).first);
      await settle(tester);
      await tester.tap(find.text('Deuda total hoy (todo lo que debes)'));
      await settle(tester);
      await typeAmount(tester, '3550000');
      final Finder field = find.text('Pago mínimo del último extracto (opcional)');
      await tester.scrollUntilVisible(field, 150, scrollable: find.byType(Scrollable).first);
      // La aclaración se ve siempre, aunque la fecha límite no haya pasado.
      expect(find.textContaining('Si ya lo pagaste, escribe 0'), findsOneWidget);
      await tester.tap(field);
      await settle(tester);
      await typeAmount(tester, '450000');
      expect(find.text('¿Ya lo pagaste?'), findsOneWidget);
      await tester.tap(find.text('Sí, ya lo pagué'));
      await settle(tester);
      expect(find.textContaining('Ese extracto ya está pagado'), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      final Ledger l = env.services.ledger;
      final Account card = l.accounts.firstWhere((Account a) => a.isCredit);
      expect(card.statementDueMinor, 0);
      expect(l.cardDue(card, now: DateTime(2026, 11, 6)).overdue, isFalse);
      expect(l.nextPayment(card, now: DateTime(2026, 11, 1)).dueMinor, 0);
      await syncLedger(tester, env);
      await finish(tester);
    });
  });

  testWidgets('G1: el aviso informativo separa «Ya pagué» de «Pagué solo el mínimo», y este no enciende la mora', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester);
      final Ledger l = env.services.ledger;
      final Account tc = await cardWithPastStatement(tester, l);
      await goTab(tester, 'Más');
      await openMore(tester, 'Tarjetas de crédito');
      expect(find.byType(UnconfirmedBanner), findsOneWidget);
      expect(find.text('Ya pagué: registrar el pago'), findsOneWidget);
      await tester.tap(find.text('Pagué solo el mínimo: anotarlo'));
      await settle(tester);
      await typeAmount(tester, '80000');
      // No pregunta: el botón ya dice que se pagó.
      expect(find.text('¿Ya lo pagaste?'), findsNothing);
      expect(find.byType(UnconfirmedBanner), findsNothing);
      expect(find.byType(OverdueBanner), findsNothing);
      expect(l.isStatementPaid(tc, DateTime(2026, 9, 30)), isTrue);
      expect(find.textContaining('El extracto queda pagado'), findsOneWidget);
      await syncLedger(tester, env);
      await finish(tester);
    });
  });

  testWidgets('G1: «Ya lo pagué» desde la notificación marca el extracto como pagado', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester);
      final Ledger l = env.services.ledger;
      final Account tc = await cardWithPastStatement(tester, l);
      l.setStatementMinimum(tc, DateTime(2026, 9, 30), 8000000);
      await settle(tester);
      expect(l.cardDue(tc).overdue, isTrue);
      env.notifier.respond(const NotifierResponse(payload: 'o:tc:2026-09-30', actionId: Notifier.paidAction));
      await settle(tester);
      expect(l.isStatementPaid(tc, DateTime(2026, 9, 30)), isTrue);
      expect(l.cardDue(tc).overdue, isFalse);
      expect(find.textContaining('Marcado como pagado'), findsOneWidget);
      // Tocar el aviso (sin el botón) abre Tarjetas.
      env.notifier.respond(const NotifierResponse(payload: 'o:tc:2026-09-30'));
      await settle(tester);
      expect(find.text('Tarjetas de crédito'), findsWidgets);
      expect(find.byType(OverdueBanner), findsNothing);
      await syncLedger(tester, env);
      await finish(tester);
    });
  });

  testWidgets('M2: Tarjetas dice en qué día cae el pago corrido', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester);
      // Corte el 15 y pago el 5: el pago del 5 de diciembre de 2026 (sábado)
      // se corre al lunes 7.
      await tester.runAsync(() async {
        await env.services.ledger.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, icon: 'card', cutDay: 15, payDay: 5));
        await env.services.ledger.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 1000000, accountId: 'tc', categoryId: 'c_food', date: DateTime(2026, 10, 16, 12)));
      });
      await goTab(tester, 'Más');
      await openMore(tester, 'Tarjetas de crédito');
      expect(find.textContaining('lun 07 dic 2026 (el sáb 05 dic no es hábil)'), findsOneWidget);
      await finish(tester);
    });
  });

  testWidgets('M3: las copias automáticas se ven con nombre legible', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester);
      await tester.runAsync(() async {
        await env.services.backups.autoBackup(force: true, now: DateTime(2026, 10, 16, 8));
        await env.services.backups.autoBackup(beforeRestore: true, now: DateTime(2026, 10, 16, 9, 12, 33));
      });
      await goTab(tester, 'Más');
      await openMore(tester, 'Copias de seguridad');
      // La lista se lee del disco con tiempo real.
      await waitFor(tester, () => find.textContaining('antes de restaurar (').evaluate().isNotEmpty);
      final Finder before = find.text('16 oct 2026 · antes de restaurar (09:12)');
      await tester.scrollUntilVisible(before, 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('16 oct 2026'), findsOneWidget);
      expect(find.text('16 oct 2026 · antes de restaurar (09:12)'), findsOneWidget);
      expect(find.textContaining('.json.enc'), findsNothing);
      expect(find.textContaining('las 5 de antes de restaurar'), findsOneWidget);
      await finish(tester);
    });
  });

  testWidgets('M4 (ronda 4): mientras se elige y copia el archivo, un segundo toque no abre otro selector', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      await start(tester);
      final Completer<Object?> pending = Completer<Object?>();
      int calls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(backupPickerChannel, (MethodCall call) async {
        calls += 1;
        return pending.future;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(backupPickerChannel, null));
      await goTab(tester, 'Más');
      await openMore(tester, 'Copias de seguridad');
      await tester.tap(find.text('Restaurar desde archivo'));
      await tester.pump();
      await tester.tap(find.text('Restaurar desde archivo'));
      await tester.pump();
      expect(calls, 1);
      pending.complete(null);
      await settle(tester);
      // Terminado (se canceló la elección), se puede volver a abrir.
      final Completer<Object?> again = Completer<Object?>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(backupPickerChannel, (MethodCall call) async {
        calls += 1;
        return again.future;
      });
      await tester.tap(find.text('Restaurar desde archivo'));
      await tester.pump();
      expect(calls, 2);
      again.complete(null);
      await settle(tester);
      await finish(tester);
    });
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('M5: «Quitar fecha de fin» y «Quitar cuenta» tienen nombre', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester);
      final Ledger l = env.services.ledger;
      late Scheduled s;
      late Budget b;
      await tester.runAsync(() async {
        s = await l.addScheduled(Scheduled(id: 's', name: 'Cuota', kind: TxKind.expense, amountMinor: 100, accountId: 'a_cash', nextDate: DateTime(2026, 10, 20), endDate: DateTime(2027, 10, 20)));
        b = await l.addBudget(Budget(id: 'b', name: 'Mercado', amountMinor: 10000, accountId: 'a_cash', startDate: DateTime(2026, 10, 1)));
      });
      await open(tester, ScheduledEditor(existing: s));
      final Finder end = find.byTooltip('Quitar fecha de fin');
      await tester.scrollUntilVisible(end, 150, scrollable: find.byType(Scrollable).first);
      expect(end, findsOneWidget);
      await back(tester);
      await open(tester, BudgetEditor(existing: b));
      final Finder acc = find.byTooltip('Quitar cuenta');
      await tester.scrollUntilVisible(acc, 150, scrollable: find.byType(Scrollable).first);
      expect(acc, findsOneWidget);
      await back(tester);
      await finish(tester);
    });
  });
}
