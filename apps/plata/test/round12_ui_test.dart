// Duodécima ronda de la auditoría, en la interfaz: el remedio «Ya lo anoté en
// Plata: elegir el movimiento» de la fila de un extracto marcado, para quien
// anota el pago fuera de la ventana de la pregunta.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plata/app.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/model/models.dart';

import 'support/env.dart';

Future<TestEnv> start(WidgetTester tester, {Future<void> Function(TestEnv env)? before}) async {
  final TestEnv env = (await tester.runAsync(() async {
    final TestEnv e = await makeEnv();
    await before?.call(e);
    return e;
  }))!;
  addTearDown(env.dispose);
  await tester.pumpWidget(PlataApp(services: env.services));
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
  testWidgets('remedio: un pago anotado fuera de la ventana se elige desde la fila y reemplaza lo pagado fuera', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      late Account tc;
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        final Ledger l = e.services.ledger;
        await l.addAccount(Account(id: 'ah', name: 'Ahorros', type: AccountType.bank, initialMinor: 500000000));
        tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, icon: 'card', cutDay: 30, payDay: 15));
        await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 100000000, accountId: 'tc', categoryId: 'c_food', date: DateTime(2026, 9, 20, 12)));
        l.setStatementMinimum(tc, cut, 8000000);
        l.markStatementPaid(tc, cut, on: DateTime(2026, 10, 16));
        // El pago del 14 oct, anotado antes de la marca (fuera de la ventana):
        // no pregunta y cuenta dos veces hasta elegirlo.
        await l.addTx(Tx(id: 'p', kind: TxKind.transfer, amountMinor: 8000000, accountId: 'ah', toAccountId: 'tc', date: DateTime(2026, 10, 14, 12), loggedOn: DateTime(2026, 10, 10), description: 'Pago Visa'));
      });
      final Ledger l = env.services.ledger;
      expect(l.pendingOutsideMatches(), isEmpty);
      expect(-l.balanceMinor('tc'), 84000000);
      await goTab(tester, 'Más');
      await openMore(tester, 'Tarjetas de crédito');
      final Finder remedy = find.text('Ya lo anoté en Plata: elegir el movimiento');
      await tester.scrollUntilVisible(remedy, 150, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(remedy);
      await settle(tester);
      await tester.tap(remedy);
      await settle(tester);
      expect(find.text('¿Cuál es el pago del extracto del 30 sep?'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.textContaining('Pago Visa')));
      await settle(tester);
      await syncLedger(tester, env);
      expect(l.txs.firstWhere((Tx t) => t.id == 'p').statementOf, '2026-09-30');
      expect(l.outsidePayment(tc, cut), 0);
      expect(l.isStatementPaid(tc, cut), isTrue);
      expect(-l.balanceMinor('tc'), 92000000);
      expect(find.textContaining('Vinculado al extracto del 30 sep'), findsOneWidget);
      await finish(tester);
    });
  });
}
