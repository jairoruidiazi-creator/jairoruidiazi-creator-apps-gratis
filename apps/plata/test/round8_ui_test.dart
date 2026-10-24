// Octava ronda de la auditoría, en la interfaz: la fila de un extracto con
// un pago vinculado parcial (M1), el nombre del botón de abajo (M3) y la
// pregunta del editor cuando dos extractos caerían en el mismo al cambiar el
// día de corte (G1).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plata/app.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/core/notifications.dart';
import 'package:plata/model/models.dart';
import 'package:plata/ui/more/accounts_screen.dart';

import 'support/env.dart';

Future<TestEnv> start(WidgetTester tester, {Future<void> Function(TestEnv env)? before}) async {
  final TestEnv env = (await tester.runAsync(() async {
    final TestEnv e = await makeEnv();
    await before?.call(e);
    return e;
  }))!;
  addTearDown(env.dispose);
  await tester.pumpWidget(PlataApp(services: env.services, startup: false));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return env;
}

Future<void> syncLedger(WidgetTester tester, TestEnv env) async {
  await tester.pump(const Duration(milliseconds: 500));
  await waitFor(tester, () => !env.services.ledger.busy);
}

final DateTime cut = DateTime(2026, 9, 30);

void main() {
  testWidgets('M1: con un pago vinculado parcial, la fila dice cuánto se da por pagado fuera y deja registrarlo', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      late Account tc;
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        final Ledger l = e.services.ledger;
        await l.addAccount(Account(id: 'ah', name: 'Ahorros', type: AccountType.bank, initialMinor: 500000000));
        tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, icon: 'card', cutDay: 30, payDay: 15));
        await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 100000000, accountId: 'tc', categoryId: 'c_food', date: DateTime(2026, 9, 20, 12)));
        l.setStatementMinimum(tc, cut, 8000000);
        l.markStatementPaid(tc, cut);
        await l.addTx(Tx(id: 'p', kind: TxKind.transfer, amountMinor: 4000000, accountId: 'ah', toAccountId: 'tc', date: DateTime(2026, 10, 15, 12), statementOf: '2026-09-30'));
      });
      final Ledger l = env.services.ledger;
      await goTab(tester, 'Más');
      await openMore(tester, 'Tarjetas de crédito');
      // «Extracto del 30 sep pagado: $ 40.000 con el movimiento del 15 oct, $ 40.000 por fuera de Plata».
      final Finder row = find.textContaining('Extracto del 30 sep pagado: ');
      expect(row, findsOneWidget);
      final String text = tester.widget<Text>(row).data!;
      expect(text, contains('con el movimiento del 15 oct'));
      expect(text, contains('por fuera de Plata'));
      expect(RegExp('40.000').allMatches(text), hasLength(2));
      // El botón de abajo tiene un nombre claro.
      expect(find.text('Abonar a la tarjeta'), findsOneWidget);
      final Finder log = find.text('Registrar el pago');
      await tester.scrollUntilVisible(log, 150, scrollable: find.byType(Scrollable).first);
      await tester.tap(log);
      await settle(tester);
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      await syncLedger(tester, env);
      // Registró los 40.000 que faltaban, vinculados: ya no queda nada fuera.
      expect(l.linkedPayments(tc, cut), 8000000);
      expect(l.outsidePayment(tc, cut), 0);
      expect(find.textContaining('Extracto del 30 sep pagado con los movimientos del 15 oct'), findsOneWidget);
      expect(find.text('Registrar el pago'), findsNothing);
      await finish(tester);
    });
  });

  testWidgets('G1: al cambiar el corte, si dos extractos caerían en el mismo, el editor pregunta cuál dejar', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      late Account tc;
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        final Ledger l = e.services.ledger;
        tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, icon: 'card', cutDay: 14, payDay: 30));
        l.setStatementMinimum(tc, DateTime(2026, 9, 14), 7000000);
        l.setStatementMinimum(tc, DateTime(2026, 10, 14), 9000000);
      });
      tester.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute<void>(builder: (_) => AccountEditor(existing: tc)));
      await settle(tester);
      // Hoy es el 16 oct: con el corte el 16, el extracto del 16 oct aún no
      // cierra, así que el del 14 oct pasa al del 16 sep, igual que el del 14 sep.
      final Finder field = find.ancestor(of: find.text('Día de corte'), matching: find.byWidgetPredicate((Widget w) => w is DropdownButtonFormField<int>));
      await tester.scrollUntilVisible(field, 150, scrollable: find.byType(Scrollable).first);
      await tester.tap(field);
      await settle(tester);
      await tester.tap(find.text('16').last);
      await settle(tester);
      expect(find.descendant(of: field, matching: find.text('16')), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      expect(find.text('¿Cuál es el pago mínimo del extracto del 16 sep?'), findsOneWidget);
      await tester.tap(find.textContaining('(del 14 sep)'));
      await settle(tester);
      expect(tc.cutDay, 16);
      expect(tc.statementMinimums, <String, int>{'2026-09-16': 7000000});
      await syncLedger(tester, env);
      await finish(tester);
    });
  });

  testWidgets('M4: «Ya lo pagué» de una notificación anterior a un cambio de corte no marca nada y lo dice', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      late Account tc;
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        final Ledger l = e.services.ledger;
        tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, icon: 'card', cutDay: 30, payDay: 15));
        await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 100000000, accountId: 'tc', categoryId: 'c_food', date: DateTime(2026, 9, 20, 12)));
        l.setStatementMinimum(tc, cut, 8000000);
        // El aviso del extracto del 30 sep salió; después se corrigió el corte a 29.
        tc.cutDay = 29;
        l.moveCardCut(tc, 30, oldPayDay: 15);
      });
      final Ledger l = env.services.ledger;
      env.notifier.respond(const NotifierResponse(payload: 'o:tc:2026-09-30', actionId: Notifier.paidAction));
      await settle(tester);
      expect(l.txs.where((Tx t) => t.isOutsidePayment), isEmpty);
      expect(find.textContaining('antes de cambiar el día de corte'), findsOneWidget);
      expect(find.textContaining('Marcado como pagado'), findsNothing);
      // El aviso que sí corresponde es el del extracto del 29 sep.
      expect(l.cardDue(tc).statementCut, DateTime(2026, 9, 29));
      await syncLedger(tester, env);
      await finish(tester);
    });
  });
}
