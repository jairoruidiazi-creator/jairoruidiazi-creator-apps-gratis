// Sexta ronda de la auditoría, en la interfaz: «Ya lo pagué» se deshace
// («Deshacer» y «Desmarcar», y «Todavía no» desmarca), el pago de un extracto
// marcado se registra con su fecha límite (G1), el arranque desde la
// notificación y la espera al desbloqueo (M1, M4), y el editor de la tarjeta
// con la fecha corrida y una pregunta que no se cierra tocando fuera (M2).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plata/app.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/core/notifications.dart';
import 'package:plata/model/models.dart';
import 'package:plata/ui/more/cards_screen.dart';
import 'package:plata/ui/transactions/tx_editor.dart';

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

Future<void> typeAmount(WidgetTester tester, String digits) async {
  for (final String k in digits.split('')) {
    await tapKey(tester, k);
  }
  await tester.tap(find.text('Listo'));
  await settle(tester);
}

/// Tarjeta con corte el 30 y pago el 15, una compra del 20 sep y un mínimo
/// de $80.000 del extracto del 30 sep, que vencía el jue 15 oct; "hoy" es el
/// 16. Hay una cuenta de ahorros para pagarla.
Future<Account> overdueCard(WidgetTester tester, Ledger l) async {
  late Account tc;
  await tester.runAsync(() async {
    tc = await seedCard(l);
  });
  return tc;
}

Future<Account> seedCard(Ledger l) async {
  await l.addAccount(Account(id: 'ah', name: 'Ahorros', type: AccountType.bank, initialMinor: 500000000));
  final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, icon: 'card', cutDay: 30, payDay: 15));
  await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 100000000, accountId: 'tc', categoryId: 'c_food', date: DateTime(2026, 9, 20, 12)));
  l.setStatementMinimum(tc, DateTime(2026, 9, 30), 8000000);
  return tc;
}

final DateTime cut = DateTime(2026, 9, 30);

void main() {
  testWidgets('M1: «Ya lo pagué» se deshace con «Deshacer» y con «Desmarcar» en Tarjetas', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester);
      final Ledger l = env.services.ledger;
      final Account tc = await overdueCard(tester, l);
      await goTab(tester, 'Más');
      await openMore(tester, 'Tarjetas de crédito');
      expect(find.byType(OverdueBanner), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(OverdueBanner), matching: find.text('Ya lo pagué')));
      await settle(tester);
      expect(l.isStatementPaid(tc, cut), isTrue);
      expect(find.byType(OverdueBanner), findsNothing);
      expect(find.textContaining('Marcado como pagado'), findsOneWidget);
      await tester.tap(find.text('Deshacer'));
      await settle(tester);
      expect(l.isStatementPaid(tc, cut), isFalse);
      expect(find.byType(OverdueBanner), findsOneWidget);
      // Marcado otra vez: Tarjetas lo dice y deja desmarcarlo después.
      await tester.tap(find.descendant(of: find.byType(OverdueBanner), matching: find.text('Ya lo pagué')));
      await settle(tester);
      await tester.pump(const Duration(seconds: 10));
      await settle(tester);
      final Finder row = find.text('Extracto del 30 sep marcado como pagado');
      await tester.scrollUntilVisible(row, 150, scrollable: find.byType(Scrollable).first);
      expect(row, findsOneWidget);
      await tester.tap(find.text('Desmarcar'));
      await settle(tester);
      expect(l.isStatementPaid(tc, cut), isFalse);
      expect(row, findsNothing);
      await syncLedger(tester, env);
      await finish(tester);
    });
  });

  testWidgets('G1: «Registrar el pago» de un extracto marcado propone su fecha límite, y no lo cuenta dos veces', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester);
      final Ledger l = env.services.ledger;
      final Account tc = await overdueCard(tester, l);
      l.markStatementPaid(tc, cut);
      final int before = l.statement(tc, date: DateTime(2026, 10, 30)).dueMinor;
      await goTab(tester, 'Más');
      await openMore(tester, 'Tarjetas de crédito');
      final Finder log = find.text('Registrar el pago');
      await tester.scrollUntilVisible(log, 150, scrollable: find.byType(Scrollable).first);
      await tester.tap(log);
      await settle(tester);
      expect(find.byType(TxEditor), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      await syncLedger(tester, env);
      final Tx paid = l.txs.firstWhere((Tx t) => t.kind == TxKind.transfer && t.toAccountId == 'tc');
      // La fecha límite real (jue 15 oct), no hoy (16): el pago se hizo antes.
      expect(dateOnly(paid.date), DateTime(2026, 10, 15));
      expect(paid.amountMinor, 8000000);
      // El registro reemplaza al abono supuesto: el extracto siguiente no cambia.
      expect(l.statement(tc, date: DateTime(2026, 10, 30)).dueMinor, before);
      expect(l.cardDue(tc).overdue, isFalse);
      await finish(tester);
    });
  });

  testWidgets('M1: «Todavía no» desmarca un extracto marcado como pagado', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester);
      final Ledger l = env.services.ledger;
      final Account tc = await overdueCard(tester, l);
      l.markStatementPaid(tc, cut);
      await goTab(tester, 'Más');
      await openMore(tester, 'Tarjetas de crédito');
      expect(find.byType(OverdueBanner), findsNothing);
      await tester.tap(find.text('Cambiar'));
      await settle(tester);
      // El mismo mínimo: "Listo" lo deja como está.
      await tester.tap(find.text('Listo'));
      await settle(tester);
      expect(find.text('¿Ya lo pagaste?'), findsOneWidget);
      // No se cierra tocando fuera: hay que contestar.
      await tester.tapAt(const Offset(8, 8));
      await settle(tester);
      expect(find.text('¿Ya lo pagaste?'), findsOneWidget);
      await tester.tap(find.text('Todavía no'));
      await settle(tester);
      expect(l.isStatementPaid(tc, cut), isFalse);
      expect(find.byType(OverdueBanner), findsOneWidget);
      await syncLedger(tester, env);
      await finish(tester);
    });
  });

  testWidgets('M4: abrir la app con «Ya lo pagué» de la notificación (arranque) marca el extracto', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      // La app estaba cerrada: la tarjeta ya está en el libro y la respuesta
      // llega con el arranque (getNotificationAppLaunchDetails).
      final TestEnv env = await start(tester, startup: true, before: (TestEnv env) async {
        await seedCard(env.services.ledger);
        env.services.settings.autoBackup = false;
        env.notifier.launch = const NotifierResponse(payload: 'o:tc:2026-09-30', actionId: Notifier.paidAction);
      });
      final Ledger l = env.services.ledger;
      final Account tc = l.account('tc')!;
      await waitFor(tester, () => l.isStatementPaid(tc, cut));
      expect(l.isStatementPaid(tc, cut), isTrue);
      expect(find.textContaining('Marcado como pagado'), findsOneWidget);
      await syncLedger(tester, env);
      await finish(tester);
    });
  });

  testWidgets('M1: con la app bloqueada, el botón de la notificación espera al desbloqueo', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester);
      final Ledger l = env.services.ledger;
      final Account tc = await overdueCard(tester, l);
      await tester.runAsync(() => env.services.lock.setPasscode('2468'));
      env.services.lock.lockNow();
      await tester.pump();
      env.notifier.respond(const NotifierResponse(payload: 'o:tc:2026-09-30', actionId: Notifier.paidAction));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Bloqueada: no se marca nada detrás de la pantalla de la clave.
      expect(l.isStatementPaid(tc, cut), isFalse);
      expect(find.textContaining('Marcado como pagado'), findsNothing);
      await tester.runAsync(() => env.services.lock.verify('2468'));
      await settle(tester);
      expect(env.services.lock.locked, isFalse);
      expect(l.isStatementPaid(tc, cut), isTrue);
      expect(find.textContaining('Marcado como pagado'), findsOneWidget);
      await syncLedger(tester, env);
      await finish(tester);
    });
  });

  testWidgets('M2: el editor de la tarjeta dice la fecha límite corrida', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      await start(tester);
      await goTab(tester, 'Más');
      await openMore(tester, 'Cuentas');
      await tester.tap(find.widgetWithText(FloatingActionButton, 'Cuenta'));
      await settle(tester);
      await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.widgetWithText(ListTile, 'Tarjeta de crédito')).first);
      await settle(tester);
      // Corte el 15 y pago el 7: el extracto del 15 oct vence el sáb 7 nov,
      // que se corre al lun 9.
      final Finder pay = find.ancestor(of: find.text('Día de pago'), matching: find.byWidgetPredicate((Widget w) => w is DropdownButtonFormField<int>));
      await tester.scrollUntilVisible(pay, 150, scrollable: find.byType(Scrollable).first);
      await tester.tap(pay);
      await settle(tester);
      await tester.tap(find.text('7').last);
      await settle(tester);
      await tester.ensureVisible(find.text('Deuda total hoy (todo lo que debes)'));
      await settle(tester);
      await tester.tap(find.text('Deuda total hoy (todo lo que debes)'));
      await settle(tester);
      await typeAmount(tester, '1000000');
      final Finder hint = find.textContaining('que vence el lun 09 nov (el sáb 07 nov no es hábil)');
      await tester.scrollUntilVisible(hint, 150, scrollable: find.byType(Scrollable).first);
      expect(hint, findsOneWidget);
      expect(find.textContaining('Ya venció'), findsNothing);
      // «¿Ya lo pagaste?» no se cierra tocando fuera.
      await tester.ensureVisible(find.text('Pago mínimo del último extracto (opcional)'));
      await settle(tester);
      await tester.tap(find.text('Pago mínimo del último extracto (opcional)'));
      await settle(tester);
      await typeAmount(tester, '100000');
      expect(find.text('¿Ya lo pagaste?'), findsOneWidget);
      await tester.tapAt(const Offset(8, 8));
      await settle(tester);
      expect(find.text('¿Ya lo pagaste?'), findsOneWidget);
      await tester.tap(find.text('Todavía no'));
      await settle(tester);
      expect(find.text('¿Ya lo pagaste?'), findsNothing);
      await finish(tester);
    });
  });
}
