import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/lock.dart';
import '../core/wipe.dart';

/// Pantalla de bloqueo: teclado numérico, biometría y, si se olvidó la clave,
/// borrar todo para volver a usar la app.
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

  /// Se está mostrando el panel de "olvidé la clave".
  bool _forgot = false;
  bool _understood = false;
  bool _wiping = false;

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

  Future<void> _wipe() async {
    setState(() => _wiping = true);
    try {
      await wipeAllData(AppScope.of(context));
    } catch (e) {
      debugPrint('Borrar todo: $e');
      if (mounted) {
        setState(() {
          _wiping = false;
          _forgot = false;
        });
      }
    }
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: _forgot ? _forgotPanel(context, cs) : _keypad(context, lock, cs, wait),
            ),
          ),
        ),
      ),
    );
  }

  Widget _keypad(BuildContext context, AppLock lock, ColorScheme cs, int wait) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.5,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.lock_outline, size: 48, color: cs.primary),
          const SizedBox(height: 8),
          Text('Plata', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Semantics(
            liveRegion: true,
            child: Text(wait > 0 ? t(context, 'Espera $wait s para intentar de nuevo', 'Wait $wait s before trying again') : (_error ? t(context, 'Clave incorrecta', 'Wrong passcode') : t(context, 'Escribe tu clave', 'Enter your passcode')), style: TextStyle(color: _error || wait > 0 ? cs.error : cs.onSurface.withValues(alpha: 0.7))),
          ),
          const SizedBox(height: 20),
          Semantics(
            label: t(context, '${_code.length} dígitos escritos', '${_code.length} digits entered'),
            child: ExcludeSemantics(
              child: Row(
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
            ),
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
                          ? (lock.biometric
                              ? IconButton(
                                  tooltip: t(context, 'Desbloquear con huella o rostro', 'Unlock with fingerprint or face'),
                                  icon: const Icon(Icons.fingerprint, size: 32),
                                  onPressed: () async {
                                    _triedBiometric = false;
                                    await _biometric();
                                  },
                                )
                              : const SizedBox.shrink())
                          : FilledButton.tonal(
                              onPressed: wait > 0 ? null : () => _press(k),
                              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                              child: k == '⌫' ? Icon(Icons.backspace_outlined, semanticLabel: t(context, 'Borrar', 'Delete')) : Text(k, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                            ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          TextButton(onPressed: _code.length >= 4 && !_checking && wait == 0 ? () => _check(lock) : null, child: Text(t(context, 'Entrar', 'Enter'))),
          TextButton(onPressed: () => setState(() => _forgot = true), child: Text(t(context, '¿Olvidaste la clave?', 'Forgot the passcode?'))),
        ],
      ),
    );
  }

  /// Sin la clave no hay forma de abrir los datos (no se guarda en ningún otro
  /// lado). Se ofrece borrar todo, con una confirmación explícita.
  Widget _forgotPanel(BuildContext context, ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.delete_forever_outlined, size: 44, color: cs.error),
        const SizedBox(height: 8),
        Text(t(context, 'Borrar todo y empezar de nuevo', 'Erase everything and start over'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(t(
          context,
          'Plata no guarda tu clave en ningún otro lado, así que nadie puede recuperarla. Si la olvidaste, puedes borrar todo lo que la app tiene en este teléfono —cuentas, movimientos, presupuestos, fotos de recibos, copias automáticas y la clave— y empezar de cero.\n\nNo se puede deshacer. Si tienes una copia cifrada con contraseña (.plata), después podrás restaurarla en Más › Copias de seguridad.',
          'Plata does not store your passcode anywhere else, so nobody can recover it. If you forgot it, you can erase everything the app keeps on this phone —accounts, transactions, budgets, receipt photos, automatic copies and the passcode— and start from scratch.\n\nThis cannot be undone. If you have a password-protected backup (.plata), you can restore it afterwards under More › Backups.',
        )),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _understood,
          onChanged: _wiping ? null : (bool? v) => setState(() => _understood = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(t(context, 'Entiendo que se borran todos mis datos de este teléfono', 'I understand all my data on this phone will be erased')),
        ),
        const SizedBox(height: 8),
        // Con texto grande los dos botones van uno debajo del otro.
        OverflowBar(
          alignment: MainAxisAlignment.spaceBetween,
          overflowAlignment: OverflowBarAlignment.end,
          overflowSpacing: 8,
          children: <Widget>[
            TextButton(
              onPressed: _wiping
                  ? null
                  : () => setState(() {
                        _forgot = false;
                        _understood = false;
                      }),
              child: Text(t(context, 'Cancelar', 'Cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
              onPressed: _understood && !_wiping ? _wipe : null,
              child: _wiping ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onError)) : Text(t(context, 'Borrar todo', 'Erase everything')),
            ),
          ],
        ),
      ],
    );
  }
}
