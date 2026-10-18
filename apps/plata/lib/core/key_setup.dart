import 'package:clock/clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crypto_store.dart';
import 'storage.dart';

/// Cómo quedó la llave del libro al arrancar.
class KeySetup {
  const KeySetup({required this.keys, required this.box, required this.usesFile});

  /// Almacén donde viven la llave y la clave de acceso.
  final KeyStore keys;
  final CryptoBox box;

  /// Verdadero si la llave vive en el archivo privado de la app (teléfono
  /// cuyo almacén seguro no funcionó en la primera instalación).
  final bool usesFile;
}

/// El almacén seguro del sistema no respondió y hay datos que dependen de él:
/// la app no crea una llave nueva (dejaría los datos ilegibles) y pide
/// reintentar.
class SecureStoreUnavailable implements Exception {
  const SecureStoreUnavailable(this.cause);

  final Object cause;

  @override
  String toString() => 'Almacén seguro no disponible: $cause';
}

/// Nombre del libro en la carpeta de la app.
const String kLedgerFile = 'ledger.json';

/// Si en la carpeta de la app hay un libro (o el temporal de una escritura
/// que se cortó).
Future<bool> ledgerDataExists(JsonStore store) async {
  if (await store.exists(kLedgerFile)) {
    return true;
  }
  final List<String> temps = await store.list('', prefix: '$kLedgerFile.', extension: JsonStore.tmpSuffix);
  return temps.isNotEmpty;
}

/// Abre la llave del libro.
///
/// 1. Si la app ya usa la llave en archivo (respaldo de una instalación con el
///    almacén seguro roto), la sigue usando.
/// 2. Si no, lee del almacén seguro, con [attempts] intentos: un fallo pasajero
///    del Keystore o del Llavero no debe cambiar la llave.
/// 3. Si el almacén seguro no responde y no hay datos, es una instalación
///    nueva: la llave va al archivo privado. Si hay datos, lanza
///    [SecureStoreUnavailable] sin crear nada.
Future<KeySetup> openLedgerKeys({required KeyStore secure, required KeyStore file, required bool dataExists, int attempts = 3, Duration pause = const Duration(milliseconds: 300)}) async {
  String? fileKey;
  try {
    fileKey = await file.read(CryptoBox.keyName);
  } catch (_) {
    fileKey = null;
  }
  if (fileKey != null && fileKey.isNotEmpty) {
    return KeySetup(keys: file, box: CryptoBox.fromStored(fileKey), usesFile: true);
  }
  Object? lastError;
  for (int i = 0; i < attempts; i++) {
    if (i > 0) {
      await Future<void>.delayed(pause);
    }
    try {
      final CryptoBox box = await CryptoBox.fromKeyStore(secure);
      return KeySetup(keys: secure, box: box, usesFile: false);
    } catch (e) {
      lastError = e;
    }
  }
  if (dataExists) {
    throw SecureStoreUnavailable(lastError ?? 'sin respuesta');
  }
  final CryptoBox box = await CryptoBox.fromKeyStore(file);
  return KeySetup(keys: file, box: box, usesFile: true);
}

/// Marca de "la app ya arrancó en esta instalación". Vive en las preferencias,
/// que iOS borra al desinstalar (el Llavero no).
const String kInstallMarker = 'plata.installMarker';

/// En iOS el Llavero sobrevive a la desinstalación: sin esto, una clave de
/// acceso olvidada seguiría pidiéndose después de reinstalar. En el primer
/// arranque de una instalación (sin marca y sin datos) se borra lo que haya
/// dejado una instalación anterior. Si ya hay datos (una actualización desde
/// una versión sin la marca), no se toca nada. Devuelve si borró algo.
Future<bool> clearKeychainAfterReinstall({required SharedPreferences prefs, required KeyStore secure, required bool dataExists, required bool ios}) async {
  if (prefs.getBool(kInstallMarker) ?? false) {
    return false;
  }
  bool wiped = false;
  if (ios && !dataExists) {
    try {
      await secure.deleteAll();
      wiped = true;
    } catch (_) {
      // Si el Llavero no responde, lo intentará openLedgerKeys con sus reintentos.
    }
  }
  await prefs.setBool(kInstallMarker, true);
  return wiped;
}

/// Aparta el libro que no se puede abrir (el almacén seguro no responde y el
/// usuario eligió empezar de nuevo): queda en recovery/ por si la llave
/// vuelve, y el siguiente arranque crea un libro nuevo.
Future<void> setAsideUnreadableLedger(JsonStore store) async {
  final String stamp = clock.now().toIso8601String().replaceAll(':', '-');
  if (await store.exists(kLedgerFile)) {
    await store.move(kLedgerFile, 'recovery/ledger-$stamp.json.enc');
  }
  for (final String tmp in await store.list('', prefix: '$kLedgerFile.', extension: JsonStore.tmpSuffix)) {
    await store.delete(tmp);
  }
  // Las copias automáticas usan la misma llave: se apartan también.
  for (final String rel in await store.list('backups')) {
    await store.move(rel, 'recovery/${rel.split('/').last}');
  }
}
