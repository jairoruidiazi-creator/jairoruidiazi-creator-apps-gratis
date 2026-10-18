import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'storage.dart';

/// Dónde vive la clave de cifrado: el llavero del sistema (Keychain en iOS,
/// Keystore en Android) o memoria en pruebas.
abstract class KeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// Borra todas las claves de la app (borrar todo, o el primer arranque
  /// después de reinstalar en iOS).
  Future<void> deleteAll();
}

class SecureKeyStore implements KeyStore {
  SecureKeyStore()
      : _s = const FlutterSecureStorage(
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
          // Si el Keystore falla, el complemento por defecto BORRA todas las
          // claves para recuperarse (resetOnError): eso dejaría los datos sin
          // llave para siempre. Con false, el error llega a la app, que
          // reintenta y avisa (ver core/key_setup.dart). La migración de
          // algoritmo guarda antes una copia de las claves.
          aOptions: AndroidOptions(resetOnError: false, migrateWithBackup: true),
        );

  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);

  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _s.delete(key: key);

  @override
  Future<void> deleteAll() => _s.deleteAll();
}

class MemoryKeyStore implements KeyStore {
  final Map<String, String> _m = <String, String>{};

  /// Copia de las claves (para pruebas).
  Map<String, String> get entries => Map<String, String>.unmodifiable(_m);

  @override
  Future<String?> read(String key) async => _m[key];

  @override
  Future<void> write(String key, String value) async => _m[key] = value;

  @override
  Future<void> delete(String key) async => _m.remove(key);

  @override
  Future<void> deleteAll() async => _m.clear();
}

/// El archivo existe pero no se puede descifrar con la llave actual.
class DecryptException implements Exception {
  const DecryptException(this.path);

  final String path;

  @override
  String toString() => 'No se pudo descifrar $path';
}

/// Respaldo cuando el llavero del sistema no está disponible: guarda las
/// claves en un archivo del almacenamiento privado de la app (protegido por
/// el sistema de archivos, no por hardware). Solo se usa en una instalación
/// nueva cuyo llavero no responde (ver core/key_setup.dart).
class FileKeyStore implements KeyStore {
  FileKeyStore(this.store, {this.file = 'keys.json'});

  final JsonStore store;
  final String file;
  Map<String, dynamic>? _cache;

  Future<Map<String, dynamic>> _load() async => _cache ??= (await store.readJson(file)) ?? <String, dynamic>{};

  @override
  Future<String?> read(String key) async => (await _load())[key] as String?;

  @override
  Future<void> write(String key, String value) async {
    final Map<String, dynamic> m = await _load();
    m[key] = value;
    await store.writeJson(file, m);
  }

  @override
  Future<void> delete(String key) async {
    final Map<String, dynamic> m = await _load();
    m.remove(key);
    await store.writeJson(file, m);
  }

  @override
  Future<void> deleteAll() async {
    _cache = <String, dynamic>{};
    await store.delete(file);
  }
}

/// Cifrado autenticado (ChaCha20-Poly1305) de los archivos de datos.
///
/// Formato del archivo: "PLATA1" + nonce (12 bytes) + texto cifrado + MAC (16).
/// La clave de 256 bits se crea la primera vez y se guarda en el llavero del
/// sistema; nunca se escribe junto a los datos.
class CryptoBox {
  CryptoBox(this._key);

  final SecretKey _key;
  static final Chacha20 _algo = Chacha20.poly1305Aead();
  static const List<int> magic = <int>[0x50, 0x4C, 0x41, 0x54, 0x41, 0x31]; // PLATA1

  /// Nombre de la llave del libro en el llavero.
  static const String keyName = 'ledger-key';

  /// Caja con una llave ya guardada (en Base64).
  static CryptoBox fromStored(String base64Key) => CryptoBox(SecretKey(base64Decode(base64Key)));

  /// Lee la llave del llavero o, si no hay ninguna, crea una y la guarda.
  /// Los errores del llavero se propagan: nunca se inventa una llave porque
  /// la lectura falló.
  static Future<CryptoBox> fromKeyStore(KeyStore ks, {String name = keyName}) async {
    final String? stored = await ks.read(name);
    if (stored != null && stored.isNotEmpty) {
      return fromStored(stored);
    }
    final SecretKey key = await _algo.newSecretKey();
    final List<int> bytes = await key.extractBytes();
    await ks.write(name, base64Encode(bytes));
    return CryptoBox(SecretKey(bytes));
  }

  /// Clave derivada de una contraseña (respaldo portátil). PBKDF2-HMAC-SHA256,
  /// 120 000 iteraciones.
  static Future<CryptoBox> fromPassword(String password, List<int> salt) async {
    final Pbkdf2 kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 120000, bits: 256);
    final SecretKey key = await kdf.deriveKeyFromPassword(password: password, nonce: salt);
    return CryptoBox(key);
  }

  Future<Uint8List> encrypt(List<int> clear) async {
    final SecretBox box = await _algo.encrypt(clear, secretKey: _key);
    return Uint8List.fromList(<int>[...magic, ...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<Uint8List> decrypt(List<int> data) async {
    if (data.length < magic.length + 12 + 16 || !_hasMagic(data)) {
      throw const FormatException('Archivo no cifrado o dañado');
    }
    final List<int> body = data.sublist(magic.length);
    final SecretBox box = SecretBox.fromConcatenation(body, nonceLength: 12, macLength: 16);
    final List<int> clear = await _algo.decrypt(box, secretKey: _key);
    return Uint8List.fromList(clear);
  }

  static bool _hasMagic(List<int> data) {
    for (int i = 0; i < magic.length; i++) {
      if (data[i] != magic[i]) {
        return false;
      }
    }
    return true;
  }

  static bool isEncrypted(List<int> data) => data.length >= magic.length && _hasMagic(data);
}

/// Archivos JSON cifrados sobre [JsonStore].
///
/// Solo se aceptan archivos cifrados: uno en claro (sin la cabecera PLATA1) se
/// trata como dañado, para que nadie pueda reemplazar los datos por un JSON
/// abierto escrito a mano y saltarse el cifrado.
class EncryptedStore {
  EncryptedStore(this.store, this.box);

  final JsonStore store;

  /// Llave actual. Cambia solo al borrar todo (se crea una llave nueva).
  CryptoBox box;

  Future<Map<String, dynamic>?> readJson(String relativePath) async {
    final Uint8List? data = await store.readBytes(relativePath);
    if (data == null || data.isEmpty) {
      return null;
    }
    if (!CryptoBox.isEncrypted(data)) {
      throw DecryptException(relativePath);
    }
    try {
      final Uint8List clear = await box.decrypt(data);
      final dynamic decoded = jsonDecode(utf8.decode(clear));
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw DecryptException(relativePath);
    } on FormatException {
      // Archivo dañado: tampoco se trata como vacío, por la misma razón.
      throw DecryptException(relativePath);
    } on SecretBoxAuthenticationError {
      // Llave distinta o archivo alterado: no se devuelve "vacío" para que
      // nadie sobrescriba los datos cifrados con otros nuevos.
      throw DecryptException(relativePath);
    }
  }

  Future<void> writeJson(String relativePath, Map<String, dynamic> data) async {
    final Uint8List cipher = await box.encrypt(utf8.encode(jsonEncode(data)));
    await store.writeBytes(relativePath, cipher);
  }

  /// Guarda un archivo binario cifrado (por ejemplo la foto de un recibo).
  Future<void> writeBytes(String relativePath, List<int> data) async {
    await store.writeBytes(relativePath, await box.encrypt(data));
  }

  /// Lee un archivo binario cifrado.
  Future<Uint8List?> readBytes(String relativePath) async {
    final Uint8List? data = await store.readBytes(relativePath);
    if (data == null || data.isEmpty) {
      return null;
    }
    if (!CryptoBox.isEncrypted(data)) {
      throw DecryptException(relativePath);
    }
    try {
      return await box.decrypt(data);
    } on FormatException {
      throw DecryptException(relativePath);
    } on SecretBoxAuthenticationError {
      throw DecryptException(relativePath);
    }
  }
}
