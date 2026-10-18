// Avisos bancarios: los hallazgos B4, G12–G15, M3, M4 y M12 del informe de
// auditoría.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plata/core/bank_rules.dart';
import 'package:plata/core/crypto_store.dart';
import 'package:plata/core/exports.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/core/notices.dart';
import 'package:plata/core/settings.dart';
import 'package:plata/core/storage.dart';
import 'package:plata/model/models.dart';

const String bancolombia = 'co.com.bancolombia.personas.superapp';
const String nequi = 'com.nequi.MobileApp';

DateTime d(int y, int m, int day, [int h = 12]) => DateTime(y, m, day, h);

/// Paquetes del servicio nativo que lee las notificaciones (Kotlin).
Set<String> kotlinPackages(String path) {
  final String src = File(path).readAsStringSync();
  final RegExpMatch? m = RegExp(r'val packages: Set<String> = setOf\(([^)]*)\)').firstMatch(src);
  expect(m, isNotNull, reason: 'No encontré la lista de paquetes en $path');
  return RegExp(r'"([^"]+)"').allMatches(m!.group(1)!).map((RegExpMatch x) => x.group(1)!).toSet();
}

BankSuggestion? parse(String package, String text, {String title = ''}) => BankRules.parse(packageName: package, title: title, text: text);

void main() {
  group('B4: las apps que se leen existen y son las mismas en Dart y en Android', () {
    test('la lista del servicio nativo es la de BankRules (fuente y copia generada)', () {
      final Set<String> dart = BankRules.packages.keys.toSet();
      expect(kotlinPackages('native/android/BankNoticeListener.kt'), dart);
      expect(kotlinPackages('android/app/src/main/kotlin/co/appsgratis/plata/BankNoticeListener.kt'), dart);
    });

    test('cada paquete es de un banco con nombre y Mi Bancolombia es la app que se lee', () {
      expect(BankRules.packages[bancolombia], 'bancolombia');
      for (final String bank in BankRules.packages.values) {
        expect(BankRules.bankNames.containsKey(bank), isTrue, reason: bank);
      }
      // Cada banco que se ofrece en la app tiene su paquete: no se promete uno que no se lee.
      expect(BankRules.bankNames.keys.toSet(), BankRules.packages.values.toSet());
      // Paquetes que no existen en Google Play o no son de Colombia.
      for (final String gone in <String>['com.bancolombia.personas', 'com.bancolombia.app.personas', 'com.nequi.mobileapp', 'co.com.bancodeoccidente.bancamovil', 'com.scotiabankcolpatria.mobile', 'com.lulobank.app', 'co.com.rappi.pay', 'co.uala.app', 'com.movii.movii']) {
        expect(BankRules.packages.containsKey(gone), isFalse, reason: gone);
      }
    });

    test('la política, la ficha y la guía nombran los mismos bancos', () {
      final List<String> texts = <String>[
        File('assets/legal/privacy_es.md').readAsStringSync(),
        File('assets/legal/privacy_en.md').readAsStringSync(),
        File('fastlane/metadata/android/es-419/full_description.txt').readAsStringSync(),
        File('fastlane/metadata/android/en-US/full_description.txt').readAsStringSync(),
      ];
      for (final String t in texts) {
        for (final String removed in <String>['Ualá', 'Uala', 'RappiPay', 'Rappi Pay', 'Scotiabank Colpatria app']) {
          expect(t.contains(removed), isFalse, reason: removed);
        }
      }
      for (final String t in texts.take(2)) {
        for (final String key in BankRules.bankNames.keys) {
          expect(t.contains(BankRules.displayName(key).split(' (').first), isTrue, reason: '${BankRules.displayName(key)} en la política');
        }
      }
      // La ficha de Google Play dice cuántas apps se leen.
      for (final String t in texts.skip(2)) {
        expect(t, contains('${BankRules.packages.length} '));
      }
      expect(BankRules.namesList(spanish: true), endsWith('y MOVii'));
      expect(BankRules.namesList(spanish: false), contains('DAVIbank (formerly Scotiabank Colpatria)'));
    });
  });

  group('G12: montos que cierran la frase', () {
    test('el punto o la coma final no se lee como decimal', () {
      expect(parse(bancolombia, r'Bancolombia: Compraste $500.000,00. en ALKOSTO con tu T.Cred *4821.')!.amountMinor, 50000000);
      expect(parse(bancolombia, r'Compraste $85.900. Gracias por usar tu tarjeta *4821')!.amountMinor, 8590000);
      expect(parse(nequi, r'Pagaste $1.250,50, en Tostao. Tu saldo es $80.000')!.amountMinor, 125050);
      expect(parse(nequi, r'Te llegaron $120.000; ya están en tu Nequi.')!.amountMinor, 12000000);
    });
  });

  group('G13: moneda y transferencias', () {
    test('un aviso en dólares queda en dólares', () {
      final BankSuggestion s = parse(bancolombia, r'Compraste US$25,99 en NETFLIX.COM con tu T.Cred *4821.')!;
      expect(s.currency, 'USD');
      expect(s.amountMinor, 2599);
      expect(s.kind, TxKind.expense);
      expect(s.last4, '4821');
    });

    test('pagar la tarjeta, retirar y pasar a un bolsillo son transferencias', () {
      final BankSuggestion pay = parse(bancolombia, r'Bancolombia: Pagaste $1.200.000 a tu tarjeta de crédito *4821 desde tu cuenta *7310.')!;
      expect(pay.kind, TxKind.transfer);
      expect(pay.flow, NoticeFlow.cardPayment);
      expect(pay.toLast4, '4821');
      expect(pay.last4, '7310');
      final BankSuggestion atm = parse(bancolombia, r'Retiraste $300.000 en el cajero CENTRO con tu tarjeta débito *1234.')!;
      expect(atm.kind, TxKind.transfer);
      expect(atm.flow, NoticeFlow.withdrawal);
      final BankSuggestion pocket = parse(nequi, r'Pasaste $50.000 a tu bolsillo Viaje.')!;
      expect(pocket.kind, TxKind.transfer);
      expect(pocket.flow, NoticeFlow.transferOut);
      // "Pago con tu tarjeta" es una compra, no un pago de la tarjeta.
      final BankSuggestion buy = parse(bancolombia, r'Pago por $45.000 con tu tarjeta *4821 en FARMATODO.')!;
      expect(buy.kind, TxKind.expense);
    });

    test('la publicidad con montos no es un movimiento', () {
      expect(parse(bancolombia, r'Aprovecha 20% de descuento en compras superiores a $100.000 con tu tarjeta.'), isNull);
      expect(parse(nequi, r'¡Gana hasta $1.000.000! Participa en el sorteo.'), isNull);
      expect(parse(bancolombia, r'Tienes un crédito preaprobado por $5.000.000. Solicítalo hoy.'), isNull);
      expect(parse(bancolombia, r'Compra rechazada por $20.000 en NETFLIX. Fondos insuficientes.'), isNull);
      // Una compra real que menciona un beneficio sí cuenta.
      expect(parse(bancolombia, r'Compraste $50.000 en EXITO con tu T.Cred *4821. Ganaste cashback.')!.amountMinor, 5000000);
    });

    late Directory tmp;
    late Ledger l;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('plata_notices');
      l = Ledger(EncryptedStore(JsonStore(root: tmp), await CryptoBox.fromKeyStore(MemoryKeyStore())), clock: () => d(2026, 10, 16));
      await l.load();
      await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, bank: 'bancolombia', last4: '4821', cutDay: 15, payDay: 5));
      await l.addAccount(Account(id: 'ah', name: 'Ahorros', type: AccountType.bank, bank: 'bancolombia', last4: '7310'));
    });

    tearDown(() async {
      l.dispose();
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('al anotar se convierte a la moneda de la cuenta; sin tasa no se anota', () async {
      final InboxItem usd = await l.addInbox(InboxItem(id: 'u', bank: 'bancolombia', kind: TxKind.expense, amountMinor: 2599, currency: 'USD', last4: '4821', merchant: 'NETFLIX.COM', receivedAt: d(2026, 10, 16, 9), rawText: 'Compraste US\$25,99 en NETFLIX.COM'));
      expect(usd.accountId, 'tc');
      expect(await l.acceptInbox(usd), isNull);
      expect(usd.status, 'pending');
      l.rates.rates['USD'] = 4000;
      final Tx? t = await l.acceptInbox(usd);
      expect(t!.amountMinor, 2599 * 4000);
      expect(t.currency, 'COP');
      expect(usd.status, 'accepted');
    });

    test('una transferencia nunca se anota sola como gasto', () async {
      final InboxItem pay = await l.addInbox(InboxItem(id: 'p', bank: 'bancolombia', kind: TxKind.transfer, flow: NoticeFlow.cardPayment, amountMinor: 120000000, last4: '7310', toLast4: '4821', receivedAt: d(2026, 10, 16, 9), rawText: 'Pagaste a tu tarjeta'));
      expect(await l.acceptInbox(pay), isNull);
      expect(l.matchNotice(pay).account!.id, 'ah'); // la de origen, no la tarjeta
      expect(l.noticeCard(pay)!.id, 'tc');
      final AppSettings settings = AppSettings()
        ..noticesEnabled = true
        ..noticesAutoPost = true;
      final FakeNoticeBridge bridge = FakeNoticeBridge();
      final NoticeService svc = NoticeService(bridge: bridge, ledger: l, settings: settings);
      await svc.handle(RawNotice(package: bancolombia, title: 'Bancolombia', text: r'Pagaste $500.000 a tu tarjeta de crédito *4821 desde tu cuenta *7310.', time: d(2026, 10, 16, 10)));
      await svc.handle(RawNotice(package: bancolombia, title: 'Bancolombia', text: r'Compraste US$10,00 en STEAM con tu T.Cred *4821.', time: d(2026, 10, 16, 11)));
      await svc.handle(RawNotice(package: bancolombia, title: 'Bancolombia', text: r'Compraste $62.400 en EL FOGON con tu T.Cred *4821.', time: d(2026, 10, 16, 12)));
      // Solo la compra en pesos con la tarjeta identificada se anotó sola.
      expect(l.txs.single.amountMinor, 6240000);
      expect(l.txs.single.accountId, 'tc');
      expect(l.pendingInbox.length, 3);
      expect(l.pendingInbox.where((InboxItem i) => i.kind == TxKind.transfer).length, 2);
    });
  });

  group('G14: emparejar un aviso con su cuenta', () {
    late Directory tmp;
    late Ledger l;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('plata_match');
      l = Ledger(EncryptedStore(JsonStore(root: tmp), await CryptoBox.fromKeyStore(MemoryKeyStore())), clock: () => d(2026, 10, 16));
      await l.load();
    });

    tearDown(() async {
      l.dispose();
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('el banco escrito con su nombre (o el de antes) sirve igual que la clave', () async {
      expect(BankRules.keyFor('Bancolombia'), 'bancolombia');
      expect(BankRules.keyFor('Mi Bancolombia'), 'bancolombia');
      expect(BankRules.keyFor('Banco de Bogotá'), 'bogota');
      expect(BankRules.keyFor('  scotiabank colpatria '), 'davibank');
      expect(BankRules.keyFor('Mi banco de barrio'), '');
      await l.addAccount(Account(id: 'bog', name: 'Nómina', type: AccountType.bank, bank: 'Banco de Bogotá', last4: '5555'));
      final InboxItem n = await l.addInbox(InboxItem(id: 'n', bank: 'bogota', kind: TxKind.expense, amountMinor: 100, last4: '5555', receivedAt: d(2026, 10, 16)));
      expect(n.accountId, 'bog');
      expect(l.matchNotice(n).certain, isTrue);
    });

    test('si hay dudas no se adivina', () async {
      await l.addAccount(Account(id: 'a1', name: 'Ahorros', type: AccountType.bank, bank: 'davivienda', last4: '1111'));
      await l.addAccount(Account(id: 'a2', name: 'Corriente', type: AccountType.bank, bank: 'davivienda', last4: '2222'));
      final InboxItem sinDigitos = InboxItem(id: 'x', bank: 'davivienda', kind: TxKind.expense, amountMinor: 100, receivedAt: d(2026, 10, 16));
      expect(l.matchNotice(sinDigitos).account, isNull);
      final InboxItem otros = InboxItem(id: 'y', bank: 'davivienda', kind: TxKind.expense, amountMinor: 100, last4: '9999', receivedAt: d(2026, 10, 16));
      expect(l.matchNotice(otros).account, isNull);
      final InboxItem bueno = InboxItem(id: 'z', bank: 'davivienda', kind: TxKind.expense, amountMinor: 100, last4: '2222', receivedAt: d(2026, 10, 16));
      expect(l.matchNotice(bueno).account!.id, 'a2');
    });
  });

  group('G15: apagar la lectura de avisos', () {
    late Directory tmp;
    late Ledger l;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('plata_off');
      l = Ledger(EncryptedStore(JsonStore(root: tmp), await CryptoBox.fromKeyStore(MemoryKeyStore())), clock: () => d(2026, 10, 16));
      await l.load();
    });

    tearDown(() async {
      l.dispose();
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('apaga el servicio nativo y borra lo capturado', () async {
      final AppSettings settings = AppSettings()..noticesEnabled = true;
      final FakeNoticeBridge bridge = FakeNoticeBridge();
      final NoticeService svc = NoticeService(bridge: bridge, ledger: l, settings: settings);
      await svc.start();
      expect(bridge.capturing, isTrue);
      settings.noticesEnabled = false;
      bridge.pending.add(RawNotice(package: nequi, title: 'Nequi', text: r'Pagaste $3.000 en Bus.', time: d(2026, 10, 16, 9)));
      await svc.disable();
      expect(bridge.capturing, isFalse);
      expect(bridge.pending, isEmpty);
      // Al abrir la app con la lectura apagada, el servicio nativo queda apagado.
      final FakeNoticeBridge again = FakeNoticeBridge();
      again.pending.add(RawNotice(package: nequi, title: 'Nequi', text: r'Pagaste $3.000 en Bus.', time: d(2026, 10, 16, 9)));
      await NoticeService(bridge: again, ledger: l, settings: settings).start();
      expect(again.capturing, isFalse);
      expect(again.pending, isEmpty);
      expect(l.inbox, isEmpty);
    });

    test('el servicio de Android no captura nada si la lectura está apagada (M12: ni resúmenes de grupo)', () {
      for (final String path in <String>['native/android/BankNoticeListener.kt', 'android/app/src/main/kotlin/co/appsgratis/plata/BankNoticeListener.kt']) {
        final String src = File(path).readAsStringSync();
        final String posted = src.substring(src.indexOf('override fun onNotificationPosted'));
        final int enabledCheck = posted.indexOf('if (!isEnabled(this)) return');
        final int firstSave = posted.indexOf('save(record)');
        expect(enabledCheck, greaterThan(0), reason: path);
        expect(firstSave, greaterThan(enabledCheck), reason: path);
        expect(posted, contains('FLAG_GROUP_SUMMARY'));
        expect(posted, contains('EXTRA_TEXT_LINES'));
        // Lo pendiente se guarda cifrado con una llave del Keystore.
        expect(src, contains('AndroidKeyStore'));
        expect(src, contains('AES/GCM/NoPadding'));
        // La actividad en vivo se guarda con una referencia débil.
        expect(src, contains('WeakReference'));
      }
      expect(File('native/android/MainActivity.kt').readAsStringSync(), contains('"setEnabled"'));
    });
  });

  test('M3: el historial de avisos muestra primero los más recientes', () async {
    final Directory tmp = await Directory.systemTemp.createTemp('plata_hist');
    final Ledger l = Ledger(EncryptedStore(JsonStore(root: tmp), await CryptoBox.fromKeyStore(MemoryKeyStore())), clock: () => d(2026, 10, 16));
    await l.load();
    for (int i = 0; i < 40; i++) {
      final InboxItem it = await l.addInbox(InboxItem(id: 'i$i', bank: 'nequi', kind: TxKind.expense, amountMinor: 100 + i, receivedAt: d(2026, 10, 1).add(Duration(hours: i)), rawText: 'aviso $i'));
      l.dismissInbox(it);
    }
    final List<InboxItem> h = l.noticeHistory();
    expect(h.length, 30);
    expect(h.first.id, 'i39');
    expect(h.last.id, 'i10');
    l.dispose();
    await tmp.delete(recursive: true);
  });

  test('M4: un CSV no deja fórmulas en el texto que viene de los avisos', () async {
    final Directory tmp = await Directory.systemTemp.createTemp('plata_csv');
    final Ledger l = Ledger(EncryptedStore(JsonStore(root: tmp), await CryptoBox.fromKeyStore(MemoryKeyStore())), clock: () => d(2026, 10, 16));
    await l.load();
    await l.addTx(Tx(id: '1', kind: TxKind.expense, amountMinor: 100, accountId: 'a_cash', date: d(2026, 10, 10), description: '=HYPERLINK("http://x.co","Clic")', payee: '+57 300', notes: '@SUM(A1)'));
    final List<String> lines = const LineSplitter().convert(Exports.csv(l, l.txs));
    final String row = lines[1];
    expect(row, contains(r'''"'=HYPERLINK(""http://x.co"",""Clic"")"'''));
    expect(row, contains("'+57 300"));
    expect(row, contains("'@SUM(A1)"));
    // El monto negativo sigue siendo un número.
    expect(row, contains(',-1.00,'));
    l.dispose();
    await tmp.delete(recursive: true);
  });
}
