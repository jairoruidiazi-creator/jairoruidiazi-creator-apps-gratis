import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Grupo del selector para restaurar en iOS: sin filtro de extensión ni de
/// tipo (equivale a `public.data`). El archivo se reconoce después por su
/// contenido (`BackupManager.detect`).
const XTypeGroup backupPickerGroup = XTypeGroup(label: 'Plata');

/// Tamaño máximo de un archivo para restaurar. Un libro de 10 000
/// movimientos son unos 3 MB; esto deja margen de sobra.
const int maxBackupBytes = 200 * 1024 * 1024;

/// Canal del selector propio de Android (`MainActivity.kt`).
const MethodChannel backupPickerChannel = MethodChannel('co.appsgratis.plata/files');

/// El archivo elegido pasa del tope: no se leyó.
class BackupTooBig implements Exception {
  const BackupTooBig(this.name);

  final String name;
}

/// El sistema no dejó leer el archivo elegido.
class BackupUnreadable implements Exception {
  const BackupUnreadable(this.name);

  final String name;
}

/// Un archivo elegido para restaurar. Si [isCopy], es una copia que el
/// selector dejó en la carpeta temporal de la app: se borra al leerla.
class PickedBackup {
  const PickedBackup({required this.name, required this.path, this.isCopy = false});

  final String name;
  final String path;
  final bool isCopy;

  /// Lee el archivo y borra la copia temporal, pase lo que pase: una copia
  /// del JSON sin cifrar no debe quedar en la caché.
  Future<Uint8List> readAndDiscard() async {
    try {
      return await File(path).readAsBytes();
    } finally {
      if (isCopy) {
        await _deleteQuietly(File(path));
      }
    }
  }
}

/// Abre el selector del sistema para elegir una copia.
///
/// En Android usa un selector propio en vez de file_selector: ese plugin lee
/// el archivo entero en memoria antes de devolverlo (un video enorme podía
/// cerrar la app antes de cualquier control de tamaño) y deja otra copia en
/// `<caché>/<uuid>/`. El propio mira el tamaño antes de leer, corta la copia
/// si pasa del tope y la deja en `<caché>/restore/`, que se borra al leerla.
Future<PickedBackup?> pickBackupFile({int maxBytes = maxBackupBytes}) async {
  if (defaultTargetPlatform == TargetPlatform.android) {
    final Map<Object?, Object?>? r = await backupPickerChannel.invokeMapMethod<Object?, Object?>('pickBackup', <String, Object>{'maxBytes': maxBytes});
    if (r == null) {
      return null;
    }
    final String name = (r['name'] as String?) ?? '';
    final String? error = r['error'] as String?;
    if (error == 'tooBig') {
      throw BackupTooBig(name);
    }
    final String? path = r['path'] as String?;
    if (error != null || path == null) {
      throw BackupUnreadable(name);
    }
    return PickedBackup(name: name, path: path, isCopy: true);
  }
  final XFile? f = await openFile(acceptedTypeGroups: const <XTypeGroup>[backupPickerGroup]);
  if (f == null) {
    return null;
  }
  // En iOS el selector entrega una copia en tmp/: se mira el tamaño antes de
  // leerla y, si es nuestra, se borra.
  final bool copy = await isInTempDirectory(f.path);
  if (await f.length() > maxBytes) {
    if (copy) {
      await _deleteQuietly(File(f.path));
    }
    throw BackupTooBig(f.name);
  }
  return PickedBackup(name: f.name, path: f.path, isCopy: copy);
}

/// Si [path] está dentro de una carpeta temporal de la app (la caché o, en
/// iOS, `tmp/`): solo eso se borra, nunca el archivo original del usuario.
Future<bool> isInTempDirectory(String path) async {
  final String sep = Platform.pathSeparator;
  final List<String> roots = <String>[Directory.systemTemp.path];
  try {
    roots.add((await getTemporaryDirectory()).path);
  } catch (_) {
    // Sin path_provider (pruebas): basta la carpeta temporal del sistema.
  }
  return roots.any((String r) => path.startsWith(r.endsWith(sep) ? r : '$r$sep'));
}

final RegExp _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

/// Borra las copias de archivos elegidos para restaurar que hayan quedado en
/// la caché: la carpeta `restore/` del selector propio y las carpetas con
/// nombre de UUID que dejaba file_selector en versiones anteriores. Se llama
/// al abrir la app y al borrar todo. [temp] es para las pruebas.
Future<void> clearPickedCopies({Directory? temp}) async {
  try {
    final Directory dir = temp ?? await getTemporaryDirectory();
    if (!await dir.exists()) {
      return;
    }
    await for (final FileSystemEntity e in dir.list()) {
      final String name = e.uri.pathSegments.where((String s) => s.isNotEmpty).last;
      if (e is Directory && (name == 'restore' || _uuid.hasMatch(name))) {
        await e.delete(recursive: true);
      }
    }
  } catch (e) {
    debugPrint('Copias del selector: $e');
  }
}

Future<void> _deleteQuietly(File f) async {
  try {
    if (await f.exists()) {
      await f.delete();
    }
  } catch (e) {
    debugPrint('Borrar copia: $e');
  }
}
