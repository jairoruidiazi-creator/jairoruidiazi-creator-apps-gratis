import 'dart:async';
import 'dart:io';
import 'dart:ui' show FlutterView;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/app_scope.dart';
import 'core/backups.dart';
import 'core/crypto_store.dart';
import 'core/key_setup.dart';
import 'core/ledger.dart';
import 'core/lock.dart';
import 'core/notices.dart';
import 'core/notifications.dart';
import 'core/rates.dart';
import 'core/settings.dart';
import 'core/storage.dart';
import 'ui/startup_error.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Las flechas y marcas vienen de un subconjunto de DejaVu Sans: su licencia
  // aparece en Licencias de código abierto.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(<String>['DejaVu Sans (Simbolos)'], await rootBundle.loadString('assets/legal/LICENSE-DejaVu.txt'));
  });
  await _start();
  WidgetsBinding.instance.addPostFrameCallback((_) => lockPhonePortrait());
}

/// Arranca la app; si algo falla, muestra una pantalla que explica qué pasó y
/// permite reintentar sin perder datos.
Future<void> _start() async {
  final JsonStore store = JsonStore();
  try {
    runApp(PlataApp(services: await _bootstrap(store)));
  } on SecureStoreUnavailable catch (e) {
    debugPrint('$e');
    runApp(StartupErrorApp(
      problem: StartupProblem.secureStore,
      onRetry: _start,
      onStartOver: () async {
        await setAsideUnreadableLedger(store);
        await _start();
      },
    ));
  } catch (e, st) {
    debugPrint('Arranque: $e\n$st');
    runApp(StartupErrorApp(problem: StartupProblem.unexpected, onRetry: _start));
  }
}

Future<Services> _bootstrap(JsonStore store) async {
  final AppSettings settings = AppSettings();
  await settings.load();
  final bool dataExists = await ledgerDataExists(store);
  final SecureKeyStore secure = SecureKeyStore();
  // iOS: el Llavero sobrevive a la desinstalación; en una instalación nueva se
  // limpia lo que haya dejado la anterior (por ejemplo, una clave olvidada).
  await clearKeychainAfterReinstall(prefs: await SharedPreferences.getInstance(), secure: secure, dataExists: dataExists, ios: Platform.isIOS);

  // Llave del libro en el Keystore/Llavero. Un fallo pasajero se reintenta; si
  // persiste y hay datos, no se crea una llave nueva (ver core/key_setup.dart).
  final KeySetup keys = await openLedgerKeys(secure: secure, file: FileKeyStore(store), dataExists: dataExists);
  final EncryptedStore encrypted = EncryptedStore(store, keys.box);
  final Ledger ledger = Ledger(encrypted, spanish: settings.spanish);
  await ledger.load();
  // Las categorías de fábrica siguen el idioma de la app (por ejemplo, tras
  // restaurar una copia hecha en el otro idioma).
  if (!ledger.readOnly) {
    ledger.applyLanguage(settings.spanish);
  }
  // Las exportaciones (CSV, Excel, copias) ya se compartieron y no van cifradas;
  // las fotos de recibos huérfanas se borran, y también las copias sin cifrar
  // que el selector de fotos haya dejado en la caché.
  await store.clear('exports');
  await ledger.pruneAttachments();
  await _clearPickerLeftovers();

  final AppLock lock = AppLock(keys.keys, auth: LocalAuthentication(), window: ChannelSecureWindow());
  await lock.load();

  final Notifier notifier = LocalNotifier();
  final RateService rates = RateService();
  final NoticeService notices = NoticeService(bridge: PlatformNoticeBridge(), ledger: ledger, settings: settings);
  final BackupManager backups = BackupManager(store: store, ledger: ledger, settings: settings);
  return Services(settings: settings, ledger: ledger, store: store, keys: keys.keys, lock: lock, notifier: notifier, rates: rates, notices: notices, backups: backups);
}

/// El selector de fotos copia la imagen (y, al reducirla, su original) en la
/// caché de la app. La app las cifra al adjuntarlas y borra las copias; esto
/// recoge las que hubieran quedado si la app se cerró a mitad de camino.
Future<void> _clearPickerLeftovers() async {
  try {
    final Directory tmp = await getTemporaryDirectory();
    if (!await tmp.exists()) {
      return;
    }
    final DateTime old = DateTime.now().subtract(const Duration(minutes: 10));
    await for (final FileSystemEntity e in tmp.list(recursive: true)) {
      if (e is File && isPickerImage(e.path)) {
        try {
          if ((await e.lastModified()).isBefore(old)) {
            await e.delete();
          }
        } catch (_) {}
      }
    }
  } catch (e) {
    debugPrint('Caché de fotos: $e');
  }
}

/// Fotos que deja el selector (jpg, png, heic, webp, gif), por extensión.
bool isPickerImage(String path) {
  final String p = path.toLowerCase();
  return p.endsWith('.jpg') || p.endsWith('.jpeg') || p.endsWith('.png') || p.endsWith('.heic') || p.endsWith('.heif') || p.endsWith('.webp') || p.endsWith('.gif');
}

/// Los teléfonos van en vertical; las tabletas (lado corto de 600 dp o más)
/// giran libremente. En iPhone lo mismo lo fija el Info.plist.
void lockPhonePortrait() {
  final FlutterView? view = WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view == null || view.devicePixelRatio <= 0) {
    return;
  }
  final double shortest = view.physicalSize.shortestSide / view.devicePixelRatio;
  if (shortest > 0 && shortest < 600) {
    unawaited(SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]));
  }
}
