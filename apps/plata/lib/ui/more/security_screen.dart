import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/lock.dart';
import '../widgets/adaptive.dart';

/// Clave de acceso, biometría y ocultar saldos.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool? _bio;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final bool b = await AppScope.of(context).lock.canUseBiometrics();
      if (mounted) {
        setState(() => _bio = b);
      }
    });
  }

  Future<void> _setPasscode(BuildContext context, AppLock lock) async {
    final String? a = await askPasscode(context, t(context, 'Nueva clave (4 a 8 dígitos)', 'New passcode (4 to 8 digits)'));
    if (a == null || !context.mounted) {
      return;
    }
    // Solo cifras: el teclado del candado no tiene signos ni espacios.
    if (!validPasscode(a)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Usa entre 4 y 8 dígitos.', 'Use 4 to 8 digits.'))));
      return;
    }
    final String? b = await askPasscode(context, t(context, 'Repite la clave', 'Repeat the passcode'));
    if (b == null || !context.mounted) {
      return;
    }
    if (a != b) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'No coinciden.', 'They do not match.'))));
      return;
    }
    await lock.setPasscode(a);
    if (context.mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Clave guardada. Nadie puede recuperarla: si la olvidas, en la pantalla de bloqueo podrás borrar todo y empezar de nuevo.', 'Passcode saved. Nobody can recover it: if you forget it, the lock screen lets you erase everything and start over.'))));
    }
  }

  /// Pide la clave actual. Durante la espera tras varios fallos no se puede
  /// comprobar: se dice cuánto falta en lugar de "clave incorrecta".
  Future<bool> _checkCurrent(BuildContext context, AppLock lock) async {
    void tell(String es, String en) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, es, en))));
      }
    }

    final int before = lock.waitSeconds;
    if (before > 0) {
      tell('Espera $before s para intentar de nuevo.', 'Wait $before s before trying again.');
      return false;
    }
    final String? cur = await askPasscode(context, t(context, 'Clave actual', 'Current passcode'));
    if (cur == null || !context.mounted) {
      return false;
    }
    if (await lock.verify(cur)) {
      return true;
    }
    final int wait = lock.waitSeconds;
    tell(wait > 0 ? 'Clave incorrecta. Espera $wait s para intentar de nuevo.' : 'Clave incorrecta.', wait > 0 ? 'Wrong passcode. Wait $wait s before trying again.' : 'Wrong passcode.');
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final AppLock lock = s.lock;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[lock, s.settings]),
      builder: (BuildContext context, Widget? _) => ReadableScaffold(
        appBar: AppBar(title: Text(t(context, 'Seguridad', 'Security'))),
        body: ListView(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(lock.enabled ? t(context, 'Cambiar clave', 'Change passcode') : t(context, 'Poner clave de acceso', 'Set a passcode')),
              subtitle: Text(lock.enabled ? t(context, 'La app pide la clave al abrirla.', 'The app asks for the passcode when opened.') : t(context, 'Sin clave, cualquiera con el teléfono desbloqueado ve tus cuentas.', 'Without one, anyone holding the unlocked phone sees your accounts.')),
              onTap: () async {
                if (lock.enabled) {
                  if (!await _checkCurrent(context, lock)) {
                    return;
                  }
                }
                if (context.mounted) {
                  await _setPasscode(context, lock);
                }
              },
            ),
            if (lock.enabled)
              ListTile(
                leading: const Icon(Icons.lock_open_outlined),
                title: Text(t(context, 'Quitar la clave', 'Remove passcode')),
                onTap: () async {
                  if (await _checkCurrent(context, lock)) {
                    await lock.clearPasscode();
                  }
                },
              ),
            if (lock.enabled)
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                value: lock.biometric,
                onChanged: _bio == true ? (bool v) => lock.setBiometric(v) : null,
                title: Text(t(context, 'Huella o rostro', 'Fingerprint or face')),
                subtitle: Text(_bio == false ? t(context, 'Este teléfono no tiene biometría configurada.', 'This phone has no biometrics set up.') : t(context, 'Desbloquea con la biometría del teléfono; la clave sigue siendo el respaldo.', 'Unlock with the phone biometrics; the passcode remains the fallback.')),
              ),
            if (lock.enabled)
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(t(context, 'Bloquear al salir', 'Lock when leaving')),
                subtitle: Text(_afterLabel(context, lock.lockAfterSeconds)),
                trailing: DropdownButton<int>(
                  value: <int>[0, 15, 60, 300, 900].contains(lock.lockAfterSeconds) ? lock.lockAfterSeconds : 60,
                  underline: const SizedBox.shrink(),
                  items: <DropdownMenuItem<int>>[for (final int v in <int>[0, 15, 60, 300, 900]) DropdownMenuItem<int>(value: v, child: Text(_afterLabel(context, v)))],
                  onChanged: (int? v) => lock.setLockAfter(v ?? 60),
                ),
              ),
            const Divider(),
            SwitchListTile(
              secondary: const Icon(Icons.visibility_off_outlined),
              value: s.settings.hideBalances,
              onChanged: (bool v) {
                s.settings.hideBalances = v;
                s.settings.save();
              },
              title: Text(t(context, 'Ocultar saldos', 'Hide balances')),
              subtitle: Text(t(context, 'Muestra •••• en lugar de montos (útil en público). Se alterna con el ojo de Inicio.', 'Shows •••• instead of amounts (handy in public). Toggle with the eye on Home.')),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${s.keyInFile ? t(context, 'Tus datos se guardan cifrados (ChaCha20-Poly1305) en el almacenamiento privado de la app. Este teléfono no ofreció su almacén seguro al instalar Plata, así que la llave quedó en un archivo de esa misma carpeta privada: la protege el sistema, no el hardware.', 'Your data is stored encrypted (ChaCha20-Poly1305) in the app private storage. This phone did not offer its secure store when Plata was installed, so the key is kept in a file in that same private folder: the system protects it, not the hardware.') : t(context, 'Tus datos se guardan cifrados (ChaCha20-Poly1305) en el almacenamiento privado de la app; la llave vive en el Keystore de Android o el Llavero de iOS.', 'Your data is stored encrypted (ChaCha20-Poly1305) in the app private storage; the key lives in the Android Keystore or iOS Keychain.')} ${t(
                  context,
                  'La clave de acceso se guarda como un hash PBKDF2, no en claro. Tras 3 intentos fallidos la espera entre intentos se duplica, aunque cierres la app. Con clave, Android no deja tomar capturas de Plata y la vista de apps recientes no muestra tus saldos. Si olvidas la clave, desde la pantalla de bloqueo puedes borrar todo y empezar de nuevo: sin ella tus datos no se pueden abrir.',
                  'The passcode is stored as a PBKDF2 hash, never in clear. After 3 failed attempts the wait doubles each time, even if you close the app. With a passcode, Android blocks screenshots of Plata and the recent apps view does not show your balances. If you forget the passcode, the lock screen lets you erase everything and start over: without it your data cannot be opened.',
                )}',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _afterLabel(BuildContext context, int seconds) {
    if (seconds <= 0) {
      return t(context, 'De inmediato', 'Immediately');
    }
    if (seconds < 60) {
      return t(context, 'Tras $seconds segundos', 'After $seconds seconds');
    }
    final int m = seconds ~/ 60;
    return t(context, m == 1 ? 'Tras 1 minuto' : 'Tras $m minutos', m == 1 ? 'After 1 minute' : 'After $m minutes');
  }
}

/// Diálogo de clave numérica oculta.
Future<String?> askPasscode(BuildContext context, String title) async {
  final TextEditingController ctrl = TextEditingController();
  final String? v = await showDialog<String>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctrl, autofocus: true, obscureText: true, autocorrect: false, enableSuggestions: false, enableIMEPersonalizedLearning: false, keyboardType: TextInputType.number, inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly], maxLength: 8, decoration: const InputDecoration(counterText: ''), onSubmitted: (String s) => Navigator.pop(context, s)),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t(context, 'Cancelar', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: Text(t(context, 'Aceptar', 'OK'))),
      ],
    ),
  );
  disposeLater(<ChangeNotifier>[ctrl]);
  return v;
}

/// Una clave de acceso válida: de 4 a 8 cifras y nada más (el teclado del
/// candado no tiene signos: "-123" o "+123" no se podrían escribir).
bool validPasscode(String code) => RegExp(r'^[0-9]{4,8}$').hasMatch(code);
