import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'crypto_store.dart';

/// Protección de la ventana del sistema mientras hay clave: en Android,
/// FLAG_SECURE (sin capturas y con la miniatura de apps recientes en negro);
/// en iOS, una cubierta al salir de primer plano (ver native/).
abstract class SecureWindow {
  Future<void> setSecure(bool on);
}

class ChannelSecureWindow implements SecureWindow {
  static const MethodChannel _channel = MethodChannel('co.appsgratis.plata/privacy');

  @override
  Future<void> setSecure(bool on) async {
    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      await _channel.invokeMethod<bool>('setSecure', on);
    } catch (e) {
      debugPrint('Ventana segura: $e');
    }
  }
}

/// Para pruebas: recuerda el último valor.
class MemorySecureWindow implements SecureWindow {
  bool? secure;

  @override
  Future<void> setSecure(bool on) async => secure = on;
}

/// Bloqueo de la app: código numérico (guardado como PBKDF2 con sal en el
/// llavero), huella/rostro del sistema y retardo creciente tras fallos.
class AppLock extends ChangeNotifier {
  AppLock(this.keys, {LocalAuthentication? auth, this.biometricsAvailable = true, SecureWindow? window})
      : _auth = auth,
        _window = window;

  final KeyStore keys;
  final LocalAuthentication? _auth;
  final SecureWindow? _window;
  final bool biometricsAvailable;

  bool _enabled = false;
  bool _biometric = false;
  bool locked = false;

  /// La app está tapada por una cubierta (salió de primer plano y aún no se
  /// sabe si toca bloquear): nada de lo que hay detrás se ve ni se alcanza.
  bool obscured = false;
  int lockAfterSeconds = 60;

  /// Largo de la clave (para enviar sola al completarla); 0 si no hay clave.
  int passcodeLength = 0;
  int _failures = 0;
  DateTime? _blockedUntil;
  DateTime? _background;

  /// Espera máxima tras varios fallos (30 s duplicados seis veces).
  static const int maxWaitSeconds = 30 * 64;

  bool get enabled => _enabled;
  bool get biometric => _biometric;

  /// Segundos que faltan para poder intentar de nuevo (0 si se puede).
  int get waitSeconds {
    final DateTime? b = _blockedUntil;
    if (b == null) {
      return 0;
    }
    final int s = b.difference(clock.now()).inSeconds;
    return s > 0 ? s : 0;
  }

  /// Lee el estado guardado. Si el almacén seguro no responde, la app queda
  /// bloqueada (falla cerrada): el candado vuelve a intentar al verificar.
  Future<void> load() async {
    try {
      _enabled = (await keys.read('lock.hash')) != null;
      _biometric = (await keys.read('lock.biometric')) == '1';
      lockAfterSeconds = int.tryParse(await keys.read('lock.after') ?? '') ?? 60;
      passcodeLength = int.tryParse(await keys.read('lock.len') ?? '') ?? 0;
      _failures = int.tryParse(await keys.read('lock.failures') ?? '') ?? 0;
      final int? until = int.tryParse(await keys.read('lock.until') ?? '');
      _blockedUntil = until == null ? null : DateTime.fromMillisecondsSinceEpoch(until);
      final DateTime cap = clock.now().add(const Duration(seconds: maxWaitSeconds));
      if (_blockedUntil != null && _blockedUntil!.isAfter(cap)) {
        // El reloj del teléfono se atrasó: la espera no pasa del máximo.
        _blockedUntil = cap;
      }
    } catch (e) {
      debugPrint('Bloqueo: $e');
      _enabled = true;
      passcodeLength = 0;
    }
    locked = _enabled;
    obscured = false;
    await _window?.setSecure(_enabled);
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
    await _resetFailures();
    await _window?.setSecure(true);
    notifyListeners();
  }

  Future<void> clearPasscode() async {
    await keys.delete('lock.salt');
    await keys.delete('lock.hash');
    await keys.delete('lock.biometric');
    await keys.delete('lock.len');
    await _resetFailures();
    passcodeLength = 0;
    _enabled = false;
    _biometric = false;
    locked = false;
    obscured = false;
    await _window?.setSecure(false);
    notifyListeners();
  }

  /// Deja el candado como recién instalado (después de borrar todo).
  Future<void> reset() async {
    _enabled = false;
    _biometric = false;
    locked = false;
    obscured = false;
    passcodeLength = 0;
    lockAfterSeconds = 60;
    _failures = 0;
    _blockedUntil = null;
    _background = null;
    await _window?.setSecure(false);
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

  Future<void> _resetFailures() async {
    _failures = 0;
    _blockedUntil = null;
    try {
      await keys.delete('lock.failures');
      await keys.delete('lock.until');
    } catch (e) {
      debugPrint('Bloqueo: $e');
    }
  }

  /// Comprueba el código. Tras 3 fallos impone esperas de 30 s que se
  /// duplican. Los fallos y la espera se guardan en el almacén seguro, así que
  /// cerrar y abrir la app no los reinicia.
  Future<bool> verify(String code) async {
    if (waitSeconds > 0) {
      return false;
    }
    String? saltB64;
    String? hashB64;
    try {
      saltB64 = await keys.read('lock.salt');
      hashB64 = await keys.read('lock.hash');
    } catch (e) {
      debugPrint('Bloqueo: $e');
      return false;
    }
    if (saltB64 == null || hashB64 == null) {
      locked = false;
      notifyListeners();
      return true;
    }
    final List<int> h = await _hash(code, base64Decode(saltB64));
    final bool ok = _constantTimeEquals(h, base64Decode(hashB64));
    if (ok) {
      await _resetFailures();
      locked = false;
      obscured = false;
    } else {
      _failures += 1;
      if (_failures >= 3) {
        final int seconds = 30 * (1 << (_failures - 3).clamp(0, 6));
        _blockedUntil = clock.now().add(Duration(seconds: seconds));
      }
      try {
        await keys.write('lock.failures', '$_failures');
        if (_blockedUntil != null) {
          await keys.write('lock.until', '${_blockedUntil!.millisecondsSinceEpoch}');
        }
      } catch (e) {
        debugPrint('Bloqueo: $e');
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

  /// Huella o rostro con la pantalla del sistema. Solo biometría: el PIN del
  /// teléfono no reemplaza la clave de Plata.
  Future<bool> authenticateBiometric(String reason) async {
    if (!_biometric || !biometricsAvailable || _auth == null) {
      return false;
    }
    try {
      final bool ok = await _auth.authenticate(localizedReason: reason, biometricOnly: true);
      if (ok) {
        await _resetFailures();
        locked = false;
        obscured = false;
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

  /// La app deja de estar activa sin irse al fondo (iOS: centro de control,
  /// cambio de app): se tapa para que la vista de apps recientes no muestre
  /// nada. No se tapa el candado mismo (la cara o la huella lo usan).
  void onInactive() {
    if (_enabled && !locked && !obscured) {
      obscured = true;
      notifyListeners();
    }
  }

  /// La app se fue al fondo. Con "Bloquear al salir: de inmediato" se bloquea
  /// ya; si no, queda tapada hasta volver y saber cuánto tiempo pasó.
  void onBackground() {
    _background ??= clock.now();
    if (!_enabled || locked) {
      return;
    }
    if (lockAfterSeconds <= 0) {
      locked = true;
    }
    obscured = true;
    notifyListeners();
  }

  void onForeground() {
    final DateTime? b = _background;
    _background = null;
    if (_enabled && !locked && b != null && clock.now().difference(b).inSeconds >= lockAfterSeconds) {
      locked = true;
    }
    if (obscured || locked) {
      obscured = false;
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
