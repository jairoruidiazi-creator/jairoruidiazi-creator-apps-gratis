import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/lock.dart';
import '../../core/wipe.dart';
import '../widgets/adaptive.dart';
import 'security_screen.dart';

/// Borrar todo lo que Plata guarda en el teléfono desde Ajustes (la misma
/// salida que «¿Olvidaste la clave?» en la pantalla de bloqueo). Con clave de
/// acceso, primero la pide.
class EraseAllScreen extends StatefulWidget {
  const EraseAllScreen({super.key});

  @override
  State<EraseAllScreen> createState() => _EraseAllScreenState();
}

class _EraseAllScreenState extends State<EraseAllScreen> {
  bool _understood = false;
  bool _wiping = false;

  Future<void> _erase() async {
    final Services s = AppScope.of(context);
    final AppLock lock = s.lock;
    if (lock.enabled) {
      final int wait = lock.waitSeconds;
      if (wait > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Espera $wait s para intentar de nuevo.', 'Wait $wait s before trying again.'))));
        return;
      }
      final String? code = await askPasscode(context, t(context, 'Clave actual', 'Current passcode'));
      if (code == null || !mounted) {
        return;
      }
      if (!await lock.verify(code)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lock.waitSeconds > 0 ? t(context, 'Clave incorrecta. Espera ${lock.waitSeconds} s para intentar de nuevo.', 'Wrong passcode. Wait ${lock.waitSeconds} s before trying again.') : t(context, 'Clave incorrecta.', 'Wrong passcode.'))));
        }
        return;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() => _wiping = true);
    try {
      await wipeAllData(s);
      if (mounted) {
        Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
      }
    } catch (e) {
      debugPrint('Borrar todo: $e');
      if (mounted) {
        setState(() => _wiping = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'No se pudo borrar todo. Intenta de nuevo.', 'Could not erase everything. Try again.'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ReadableScaffold(
      appBar: AppBar(title: Text(t(context, 'Borrar todos los datos', 'Erase all data'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          Icon(Icons.delete_forever_outlined, size: 44, color: cs.error),
          const SizedBox(height: 8),
          Text(t(
            context,
            'Se borra todo lo que Plata guarda en este teléfono: cuentas, movimientos, presupuestos, programados, fotos de recibos, copias automáticas, avisos pendientes, la clave de acceso y la llave de cifrado. La app queda como recién instalada.\n\nNo se puede deshacer. Las copias que exportaste (.plata o JSON) no se tocan: después puedes restaurar una en Más › Copias de seguridad.',
            'Everything Plata keeps on this phone is erased: accounts, transactions, budgets, scheduled items, receipt photos, automatic copies, pending notices, the passcode and the encryption key. The app is left as if just installed.\n\nThis cannot be undone. Backups you exported (.plata or JSON) are not touched: you can restore one afterwards under More › Backups.',
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
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
              onPressed: _understood && !_wiping ? _erase : null,
              child: _wiping ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onError)) : Text(t(context, 'Borrar todo', 'Erase everything')),
            ),
          ),
        ],
      ),
    );
  }
}
