import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/backup_picker.dart';
import '../../core/backups.dart';
import '../../core/ledger.dart';
import '../../core/sharing.dart';
import '../../model/models.dart';
import '../widgets/adaptive.dart';
import '../widgets/common.dart';

/// Copias de seguridad: automáticas locales, exportar (cifrada o abierta)
/// e importar/restaurar.
///
/// Con [recovery] es la pantalla de recuperación: los datos guardados no se
/// pudieron abrir, así que solo se ofrece restaurar una copia o empezar de
/// cero, y la app no deja anotar nada hasta entonces (lo anotado se perdería).
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, this.recovery = false});

  final bool recovery;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

/// Nombre legible de una copia automática: «18 oct 2026» o «18 oct 2026 ·
/// antes de restaurar (09:12)», en vez del nombre del archivo.
String backupLabel(BuildContext context, String rel) {
  final String name = rel.split('/').last;
  final RegExpMatch? m = RegExp(r'^plata-(\d{4})-(\d{2})-(\d{2})(?:-antes-(\d{2})(\d{2})\d{2}(?:-\d+)?)?\.json\.enc$').firstMatch(name);
  if (m == null) {
    return name;
  }
  final DateTime day = DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  final String date = dayText(context, day, year: true);
  if (m.group(4) == null) {
    return date;
  }
  return '$date · ${t(context, 'antes de restaurar', 'before restoring')} (${m.group(4)}:${m.group(5)})';
}

/// Avisa con claridad que el archivo elegido no es una copia de Plata.
Future<void> showNotPlata(BuildContext context, String name) => showDialog<void>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text(t(c, 'No es una copia de Plata', 'Not a Plata backup')),
        content: Text(t(c, '«$name» no es una copia de Plata, así que no se cambió nada. Elige la copia cifrada (.plata) o el JSON que exportaste desde Plata.', '"$name" is not a Plata backup, so nothing was changed. Choose the encrypted backup (.plata) or the JSON you exported from Plata.')),
        actions: <Widget>[TextButton(onPressed: () => Navigator.of(c).pop(), child: Text(t(c, 'Entendido', 'OK')))],
      ),
    );

class _BackupScreenState extends State<BackupScreen> {
  List<String> _auto = <String>[];
  bool _busy = false;

  /// Restaurar desde archivo en curso (eligiendo, copiando o preguntando).
  bool _picking = false;

  /// Mínimo de la contraseña de la copia cifrada.
  static const int _minPassword = 8;

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

  Future<void> _run(Future<void> Function() f, {required String failed}) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      debugPrint('Copias: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failed)));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _exportEncrypted() async {
    final Services s = AppScope.of(context);
    final String? pass = await askSecret(
      context,
      t(context, 'Contraseña de la copia', 'Backup password'),
      help: t(context, 'Mínimo $_minPassword caracteres. Sin ella la copia no se puede abrir, y nadie puede recuperarla.', 'At least $_minPassword characters. Without it the backup cannot be opened, and nobody can recover it.'),
      repeat: true,
      minLength: _minPassword,
    );
    if (pass == null || !mounted) {
      return;
    }
    await _run(() async {
      await s.ledger.flush();
      final Uint8List bytes = await s.backups.exportEncrypted(pass);
      await shareBytes(s.store, 'plata-${dayKey(clock.now())}.plata', bytes, text: 'Plata backup');
    }, failed: t(context, 'No se pudo crear la copia. Intenta de nuevo.', 'The backup could not be created. Try again.'));
  }

  Future<void> _exportPlain() async {
    final Services s = AppScope.of(context);
    if (!await confirm(context, t(context, '¿Exportar sin cifrar?', 'Export unencrypted?'), t(context, 'El archivo JSON se puede leer con cualquier editor. Úsalo para migrar o analizar tus datos, y bórralo después.', 'The JSON file can be read with any editor. Use it to migrate or analyse your data, and delete it afterwards.'), yes: t(context, 'Exportar', 'Export')) || !mounted) {
      return;
    }
    await _run(() async {
      await s.ledger.flush();
      await shareBytes(s.store, 'plata-${dayKey(clock.now())}.json', s.backups.exportPlain(), text: 'Plata JSON');
    }, failed: t(context, 'No se pudo exportar. Intenta de nuevo.', 'Could not export. Try again.'));
  }

  /// Restaurar desde un archivo. La pantalla queda ocupada desde que se
  /// toca hasta que el archivo se leyó: un segundo toque no abre otro
  /// selector mientras el primero todavía copia (un archivo de Drive puede
  /// tardar en bajar).
  Future<void> _import() async {
    if (_busy || _picking) {
      return;
    }
    setState(() => _picking = true);
    try {
      await _importNow();
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  Future<void> _importNow() async {
    final Services s = AppScope.of(context);
    PickedBackup? file;
    try {
      file = await pickBackupFile();
    } on BackupTooBig catch (e) {
      // Una copia de Plata pesa pocos megas: lo enorme ni se lee.
      if (mounted) {
        await showNotPlata(context, e.name);
      }
      return;
    } on BackupUnreadable catch (e) {
      debugPrint('Leer archivo: ${e.name}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'No se pudo leer el archivo. Intenta de nuevo.', 'The file could not be read. Try again.'))));
      }
      return;
    } catch (e) {
      debugPrint('Selector de archivos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'No se pudo abrir el selector de archivos.', 'Could not open the file picker.'))));
      }
      return;
    }
    if (file == null) {
      return;
    }
    Uint8List bytes;
    try {
      // Se lee y la copia temporal se borra enseguida, aunque falle.
      bytes = await file.readAndDiscard();
    } catch (e) {
      debugPrint('Leer archivo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'No se pudo leer el archivo. Intenta de nuevo.', 'The file could not be read. Try again.'))));
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final BackupKind kind = BackupManager.detect(bytes);
    if (kind == BackupKind.foreign) {
      await showNotPlata(context, file.name);
      return;
    }
    String? pass;
    if (kind == BackupKind.encrypted) {
      pass = await askSecret(context, t(context, 'Contraseña de la copia', 'Backup password'));
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
      debugPrint('Leer copia: $e');
      if (mounted) {
        final bool newer = e is FormatException && e.message.contains('versión más nueva');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(newer
              ? t(context, 'La copia es de una versión más nueva de Plata: actualiza la app para abrirla.', 'The backup is from a newer version of Plata: update the app to open it.')
              : t(context, 'No se pudo leer la copia (¿contraseña incorrecta o archivo dañado?).', 'Could not read the backup (wrong password or damaged file?).')),
        ));
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final int n = (data['txs'] as List<dynamic>?)?.length ?? 0;
    final int a = (data['accounts'] as List<dynamic>?)?.length ?? 0;
    final String replaced = s.ledger.readOnly
        ? t(context, 'Los datos que no se pudieron abrir quedan apartados en la carpeta de la app.', 'The data that could not be opened is set aside in the app folder.')
        : t(context, 'Lo que hay ahora en la app se sustituye por completo (antes se guarda una copia automática).', 'What is in the app now will be fully replaced (an automatic copy is saved first).');
    if (!await confirm(context, t(context, '¿Reemplazar todos los datos?', 'Replace all data?'), '${t(context, 'La copia tiene', 'The backup has')} ${counted(context, a, oneEs: 'cuenta', manyEs: 'cuentas', oneEn: 'account', manyEn: 'accounts')} ${t(context, 'y', 'and')} ${counted(context, n, oneEs: 'movimiento', manyEs: 'movimientos', oneEn: 'transaction', manyEn: 'transactions')}. $replaced', yes: t(context, 'Restaurar', 'Restore')) || !mounted) {
      return;
    }
    await _run(() async {
      await s.backups.autoBackup(beforeRestore: true);
      await s.backups.restore(data);
      s.ledger.applyLanguage(s.settings.spanish);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context, 'Datos restaurados.', 'Data restored.'))));
      }
    }, failed: t(context, 'No se pudo restaurar la copia. Tus datos actuales no cambiaron.', 'The backup could not be restored. Your current data did not change.'));
  }

  Future<void> _deleteAuto(Services s) async {
    if (!await confirm(context, t(context, '¿Borrar las copias automáticas?', 'Delete the automatic copies?'), t(context, 'Se borran las ${_auto.length} copias guardadas en este teléfono. Tus datos actuales y los archivos que exportaste no cambian.', 'The ${_auto.length} copies kept on this phone are deleted. Your current data and the files you exported do not change.'), yes: t(context, 'Borrar', 'Delete')) || !mounted) {
      return;
    }
    await _run(() async {
      await s.backups.deleteAutoBackups();
      await _load();
    }, failed: t(context, 'No se pudieron borrar las copias. Intenta de nuevo.', 'The copies could not be deleted. Try again.'));
  }

  Future<void> _startFresh(Services s) async {
    if (!await confirm(context, t(context, '¿Empezar de cero?', 'Start from scratch?'), t(context, 'La app abrirá vacía. Los datos que no se pudieron abrir quedan apartados en la carpeta de la app; después puedes restaurar una copia.', 'The app will open empty. The data that could not be opened is set aside in the app folder; you can restore a backup afterwards.'), yes: t(context, 'Empezar de cero', 'Start from scratch')) || !mounted) {
      return;
    }
    await _run(() => s.ledger.startFresh(), failed: t(context, 'No se pudo empezar de cero. Intenta de nuevo.', 'Could not start from scratch. Try again.'));
  }

  String _recoveryText(BuildContext context, RecoveryReason? r) {
    switch (r) {
      case RecoveryReason.missing:
        return t(context, 'El archivo de tus datos no está en el teléfono, pero quedan copias automáticas. Restaura la más reciente para seguir donde ibas.', 'Your data file is not on the phone, but there are automatic copies. Restore the latest one to continue where you left off.');
      case RecoveryReason.invalid:
        return t(context, 'Tus datos se abrieron, pero no tienen la forma que espera esta versión de Plata (¿son de una versión más nueva?). Actualiza la app o restaura una copia.', 'Your data opened, but it does not have the shape this version of Plata expects (is it from a newer version?). Update the app or restore a backup.');
      case RecoveryReason.unreadable:
      case null:
        return t(context, 'No se pudieron descifrar los datos guardados: la llave del teléfono cambió o el archivo se dañó. Para no perder nada, la app no guardará cambios hasta que restaures una copia de seguridad o decidas empezar de cero.', 'The saved data could not be decrypted: the phone key changed or the file is damaged. To avoid losing anything, the app will not save changes until you restore a backup or choose to start from scratch.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool recovery = widget.recovery;
    return ListenableBuilder(
      listenable: s.settings,
      builder: (BuildContext context, Widget? _) => ReadableScaffold(
        appBar: AppBar(title: Text(recovery ? t(context, 'Recuperar tus datos', 'Recover your data') : t(context, 'Copias de seguridad', 'Backups')), automaticallyImplyLeading: !recovery),
        body: Stack(
          children: <Widget>[
            ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: <Widget>[
                if (recovery)
                  Card(
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    color: cs.errorContainer,
                    child: Padding(padding: const EdgeInsets.all(16), child: Text(_recoveryText(context, s.ledger.recoveryReason), style: TextStyle(color: cs.onErrorContainer))),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(t(context, 'Plata no tiene nube y sus datos no entran en las copias de Google o iCloud (la llave que los abre no sale del teléfono). Tú decides dónde guardar tus copias: Drive, correo o computador. Exporta una copia cifrada cada mes y antes de cambiar de teléfono. Las copias llevan tus datos, no las fotos de recibos.', 'Plata has no cloud and its data is not included in Google or iCloud backups (the key that opens it never leaves the phone). You decide where to keep your backups: Drive, email or computer. Export an encrypted copy every month and before switching phones. Backups carry your data, not receipt photos.'), style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                if (!recovery) ...<Widget>[
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
                ],
                ListTile(
                  leading: const Icon(Icons.file_open_outlined),
                  title: Text(t(context, 'Restaurar desde archivo', 'Restore from file')),
                  subtitle: Text(t(context, 'Abre una copia .plata o .json y reemplaza los datos actuales.', 'Open a .plata or .json backup and replace the current data.')),
                  onTap: _busy || _picking ? null : _import,
                ),
                const Divider(),
                if (!recovery) ...<Widget>[
                  SwitchListTile(
                    secondary: const Icon(Icons.history),
                    value: s.settings.autoBackup,
                    onChanged: (bool v) {
                      s.settings.autoBackup = v;
                      s.settings.save();
                    },
                    title: Text(t(context, 'Copia automática diaria', 'Daily automatic copy')),
                    subtitle: Text(t(context, 'Se guardan las últimas 7 diarias y las 5 de antes de restaurar, en el almacenamiento privado de la app (se pierden si desinstalas).', 'The last 7 daily copies and the 5 made before restoring are kept in the app private storage (lost if you uninstall).')),
                  ),
                  if (s.settings.lastBackupAt != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('${t(context, 'Última', 'Last')}: ${formatDate(s.settings.lastBackupAt!, 'dd MMM yyyy HH:mm', spanish: s.settings.spanish)}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                                await s.ledger.flush();
                                await s.backups.autoBackup(force: true);
                                await _load();
                              }, failed: t(context, 'No se pudo hacer la copia. Intenta de nuevo.', 'The copy could not be made. Try again.')),
                      icon: const Icon(Icons.save_outlined),
                      label: Text(t(context, 'Hacer copia local ahora', 'Make a local copy now')),
                    ),
                  ),
                  if (_auto.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: TextButton.icon(
                        onPressed: _busy ? null : () => _deleteAuto(s),
                        icon: const Icon(Icons.delete_outline),
                        label: Text(t(context, 'Borrar las copias automáticas', 'Delete the automatic copies')),
                      ),
                    ),
                ] else if (_auto.isNotEmpty)
                  Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 4), child: Text(t(context, 'Copias automáticas en este teléfono', 'Automatic copies on this phone'), style: Theme.of(context).textTheme.titleSmall)),
                for (final String rel in _auto)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.restore_page_outlined),
                    title: Text(backupLabel(context, rel)),
                    trailing: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _restore(() async {
                                final Map<String, dynamic>? d = await s.backups.readAutoBackup(rel);
                                if (d == null) {
                                  throw const FormatException('Copia vacía');
                                }
                                LedgerSnapshot.parse(d);
                                return d;
                              }, s),
                      child: Text(t(context, 'Restaurar', 'Restore')),
                    ),
                  ),
                if (recovery) ...<Widget>[
                  const Divider(),
                  ListTile(
                    leading: Icon(Icons.restart_alt, color: cs.error),
                    title: Text(t(context, 'Empezar de cero', 'Start from scratch')),
                    subtitle: Text(t(context, 'Si no tienes copia. Lo que no se pudo abrir queda apartado.', 'If you have no backup. What could not be opened is set aside.')),
                    onTap: _busy ? null : () => _startFresh(s),
                  ),
                ],
              ],
            ),
            if (_busy) const Positioned.fill(child: ColoredBox(color: Color(0x33000000), child: Center(child: CircularProgressIndicator()))),
          ],
        ),
      ),
    );
  }
}
