// Undécima ronda de la auditoría, en la interfaz: la pregunta «¿Es el pago
// del extracto…?» sale por todos los caminos con pantalla, justo después de
// la acción y con el mismo diálogo (botón +, favorito de un toque, «Anotar
// ahora» de un programado, «Duplicar hoy»); la de un programado automático
// queda pendiente en Inicio y en Tarjetas hasta contestarla (G1-bis). Un
// pago de fuera no se duplica ni se vuelve plantilla (M2) y «Cambiar monto»
// sigue en la fila con lo de fuera en cero (M3).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plata/app.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/model/models.dart';
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

final DateTime cut = DateTime(2026, 9, 30);
const String question = '¿Es el pago del extracto del 30 sep?';

/// Tarjeta con corte el 30 y pago el 15, una compra de $1.000.000 del 20 sep,
/// un pago de $50.000 del 25 sep (el del mes pasado) y un mínimo de $80.000
/// del extracto del 30 sep, marcado «Ya lo pagué» el 16 oct ("hoy"). Hay una
/// cuenta de ahorros.
Future<Account> seedCard(Ledger l) async {
  await l.addAccount(Account(id: 'ah', name: 'Ahorros', type: AccountType.bank, initialMinor: 500000000));
  final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, icon: 'card', cutDay: 30, payDay: 15));
  await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 100000000, accountId: 'tc', categoryId: 'c_food', date: DateTime(2026, 9, 20, 12)));
  await l.addTx(Tx(id: 'prev', kind: TxKind.transfer, amountMinor: 5000000, accountId: 'ah', toAccountId: 'tc', date: DateTime(2026, 9, 25, 12), description: 'Pago Visa'));
  l.setStatementMinimum(tc, cut, 8000000);
  l.markStatementPaid(tc, cut, on: DateTime(2026, 10, 16));
  return tc;
}

int debt(Ledger l) => -l.balanceMinor('tc', before: DateTime(2040));

Future<void> answer(WidgetTester tester, {required bool same}) async {
  expect(find.text(question), findsOneWidget);
  // No se cierra tocando fuera: hay que contestar.
  await tester.tapAt(const Offset(8, 8));
  await settle(tester);
  expect(find.text(question), findsOneWidget);
  await tester.tap(find.text(same ? 'Sí, es ese pago' : 'Es otro pago'));
  await settle(tester);
}

void main() {
  testWidgets('B2: el pago anotado con el botón +, 11 días después de la marca y después del corte siguiente, pregunta', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      late Account tc;
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        final Ledger l = e.services.ledger;
        await l.addAccount(Account(id: 'ah', name: 'Ahorros', type: AccountType.bank, initialMinor: 500000000));
        // Corte el 15 y pago el 5: el extracto del 15 sep (mínimo 100.000)
        // vencía el lun 5 oct; se marcó ese día. Hoy es el 16 oct.
        tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, icon: 'card', cutDay: 15, payDay: 5));
        await l.addTx(Tx(id: 'c1', kind: TxKind.expense, amountMinor: 100000000, accountId: 'tc', categoryId: 'c_food', date: DateTime(2026, 8, 20, 12)));
        await l.addTx(Tx(id: 'c2', kind: TxKind.expense, amountMinor: 30000000, accountId: 'tc', categoryId: 'c_food', date: DateTime(2026, 9, 20, 12)));
        l.setStatementMinimum(tc, DateTime(2026, 9, 15), 10000000);
        l.markStatementPaid(tc, DateTime(2026, 9, 15), on: DateTime(2026, 10, 5));
      });
      final Ledger l = env.services.ledger;
      expect(debt(l), 120000000);
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
      expect(find.text('¿Es el pago del extracto del 15 sep?'), findsOneWidget);
      await tester.tap(find.text('Sí, es ese pago'));
      await settle(tester);
      await syncLedger(tester, env);
      expect(find.byType(TxEditor), findsNothing);
      final Tx paid = l.txs.firstWhere((Tx t) => t.kind == TxKind.transfer && t.toAccountId == 'tc');
      expect(paid.statementOf, '2026-09-15');
      expect(paid.outsidePending, isFalse);
      expect(l.outsidePayment(tc, DateTime(2026, 9, 15)), 0);
      expect(debt(l), 120000000);
      await finish(tester);
    });
  });

  testWidgets('favorito de un toque: la misma pregunta enseguida', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      late Account tc;
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        tc = await seedCard(e.services.ledger);
        await e.services.ledger.addTemplate(TxTemplate(id: 'tpl', name: 'Pago Visa', kind: TxKind.transfer, amountMinor: 8000000, accountId: 'ah', toAccountId: 'tc'));
      });
      final Ledger l = env.services.ledger;
      final Finder anyChip = find.byWidgetPredicate((Widget w) => w is ActionChip && w.label is Text && ((w.label as Text).data ?? '').startsWith('Pago Visa'));
      await tester.scrollUntilVisible(anyChip, 150, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(anyChip);
      await settle(tester);
      await tester.tap(anyChip);
      await settle(tester);
      await answer(tester, same: true);
      await syncLedger(tester, env);
      expect(l.pendingOutsideMatches(), isEmpty);
      expect(l.outsidePayment(tc, cut), 0);
      // 1.000.000 − 50.000 (sep) − 80.000 (este pago, una sola vez).
      expect(debt(l), 87000000);
      await finish(tester);
    });
  });

  testWidgets('«Anotar ahora» de un programado: la misma pregunta enseguida («Es otro pago»)', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      late Account tc;
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        tc = await seedCard(e.services.ledger);
        await e.services.ledger.addScheduled(Scheduled(id: 's', name: 'Abono Visa', kind: TxKind.transfer, amountMinor: 8000000, accountId: 'ah', toAccountId: 'tc', nextDate: DateTime(2026, 11, 14), autoPost: false));
      });
      final Ledger l = env.services.ledger;
      await goTab(tester, 'Más');
      await openMore(tester, 'Programados');
      await tester.tap(find.text('Abono Visa'));
      await settle(tester);
      await tester.tap(find.byWidgetPredicate((Widget w) => w is PopupMenuButton<String>));
      await settle(tester);
      await tester.tap(find.text('Anotar ahora'));
      await settle(tester);
      await answer(tester, same: false);
      await syncLedger(tester, env);
      expect(l.pendingOutsideMatches(), isEmpty);
      expect(l.outsidePayment(tc, cut), 8000000);
      // Pagó dos veces de verdad: 1.000.000 − 50.000 − 80.000 − 80.000.
      expect(debt(l), 79000000);
      await finish(tester);
    });
  });

  testWidgets('«Duplicar hoy» del pago del mes pasado: la misma pregunta enseguida', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      late Account tc;
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        tc = await seedCard(e.services.ledger);
      });
      final Ledger l = env.services.ledger;
      await goTab(tester, 'Movimientos');
      await tester.tap(find.text('Pago Visa'));
      await settle(tester);
      await tester.tap(find.byWidgetPredicate((Widget w) => w is PopupMenuButton<String>));
      await settle(tester);
      await tester.tap(find.text('Duplicar hoy'));
      await settle(tester);
      await answer(tester, same: true);
      await syncLedger(tester, env);
      expect(l.pendingOutsideMatches(), isEmpty);
      // La copia (50.000) reemplaza esa parte de lo de fuera: quedan 30.000.
      expect(l.outsidePayment(tc, cut), 3000000);
      expect(debt(l), 87000000);
      await finish(tester);
    });
  });

  testWidgets('programado automático: la pregunta queda en Inicio y en Tarjetas hasta contestarla', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      late Account tc;
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        final Ledger l = e.services.ledger;
        tc = await seedCard(l);
        await l.addScheduled(Scheduled(id: 'a', name: 'Pago Visa', kind: TxKind.transfer, amountMinor: 8000000, accountId: 'ah', toAccountId: 'tc', nextDate: DateTime(2026, 10, 16)));
        l.processScheduled(now: DateTime(2026, 10, 16));
      });
      final Ledger l = env.services.ledger;
      expect(l.pendingOutsideMatches(), hasLength(1));
      // Mientras tanto cuenta una sola vez.
      expect(debt(l), 87000000);
      expect(find.text(question), findsOneWidget);
      await goTab(tester, 'Más');
      await openMore(tester, 'Tarjetas de crédito');
      final Finder inCards = find.text(question);
      await tester.scrollUntilVisible(inCards, 150, scrollable: find.byType(Scrollable).first);
      expect(inCards, findsOneWidget);
      await back(tester);
      await goTab(tester, 'Inicio');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
      await settle(tester);
      final Finder yes = find.text('Sí, es ese pago');
      await tester.ensureVisible(yes);
      await settle(tester);
      await tester.tap(yes);
      await settle(tester);
      await syncLedger(tester, env);
      expect(l.pendingOutsideMatches(), isEmpty);
      expect(find.text(question), findsNothing);
      expect(l.outsidePayment(tc, cut), 0);
      expect(debt(l), 87000000);
      await finish(tester);
    });
  });

  testWidgets('M2: un pago de fuera no ofrece «Duplicar hoy» ni «Guardar como plantilla»', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        await seedCard(e.services.ledger);
      });
      await goTab(tester, 'Movimientos');
      await tester.tap(find.text('Pago hecho fuera de Plata'));
      await settle(tester);
      await tester.tap(find.byWidgetPredicate((Widget w) => w is PopupMenuButton<String>));
      await settle(tester);
      expect(find.text('Borrar'), findsOneWidget);
      expect(find.text('Duplicar hoy'), findsNothing);
      expect(find.text('Guardar como plantilla'), findsNothing);
      await tester.tapAt(const Offset(8, 8));
      await settle(tester);
      await syncLedger(tester, env);
      await finish(tester);
    });
  });

  testWidgets('M3: con lo de fuera en cero y el extracto marcado, «Cambiar monto» sigue en la fila', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      late Account tc;
      final TestEnv env = await start(tester, before: (TestEnv e) async {
        tc = await seedCard(e.services.ledger);
        e.services.ledger.setOutsidePayment(tc, cut, 0);
      });
      final Ledger l = env.services.ledger;
      expect(l.isStatementPaid(tc, cut), isTrue);
      await goTab(tester, 'Más');
      await openMore(tester, 'Tarjetas de crédito');
      final Finder change = find.text('Cambiar monto');
      await tester.scrollUntilVisible(change, 150, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(change);
      await settle(tester);
      await tester.tap(change);
      await settle(tester);
      for (final String k in '30000'.split('')) {
        await tapKey(tester, k);
      }
      await tester.tap(find.text('Listo'));
      await settle(tester);
      await syncLedger(tester, env);
      expect(l.outsidePayment(tc, cut), 3000000);
      await finish(tester);
    });
  });
}
