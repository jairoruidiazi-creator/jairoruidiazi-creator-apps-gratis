// Tercera ronda de la auditoría, en la interfaz: el campo del pago mínimo
// (G1), el rótulo de la deuda al editar (M1), restaurar en Android con el
// selector propio (M4) y los nombres del selector de ícono y color (M6).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plata/app.dart';
import 'package:plata/core/backup_picker.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/model/models.dart';

import 'support/env.dart';

Future<TestEnv> start(WidgetTester tester) async {
  final TestEnv env = (await tester.runAsync(() => makeEnv()))!;
  addTearDown(env.dispose);
  await tester.pumpWidget(PlataApp(services: env.services, startup: false));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return env;
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

void main() {
  testWidgets('G1: la tarjeta pide el pago mínimo, explica que no es el total y pregunta si se escribe casi toda la deuda', (WidgetTester tester) async {
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
      await typeAmount(tester, '4000000');
      final Finder field = find.text('Pago mínimo del último extracto (opcional)');
      await tester.scrollUntilVisible(field, 150, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('no el «pago total», que es toda la deuda'), findsOneWidget);
      // Casi toda la deuda: pregunta, y "Cancelar" no lo guarda.
      await tester.tap(field);
      await settle(tester);
      await typeAmount(tester, '3900000');
      expect(find.text('¿Es el pago mínimo?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      // El mínimo de verdad no pregunta nada.
      await tester.tap(field);
      await settle(tester);
      await typeAmount(tester, '450000');
      expect(find.text('¿Es el pago mínimo?'), findsNothing);
      expect(find.textContaining(r'El resto ($ 3.550.000) queda como deuda de antes de Plata'), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      final Ledger l = env.services.ledger;
      final Account card = l.accounts.firstWhere((Account a) => a.isCredit);
      expect(card.statementDueMinor, 45000000);
      expect(l.nextPayment(card).dueMinor, 45000000);
      await syncLedger(tester, env);
      await finish(tester);
    });
  });

  testWidgets('M1 y M6: al editar, la deuda es la del comienzo; el selector de ícono y color se lee con nombres', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final SemanticsHandle semantics = tester.ensureSemantics();
      final TestEnv env = await start(tester);
      await tester.runAsync(() => env.services.ledger.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, icon: 'card', initialMinor: -100000000, cutDay: 15, payDay: 5)));
      await goTab(tester, 'Más');
      await openMore(tester, 'Cuentas');
      await tester.longPress(find.text('Visa'));
      await settle(tester);
      expect(find.text('Deuda al empezar en Plata'), findsOneWidget);
      expect(find.text('Deuda total hoy (todo lo que debes)'), findsNothing);
      expect(find.textContaining('usa «Ajustar saldo real»'), findsOneWidget);
      final Finder picker = find.bySemanticsLabel('Ícono Billetera');
      await tester.scrollUntilVisible(picker, 150, scrollable: find.byType(Scrollable).first);
      expect(picker, findsOneWidget);
      expect(find.bySemanticsLabel('Color Verde'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Ícono (wallet|cart|card)$')), findsNothing);
      await back(tester);
      await finish(tester);
      semantics.dispose();
    });
  });

  testWidgets('M4: en Android se restaura con el selector propio; la copia se borra al leerla y lo enorme ni se lee', (WidgetTester tester) async {
    await atTestTime(() async {
      usePhone(tester);
      final TestEnv env = await start(tester);
      final Directory cache = (await tester.runAsync(() => Directory('${env.dir.path}/cache/restore').create(recursive: true)))!;
      final File copy = File('${cache.path}/elegido.bin');
      final List<Map<String, Object?>> answers = <Map<String, Object?>>[];
      final List<MethodCall> calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(backupPickerChannel, (MethodCall call) async {
        calls.add(call);
        return answers.removeAt(0);
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(backupPickerChannel, null));
      await goTab(tester, 'Más');
      await openMore(tester, 'Copias de seguridad');
      Future<void> restore() async {
        await tester.tap(find.text('Restaurar desde archivo'));
        await tester.pump();
        await waitFor(tester, () => find.byType(AlertDialog).evaluate().isNotEmpty);
      }

      // Un video enorme: el selector nativo dice que pasa del tope y no se lee.
      answers.add(<String, Object?>{'name': 'video.mp4', 'error': 'tooBig'});
      await restore();
      expect(calls.single.arguments, <String, Object>{'maxBytes': maxBackupBytes});
      expect(find.text('No es una copia de Plata'), findsOneWidget);
      await tester.tap(find.text('Entendido'));
      await settle(tester);
      // Un archivo que no es de Plata: se avisa y la copia ya no está.
      await tester.runAsync(() => copy.writeAsString('fecha,monto\n2026-10-01,5000\n'));
      answers.add(<String, Object?>{'name': 'extracto.csv', 'path': copy.path});
      await restore();
      expect(find.textContaining('«extracto.csv» no es una copia de Plata'), findsOneWidget);
      expect((await tester.runAsync(() => copy.exists()))!, isFalse);
      await tester.tap(find.text('Entendido'));
      await settle(tester);
      // El JSON de Plata: pregunta si reemplaza, y la copia sin cifrar ya se borró.
      await tester.runAsync(() => copy.writeAsString(jsonEncode(env.services.ledger.toJson())));
      answers.add(<String, Object?>{'name': 'plata.json', 'path': copy.path});
      await restore();
      expect(find.text('¿Reemplazar todos los datos?'), findsOneWidget);
      expect((await tester.runAsync(() => copy.exists()))!, isFalse);
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      await finish(tester);
    });
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}

