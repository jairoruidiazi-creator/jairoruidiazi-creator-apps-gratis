import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'app.dart';
import 'core/app_scope.dart';
import 'core/backups.dart';
import 'core/crypto_store.dart';
import 'core/ledger.dart';
import 'core/lock.dart';
import 'core/notices.dart';
import 'core/notifications.dart';
import 'core/rates.dart';
import 'core/settings.dart';
import 'core/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final AppSettings settings = AppSettings();
  await settings.load();
  final JsonStore store = JsonStore();

  // Llave del libro en el Keystore/Llavero; si falla (ROM rara), llave en archivo privado.
  KeyStore keys = SecureKeyStore();
  CryptoBox box;
  try {
    box = await CryptoBox.fromKeyStore(keys);
  } catch (e) {
    debugPrint('Llavero no disponible, usando llave local: $e');
    keys = FileKeyStore(store);
    box = await CryptoBox.fromKeyStore(keys);
  }
  final EncryptedStore encrypted = EncryptedStore(store, box);
  final Ledger ledger = Ledger(encrypted, spanish: settings.spanish);
  await ledger.load();

  final AppLock lock = AppLock(keys, auth: LocalAuthentication());
  await lock.load();

  final Notifier notifier = LocalNotifier();
  final RateService rates = RateService();
  final NoticeService notices = NoticeService(bridge: PlatformNoticeBridge(), ledger: ledger, settings: settings);
  final BackupManager backups = BackupManager(store: store, ledger: ledger, settings: settings);

  runApp(PlataApp(
    services: Services(settings: settings, ledger: ledger, store: store, keys: keys, lock: lock, notifier: notifier, rates: rates, notices: notices, backups: backups),
  ));
  WidgetsBinding.instance.addPostFrameCallback((_) => lockPhonePortrait());
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
