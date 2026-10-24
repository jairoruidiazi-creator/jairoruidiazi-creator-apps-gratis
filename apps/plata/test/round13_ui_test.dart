// Decimotercera ronda de la auditoría, en la interfaz: con letra ×2 en un
// teléfono de 360 dp, la fila marcada con el remedio y el diálogo de elegir
// el movimiento caben; el aviso que no bloquea abre el remedio (M1) y el
// remedio se deshace (M2).

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plata/app.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/model/models.dart';
import 'package:plata/ui/transactions/tx_editor.dart';

import 'support/env.dart';

Future<TestEnv> start(WidgetTester tester, {Future<void> Function(TestEnv env)? before, DateTime? today}) async {
  final TestEnv env = (await tester.runAsync(() async {
    final TestEnv e = await makeEnv(today: today);
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

final DateTime sep15 = DateTime(2026, 9, 15);

/// Corte el 15 y pago el 5. El extracto del 15 sep (mínimo 100.000) se pagó
/// fuera y se marcó el 25 sep; el del 15 oct tiene su mínimo (120.000)
/// anotado y sin pagar. Hoy es el 16 oct.
Future<Account> seed(Ledger l) async {
  await l.addAccount(Account(id: 'ah', name: 'Ahorros', type: AccountType.bank, initialMinor: 500000000));
  final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, icon: 'card', cutDay: 15, payDay: 5));
  await l.addTx(Tx(id: 'c1', kind: TxKind.expense, amountMinor: 100000000, accountId: 'tc', categoryId: 'c_food', date: DateTime(2026, 8, 20, 12)));
  await l.addTx(Tx(id: 'c2', kind: TxKind.expense, amountMinor: 30000000, accountId: 'tc', categoryId: 'c_food', date: DateTime(2026, 9, 20, 12)));
  l.setStatementMinimum(tc, sep15, 10000000);
  l.markStatementPaid(tc, sep15, on: DateTime(2026, 9, 25));
  l.setStatementMinimum(tc, DateTime(2026, 10, 15), 12000000);
  return tc;
}

void main() {
  testWidgets('letra ×2 en 360 dp: la fila marcada con el remedio y el diálogo de elegir el movimiento caben', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester, textScale: 2);
      final List<String> errors = collectErrors();
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        await seed(e.services.ledger);
        await e.services.ledger.addTx(Tx(id: 'p', kind: TxKind.transfer, amountMinor: 10000000, accountId: 'ah', toAccountId: 'tc', date: DateTime(2026, 9, 24, 12), loggedOn: DateTime(2026, 9, 24), description: 'Pago Visa'));
      });
      await goTab(tester, 'Más');
      await openMore(tester, 'Tarjetas de crédito');
      final Finder remedy = find.text('Ya lo anoté en Plata: elegir el movimiento');
      await tester.scrollUntilVisible(remedy, 150, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(remedy);
      await settle(tester);
      expect(find.textContaining('Extracto del 15 sep pagado'), findsOneWidget);
      await tester.tap(remedy);
      await settle(tester);
      expect(find.text('¿Cuál es el pago del extracto del 15 sep?'), findsOneWidget);
      expect(find.descendant(of: find.byType(SimpleDialog), matching: find.textContaining('Pago Visa')), findsOneWidget);
      await tester.tapAt(const Offset(8, 8));
      await settle(tester);
      await syncLedger(tester, env);
      await finish(tester);
      expect(errors, isEmpty, reason: errors.join('\n----\n'));
    });
  });

  testWidgets('M1 y M2: el pago que no preguntó trae el aviso «Elegir», que lo vincula; «Deshacer» lo deja como estaba', (WidgetTester tester) async {
    // Comprobación final (G1): el aviso es para el pago anotado tarde. Hoy es
    // el 10 nov, después de la ventana (5 nov); el extracto del 15 oct ya se
    // pagó el 3 nov desde Plata.
    await withClock(Clock.fixed(DateTime(2026, 11, 10, 12)), () async {
      usePhone(tester);
      late Account tc;
      final TestEnv env = await start(tester, today: DateTime(2026, 11, 10, 12), before: (TestEnv e) async {
        tc = await seed(e.services.ledger);
        await e.services.ledger.addTx(Tx(id: 'oct', kind: TxKind.transfer, amountMinor: 12000000, accountId: 'ah', toAccountId: 'tc', date: DateTime(2026, 11, 3, 12)));
      });
      final Ledger l = env.services.ledger;
      final String outId = l.outsidePayments(tc, sep15).single.id;
      // El pago del 15 sep, anotado hoy con el botón +.
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      for (final String k in '100000'.split('')) {
        await tapKey(tester, k);
      }
      await tester.tap(find.text('Listo'));
      await settle(tester);
      await tester.tap(find.text('Transf.'));
      await settle(tester);
      await tester.tap(find.text('Hacia'));
      await settle(tester);
      await tester.tap(find.text('Visa').last);
      await settle(tester);
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      // No pregunta (fuera de la ventana)…
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(TxEditor), findsNothing);
      final Tx paid = l.txs.firstWhere((Tx t) => t.kind == TxKind.transfer && t.toAccountId == 'tc' && t.id != 'oct');
      expect(paid.outsidePending, isFalse);
      expect(l.pendingOutsideMatches(), isEmpty);
      // …pero avisa, sin bloquear.
      expect(find.textContaining('¿Es el pago del extracto del 15 sep'), findsOneWidget);
      await tester.tap(find.text('Elegir'));
      await settle(tester);
      expect(find.text('¿Cuál es el pago del extracto del 15 sep?'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.textContaining('10 nov')));
      await settle(tester);
      await syncLedger(tester, env);
      expect(l.txs.firstWhere((Tx t) => t.id == paid.id).statementOf, '2026-09-15');
      expect(l.outsidePayment(tc, sep15), 0);
      expect(find.textContaining('Vinculado al extracto del 15 sep'), findsOneWidget);
      await tester.tap(find.text('Deshacer'));
      await settle(tester);
      await syncLedger(tester, env);
      expect(l.txs.firstWhere((Tx t) => t.id == paid.id).statementOf, isNull);
      expect(l.outsidePayments(tc, sep15).single.id, outId);
      expect(l.outsidePayment(tc, sep15), 10000000);
      await finish(tester);
    });
  });
}
