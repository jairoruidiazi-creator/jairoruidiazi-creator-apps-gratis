// Segunda ronda de la auditoría: B1, G3, G4, G5 y los menores M1, M4–M7,
// M10–M12, M19 y M22–M24, más las comprobaciones de los archivos de Android
// (tema AppCompat e ícono de las notificaciones).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:plata/core/backup_picker.dart';
import 'package:plata/core/backups.dart';
import 'package:plata/core/bank_rules.dart';
import 'package:plata/core/camera_draft.dart';
import 'package:plata/core/crypto_store.dart';
import 'package:plata/core/defaults.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/core/lock.dart';
import 'package:plata/core/notices.dart';
import 'package:plata/core/notifications.dart';
import 'package:plata/core/periods.dart';
import 'package:plata/core/reminders.dart';
import 'package:plata/core/settings.dart';
import 'package:plata/core/storage.dart';
import 'package:plata/model/models.dart';
import 'package:plata/ui/more/security_screen.dart';

DateTime d(int y, int m, int day, [int h = 12]) => DateTime(y, m, day, h);

const String bancolombia = 'co.com.bancolombia.personas.superapp';

void main() {
  late Directory tmp;
  late Ledger l;
  DateTime today = d(2026, 10, 16);

  setUp(() async {
    today = d(2026, 10, 16);
    tmp = await Directory.systemTemp.createTemp('plata_r2');
    l = Ledger(EncryptedStore(JsonStore(root: tmp), await CryptoBox.fromKeyStore(MemoryKeyStore())), clock: () => today);
    await l.load();
  });

  tearDown(() async {
    l.dispose();
    await tmp.delete(recursive: true);
  });

  Tx pay(String id, int minor, DateTime date, {String to = 'tc'}) => Tx(id: id, kind: TxKind.transfer, amountMinor: minor, accountId: 'bank', toAccountId: to, date: date);

  group('B1: restaurar reconoce la copia por su contenido, no por su nombre', () {
    test('el selector de Android no filtra por extensión', () {
      // Sin extensiones ni tipos: file_selector pide "*/*" en Android (un
      // .plata en Drive o Descargas llega como application/octet-stream) y
      // public.data en iOS.
      expect(backupPickerGroup.allowsAny, isTrue);
      expect(backupPickerGroup.extensions, anyOf(isNull, isEmpty));
      expect(backupPickerGroup.mimeTypes, anyOf(isNull, isEmpty));
    });

    test('copia cifrada, JSON de Plata (con o sin BOM) y archivos que no son de Plata', () async {
      await l.addTx(Tx(id: 't', kind: TxKind.expense, amountMinor: 100, accountId: 'a_cash', date: d(2026, 10, 10)));
      final BackupManager bm = BackupManager(store: JsonStore(root: tmp), ledger: l, settings: AppSettings());
      final Uint8List enc = await bm.exportEncrypted('una clave larga');
      expect(BackupManager.detect(enc), BackupKind.encrypted);
      expect(BackupManager.detect(bm.exportPlain()), BackupKind.plain);
      final List<int> withBom = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode('\n  ${jsonEncode(l.toJson())}')];
      expect(BackupManager.detect(withBom), BackupKind.plain);
      expect((await BackupManager.decode(withBom))['txs'], hasLength(1));
      for (final List<int> other in <List<int>>[
        utf8.encode('{"hola": 1}'),
        utf8.encode('fecha,monto\n2026-10-01,5000\n'),
        <int>[0x25, 0x50, 0x44, 0x46, 0x2D, ...List<int>.filled(64, 0)], // un PDF
        <int>[0xFF, 0xD8, 0xFF, ...List<int>.filled(64, 7)], // una foto
        <int>[],
        enc.sublist(0, 12), // copia cortada: la cabecera sola
      ]) {
        expect(BackupManager.detect(other), BackupKind.foreign);
      }
    });
  });

  group('G3 y G4: tarjetas', () {
    setUp(() async {
      await l.addAccount(Account(id: 'bank', name: 'Ahorros', type: AccountType.bank, initialMinor: 2000000000));
    });

    test('G3: un día después de la fecha límite lo que falta se informa y, con el mínimo anotado, está vencido hasta pagarlo', () async {
      final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
      await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 100000000, accountId: 'tc', date: d(2026, 9, 10)));
      final CardDue onDay = l.cardDue(tc, now: DateTime(2026, 10, 5));
      expect(onDay.overdue, isFalse);
      expect(onDay.unconfirmed, isFalse);
      expect(onDay.next.cycle.payDate, DateTime(2026, 10, 5));
      expect(onDay.next.dueMinor, 100000000);
      // Solo con el estimado de Plata no se habla de mora (regla de la ronda 4).
      final CardDue estimate = l.cardDue(tc, now: DateTime(2026, 10, 6));
      expect(estimate.overdue, isFalse);
      expect(estimate.unconfirmed, isTrue);
      expect(estimate.unconfirmedMinor, 100000000);
      expect(estimate.statementCut, DateTime(2026, 9, 15));
      // Con el mínimo que pidió el banco (aquí, todo) sí está vencido.
      l.setStatementMinimum(tc, DateTime(2026, 9, 15), 100000000);
      final CardDue after = l.cardDue(tc, now: DateTime(2026, 10, 6));
      expect(after.overdue, isTrue);
      expect(after.overdueMinor, 100000000);
      expect(after.overdueSince, DateTime(2026, 10, 5));
      // Después del corte siguiente sigue vencido (antes desaparecía).
      final CardDue later = l.cardDue(tc, now: DateTime(2026, 10, 20));
      expect(later.overdueSince, DateTime(2026, 10, 5));
      expect(later.overdueMinor, 100000000);
      expect(later.next.cycle.payDate, DateTime(2026, 11, 5));
      // Un abono parcial lo baja; el resto lo quita.
      await l.addTx(pay('p1', 40000000, d(2026, 10, 21)));
      expect(l.cardDue(tc, now: DateTime(2026, 10, 21)).overdueMinor, 60000000);
      await l.addTx(pay('p2', 60000000, d(2026, 10, 22)));
      expect(l.cardDue(tc, now: DateTime(2026, 10, 22)).overdue, isFalse);
    });

    test('G3: el aviso de lo vencido sale de inmediato y una sola vez', () async {
      today = d(2026, 10, 6);
      await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
      await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 100000000, accountId: 'tc', date: d(2026, 9, 10)));
      final AppSettings settings = AppSettings()..billReminders = true;
      final NoopNotifier n = NoopNotifier();
      // Sin un mínimo conocido no hay aviso de mora.
      await Reminders.sync(ledger: l, settings: settings, notifier: n, now: DateTime(2026, 10, 6, 7));
      expect(n.shown, isEmpty);
      l.setStatementMinimum(l.account('tc')!, DateTime(2026, 9, 15), 8000000);
      await Reminders.sync(ledger: l, settings: settings, notifier: n, now: DateTime(2026, 10, 6, 8));
      expect(n.shown, <String>['Revisa el pago de Visa']);
      expect(n.log.last, contains('vencía el 05 oct'));
      await Reminders.sync(ledger: l, settings: settings, notifier: n, now: DateTime(2026, 10, 6, 9));
      expect(n.shown, hasLength(1));
    });

    test('G4: con el pago del último extracto, eso vence y el resto es deuda de antes de Plata', () async {
      final Account tc = Account(id: 'tc', name: 'Visa', type: AccountType.credit, initialMinor: -400000000, creditLimitMinor: 600000000, cutDay: 15, payDay: 5)..statementDueMinor = 45000000;
      // El editor fija el extracto al anotarlo: hoy (16 oct) es el del 15 oct.
      tc.statementCut = l.referenceStatementCut(tc);
      expect(tc.statementCut, DateTime(2026, 10, 15));
      await l.addAccount(tc);
      // La deuda total sigue contando completa en el patrimonio y el cupo.
      expect(l.debtMinor(), 400000000);
      expect(l.availableCreditMinor(tc), 200000000);
      final CardStatement next = l.nextPayment(tc);
      expect(next.cycle.payDate, DateTime(2026, 11, 5));
      expect(next.dueMinor, 45000000);
      expect(next.fromBankStatement, isTrue);
      expect(next.legacyMinor, 355000000);
      // Pagar lo del extracto deja la tarjeta al día: nada vencido ni
      // "saldo anterior sin pagar" el mes siguiente.
      await l.addTx(pay('p1', 45000000, d(2026, 11, 1)));
      expect(l.cardDue(tc, now: DateTime(2026, 11, 6)).overdue, isFalse);
      final CardStatement nov = l.statement(tc, date: DateTime(2026, 11, 15));
      expect(nov.previousMinor, 0);
      expect(nov.dueMinor, 0);
      expect(nov.legacyMinor, 355000000);
      // Abonar de más baja la deuda vieja en vez de quedar como saldo a favor,
      // y las líneas siguen sumando el total.
      await l.addTx(pay('p2', 100000000, d(2026, 11, 20)));
      final CardStatement nov2 = l.statement(tc, date: DateTime(2026, 11, 15));
      expect(nov2.toLegacyMinor, 100000000);
      expect(nov2.creditMinor, 0);
      expect(nov2.legacyMinor, 255000000);
      expect(nov2.previousMinor + nov2.chargesMinor - nov2.paymentsMinor + nov2.toLegacyMinor, nov2.balanceMinor);
      expect(l.balanceMinor('tc', before: DateTime(2026, 12, 1)), -255000000);
      expect(l.legacyDebtMinor(tc, now: DateTime(2026, 12, 1)), 255000000);
    });

    test('G4: sin el dato del extracto, la deuda inicial no se suma a ningún pago', () async {
      final Account tc = await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, initialMinor: -400000000, cutDay: 15, payDay: 5));
      await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 5000000, accountId: 'tc', date: d(2026, 10, 10)));
      final CardStatement st = l.statement(tc, date: DateTime(2026, 10, 15));
      expect(st.dueMinor, 5000000); // solo lo anotado en Plata
      expect(st.legacyMinor, 400000000);
      expect(l.debtMinor(), 405000000);
      // El extracto de referencia es el anterior al primer movimiento.
      expect(l.referenceStatementCut(tc), DateTime(2026, 9, 15));
      final CardDue nov6 = l.cardDue(tc, now: DateTime(2026, 11, 6));
      expect(nov6.overdue, isFalse);
      expect(nov6.unconfirmedMinor, 5000000);
    });

    test('M1: las cuotas en pesos son pesos enteros y suman el total', () async {
      await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
      final Tx t = await l.addTx(Tx(id: 'nevera', kind: TxKind.expense, amountMinor: 239990000, accountId: 'tc', date: d(2026, 8, 22), installments: 12));
      final Account tc = l.account('tc')!;
      int sum = 0;
      for (int k = 0; k < 12; k++) {
        final int v = l.statement(tc, date: CardCycle.cutAfter(tc, DateTime(2026, 9, 15), k)).installmentsMinor;
        expect(v % 100, 0, reason: 'cuota ${k + 1}: $v');
        sum += v;
      }
      expect(sum, t.amountMinor);
      expect(Ledger.installmentAmount(239990000, 12, 1, unit: 100), 19999100);
      expect(Ledger.installmentAmount(239990000, 12, 12, unit: 100), 19999900);
      // En dólares se muestran centavos: la unidad es el centavo.
      expect(Ledger.displayUnit('USD'), 1);
      expect(Ledger.displayUnit('COP'), 100);
    });
  });

  group('M4 y M5: avisos', () {
    BankSuggestion? parse(String package, String text) => BankRules.parse(packageName: package, title: '', text: text);

    test('M4: publicidad, anuncios a futuro, reversos y comercios con "otp" en el nombre', () {
      const String nu = 'com.nu.production';
      const String davivienda = 'com.davivienda.daviviendaapp';
      expect(parse(bancolombia, r'Tienes un cupo pre-aprobado de $5.000.000 para tus compras. Actívalo en la App.'), isNull);
      expect(parse(bancolombia, r'Tu crédito pre aprobado por $8.000.000 te espera: haz tu compra de cartera hoy.'), isNull);
      expect(parse(davivienda, r'Mañana debitaremos $55.000 de tu cuenta por el pago automático de CLARO.'), isNull);
      expect(parse(bancolombia, r'Recuerda: el pago mínimo de tu tarjeta de crédito *4821 es $350.000 y vence el 05/11.'), isNull);
      for (final BankSuggestion? s in <BankSuggestion?>[
        parse(bancolombia, r'Bancolombia le informa: reverso de compra por $45.000 en EXITO.'),
        parse(nu, r'Te devolvimos $45.000 de tu compra en EXITO.'),
      ]) {
        expect(s, isNotNull);
        expect(s!.kind, TxKind.income);
        expect(s.flow, NoticeFlow.refund);
        expect(s.amountMinor, 4500000);
      }
      final BankSuggestion? hotpot = parse(bancolombia, r'Compraste $62.400 en HOTPOT ASIAN con tu tarjeta *4821.');
      expect(hotpot, isNotNull);
      expect(hotpot!.kind, TxKind.expense);
      expect(hotpot.amountMinor, 6240000);
      // Lo que sí debe seguir: compras aprobadas y códigos de seguridad fuera.
      expect(parse(bancolombia, r'Compra aprobada por $35.000 en UBER con tu tarjeta *1111.')!.kind, TxKind.expense);
      expect(parse(bancolombia, 'Tu clave dinámica es 123456. No la compartas.'), isNull);
      expect(parse(bancolombia, 'Tu código OTP es 123456.'), isNull);
    });

    test('M5: un aviso igual a un movimiento ya anotado queda como posible duplicado y no se anota solo', () async {
      await l.addAccount(Account(id: 'tc', name: 'Débito Visa', type: AccountType.bank, bank: 'bancolombia', last4: '4821'));
      final Tx manual = await l.addTx(Tx(id: 'manual', kind: TxKind.expense, amountMinor: 6240000, accountId: 'tc', date: d(2026, 10, 15, 20)));
      final AppSettings settings = AppSettings()
        ..noticesEnabled = true
        ..noticesAutoPost = true;
      final NoticeService svc = NoticeService(bridge: FakeNoticeBridge(), ledger: l, settings: settings);
      await svc.handle(RawNotice(package: bancolombia, title: 'Bancolombia', text: r'Compraste $62.400 en EL FOGON con tu T.Cred *4821.', time: d(2026, 10, 16, 9)));
      expect(l.txs, hasLength(1));
      expect(l.pendingInbox.single.duplicateOf, manual.id);
      // Un cargo distinto sí se anota solo.
      await svc.handle(RawNotice(package: bancolombia, title: 'Bancolombia', text: r'Compraste $18.000 en TAXI con tu T.Cred *4821.', time: d(2026, 10, 16, 10)));
      expect(l.txs, hasLength(2));
      // Un reverso nunca se anota solo, aunque la cuenta sea segura.
      await svc.handle(RawNotice(package: bancolombia, title: 'Bancolombia', text: r'Bancolombia le informa: reverso de compra por $18.000 en TAXI con tu T.Cred *4821.', time: d(2026, 10, 16, 11)));
      expect(l.txs, hasLength(2));
      expect(l.pendingInbox.where((InboxItem i) => i.flow == NoticeFlow.refund), hasLength(1));
      // El duplicado guardado sobrevive a guardar y abrir.
      await l.flush();
      final Ledger again = Ledger(l.store, clock: () => today);
      await again.load();
      expect(again.inbox.firstWhere((InboxItem i) => i.duplicateOf != null).duplicateOf, manual.id);
      again.dispose();
    });
  });

  group('M7: recordatorios', () {
    test('cambiar el libro no borra los avisos ya mostrados y con clave no llevan montos', () async {
      final AppSettings settings = AppSettings()..billReminders = true;
      await l.addScheduled(Scheduled(id: 's', name: 'Arriendo', kind: TxKind.expense, amountMinor: 150000000, accountId: 'a_cash', nextDate: DateTime(2026, 10, 20)));
      final NoopNotifier n = NoopNotifier();
      await Reminders.sync(ledger: l, settings: settings, notifier: n, now: d(2026, 10, 16, 8));
      // Se agendan varias ocurrencias (M2 de la ronda 4): la primera es la del 20 oct.
      final int id = Reminders.idFor('s:s:2026-10-20');
      expect(n.pending[id], contains(r'$ 1.500.000'));
      final int first = n.pending.length;
      expect(first, Reminders.occurrencesAhead);
      // Otro programado nuevo: el primero no se cancela ni cambia de id.
      await l.addScheduled(Scheduled(id: 's2', name: 'Internet', kind: TxKind.expense, amountMinor: 9000000, accountId: 'a_cash', nextDate: DateTime(2026, 10, 22)));
      n.log.clear();
      await Reminders.sync(ledger: l, settings: settings, notifier: n, now: d(2026, 10, 16, 9));
      expect(n.log.where((String x) => x.startsWith('cancel')), isEmpty);
      expect(n.pending.keys, contains(id));
      expect(n.pending, hasLength(2 * Reminders.occurrencesAhead));
      // Privado (clave o saldos ocultos): sin montos y oculto en la pantalla de bloqueo.
      await Reminders.sync(ledger: l, settings: settings, notifier: n, now: d(2026, 10, 16, 9), private: true);
      expect(n.pending.values.any((String x) => x.contains(r'$')), isFalse);
      expect(n.privateIds, containsAll(n.pending.keys));
      // Si el programado ya no toca, solo se cancela el suyo.
      l.scheduled.removeWhere((Scheduled s) => s.id == 's2');
      n.log.clear();
      await Reminders.sync(ledger: l, settings: settings, notifier: n, now: d(2026, 10, 16, 10));
      expect(n.log.where((String x) => x.startsWith('cancel')), hasLength(Reminders.occurrencesAhead));
      expect(n.pending.keys, contains(id));
      expect(n.pending, hasLength(first));
    });

    test('G2: hay recordatorios que pedir cuando hay programados con aviso o tarjetas con día de pago', () async {
      final AppSettings settings = AppSettings()..billReminders = true;
      expect(Reminders.wanted(l, settings), isFalse);
      await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
      expect(Reminders.wanted(l, settings), isTrue);
      settings.billReminders = false;
      expect(Reminders.wanted(l, settings), isFalse);
      settings.dailyReminder = true;
      expect(Reminders.wanted(l, settings), isTrue);
    });

    test('M6: el ícono de las notificaciones es un vector monocromo propio, también en native/', () {
      for (final String path in <String>['native/android/ic_stat_plata.xml', 'android/app/src/main/res/drawable/ic_stat_plata.xml']) {
        final String xml = File(path).readAsStringSync();
        expect(xml, contains('<vector'));
        expect(RegExp(r'fillColor="#([0-9A-F]{8})"').allMatches(xml).map((RegExpMatch m) => m.group(1)).toSet(), <String>{'FFFFFFFF'});
      }
      expect(File('android/app/src/main/res/raw/keep.xml').readAsStringSync(), contains('@drawable/ic_stat_plata'));
      final String code = File('lib/core/notifications.dart').readAsStringSync();
      expect(code, contains("_icon = 'ic_stat_plata'"));
      expect(code, isNot(contains('@mipmap/ic_launcher')));
    });
  });

  group('G5: huella en Android 7 a 8.1', () {
    test('los temas de la actividad son AppCompat, en claro y en oscuro, y la app trae AppCompat', () {
      for (final String path in <String>[
        'native/android/styles.xml',
        'native/android/styles-night.xml',
        'android/app/src/main/res/values/styles.xml',
        'android/app/src/main/res/values-night/styles.xml',
      ]) {
        final String xml = File(path).readAsStringSync();
        expect(RegExp(r'<style name="(LaunchTheme|NormalTheme)" parent="Theme\.AppCompat\.DayNight\.NoActionBar"').allMatches(xml), hasLength(2), reason: path);
        expect(xml, isNot(contains('@android:style/Theme.')), reason: path);
      }
      expect(File('native/android/styles.xml').readAsStringSync(), File('android/app/src/main/res/values/styles.xml').readAsStringSync());
      expect(File('native/android/styles-night.xml').readAsStringSync(), File('android/app/src/main/res/values-night/styles.xml').readAsStringSync());
      expect(File('android/app/build.gradle.kts').readAsStringSync(), contains('implementation("androidx.appcompat:appcompat:'));
      expect(File('native/android/MainActivity.kt').readAsStringSync(), contains('FlutterFragmentActivity'));
    });

    test('si la app se cerró con el diálogo de huella abierto, la siguiente vez no se abre solo', () async {
      final MemoryKeyStore keys = MemoryKeyStore();
      final AppLock first = AppLock(keys, biometricPrompt: (String reason) => Completer<bool>().future);
      await first.load();
      await first.setPasscode('2468');
      await first.setBiometric(true);
      expect(await first.shouldPromptBiometricOnOpen(), isTrue);
      // El diálogo nunca vuelve: la app "se cierra" con él abierto.
      unawaited(first.authenticateBiometric('Desbloquea Plata'));
      await Future<void>.delayed(Duration.zero);
      final AppLock reopened = AppLock(keys, biometricPrompt: (String reason) async => true);
      await reopened.load();
      expect(await reopened.shouldPromptBiometricOnOpen(), isFalse);
      // Sigue a un toque, y si esta vez vuelve, la siguiente se pide sola.
      expect(await reopened.authenticateBiometric('Desbloquea Plata'), isTrue);
      expect(await reopened.shouldPromptBiometricOnOpen(), isTrue);
    });
  });

  group('M10 y M11: presupuestos e informes', () {
    test('M10: subir el tope no cambia el arrastre de los meses anteriores', () async {
      final Budget b = await l.addBudget(Budget(id: 'b', name: 'Ocio', amountMinor: 16000000, startDate: DateTime(2026, 1, 1), rollover: true, categoryIds: <String>['c_entertainment']));
      final BudgetProgress before = l.progress(b);
      expect(before.carryMinor, 9 * 16000000);
      b.changeAmount(26000000, from: before.period.start);
      final BudgetProgress after = l.progress(b);
      expect(after.carryMinor, 9 * 16000000);
      expect(after.limitMinor, 26000000 + 9 * 16000000);
      // Los meses pasados conservan su tope, también al guardar y abrir.
      expect(l.progress(b, now: DateTime(2026, 5, 10)).limitMinor, 16000000 + 4 * 16000000);
      await l.flush();
      final Ledger again = Ledger(l.store, clock: () => today);
      await again.load();
      expect(again.progress(again.budgets.single).carryMinor, 9 * 16000000);
      again.dispose();
    });

    test('M10: el total de presupuestos solo se suma si no cuenta dos veces lo mismo', () async {
      final Budget all = await l.addBudget(Budget(id: 'all', name: 'Todo', amountMinor: 300000000, startDate: DateTime(2026, 1, 1)));
      final Budget food = await l.addBudget(Budget(id: 'food', name: 'Mercado', amountMinor: 90000000, startDate: DateTime(2026, 1, 1), categoryIds: <String>['c_food']));
      final Budget fun = await l.addBudget(Budget(id: 'fun', name: 'Ocio', amountMinor: 20000000, startDate: DateTime(2026, 1, 1), categoryIds: <String>['c_entertainment']));
      expect(l.canSumBudgets(<BudgetProgress>[l.progress(all), l.progress(food)]), isFalse);
      expect(l.canSumBudgets(<BudgetProgress>[l.progress(food), l.progress(fun)]), isTrue);
      fun.period = BudgetPeriod.quincena;
      expect(l.canSumBudgets(<BudgetProgress>[l.progress(food), l.progress(fun)]), isFalse);
    });

    test('M11: la cabecera de Movimientos resta los reembolsos del gasto, como Informes', () async {
      await l.addTx(Tx(id: 'g', kind: TxKind.expense, amountMinor: 10000000, accountId: 'a_cash', categoryId: 'c_food', date: d(2026, 10, 10)));
      await l.addTx(Tx(id: 'r', kind: TxKind.income, amountMinor: 2000000, accountId: 'a_cash', categoryId: 'c_food', date: d(2026, 10, 11)));
      final Period oct = l.periodSpec.containing(today);
      final PeriodTotals reports = l.totals(oct);
      final PeriodTotals list = l.totalsOf(oct, l.search(const TxFilter()));
      expect(list.expenseMinor, 8000000);
      expect(list.incomeMinor, 0);
      expect(list.expenseMinor, reports.expenseMinor);
      expect(list.incomeMinor, reports.incomeMinor);
      // La tendencia termina en el periodo elegido con las flechas.
      final List<PeriodTotals> trend = l.trend(6, now: DateTime(2026, 7, 1));
      expect(trend.last.period.start, DateTime(2026, 7, 1));
    });

    test('M12: buscar un monto sin separadores lo encuentra', () async {
      await l.addTx(Tx(id: 'x', kind: TxKind.expense, amountMinor: 4500000, accountId: 'a_cash', description: 'Mercado', date: d(2026, 10, 10)));
      await l.addTx(Tx(id: 'y', kind: TxKind.expense, amountMinor: 14500000, accountId: 'a_cash', description: 'Otra', date: d(2026, 10, 11)));
      for (final String q in <String>['45000', r'$45000', '45 000']) {
        expect(l.search(TxFilter(text: q)).map((Tx t) => t.id), <String>['x'], reason: q);
      }
    });
  });

  test('M19: restaurar una copia no borra de una vez las fotos de los datos reemplazados', () async {
    const String photo = 'attachments/recibo.jpg.enc';
    await l.store.writeBytes(photo, <int>[1, 2, 3]);
    await l.addTx(Tx(id: 'f', kind: TxKind.expense, amountMinor: 100, accountId: 'a_cash', date: d(2026, 10, 10), attachments: <String>[photo]));
    final Map<String, dynamic> before = l.toJson();
    // Se restaura una copia sin ese movimiento: la foto queda sin uso…
    final Map<String, dynamic> other = jsonDecode(jsonEncode(before)) as Map<String, dynamic>;
    (other['txs'] as List<dynamic>).clear();
    await l.replaceWith(other);
    await l.pruneAttachments();
    expect(await l.store.readBytes(photo), <int>[1, 2, 3]);
    // …y deshacer (restaurar la copia previa) la recupera.
    await l.replaceWith(before);
    await l.pruneAttachments();
    expect(l.tx('f')!.attachments, <String>[photo]);
    // Una foto sin uso se borra cuando pasan 30 días.
    await l.replaceWith(other);
    await l.pruneAttachments();
    today = d(2026, 11, 20);
    await l.pruneAttachments();
    expect(await l.store.readBytes(photo), isNull);
  });

  test('M21: si Android cerró la app con la cámara abierta, vuelven la foto y lo escrito', () async {
    final Tx draft = Tx(id: 'borrador', kind: TxKind.expense, amountMinor: 3200000, accountId: 'a_cash', date: d(2026, 10, 16), description: 'Almuerzo');
    await CameraDraft.save(l, draft);
    final File photo = File('${tmp.path}/scaled_foto.jpg')..writeAsBytesSync(<int>[9, 8, 7]);
    final RecoveredDraft? r = await recoverCameraDraft(l, lost: () async => LostDataResponse(file: XFile(photo.path), type: RetrieveType.image));
    expect(r, isNotNull);
    expect(r!.draft.description, 'Almuerzo');
    expect(r.draft.amountMinor, 3200000);
    expect(r.existing, isNull);
    // La foto queda cifrada en la carpeta de la app y el borrador se borra.
    expect(await l.store.readBytes(r.draft.attachments.single), <int>[9, 8, 7]);
    expect(await CameraDraft.read(l), isNull);
    // Sin foto perdida, lo escrito se recupera igual (M8 de la tercera ronda)
    // y el borrador no queda guardado.
    await CameraDraft.save(l, draft, existingId: 'x');
    final RecoveredDraft? noPhoto = await recoverCameraDraft(l, lost: () async => LostDataResponse.empty());
    expect(noPhoto!.draft.description, 'Almuerzo');
    expect(noPhoto.draft.attachments, isEmpty);
    expect(await CameraDraft.read(l), isNull);
    // Sin borrador ni foto no hay nada que recuperar.
    expect(await recoverCameraDraft(l, lost: () async => LostDataResponse.empty()), isNull);
  });

  group('M22: moneda base de un libro nuevo', () {
    test('sale del país del teléfono; sin país, pesos en español y dólares en inglés', () {
      expect(Defaults.currencyForLocales(const <Locale>[Locale('es', 'CO')]), 'COP');
      expect(Defaults.currencyForLocales(const <Locale>[Locale('en', 'US')]), 'USD');
      expect(Defaults.currencyForLocales(const <Locale>[Locale('es', 'MX')]), 'MXN');
      expect(Defaults.currencyForLocales(const <Locale>[Locale('es', 'ES')]), 'EUR');
      expect(Defaults.currencyForLocales(const <Locale>[Locale('es')]), 'COP');
      expect(Defaults.currencyForLocales(const <Locale>[Locale('en')]), 'USD');
    });

    test('el libro nuevo y su efectivo usan esa moneda; uno guardado conserva la suya', () async {
      final Directory dir = await Directory.systemTemp.createTemp('plata_usd');
      final EncryptedStore store = EncryptedStore(JsonStore(root: dir), await CryptoBox.fromKeyStore(MemoryKeyStore()));
      final Ledger usd = Ledger(store, spanish: false, defaultCurrency: 'USD');
      await usd.load();
      expect(usd.baseCurrency, 'USD');
      expect(usd.account('a_cash')!.currency, 'USD');
      await usd.flush();
      usd.dispose();
      final Ledger reopened = Ledger(store, defaultCurrency: 'COP');
      await reopened.load();
      expect(reopened.baseCurrency, 'USD');
      reopened.dispose();
      await dir.delete(recursive: true);
    });
  });

  test('M16: la clave solo acepta de 4 a 8 cifras', () {
    for (final String ok in <String>['1234', '12345678']) {
      expect(validPasscode(ok), isTrue, reason: ok);
    }
    for (final String bad in <String>['-123', '+123', '123', '123456789', '12a4', ' 1234', '١٢٣٤']) {
      expect(validPasscode(bad), isFalse, reason: bad);
    }
  });

  test('M24: un libro grande se cifra fuera del hilo de la interfaz y se lee igual', () async {
    final CryptoBox box = await CryptoBox.fromKeyStore(MemoryKeyStore());
    final List<int> big = List<int>.generate(CryptoBox.isolateThreshold * 4, (int i) => i % 251);
    final Uint8List enc = await box.encrypt(big);
    expect(await box.decrypt(enc), big);
    final List<int> small = utf8.encode('{"a":1}');
    expect(await box.decrypt(await box.encrypt(small)), small);
  });
}

