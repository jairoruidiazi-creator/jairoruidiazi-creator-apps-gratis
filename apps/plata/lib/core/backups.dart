import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../model/models.dart';
import 'crypto_store.dart';
import 'ledger.dart';
import 'settings.dart';
import 'storage.dart';

/// Respaldos: copia local automática diaria (cifrada con la clave del
/// dispositivo) y archivos portátiles para la nube del usuario, cifrados con
/// una contraseña o en JSON claro.
class BackupManager {
  BackupManager({required this.store, required this.ledger, required this.settings});

  final JsonStore store;
  final Ledger ledger;
  final AppSettings settings;

  static const List<int> magic = <int>[0x50, 0x4C, 0x41, 0x54, 0x41, 0x2D, 0x42, 0x4B, 0x31]; // PLATA-BK1
  static const int keep = 7;

  /// Copia local si hoy no se ha hecho. Devuelve la ruta relativa creada.
  Future<String?> autoBackup({DateTime? now, bool force = false}) async {
    final DateTime today = dateOnly(now ?? DateTime.now());
    final DateTime? last = settings.lastBackupAt;
    if (!force && last != null && !dateOnly(last).isBefore(today)) {
      return null;
    }
    final String rel = 'backups/plata-${dayKey(today)}.json.enc';
    await ledger.store.writeJson(rel, ledger.toJson());
    settings.lastBackupAt = now ?? DateTime.now();
    await settings.save();
    final List<String> all = await store.list('backups', extension: '.json.enc');
    if (all.length > keep) {
      for (final String old in all.take(all.length - keep)) {
        await store.delete(old);
      }
    }
    return rel;
  }

  Future<List<String>> listAutoBackups() => store.list('backups', extension: '.json.enc');

  Future<Map<String, dynamic>?> readAutoBackup(String rel) => ledger.store.readJson(rel);

  /// Archivo portátil cifrado con contraseña (PBKDF2 + ChaCha20-Poly1305).
  Future<Uint8List> exportEncrypted(String passphrase) async {
    final Random r = Random.secure();
    final List<int> salt = List<int>.generate(16, (_) => r.nextInt(256));
    final CryptoBox box = await CryptoBox.fromPassword(passphrase, salt);
    final Uint8List body = await box.encrypt(utf8.encode(jsonEncode(ledger.toJson())));
    return Uint8List.fromList(<int>[...magic, ...salt, ...body]);
  }

  Uint8List exportPlain() => Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert(ledger.toJson())));

  static bool isEncryptedBackup(List<int> bytes) {
    if (bytes.length < magic.length + 16) {
      return false;
    }
    for (int i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) {
        return false;
      }
    }
    return true;
  }

  /// Lee un respaldo (cifrado con contraseña o JSON claro). Lanza
  /// [FormatException] si no se puede leer o la contraseña no sirve.
  static Future<Map<String, dynamic>> decode(List<int> bytes, {String? passphrase}) async {
    List<int> clear = bytes;
    if (isEncryptedBackup(bytes)) {
      if (passphrase == null || passphrase.isEmpty) {
        throw const FormatException('Se necesita la contraseña del respaldo');
      }
      final List<int> salt = bytes.sublist(magic.length, magic.length + 16);
      final CryptoBox box = await CryptoBox.fromPassword(passphrase, salt);
      try {
        clear = await box.decrypt(bytes.sublist(magic.length + 16));
      } catch (_) {
        throw const FormatException('Contraseña incorrecta o archivo dañado');
      }
    }
    final dynamic decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map<String, dynamic> || decoded['accounts'] is! List) {
      throw const FormatException('No es un respaldo de Plata');
    }
    return decoded;
  }

  /// Reemplaza el libro por el respaldo.
  Future<void> restore(Map<String, dynamic> data) => ledger.replaceWith(data);
}
