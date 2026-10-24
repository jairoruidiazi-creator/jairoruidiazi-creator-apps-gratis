// Décima ronda de la auditoría, en la interfaz: el pago hecho fuera de Plata
// es un movimiento que se ve en Movimientos; un abono a la tarjeta después
// de «Ya lo pagué» pregunta al guardar si es ese pago (G1, A1 y A1b); un
// abono que llegó sin pasar por el editor se pregunta en la fila del
// extracto; «Cambiar monto» (M5); y «Ya lo pagué» de un extracto de antes de
// la tarjeta pregunta si se pagó antes o después de crearla (G4, A3).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plata/app.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/model/models.dart';
import 'package:plata/ui/more/cards_screen.dart';
import 'package:plata/ui/transactions/tx_editor.dart';

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

/// Tarjeta con corte el 30 y pago el 15, una compra de $1.000.000 del 20 sep
/// y un mínimo de $80.000 del extracto del 30 sep, que vencía el jue 15 oct;
/// "hoy" es el 16. Hay una cuenta de ahorros para pagarla.
Future<Account> seedCard(Ledger l, {bool marked = true}) async {
  await l.addAccount(Account(id: 'ah', name: 'Ahorros', type: AccountType.bank, initialMinor: 500000000));
  final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, icon: 'card', cutDay: 30, payDay: 15));
  await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 100000000, accountId: 'tc', categoryId: 'c_food', date: DateTime(2026, 9, 20, 12)));
  l.setStatementMinimum(tc, DateTime(2026, 9, 30), 8000000);
  if (marked) {
    l.markStatementPaid(tc, DateTime(2026, 9, 30));
  }
  return tc;
}

final DateTime cut = DateTime(2026, 9, 30);

void main() {
  testWidgets('el pago hecho fuera de Plata se ve en Movimientos con su nombre y sin contar como ingreso', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        await seedCard(e.services.ledger);
      });
      expect(env.services.ledger.outsidePayment(env.services.ledger.account('tc')!, cut), 8000000);
      await goTab(tester, 'Movimientos');
      expect(find.text('Pago hecho fuera de Plata'), findsWidgets);
      expect(find.textContaining('extracto del 30 sep'), findsWidgets);
      await syncLedger(tester, env);
      await finish(tester);
    });
  });

  for (final bool same in <bool>[true, false]) {
    testWidgets('caso A1b: «Abonar a la tarjeta» después de «Ya lo pagué» pregunta al guardar (${same ? '«Sí, es ese pago»' : '«Es otro pago»'})', (WidgetTester tester) async {
      await atTestTime(() async {
        usePhone(tester);
        late Account tc;
        final TestEnv env = await start(tester, before: (TestEnv e) async {
          tc = await seedCard(e.services.ledger);
        });
        final Ledger l = env.services.ledger;
        await goTab(tester, 'Más');
        await openMore(tester, 'Tarjetas de crédito');
        final Finder pay = find.text('Abonar a la tarjeta');
        await tester.scrollUntilVisible(pay, 150, scrollable: find.byType(Scrollable).first);
        await tester.tap(pay);
        await settle(tester);
        expect(find.byType(TxEditor), findsOneWidget);
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(find.text('¿Es el pago del extracto del 30 sep?'), findsOneWidget);
        // No se cierra tocando fuera: hay que contestar.
        await tester.tapAt(const Offset(8, 8));
        await settle(tester);
        expect(find.text('¿Es el pago del extracto del 30 sep?'), findsOneWidget);
        await tester.tap(find.text(same ? 'Sí, es ese pago' : 'Es otro pago'));
        await settle(tester);
        await syncLedger(tester, env);
        final Tx paid = l.txs.firstWhere((Tx t) => t.kind == TxKind.transfer && t.toAccountId == 'tc');
        // Lo abonado: el saldo del ciclo en curso (1.000.000 − 80.000 de fuera).
        expect(paid.amountMinor, 92000000);
        if (same) {
          expect(paid.statementOf, '2026-09-30');
          expect(l.outsidePayment(tc, cut), 0);
          expect(-l.balanceMinor('tc'), 8000000);
        } else {
          expect(paid.statementOf, isNull);
          expect(paid.apartFrom, '2026-09-30');
          expect(l.outsidePayment(tc, cut), 8000000);
          expect(-l.balanceMinor('tc'), 0);
        }
        expect(l.isStatementPaid(tc, cut), isTrue);
        expect(l.pendingOutsideMatches(tc, cut), isEmpty);
        await finish(tester);
      });
    });
  }

  testWidgets('un abono que llegó sin pasar por el editor se pregunta en la fila del extracto', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      late Account tc;
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        tc = await seedCard(e.services.ledger);
        // Como el aviso del banco anotado sin abrir el editor.
        await e.services.ledger.addTx(Tx(id: 'n', kind: TxKind.transfer, amountMinor: 8000000, accountId: 'ah', toAccountId: 'tc', date: DateTime(2026, 10, 15, 12), source: 'notice'));
      });
      final Ledger l = env.services.ledger;
      expect(l.pendingOutsideMatches(tc, cut), hasLength(1));
      await goTab(tester, 'Más');
      await openMore(tester, 'Tarjetas de crédito');
      final Finder question = find.textContaining('¿El abono del 15 oct');
      await tester.scrollUntilVisible(question, 150, scrollable: find.byType(Scrollable).first);
      expect(question, findsOneWidget);
      await tester.tap(find.text('Sí, es ese'));
      await settle(tester);
      await syncLedger(tester, env);
      expect(l.txs.firstWhere((Tx t) => t.id == 'n').statementOf, '2026-09-30');
      expect(l.outsidePayment(tc, cut), 0);
      expect(l.isStatementPaid(tc, cut), isTrue);
      expect(-l.balanceMinor('tc'), 92000000);
      expect(find.textContaining('¿El abono del 15 oct'), findsNothing);
      await finish(tester);
    });
  });

  testWidgets('M5: «Cambiar monto» corrige lo pagado fuera de Plata', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      late Account tc;
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        tc = await seedCard(e.services.ledger);
      });
      final Ledger l = env.services.ledger;
      await goTab(tester, 'Más');
      await openMore(tester, 'Tarjetas de crédito');
      final Finder change = find.text('Cambiar monto');
      await tester.scrollUntilVisible(change, 150, scrollable: find.byType(Scrollable).first);
      await tester.tap(change);
      await settle(tester);
      // El teclado empieza en lo guardado: se borra (tecla de borrar
      // sostenida) y se escribe 50.000.
      await tester.longPress(find.byIcon(Icons.backspace_outlined).last);
      await tester.pump();
      for (final String k in '50000'.split('')) {
        await tapKey(tester, k);
      }
      await tester.tap(find.text('Listo'));
      await settle(tester);
      await syncLedger(tester, env);
      expect(l.outsidePayment(tc, cut), 5000000);
      expect(-l.balanceMinor('tc'), 95000000);
      expect(find.textContaining('Extracto del 30 sep pagado: \$'), findsOneWidget);
      await finish(tester);
    });
  });

  for (final bool before in <bool>[true, false]) {
    testWidgets('caso A3: «Ya lo pagué» de un extracto de antes de la tarjeta pregunta (${before ? '«Antes»: solo marca' : '«Después»: es un pago'})', (WidgetTester tester) async {
      await atTestTime(() async {
        usePhone(tester);
        late Account tc;
        final TestEnv env = await start(tester, before: (TestEnv e) async {
          final Ledger l = e.services.ledger;
          // Creada hoy con una deuda de 910.000; el extracto del 30 sep (mínimo
          // 80.000, vencía el 15 oct) es de antes de que empezara en Plata.
          tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, icon: 'card', initialMinor: -91000000, cutDay: 30, payDay: 15));
          l.setStatementMinimum(tc, cut, 8000000);
        });
        final Ledger l = env.services.ledger;
        expect(l.markKind(tc, cut), MarkKind.ask);
        await goTab(tester, 'Más');
        await openMore(tester, 'Tarjetas de crédito');
        expect(find.byType(OverdueBanner), findsOneWidget);
        final Finder paid = find.descendant(of: find.byType(OverdueBanner), matching: find.text('Ya lo pagué'));
        await tester.ensureVisible(paid);
        await settle(tester);
        await tester.tap(paid);
        await settle(tester);
        expect(find.text('¿Lo pagaste antes de crear la tarjeta en Plata?'), findsOneWidget);
        await tester.tap(find.text(before ? 'Antes' : 'Después'));
        await settle(tester);
        await syncLedger(tester, env);
        expect(l.isStatementPaid(tc, cut), isTrue);
        expect(find.byType(OverdueBanner), findsNothing);
        expect(-l.balanceMinor('tc'), before ? 91000000 : 83000000);
        expect(l.outsidePayment(tc, cut), before ? 0 : 8000000);
        expect(find.textContaining('Marcado como pagado'), findsOneWidget);
        await finish(tester);
      });
    });
  }
}
