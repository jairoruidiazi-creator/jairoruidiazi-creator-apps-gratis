// Cuarta ronda de la auditoría, en la interfaz: las cuotas del avance desde
// el aviso de un retiro (G1), la pregunta de posible duplicado al confirmar
// un aviso (M1) y los nombres de los botones de ícono (M8).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plata/app.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/model/models.dart';
import 'package:plata/ui/transactions/tx_editor.dart';

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

Future<void> syncLedger(WidgetTester tester, TestEnv env) async {
  await tester.pump(const Duration(milliseconds: 500));
  await waitFor(tester, () => !env.services.ledger.busy);
}

void main() {
  testWidgets('G1: el aviso de un retiro con la tarjeta propone las cuotas del avance (24) y se guardan', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester);
      final Ledger l = env.services.ledger;
      late InboxItem notice;
      await tester.runAsync(() async {
        await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, icon: 'card', cutDay: 15, payDay: 5, bank: 'bancolombia', last4: '4821'));
        notice = await l.addInbox(InboxItem(id: 'retiro', bank: 'bancolombia', kind: TxKind.transfer, flow: NoticeFlow.withdrawal, amountMinor: 120000000, accountId: 'tc', last4: '4821', receivedAt: DateTime(2026, 10, 16, 9), rawText: r'Retiraste $1.200.000 con tu T.Cred *4821'));
      });
      await open(tester, TxEditor(inbox: notice));
      expect(find.text('Cuotas del avance'), findsOneWidget);
      expect(find.text('24'), findsOneWidget);
      expect(find.textContaining('suelen diferir los avances a 24 meses'), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      final Tx t = l.txs.single;
      expect(t.kind, TxKind.transfer);
      expect(t.accountId, 'tc');
      expect(t.installments, 24);
      expect(notice.status, 'accepted');
      await syncLedger(tester, env);
      await finish(tester);
    });
  });

  testWidgets('M1: al confirmar un aviso igual a un movimiento ya anotado, pregunta antes de contarlo dos veces', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester);
      final Ledger l = env.services.ledger;
      late InboxItem notice;
      await tester.runAsync(() async {
        await l.addAccount(Account(id: 'ah', name: 'Ahorros', type: AccountType.bank, icon: 'bank', initialMinor: 100000000, bank: 'bancolombia', last4: '7310'));
        await l.addTx(Tx(id: 'internet', kind: TxKind.expense, amountMinor: 9000000, accountId: 'ah', description: 'Internet', date: DateTime(2026, 10, 15, 12)));
        notice = await l.addInbox(InboxItem(id: 'aviso', bank: 'bancolombia', kind: TxKind.expense, amountMinor: 9000000, accountId: 'ah', last4: '7310', merchant: 'CLARO HOGAR', receivedAt: DateTime(2026, 10, 16, 9)));
      });
      await open(tester, TxEditor(inbox: notice));
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      expect(find.text('Posible duplicado'), findsOneWidget);
      expect(find.textContaining('Internet'), findsWidgets);
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      expect(l.txs, hasLength(1));
      expect(notice.status, 'pending');
      // Si de verdad son dos cargos, se anota igual.
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      await tester.tap(find.text('Anotar igual'));
      await settle(tester);
      expect(l.txs, hasLength(2));
      expect(notice.status, 'accepted');
      await syncLedger(tester, env);
      await finish(tester);
    });
  });

  testWidgets('M8: los botones de ícono que faltaban tienen nombre', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      await start(tester);
      await goTab(tester, 'Más');
      await openMore(tester, 'Cuentas');
      await tester.tap(find.text('Efectivo').first);
      await settle(tester);
      expect(find.byTooltip('Editar cuenta'), findsOneWidget);
      await back(tester);
      await finish(tester);
    });
  });
}
