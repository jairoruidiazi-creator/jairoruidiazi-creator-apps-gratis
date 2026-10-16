import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/lock.dart';

/// Pantalla de bloqueo: teclado numérico y biometría.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _code = '';
  bool _error = false;
  bool _checking = false;
  Timer? _tick;
  bool _triedBiometric = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && AppScope.of(context).lock.waitSeconds > 0) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _biometric());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _biometric() async {
    if (_triedBiometric || !mounted) {
      return;
    }
    _triedBiometric = true;
    final AppLock lock = AppScope.of(context).lock;
    if (lock.biometric) {
      await lock.authenticateBiometric(t(context, 'Desbloquea Plata', 'Unlock Plata'));
    }
  }

  Future<void> _press(String k) async {
    final AppLock lock = AppScope.of(context).lock;
    if (_checking || lock.waitSeconds > 0) {
      return;
    }
    setState(() {
      _error = false;
      if (k == '⌫') {
        _code = _code.isEmpty ? '' : _code.substring(0, _code.length - 1);
      } else if (_code.length < 8) {
        _code += k;
      }
    });
    if (lock.passcodeLength >= 4 && _code.length == lock.passcodeLength) {
      await _check(lock);
    }
  }

  Future<void> _check(AppLock lock) async {
    if (_code.length < 4) {
      return;
    }
    setState(() => _checking = true);
    final bool ok = await lock.verify(_code);
    if (!mounted) {
      return;
    }
    setState(() {
      _checking = false;
      if (!ok) {
        _error = true;
        _code = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLock lock = AppScope.of(context).lock;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int wait = lock.waitSeconds;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.lock_outline, size: 48, color: cs.primary),
                const SizedBox(height: 8),
                Text('Plata', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(wait > 0 ? t(context, 'Espera $wait s para intentar de nuevo', 'Wait $wait s before trying again') : (_error ? t(context, 'Clave incorrecta', 'Wrong passcode') : t(context, 'Escribe tu clave', 'Enter your passcode')), style: TextStyle(color: _error || wait > 0 ? cs.error : cs.onSurface.withValues(alpha: 0.7))),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    for (int i = 0; i < (_code.length < 4 ? 4 : _code.length); i++)
                      Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(shape: BoxShape.circle, color: i < _code.length ? cs.primary : Colors.transparent, border: Border.all(color: cs.primary, width: 2)),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                for (final List<String> row in const <List<String>>[<String>['1', '2', '3'], <String>['4', '5', '6'], <String>['7', '8', '9'], <String>['bio', '0', '⌫']])
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      for (final String k in row)
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: SizedBox(
                            width: 76,
                            height: 64,
                            child: k == 'bio'
                                ? (lock.biometric ? IconButton(icon: const Icon(Icons.fingerprint, size: 32), onPressed: () async { _triedBiometric = false; await _biometric(); }) : const SizedBox.shrink())
                                : FilledButton.tonal(
                                    onPressed: wait > 0 ? null : () => _press(k),
                                    style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                                    child: k == '⌫' ? const Icon(Icons.backspace_outlined) : Text(k, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                                  ),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                TextButton(onPressed: _code.length >= 4 && !_checking && wait == 0 ? () => _check(lock) : null, child: Text(t(context, 'Entrar', 'Enter'))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
