import 'package:flutter/widgets.dart';

import 'backups.dart';
import 'crypto_store.dart';
import 'ledger.dart';
import 'lock.dart';
import 'notices.dart';
import 'notifications.dart';
import 'rates.dart';
import 'settings.dart';
import 'storage.dart';

class Services {
  const Services({
    required this.settings,
    required this.ledger,
    required this.store,
    required this.keys,
    required this.lock,
    required this.notifier,
    required this.rates,
    required this.notices,
    required this.backups,
    this.keyInFile = false,
  });

  final AppSettings settings;
  final Ledger ledger;
  final JsonStore store;
  final KeyStore keys;
  final AppLock lock;
  final Notifier notifier;
  final RateService rates;
  final NoticeService notices;
  final BackupManager backups;

  /// La llave de los datos vive en un archivo de la carpeta privada (el
  /// teléfono no ofreció su almacén seguro al instalar Plata).
  final bool keyInFile;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final Services services;

  static Services of(BuildContext context) {
    final AppScope? scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No hay AppScope en el árbol');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => oldWidget.services != services;
}

/// Texto en el idioma de la app.
String t(BuildContext context, String es, String en) => AppScope.of(context).settings.spanish ? es : en;

/// Cantidad con su palabra en singular o plural: "1 bolsillo", "3 bolsillos".
String counted(BuildContext context, int n, {required String oneEs, required String manyEs, required String oneEn, required String manyEn}) => '$n ${n == 1 ? t(context, oneEs, oneEn) : t(context, manyEs, manyEn)}';

/// Libera controladores después de que cierre el diálogo que los usaba.
void disposeLater(List<ChangeNotifier> controllers) {
  Future<void>.delayed(const Duration(seconds: 1), () {
    for (final ChangeNotifier c in controllers) {
      c.dispose();
    }
  });
}
