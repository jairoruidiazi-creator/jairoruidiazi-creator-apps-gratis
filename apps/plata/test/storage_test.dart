// Integridad de los datos: los hallazgos G6–G9, G11, M13 y M17 del informe
// de auditoría (escritura atómica, llave del libro, modo de recuperación,
// restaurar copias y borrar todo).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plata/core/app_scope.dart';
import 'package:plata/core/backups.dart';
import 'package:plata/core/crypto_store.dart';
import 'package:plata/core/key_setup.dart';
import 'package:plata/core/ledger.dart';
import 'package:plata/core/lock.dart';
import 'package:plata/core/notices.dart';
import 'package:plata/core/notifications.dart';
import 'package:plata/core/rates.dart';
import 'package:plata/core/settings.dart';
import 'package:plata/core/storage.dart';
import 'package:plata/core/wipe.dart';
import 'package:plata/model/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime d(int y, int m, int day, [int h = 12]) => DateTime(y, m, day, h);

/// Almacén que falla al escribir mientras [fail] es verdadero.
class FailingStore extends JsonStore {
  FailingStore({super.root});

  bool fail = false;

  @override
  Future<File> writeBytes(String relativePath, List<int> bytes) async {
    if (fail) {
      throw const FileSystemException('Disco lleno');
    }
    return super.writeBytes(relativePath, bytes);
  }
}

/// Llavero que falla las primeras [failures] veces (o siempre, con -1).
class FlakyKeyStore implements KeyStore {
  FlakyKeyStore({this.failures = 0});

  int failures;
  final MemoryKeyStore inner = MemoryKeyStore();
  int calls = 0;

  Future<void> _maybeFail() async {
    calls += 1;
    if (failures != 0) {
      if (failures > 0) {
        failures -= 1;
      }
      throw Exception('Keystore no disponible');
    }
  }

  @override
  Future<String?> read(String key) async {
    await _maybeFail();
    return inner.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    await _maybeFail();
    await inner.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await _maybeFail();
    await inner.delete(key);
  }

  @override
  Future<void> deleteAll() async {
    await _maybeFail();
    await inner.deleteAll();
  }
}

Tx expense(String id, int amount, {DateTime? date}) => Tx(id: id, kind: TxKind.expense, amountMinor: amount, accountId: 'a_cash', date: date ?? d(2026, 10, 10), categoryId: 'c_food');

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('plata_storage');
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<Ledger> open(JsonStore store, CryptoBox box) async {
    final Ledger l = Ledger(EncryptedStore(store, box), clock: () => d(2026, 10, 16));
    await l.load();
    return l;
  }

  group('G6: la escritura del libro es atómica', () {
    test('si se corta antes del renombrado, al abrir se recupera el temporal completo', () async {
      final JsonStore store = JsonStore(root: tmp);
      final CryptoBox box = await CryptoBox.fromKeyStore(MemoryKeyStore());
      final Ledger a = await open(store, box);
      await a.addTx(expense('t1', 1200000));
      await a.flush();
      a.dispose();
      // El corte: el temporal quedó escrito y el libro no alcanzó a reemplazarse.
      await store.move(kLedgerFile, '$kLedgerFile.corte${JsonStore.tmpSuffix}');
      expect(await store.exists(kLedgerFile), isFalse);
      final Ledger b = await open(store, box);
      expect(b.readOnly, isFalse);
      expect(b.txs.single.id, 't1');
      expect(await store.exists(kLedgerFile), isTrue);
      expect(await store.list('', prefix: '$kLedgerFile.', extension: JsonStore.tmpSuffix), isEmpty);
      b.dispose();
    });

    test('un fallo de escritura deja el libro anterior intacto y el cambio pendiente', () async {
      final FailingStore store = FailingStore(root: tmp);
      final CryptoBox box = await CryptoBox.fromKeyStore(MemoryKeyStore());
      final Ledger l = await open(store, box);
      await l.addTx(expense('t1', 100));
      await l.flush();
      final Uint8List before = (await store.readBytes(kLedgerFile))!;
      store.fail = true;
      await l.addTx(expense('t2', 200));
      await expectLater(l.flush(), throwsA(isA<FileSystemException>()));
      expect(await store.readBytes(kLedgerFile), before);
      expect(l.busy, isTrue);
      store.fail = false;
      await l.flush();
      final Ledger again = await open(store, box);
      expect(again.txs.map((Tx t) => t.id).toSet(), <String>{'t1', 't2'});
      l.dispose();
      again.dispose();
    });

    test('las escrituras van en fila: la última siempre gana', () async {
      final JsonStore store = JsonStore(root: tmp);
      final CryptoBox box = await CryptoBox.fromKeyStore(MemoryKeyStore());
      final Ledger l = await open(store, box);
      final List<Future<void>> writes = <Future<void>>[];
      for (int i = 0; i < 6; i++) {
        await l.addTx(expense('t$i', 100 + i));
        writes.add(l.flush());
      }
      await Future.wait(writes);
      final Ledger again = await open(store, box);
      expect(again.txs.length, 6);
      expect(await store.list('', prefix: '$kLedgerFile.', extension: JsonStore.tmpSuffix), isEmpty);
      l.dispose();
      again.dispose();
    });

    test('dos escrituras simultáneas del mismo archivo no chocan', () async {
      final JsonStore store = JsonStore(root: tmp);
      await Future.wait(<Future<File>>[for (int i = 0; i < 8; i++) store.writeBytes('x.bin', <int>[i])]);
      expect((await store.readBytes('x.bin'))!.length, 1);
      expect(await store.list('', extension: JsonStore.tmpSuffix), isEmpty);
    });
  });

  group('G7: la llave del libro', () {
    test('un fallo pasajero del llavero se reintenta y conserva la llave', () async {
      final FlakyKeyStore secure = FlakyKeyStore();
      final CryptoBox original = await CryptoBox.fromKeyStore(secure);
      final Uint8List secret = await original.encrypt(utf8.encode('datos'));
      secure.failures = 2;
      final KeySetup k = await openLedgerKeys(secure: secure, file: FileKeyStore(JsonStore(root: tmp)), dataExists: true, pause: Duration.zero);
      expect(k.usesFile, isFalse);
      expect(utf8.decode(await k.box.decrypt(secret)), 'datos');
    });

    test('si el llavero no responde y hay datos, no inventa una llave nueva', () async {
      final JsonStore store = JsonStore(root: tmp);
      final FlakyKeyStore secure = FlakyKeyStore(failures: -1);
      await expectLater(openLedgerKeys(secure: secure, file: FileKeyStore(store), dataExists: true, pause: Duration.zero), throwsA(isA<SecureStoreUnavailable>()));
      expect(secure.calls, 3);
      expect(await store.exists('keys.json'), isFalse);
    });

    test('en una instalación nueva sin llavero, la llave va al archivo y se sigue usando', () async {
      final JsonStore store = JsonStore(root: tmp);
      final KeySetup first = await openLedgerKeys(secure: FlakyKeyStore(failures: -1), file: FileKeyStore(store), dataExists: false, pause: Duration.zero);
      expect(first.usesFile, isTrue);
      final Uint8List secret = await first.box.encrypt(utf8.encode('hola'));
      // Aunque después el llavero funcione, la llave sigue siendo la del archivo.
      final KeySetup later = await openLedgerKeys(secure: FlakyKeyStore(), file: FileKeyStore(store), dataExists: true, pause: Duration.zero);
      expect(later.usesFile, isTrue);
      expect(utf8.decode(await later.box.decrypt(secret)), 'hola');
    });

    test('apartar el libro ilegible deja empezar de nuevo sin borrarlo', () async {
      final JsonStore store = JsonStore(root: tmp);
      await store.writeBytes(kLedgerFile, <int>[1, 2, 3]);
      await store.writeBytes('backups/plata-2026-10-15.json.enc', <int>[4, 5]);
      expect(await ledgerDataExists(store), isTrue);
      await setAsideUnreadableLedger(store);
      expect(await ledgerDataExists(store), isFalse);
      final List<String> kept = await store.list('recovery');
      expect(kept.length, 2);
    });
  });

  group('G8 y M17: modo de recuperación', () {
    test('la copia automática no guarda un libro vacío ni borra las copias buenas', () async {
      final JsonStore store = JsonStore(root: tmp);
      final AppSettings settings = AppSettings();
      final CryptoBox box = await CryptoBox.fromKeyStore(MemoryKeyStore());
      final Ledger good = await open(store, box);
      await good.addTx(expense('t1', 100));
      final BackupManager bm = BackupManager(store: store, ledger: good, settings: settings);
      for (int i = 0; i < 7; i++) {
        await bm.autoBackup(now: DateTime(2026, 10, 1 + i));
      }
      final List<String> copies = await bm.listAutoBackups();
      expect(copies.length, 7);
      good.dispose();
      // Otra llave: el libro no se puede abrir.
      final Ledger locked = await open(store, await CryptoBox.fromKeyStore(MemoryKeyStore()));
      expect(locked.readOnly, isTrue);
      expect(locked.recoveryReason, RecoveryReason.unreadable);
      final BackupManager bm2 = BackupManager(store: store, ledger: locked, settings: settings);
      for (int i = 0; i < 9; i++) {
        expect(await bm2.autoBackup(now: DateTime(2026, 10, 8 + i), force: true), isNull);
      }
      expect(await bm2.listAutoBackups(), copies);
      // Lo que se anote en este estado no llega al disco.
      final Uint8List raw = (await store.readBytes(kLedgerFile))!;
      locked.save();
      await locked.flush();
      expect(await store.readBytes(kLedgerFile), raw);
      locked.dispose();
    });

    test('los avisos pendientes esperan a que se restaure una copia', () async {
      final JsonStore store = JsonStore(root: tmp);
      await store.writeBytes(kLedgerFile, utf8.encode('{"accounts": []}'));
      final Ledger locked = await open(store, await CryptoBox.fromKeyStore(MemoryKeyStore()));
      expect(locked.readOnly, isTrue);
      final AppSettings settings = AppSettings()..noticesEnabled = true;
      final FakeNoticeBridge bridge = FakeNoticeBridge();
      bridge.pending.add(RawNotice(package: 'com.nequi.MobileApp', title: 'Nequi', text: r'Pagaste $12.500 en Tostao.', time: d(2026, 10, 16, 8)));
      final NoticeService svc = NoticeService(bridge: bridge, ledger: locked, settings: settings);
      await svc.start();
      expect(await svc.pull(), 0);
      expect(bridge.cleared, 0);
      expect(bridge.pending.length, 1);
      locked.dispose();
    });

    test('M13: un libro sin cifrar no se acepta', () async {
      final JsonStore store = JsonStore(root: tmp);
      await store.writeJson(kLedgerFile, <String, dynamic>{
        'accounts': <Map<String, dynamic>>[Account(id: 'x', name: 'Falsa').toJson()],
      });
      final Ledger l = await open(store, await CryptoBox.fromKeyStore(MemoryKeyStore()));
      expect(l.readOnly, isTrue);
      expect(l.recoveryReason, RecoveryReason.unreadable);
      expect(l.account('x'), isNull);
      l.dispose();
    });

    test('un libro que se abre pero no tiene la forma esperada también protege los datos', () async {
      final JsonStore store = JsonStore(root: tmp);
      final CryptoBox box = await CryptoBox.fromKeyStore(MemoryKeyStore());
      await EncryptedStore(store, box).writeJson(kLedgerFile, <String, dynamic>{'version': 99, 'accounts': <dynamic>[]});
      final Ledger l = await open(store, box);
      expect(l.readOnly, isTrue);
      expect(l.recoveryReason, RecoveryReason.invalid);
      l.dispose();
    });

    test('si el libro desapareció y hay copias, se ofrece restaurar en vez de empezar vacío', () async {
      final JsonStore store = JsonStore(root: tmp);
      final CryptoBox box = await CryptoBox.fromKeyStore(MemoryKeyStore());
      final Ledger good = await open(store, box);
      await good.addTx(expense('t1', 100));
      final BackupManager bm = BackupManager(store: store, ledger: good, settings: AppSettings());
      final String rel = (await bm.autoBackup(force: true))!;
      good.dispose();
      await store.delete(kLedgerFile);
      final Ledger l = await open(store, box);
      expect(l.readOnly, isTrue);
      expect(l.recoveryReason, RecoveryReason.missing);
      final BackupManager bm2 = BackupManager(store: store, ledger: l, settings: AppSettings());
      await bm2.restore((await bm2.readAutoBackup(rel))!);
      expect(l.readOnly, isFalse);
      expect(l.txs.single.id, 't1');
      l.dispose();
    });

    test('empezar de cero aparta el libro ilegible y vuelve a guardar', () async {
      final JsonStore store = JsonStore(root: tmp);
      await store.writeBytes(kLedgerFile, <int>[9, 9, 9]);
      final CryptoBox box = await CryptoBox.fromKeyStore(MemoryKeyStore());
      final Ledger l = await open(store, box);
      expect(l.readOnly, isTrue);
      await l.startFresh();
      expect(l.readOnly, isFalse);
      expect(l.recoveryReason, isNull);
      expect((await store.list('recovery')).single, startsWith('recovery/ledger-'));
      expect(await store.readBytes((await store.list('recovery')).single), <int>[9, 9, 9]);
      await l.addTx(expense('t1', 100));
      await l.flush();
      final Ledger again = await open(store, box);
      expect(again.txs.single.id, 't1');
      l.dispose();
      again.dispose();
    });
  });

  group('G9: restaurar valida antes de escribir', () {
    test('un archivo que no es de Plata o es de otra versión se rechaza sin tocar nada', () async {
      final JsonStore store = JsonStore(root: tmp);
      final CryptoBox box = await CryptoBox.fromKeyStore(MemoryKeyStore());
      final Ledger l = await open(store, box);
      await l.addTx(expense('t1', 100));
      await l.flush();
      final Uint8List before = (await store.readBytes(kLedgerFile))!;
      await expectLater(BackupManager.decode(utf8.encode('{"accounts": "x"}')), throwsA(isA<FormatException>()));
      await expectLater(BackupManager.decode(utf8.encode('no es json')), throwsA(isA<FormatException>()));
      await expectLater(BackupManager.decode(utf8.encode('{"accounts": [], "txs": [{"id": 1}]}')), throwsA(isA<FormatException>()));
      await expectLater(BackupManager.decode(utf8.encode('{"version": 99, "accounts": []}')), throwsA(isA<FormatException>().having((FormatException e) => e.message, 'message', contains('versión más nueva'))));
      await expectLater(l.replaceWith(<String, dynamic>{'accounts': <dynamic>[], 'txs': <dynamic>[<String, dynamic>{'id': 1}]}), throwsA(isA<FormatException>()));
      expect(l.txs.single.id, 't1');
      expect(await store.readBytes(kLedgerFile), before);
      l.dispose();
    });

    test('después de restaurar una copia buena la app vuelve a abrir', () async {
      final JsonStore store = JsonStore(root: tmp);
      final CryptoBox box = await CryptoBox.fromKeyStore(MemoryKeyStore());
      final Ledger l = await open(store, box);
      await l.addTx(expense('t1', 100));
      final Map<String, dynamic> copy = await BackupManager.decode(BackupManager(store: store, ledger: l, settings: AppSettings()).exportPlain());
      await l.deleteTx('t1');
      await l.replaceWith(copy);
      final Ledger again = await open(store, box);
      expect(again.readOnly, isFalse);
      expect(again.txs.single.id, 't1');
      l.dispose();
      again.dispose();
    });
  });

  group('G11: reinstalar en iOS y olvidar la clave', () {
    test('el primer arranque tras reinstalar en iOS limpia el llavero', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final MemoryKeyStore keys = MemoryKeyStore();
      await keys.write('lock.hash', 'clave-olvidada');
      expect(await clearKeychainAfterReinstall(prefs: prefs, secure: keys, dataExists: false, ios: true), isTrue);
      expect(keys.entries, isEmpty);
      expect(prefs.getBool(kInstallMarker), isTrue);
      // Los arranques siguientes no tocan nada.
      await keys.write('lock.hash', 'clave-nueva');
      expect(await clearKeychainAfterReinstall(prefs: prefs, secure: keys, dataExists: false, ios: true), isFalse);
      expect(keys.entries, isNotEmpty);
    });

    test('con datos (una actualización) o en Android no se borra nada', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final MemoryKeyStore keys = MemoryKeyStore();
      await keys.write('ledger-key', 'llave');
      expect(await clearKeychainAfterReinstall(prefs: prefs, secure: keys, dataExists: true, ios: true), isFalse);
      expect(keys.entries, isNotEmpty);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences fresh = await SharedPreferences.getInstance();
      expect(await clearKeychainAfterReinstall(prefs: fresh, secure: keys, dataExists: false, ios: false), isFalse);
      expect(keys.entries, isNotEmpty);
    });

    test('borrar todo deja la app como recién instalada, sin clave y con llave nueva', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'language': 'en', 'onboarded': true, 'noticesEnabled': true});
      final AppSettings settings = AppSettings();
      await settings.load();
      final JsonStore store = JsonStore(root: tmp);
      final MemoryKeyStore keys = MemoryKeyStore();
      final CryptoBox box = await CryptoBox.fromKeyStore(keys);
      final Ledger ledger = await open(store, box);
      await ledger.addTx(expense('t1', 100));
      await ledger.store.writeBytes('attachments/r.jpg.enc', <int>[1, 2, 3]);
      final MemorySecureWindow window = MemorySecureWindow();
      final AppLock lock = AppLock(keys, biometricsAvailable: false, window: window);
      await lock.load();
      await lock.setPasscode('2468');
      lock.lockNow();
      final FakeNoticeBridge bridge = FakeNoticeBridge();
      final BackupManager backups = BackupManager(store: store, ledger: ledger, settings: settings);
      await backups.autoBackup(force: true);
      final Services s = Services(
        settings: settings,
        ledger: ledger,
        store: store,
        keys: keys,
        lock: lock,
        notifier: NoopNotifier(),
        rates: RateService(client: MockClient((http.Request r) async => http.Response('', 503))),
        notices: NoticeService(bridge: bridge, ledger: ledger, settings: settings),
        backups: backups,
      );
      final String oldKey = keys.entries[CryptoBox.keyName]!;
      await wipeAllData(s);
      expect(lock.enabled, isFalse);
      expect(lock.locked, isFalse);
      expect(window.secure, isFalse);
      expect(keys.entries.containsKey('lock.hash'), isFalse);
      expect(keys.entries[CryptoBox.keyName], isNot(oldKey));
      expect(ledger.txs, isEmpty);
      expect(ledger.readOnly, isFalse);
      expect(await store.list('attachments'), isEmpty);
      expect(await backups.listAutoBackups(), isEmpty);
      expect(bridge.capturing, isFalse);
      expect(settings.onboarded, isFalse);
      expect(settings.noticesEnabled, isFalse);
      expect(settings.language, 'en');
      // El libro nuevo se abre con la llave nueva.
      final Ledger again = await open(store, await CryptoBox.fromKeyStore(keys));
      expect(again.readOnly, isFalse);
      again.dispose();
      ledger.dispose();
    });
  });
}
