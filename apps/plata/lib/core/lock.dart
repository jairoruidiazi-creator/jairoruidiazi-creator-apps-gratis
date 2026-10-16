import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import 'crypto_store.dart';

/// Bloqueo de la app: código numérico (guardado como PBKDF2 con sal en el
/// llavero), huella/rostro del sistema y retardo creciente tras fallos.
class AppLock extends ChangeNotifier {
  AppLock(this.keys, {LocalAuthentication? auth, this.biometricsAvailable = true}) : _auth = auth;

  final KeyStore keys;
  final LocalAuthentication? _auth;
  final bool biometricsAvailable;

  bool _enabled = false;
  bool _biometric = false;
  bool locked = false;
  int lockAfterSeconds = 60;

  /// Largo de la clave (para enviar sola al completarla); 0 si no hay clave.
  int passcodeLength = 0;
  int _failures = 0;
  DateTime? _blockedUntil;
  DateTime? _background;

  bool get enabled => _enabled;
  bool get biometric => _biometric;

  /// Segundos que faltan para poder intentar de nuevo (0 si se puede).
  int get waitSeconds {
    final DateTime? b = _blockedUntil;
    if (b == null) {
      return 0;
    }
    final int s = b.difference(DateTime.now()).inSeconds;
    return s > 0 ? s : 0;
  }

  Future<void> load() async {
    _enabled = (await keys.read('lock.hash')) != null;
    _biometric = (await keys.read('lock.biometric')) == '1';
    lockAfterSeconds = int.tryParse(await keys.read('lock.after') ?? '') ?? 60;
    passcodeLength = int.tryParse(await keys.read('lock.len') ?? '') ?? 0;
    locked = _enabled;
    notifyListeners();
  }

  static Future<List<int>> _hash(String code, List<int> salt) async {
    final Pbkdf2 kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 60000, bits: 256);
    final SecretKey k = await kdf.deriveKeyFromPassword(password: code, nonce: salt);
    return k.extractBytes();
  }

  Future<void> setPasscode(String code) async {
    final Random r = Random.secure();
    final List<int> salt = List<int>.generate(16, (_) => r.nextInt(256));
    final List<int> h = await _hash(code, salt);
    await keys.write('lock.salt', base64Encode(salt));
    await keys.write('lock.hash', base64Encode(h));
    await keys.write('lock.len', '${code.length}');
    passcodeLength = code.length;
    _enabled = true;
    _failures = 0;
    _blockedUntil = null;
    notifyListeners();
  }

  Future<void> clearPasscode() async {
    await keys.delete('lock.salt');
    await keys.delete('lock.hash');
    await keys.delete('lock.biometric');
    await keys.delete('lock.len');
    passcodeLength = 0;
    _enabled = false;
    _biometric = false;
    locked = false;
    notifyListeners();
  }

  Future<void> setBiometric(bool on) async {
    _biometric = on;
    await keys.write('lock.biometric', on ? '1' : '0');
    notifyListeners();
  }

  Future<void> setLockAfter(int seconds) async {
    lockAfterSeconds = seconds;
    await keys.write('lock.after', '$seconds');
    notifyListeners();
  }

  /// Comprueba el código. Tras 3 fallos impone esperas de 30 s que se duplican.
  Future<bool> verify(String code) async {
    if (waitSeconds > 0) {
      return false;
    }
    final String? saltB64 = await keys.read('lock.salt');
    final String? hashB64 = await keys.read('lock.hash');
    if (saltB64 == null || hashB64 == null) {
      locked = false;
      notifyListeners();
      return true;
    }
    final List<int> h = await _hash(code, base64Decode(saltB64));
    final bool ok = _constantTimeEquals(h, base64Decode(hashB64));
    if (ok) {
      _failures = 0;
      _blockedUntil = null;
      locked = false;
    } else {
      _failures += 1;
      if (_failures >= 3) {
        final int seconds = 30 * (1 << (_failures - 3).clamp(0, 6));
        _blockedUntil = DateTime.now().add(Duration(seconds: seconds));
      }
    }
    notifyListeners();
    return ok;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Huella o rostro con la pantalla del sistema.
  Future<bool> authenticateBiometric(String reason) async {
    if (!_biometric || !biometricsAvailable || _auth == null) {
      return false;
    }
    try {
      final bool ok = await _auth.authenticate(localizedReason: reason);
      if (ok) {
        locked = false;
        _failures = 0;
        notifyListeners();
      }
      return ok;
    } catch (e) {
      debugPrint('Biometría: $e');
      return false;
    }
  }

  Future<bool> canUseBiometrics() async {
    if (!biometricsAvailable || _auth == null) {
      return false;
    }
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  void onBackground() => _background = DateTime.now();

  void onForeground() {
    final DateTime? b = _background;
    _background = null;
    if (_enabled && !locked && b != null && DateTime.now().difference(b).inSeconds >= lockAfterSeconds) {
      locked = true;
      notifyListeners();
    }
  }

  void lockNow() {
    if (_enabled) {
      locked = true;
      notifyListeners();
    }
  }
}
