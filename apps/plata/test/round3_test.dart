// Tercera ronda de la auditoría: el pago mínimo del extracto (G1), la
// historia de topes al cambiar la moneda base (G2) y los menores M2, M3, M4,
// M5, M6 y M8.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:plata/core/backup_picker.dart';
import 'package:plata/core/camera_draft.dart';
import 'package:plata/core/crypto_store.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/core/notifications.dart';
import 'package:plata/core/reminders.dart';
import 'package:plata/core/settings.dart';
import 'package:plata/core/storage.dart';
import 'package:plata/model/models.dart';
import 'package:plata/ui/widgets/icons.dart';

DateTime d(int y, int m, int day, [int h = 12]) => DateTime(y, m, day, h);

void main() {
  late Directory tmp;
  late Ledger l;
  DateTime today = d(2026, 10, 18);

  setUp(() async {
    today = d(2026, 10, 18);
    tmp = await Directory.systemTemp.createTemp('plata_r3');
    l = Ledger(EncryptedStore(JsonStore(root: tmp), await CryptoBox.fromKeyStore(MemoryKeyStore())), clock: () => today);
    await l.load();
    await l.addAccount(Account(id: 'bank', name: 'Ahorros', type: AccountType.bank, initialMinor: 2000000000));
  });

  tearDown(() async {
    l.dispose();
    await tmp.delete(recursive: true);
  });

  Tx pay(String id, int minor, DateTime date) => Tx(id: id, kind: TxKind.transfer, amountMinor: minor, accountId: 'bank', toAccountId: 'tc', date: date);

  /// La tarjeta del caso del Árbitro: deuda de $ 4.000.000, creada el 18 de
  /// octubre (corte 15, pago 5) con el pago mínimo del extracto, $ 450.000.
  Future<Account> cardWithMinimum() async {
    final Account tc = Account(id: 'tc', name: 'Visa', type: AccountType.credit, initialMinor: -400000000, cutDay: 15, payDay: 5)..statementDueMinor = 45000000;
    tc.statementCut = l.referenceStatementCut(tc);
    return l.addAccount(tc);
  }

  group('G1: el pago mínimo del último extracto', () {
    test('pagar el mínimo deja la tarjeta al día: al día siguiente del límite no está vencida', () async {
      final Account tc = await cardWithMinimum();
      expect(tc.statementCut, DateTime(2026, 10, 15));
      final CardStatement first = l.nextPayment(tc);
      expect(first.cycle.payDate, DateTime(2026, 11, 5));
      expect(first.dueMinor, 45000000);
      expect(first.legacyMinor, 355000000);
      await l.addTx(pay('minimo', 45000000, d(2026, 11, 3)));
      final CardDue nov6 = l.cardDue(tc, now: DateTime(2026, 11, 6));
      expect(nov6.overdue, isFalse);
      expect(nov6.overdueMinor, 0);
      expect(nov6.next.dueMinor, 0);
      // La deuda total baja con el pago y la de antes de Plata sigue aparte.
      expect(l.balanceMinor('tc', before: DateTime(2026, 11, 7)), -355000000);
      expect(l.legacyDebtMinor(tc, now: DateTime(2026, 11, 6)), 355000000);
      // Y la notificación de vencido no sale.
      final NoopNotifier n = NoopNotifier();
      await Reminders.sync(ledger: l, settings: AppSettings()..billReminders = true, notifier: n, now: DateTime(2026, 11, 6, 8));
      expect(n.shown, isEmpty);
    });

    test('pagar menos del mínimo sí queda vencido, por lo que falta', () async {
      final Account tc = await cardWithMinimum();
      await l.addTx(pay('parcial', 40000000, d(2026, 11, 3)));
      final CardDue nov6 = l.cardDue(tc, now: DateTime(2026, 11, 6));
      expect(nov6.overdue, isTrue);
      expect(nov6.overdueMinor, 5000000);
      expect(nov6.overdueSince, DateTime(2026, 11, 5));
    });

    test('el editor pide el mínimo, no el pago total, y lo explica', () {
      final String src = File('lib/ui/more/accounts_screen.dart').readAsStringSync();
      expect(src, contains("'Pago mínimo del último extracto (opcional)'"));
      expect(src, contains('no el «pago total», que es toda la deuda'));
      expect(src, isNot(contains('Pago total del último extracto')));
      expect(src, isNot(contains('full payment')));
    });
  });

  test('G2: cambiar la moneda base convierte la historia de topes, y el arrastre sigue cuadrando', () async {
    l.rates.rates['USD'] = 4000;
    final Budget b = await l.addBudget(Budget(id: 'b', name: 'Ocio', amountMinor: 50000000, startDate: DateTime(2026, 1, 1), rollover: true, categoryIds: <String>['c_entertainment']));
    b.changeAmount(60000000, from: DateTime(2026, 7, 1));
    await l.addTx(Tx(id: 'cine', kind: TxKind.expense, amountMinor: 10000000, accountId: 'a_cash', categoryId: 'c_entertainment', date: d(2026, 2, 10)));
    // En pesos: seis meses de 500.000 y tres de 600.000, menos 100.000 gastados.
    expect(l.progress(b).carryMinor, 6 * 50000000 + 3 * 60000000 - 10000000);
    expect(l.progress(b, now: DateTime(2026, 5, 10)).limitMinor, 50000000 + 4 * 50000000 - 10000000);
    l.changeBaseCurrency('USD');
    // En dólares (centavos): 4.700.000 pesos son US$ 1.175.
    expect(b.amountMinor, 15000);
    expect(b.amountHistory.single.amountMinor, 12500);
    final BudgetProgress now = l.progress(b);
    expect(now.carryMinor, 117500);
    expect(now.limitMinor, 15000 + 117500);
    // Un mes anterior al cambio de tope, con su tope de entonces en dólares.
    final BudgetProgress may = l.progress(b, now: DateTime(2026, 5, 10));
    expect(may.limitMinor, 12500 + 4 * 12500 - 2500);
  });

  test('M2: un programado automático no se anota si un aviso ya anotó ese cargo', () async {
    await l.addTx(Tx(id: 'aviso', kind: TxKind.expense, amountMinor: 9000000, accountId: 'bank', date: d(2026, 10, 4), source: 'notice'));
    final Scheduled internet = await l.addScheduled(Scheduled(id: 'net', name: 'Internet', kind: TxKind.expense, amountMinor: 9000000, accountId: 'bank', nextDate: DateTime(2026, 10, 5)));
    final Scheduled gym = await l.addScheduled(Scheduled(id: 'gym', name: 'Gimnasio', kind: TxKind.expense, amountMinor: 12000000, accountId: 'bank', nextDate: DateTime(2026, 10, 5)));
    final List<Tx> created = l.processScheduled();
    expect(created.map((Tx t) => t.amountMinor), <int>[12000000]);
    expect(gym.nextDate.isAfter(DateTime(2026, 10, 5)), isTrue);
    // El de Internet queda vencido, para confirmarlo o saltarlo.
    expect(internet.nextDate, DateTime(2026, 10, 5));
    expect(l.noticeDuplicateFor(internet)!.id, 'aviso');
    expect(l.txs.where((Tx t) => t.amountMinor == 9000000), hasLength(1));
    // Un movimiento anotado a mano no cuenta como aviso.
    await l.addTx(Tx(id: 'mano', kind: TxKind.expense, amountMinor: 12000000, accountId: 'bank', date: gym.nextDate));
    expect(l.noticeDuplicateFor(gym), isNull);
  });

  test('M3: el aviso de pago vencido solo se da por enviado si se mostró', () async {
    await l.addAccount(Account(id: 'tc', name: 'Visa', type: AccountType.credit, cutDay: 15, payDay: 5));
    await l.addTx(Tx(id: 'c', kind: TxKind.expense, amountMinor: 100000000, accountId: 'tc', date: d(2026, 9, 10)));
    // El aviso de mora necesita un mínimo conocido (regla de la ronda 4).
    l.setStatementMinimum(l.account('tc')!, DateTime(2026, 9, 15), 8000000);
    final AppSettings settings = AppSettings()..billReminders = true;
    final NoopNotifier n = NoopNotifier(granted: false);
    await Reminders.sync(ledger: l, settings: settings, notifier: n, now: DateTime(2026, 10, 6, 8));
    expect(n.shown, isEmpty);
    expect(settings.overdueNotified, isEmpty);
    // Con el permiso dado, sale en la siguiente sincronización.
    n.granted = true;
    await Reminders.sync(ledger: l, settings: settings, notifier: n, now: DateTime(2026, 10, 6, 9));
    expect(n.shown, <String>['Pago vencido: Visa']);
    expect(settings.overdueNotified, hasLength(1));
    // En iOS el AppDelegate es el delegado del centro de notificaciones, para
    // que se vean con la app abierta.
    for (final String path in <String>['native/ios/AppDelegate.swift', 'ios/Runner/AppDelegate.swift']) {
      final String swift = File(path).readAsStringSync();
      expect(swift, contains('import UserNotifications'), reason: path);
      expect(swift, contains('UNUserNotificationCenter.current().delegate = self'), reason: path);
    }
  });

  group('M4: copias del selector de archivos', () {
    test('se borran al leerlas y, al abrir o borrar todo, las carpetas que quedaron', () async {
      final Directory cache = await Directory('${tmp.path}/cache').create();
      final File copy = File('${cache.path}/restore/elegido.bin')..createSync(recursive: true);
      copy.writeAsStringSync('{"accounts": [], "txs": []}');
      expect(await PickedBackup(name: 'plata.json', path: copy.path, isCopy: true).readAndDiscard(), isNotEmpty);
      expect(copy.existsSync(), isFalse);
      // El archivo original del usuario (no es copia) nunca se borra.
      final File original = File('${tmp.path}/original.plata')..writeAsBytesSync(<int>[1, 2, 3]);
      expect(await PickedBackup(name: 'original.plata', path: original.path).readAndDiscard(), <int>[1, 2, 3]);
      expect(original.existsSync(), isTrue);
      // Lo que dejaba file_selector (una carpeta con nombre de UUID) y la de
      // restaurar se borran; lo demás de la caché, no.
      File('${cache.path}/3f2504e0-4f89-31d3-9a0c-0305e82c3301/plata.json').createSync(recursive: true);
      File('${cache.path}/restore/elegido.bin').createSync(recursive: true);
      File('${cache.path}/otra/archivo.txt').createSync(recursive: true);
      await clearPickedCopies(temp: cache);
      expect(cache.listSync().map((FileSystemEntity e) => e.uri.pathSegments.where((String s) => s.isNotEmpty).last), <String>['otra']);
    });
  });

  group('M5: datos de las versiones de prueba en iOS', () {
    test('se mueven aunque la carpeta nueva ya exista vacía (la crea el AppDelegate)', () async {
      final Directory old = Directory('${tmp.path}/Documents/plata');
      File('${old.path}/ledger.json').createSync(recursive: true);
      File('${old.path}/attachments/a.jpg.enc').createSync(recursive: true);
      final Directory dir = await Directory('${tmp.path}/Support/plata').create(recursive: true);
      expect(await JsonStore.migrateLegacy(old, dir), isTrue);
      expect(File('${dir.path}/ledger.json').existsSync(), isTrue);
      expect(File('${dir.path}/attachments/a.jpg.enc').existsSync(), isTrue);
      expect(old.existsSync(), isFalse);
      // Si la nueva ya tiene libro, no se toca nada.
      File('${old.path}/ledger.json').createSync(recursive: true);
      expect(await JsonStore.migrateLegacy(old, dir), isFalse);
      expect(File('${old.path}/ledger.json').existsSync(), isTrue);
    });
  });

  test('M6: cada ícono y cada color tienen nombre en español y en inglés', () {
    expect(AppIcons.names.keys.toSet(), AppIcons.all.keys.toSet());
    expect(AppIcons.colorNames, hasLength(AppIcons.palette.length));
    expect(AppIcons.nameOf('cart', spanish: true), 'Mercado');
    expect(AppIcons.nameOf('cart', spanish: false), 'Groceries');
    for (final List<String> n in <List<String>>[...AppIcons.names.values, ...AppIcons.colorNames]) {
      expect(n, hasLength(2));
      expect(n.every((String x) => x.isNotEmpty), isTrue);
    }
  });

  test('M8: el borrador de la cámara conserva el aviso que se estaba confirmando', () async {
    final InboxItem notice = await l.addInbox(InboxItem(id: 'aviso', bank: 'bancolombia', kind: TxKind.expense, amountMinor: 6240000, receivedAt: d(2026, 10, 18, 9), merchant: 'EL FOGON'));
    final Tx draft = Tx(id: 'b', kind: TxKind.expense, amountMinor: 6240000, accountId: 'bank', date: d(2026, 10, 18, 9), description: 'EL FOGON');
    await CameraDraft.save(l, draft, inboxId: notice.id);
    final RecoveredDraft? r = await recoverCameraDraft(l, lost: () async => LostDataResponse.empty());
    expect(r!.inbox, same(notice));
    expect(r.draft.description, 'EL FOGON');
  });
}
