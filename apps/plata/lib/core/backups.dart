import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:clock/clock.dart';

import '../model/models.dart';
import 'crypto_store.dart';
import 'ledger.dart';
import 'settings.dart';
import 'storage.dart';

/// Lo que contiene un archivo elegido para restaurar.
enum BackupKind {
  /// Copia cifrada con contraseña (cabecera `PLATA-BK1`).
  encrypted,

  /// JSON sin cifrar exportado desde Plata.
  plain,

  /// Cualquier otro archivo.
  foreign,
}

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
  ///
  /// Mientras el libro no se pueda abrir (modo de recuperación) no hace nada:
  /// copiaría un libro vacío y, al rotar, borraría las copias buenas. Las
  /// copias viejas se borran solo después de escribir la nueva.
  Future<String?> autoBackup({DateTime? now, bool force = false}) async {
    if (ledger.readOnly || !ledger.loaded) {
      return null;
    }
    final DateTime today = dateOnly(now ?? clock.now());
    final DateTime? last = settings.lastBackupAt;
    if (!force && last != null && !dateOnly(last).isBefore(today)) {
      return null;
    }
    final String rel = 'backups/plata-${dayKey(today)}.json.enc';
    await ledger.store.writeJson(rel, ledger.toJson());
    settings.lastBackupAt = now ?? clock.now();
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

  /// Qué es un archivo, mirando su contenido y no su nombre: en Android el
  /// selector no filtra por extensión (un `.plata` guardado en Drive o en
  /// Descargas llega como `application/octet-stream`), así que se reconoce
  /// por la cabecera `PLATA-BK1` o por ser el JSON de un libro de Plata.
  static BackupKind detect(List<int> bytes) {
    if (isEncryptedBackup(bytes)) {
      return BackupKind.encrypted;
    }
    int i = 0;
    // Marca de orden de bytes UTF-8 y espacios antes del JSON.
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      i = 3;
    }
    while (i < bytes.length && (bytes[i] == 0x20 || bytes[i] == 0x0A || bytes[i] == 0x0D || bytes[i] == 0x09)) {
      i++;
    }
    if (i >= bytes.length || bytes[i] != 0x7B) {
      return BackupKind.foreign;
    }
    try {
      final dynamic decoded = jsonDecode(utf8.decode(bytes.sublist(i)));
      if (decoded is Map<String, dynamic> && decoded['accounts'] is List && decoded['txs'] is List) {
        return BackupKind.plain;
      }
    } catch (_) {
      // No es texto JSON.
    }
    return BackupKind.foreign;
  }

  /// Borra las copias automáticas guardadas en el teléfono.
  Future<int> deleteAutoBackups() async {
    final List<String> all = await listAutoBackups();
    for (final String rel in all) {
      await store.delete(rel);
    }
    return all.length;
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
    dynamic decoded;
    try {
      String text = utf8.decode(clear);
      if (text.startsWith('\uFEFF')) {
        text = text.substring(1);
      }
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FormatException('No es un respaldo de Plata');
    }
    if (decoded is! Map<String, dynamic> || decoded['accounts'] is! List) {
      throw const FormatException('No es un respaldo de Plata');
    }
    // Se valida completo aquí, antes de preguntar si se reemplazan los datos.
    LedgerSnapshot.parse(decoded);
    return decoded;
  }

  /// Reemplaza el libro por el respaldo.
  Future<void> restore(Map<String, dynamic> data) => ledger.replaceWith(data);
}
