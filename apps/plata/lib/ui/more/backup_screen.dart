import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/backups.dart';
import '../../core/sharing.dart';
import '../../model/models.dart';
import '../widgets/common.dart';

/// Copias de seguridad: automáticas locales, exportar (cifrada o abierta)
/// e importar/restaurar.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  List<String> _auto = <String>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    final List<String> list = await AppScope.of(context).backups.listAutoBackups();
    if (mounted) {
      setState(() => _auto = list.reversed.toList());
    }
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t(context, 'Error', 'Error')}: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _exportEncrypted() async {
    final Services s = AppScope.of(context);
    final String? pass = await askText(context, t(context, 'Contraseña de la copia', 'Backup password'), hint: t(context, 'Mínimo 6 caracteres; sin ella no se puede abrir', 'At least 6 characters; without it the file cannot be opened'));
    if (pass == null || !mounted) {
      return;
    }
    if (pass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Usa al menos 6 caracteres.', 'Use at least 6 characters.'))));
      return;
    }
    await _run(() async {
      await s.ledger.flush();
      final Uint8List bytes = await s.backups.exportEncrypted(pass);
      await shareBytes(s.store, 'plata-${dayKey(DateTime.now())}.plata', bytes, text: 'Plata backup');
    });
  }

  Future<void> _exportPlain() async {
    final Services s = AppScope.of(context);
    if (!await confirm(context, t(context, '¿Exportar sin cifrar?', 'Export unencrypted?'), t(context, 'El archivo JSON se puede leer con cualquier editor. Úsalo para migrar o analizar tus datos, y bórralo después.', 'The JSON file can be read with any editor. Use it to migrate or analyse your data, and delete it afterwards.'), yes: t(context, 'Exportar', 'Export')) || !mounted) {
      return;
    }
    await _run(() async {
      await s.ledger.flush();
      await shareBytes(s.store, 'plata-${dayKey(DateTime.now())}.json', s.backups.exportPlain(), text: 'Plata JSON');
    });
  }

  Future<void> _import() async {
    final Services s = AppScope.of(context);
    const XTypeGroup group = XTypeGroup(label: 'Plata', extensions: <String>['plata', 'json', 'enc'], uniformTypeIdentifiers: <String>['public.data', 'public.json']);
    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t(context, 'No se pudo abrir el selector', 'Could not open the picker')}: $e')));
      }
      return;
    }
    if (file == null || !mounted) {
      return;
    }
    final Uint8List bytes = await file.readAsBytes();
    if (!mounted) {
      return;
    }
    String? pass;
    if (BackupManager.isEncryptedBackup(bytes)) {
      pass = await askText(context, t(context, 'Contraseña de la copia', 'Backup password'));
      if (pass == null || !mounted) {
        return;
      }
    }
    await _restore(() => BackupManager.decode(bytes, passphrase: pass), s);
  }

  Future<void> _restore(Future<Map<String, dynamic>> Function() read, Services s) async {
    Map<String, dynamic> data;
    try {
      data = await read();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'No se pudo leer la copia (¿contraseña incorrecta o archivo dañado?).', 'Could not read the backup (wrong password or damaged file?).'))));
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final int n = (data['txs'] as List<dynamic>?)?.length ?? 0;
    final int a = (data['accounts'] as List<dynamic>?)?.length ?? 0;
    if (!await confirm(context, t(context, '¿Reemplazar todos los datos?', 'Replace all data?'), t(context, 'La copia tiene $a cuentas y $n movimientos. Lo que hay ahora en la app se sustituye por completo (antes se guarda una copia automática).', 'The backup has $a accounts and $n transactions. What is in the app now will be fully replaced (an automatic copy is saved first).'), yes: t(context, 'Restaurar', 'Restore')) || !mounted) {
      return;
    }
    await _run(() async {
      await s.backups.autoBackup(force: true);
      await s.backups.restore(data);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Datos restaurados.', 'Data restored.'))));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: s.settings,
      builder: (BuildContext context, Widget? _) => Scaffold(
        appBar: AppBar(title: Text(t(context, 'Copias de seguridad', 'Backups'))),
        body: Stack(
          children: <Widget>[
            ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(t(context, 'Plata no tiene nube: tú decides dónde guardar tus copias (Drive, correo, computador). Recomendación: exporta una copia cifrada cada mes y antes de cambiar de teléfono.', 'Plata has no cloud: you decide where to keep your backups (Drive, email, computer). Tip: export an encrypted copy monthly and before switching phones.'), style: TextStyle(color: cs.onSurface.withValues(alpha: 0.75))),
                ),
                ListTile(
                  leading: const Icon(Icons.enhanced_encryption_outlined),
                  title: Text(t(context, 'Exportar copia cifrada', 'Export encrypted backup')),
                  subtitle: Text(t(context, 'Archivo .plata protegido con contraseña. Se abre solo en Plata.', '.plata file protected with a password. Opens only in Plata.')),
                  onTap: _busy ? null : _exportEncrypted,
                ),
                ListTile(
                  leading: const Icon(Icons.data_object),
                  title: Text(t(context, 'Exportar JSON sin cifrar', 'Export unencrypted JSON')),
                  subtitle: Text(t(context, 'Para migrar o analizar en otra herramienta.', 'To migrate or analyse in another tool.')),
                  onTap: _busy ? null : _exportPlain,
                ),
                ListTile(
                  leading: const Icon(Icons.file_open_outlined),
                  title: Text(t(context, 'Restaurar desde archivo', 'Restore from file')),
                  subtitle: Text(t(context, 'Abre una copia .plata o .json y reemplaza los datos actuales.', 'Open a .plata or .json backup and replace the current data.')),
                  onTap: _busy ? null : _import,
                ),
                const Divider(),
                SwitchListTile(
                  secondary: const Icon(Icons.history),
                  value: s.settings.autoBackup,
                  onChanged: (bool v) {
                    s.settings.autoBackup = v;
                    s.settings.save();
                  },
                  title: Text(t(context, 'Copia automática diaria', 'Daily automatic copy')),
                  subtitle: Text(t(context, 'Se guardan las últimas 7 en el almacenamiento privado de la app (se pierden si desinstalas).', 'The last 7 are kept in the app private storage (lost if you uninstall).')),
                ),
                if (s.settings.lastBackupAt != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('${t(context, 'Última', 'Last')}: ${formatDate(s.settings.lastBackupAt!, 'dd MMM yyyy HH:mm', spanish: s.settings.spanish)}', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              await s.ledger.flush();
                              await s.backups.autoBackup(force: true);
                              await _load();
                            }),
                    icon: const Icon(Icons.save_outlined),
                    label: Text(t(context, 'Hacer copia local ahora', 'Make a local copy now')),
                  ),
                ),
                for (final String rel in _auto)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.restore_page_outlined),
                    title: Text(rel.split('/').last),
                    trailing: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _restore(() async {
                                final Map<String, dynamic>? d = await s.backups.readAutoBackup(rel);
                                if (d == null) {
                                  throw StateError('vacía');
                                }
                                return d;
                              }, s),
                      child: Text(t(context, 'Restaurar', 'Restore')),
                    ),
                  ),
              ],
            ),
            if (_busy) const Positioned.fill(child: ColoredBox(color: Color(0x33000000), child: Center(child: CircularProgressIndicator()))),
          ],
        ),
      ),
    );
  }
}
