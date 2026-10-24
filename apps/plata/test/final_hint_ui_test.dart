// Comprobación final después de la ronda 13, en la interfaz: el aviso
// «¿Es el pago del extracto del …? Elegir» y el «Vinculado… Deshacer» del
// remedio se cierran a los 8 s sin lector de pantalla y se quedan con
// TalkBack o VoiceOver (accessibleNavigation); el aviso sale una sola vez por
// extracto, y «Elegir» dice el extracto al lector de pantalla (M-b).

import 'package:clock/clock.dart';
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

final DateTime sep15 = DateTime(2026, 9, 15);

/// Hoy es el 10 nov. Corte el 15 y pago el 5. El extracto del 15 sep
/// (mínimo 100.000) se pagó fuera y se marcó el 25 sep; el del 15 oct
/// (mínimo 120.000) se pagó desde Plata el 3 nov. La persona anota hoy, tarde,
/// la transferencia con la que pagó el del 15 sep.
Future<Account> seed(Ledger l) async {
  await l.addAccount(Account(id: 'ah', name: 'Ahorros', type: AccountType.bank, initialMinor: 500000000));
  final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, icon: 'card', cutDay: 15, payDay: 5));
  await l.addTx(Tx(id: 'c1', kind: TxKind.expense, amountMinor: 100000000, accountId: 'tc', categoryId: 'c_food', date: DateTime(2026, 8, 20, 12)));
  await l.addTx(Tx(id: 'c2', kind: TxKind.expense, amountMinor: 30000000, accountId: 'tc', categoryId: 'c_food', date: DateTime(2026, 9, 20, 12)));
  l.setStatementMinimum(tc, sep15, 10000000);
  l.markStatementPaid(tc, sep15, on: DateTime(2026, 9, 25));
  l.setStatementMinimum(tc, DateTime(2026, 10, 15), 12000000);
  await l.addTx(Tx(id: 'oct', kind: TxKind.transfer, amountMinor: 12000000, accountId: 'ah', toAccountId: 'tc', date: DateTime(2026, 11, 3, 12)));
  return tc;
}

/// Anota con el botón + una transferencia de [amount] pesos de Ahorros a Visa.
Future<void> payWithFab(WidgetTester tester, String amount) async {
  await tester.tap(find.byType(FloatingActionButton));
  await settle(tester);
  for (final String k in amount.split('')) {
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
}

final Finder hint = find.textContaining('¿Es el pago del extracto del 15 sep');

void main() {
  testWidgets('sin lector de pantalla: el aviso se cierra a los 8 s, sale una sola vez, y «Vinculado… Deshacer» también se cierra', (WidgetTester tester) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 10, 12)), () async {
      usePhone(tester);
      late Account tc;
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        tc = await seed(e.services.ledger);
      });
      final Ledger l = env.services.ledger;
      final SemanticsHandle semantics = tester.ensureSemantics();
      await payWithFab(tester, '100000');
      await syncLedger(tester, env);
      expect(find.byType(AlertDialog), findsNothing);
      expect(hint, findsOneWidget);
      // M-b: «Elegir» dice el extracto.
      expect(find.bySemanticsLabel('Elegir el pago del extracto del 15 sep'), findsOneWidget);
      expect(tc.outsideHinted, <String>['2026-09-15']);
      await tester.pump(const Duration(seconds: 9));
      await settle(tester);
      expect(hint, findsNothing);
      // Otro abono que también cabe: ya no avisa por el mismo extracto.
      await payWithFab(tester, '50000');
      await syncLedger(tester, env);
      expect(hint, findsNothing);
      // El remedio de la fila: su «Deshacer» también se cierra solo.
      await goTab(tester, 'Más');
      await openMore(tester, 'Tarjetas de crédito');
      final Finder remedy = find.text('Ya lo anoté en Plata: elegir el movimiento');
      await tester.scrollUntilVisible(remedy, 150, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(remedy);
      await settle(tester);
      await tester.tap(remedy);
      await settle(tester);
      await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.textContaining('100.000')).first);
      await settle(tester);
      await syncLedger(tester, env);
      expect(l.outsidePayment(tc, sep15), 0);
      expect(find.textContaining('Vinculado al extracto del 15 sep'), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      await settle(tester);
      expect(find.textContaining('Vinculado al extracto del 15 sep'), findsNothing);
      semantics.dispose();
      await finish(tester);
    });
  });

  testWidgets('con lector de pantalla (accessibleNavigation): el aviso y «Deshacer» se quedan hasta que se atienden', (WidgetTester tester) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 10, 12)), () async {
      usePhone(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      late Account tc;
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        tc = await seed(e.services.ledger);
      });
      final Ledger l = env.services.ledger;
      final String outId = l.outsidePayments(tc, sep15).single.id;
      await payWithFab(tester, '100000');
      await syncLedger(tester, env);
      expect(hint, findsOneWidget);
      await tester.pump(const Duration(seconds: 20));
      await settle(tester);
      expect(hint, findsOneWidget);
      await tester.tap(find.text('Elegir'));
      await settle(tester);
      expect(find.text('¿Cuál es el pago del extracto del 15 sep?'), findsOneWidget);
      // El abono del 3 nov es el pago del extracto del 15 oct: lo advierte.
      expect(find.descendant(of: find.byType(SimpleDialog), matching: find.text('Es el pago del extracto del 15 oct')), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.textContaining('10 nov')));
      await settle(tester);
      await syncLedger(tester, env);
      expect(l.outsidePayment(tc, sep15), 0);
      await tester.pump(const Duration(seconds: 20));
      await settle(tester);
      expect(find.textContaining('Vinculado al extracto del 15 sep'), findsOneWidget);
      await tester.tap(find.text('Deshacer'));
      await settle(tester);
      await syncLedger(tester, env);
      expect(l.outsidePayments(tc, sep15).single.id, outId);
      expect(find.text('Se deshizo el vínculo.'), findsOneWidget);
      await finish(tester);
    });
  });
}
