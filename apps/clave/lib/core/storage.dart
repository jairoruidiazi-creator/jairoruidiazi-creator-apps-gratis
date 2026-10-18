import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Aviso para la persona cuando un archivo de datos llegó dañado.
class StoreNotice {
  const StoreNotice({required this.file, required this.recovered, this.keptAs});

  /// Ruta relativa del archivo (por ejemplo "presets.json").
  final String file;

  /// true si se recuperó la copia anterior (.bak).
  final bool recovered;

  /// Nombre con el que quedó apartado el archivo dañado.
  final String? keptAs;
}

/// Guarda y lee archivos JSON y binarios en la carpeta de documentos de la app.
///
/// Cada escritura de una ruta espera a la anterior (cola por ruta), se hace en
/// un temporal con nombre único y se renombra encima del original, que antes
/// se copia a `.bak`; el original nunca se borra antes de tener el nuevo. Al
/// leer, un JSON dañado no se pisa en silencio: se aparta como
/// `<archivo>.danado-<fecha>`, se recupera la copia `.bak` si sirve y queda un
/// aviso en [notices] para mostrarlo.
class JsonStore {
  JsonStore({Directory? root}) : _rootOverride = root;

  final Directory? _rootOverride;
  Directory? _root;
  final Map<String, Future<void>> _queues = <String, Future<void>>{};
  int _tmpCounter = 0;

  /// Archivos que llegaron dañados en esta ejecución.
  final List<StoreNotice> notices = <StoreNotice>[];

  Future<Directory> root() async {
    final Directory? cached = _root;
    if (cached != null) {
      return cached;
    }
    final Directory base = _rootOverride ?? await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}${Platform.pathSeparator}clave');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _root = dir;
    return dir;
  }

  Future<File> _file(String relativePath) async {
    final Directory dir = await root();
    final String sep = Platform.pathSeparator;
    final String path = '${dir.path}$sep${relativePath.replaceAll('/', sep)}';
    final File file = File(path);
    final Directory parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    return file;
  }

  /// Ejecuta [op] cuando terminen las operaciones pendientes sobre [key].
  Future<T> _enqueue<T>(String key, Future<T> Function() op) {
    final Future<void> previous = _queues[key] ?? Future<void>.value();
    final Future<T> next = previous.catchError((Object _) {}).then((_) => op());
    final Future<void> tail = next.then<void>((T _) {}, onError: (Object _) {});
    _queues[key] = tail;
    unawaited(tail.whenComplete(() {
      if (identical(_queues[key], tail)) {
        _queues.remove(key);
      }
    }));
    return next;
  }

  /// Espera a que terminen las escrituras pendientes (para pruebas y al cerrar).
  Future<void> flush() async {
    while (_queues.isNotEmpty) {
      await Future.wait(_queues.values.toList());
    }
  }

  Future<Map<String, dynamic>?> readJson(String relativePath) {
    return _enqueue<Map<String, dynamic>?>(relativePath, () => _readJson(relativePath));
  }

  Future<Map<String, dynamic>?> _readJson(String relativePath) async {
    final File file = await _file(relativePath);
    final File bak = File('${file.path}.bak');
    final _Parsed main = await _parse(file);
    if (main.data != null) {
      return main.data;
    }
    if (main.state == _ParseState.missing && !await bak.exists()) {
      return null;
    }
    // El archivo falta o está dañado: se aparta y se prueba la copia anterior.
    String? keptAs;
    if (main.state == _ParseState.corrupt) {
      final String stamp = clock.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final String target = '${file.path}.danado-$stamp';
      try {
        await file.rename(target);
        keptAs = target.split(Platform.pathSeparator).last;
      } catch (e) {
        debugPrint('No se pudo apartar $relativePath dañado: $e');
      }
    }
    final _Parsed backup = await _parse(bak);
    final Map<String, dynamic>? data = backup.data;
    if (main.state == _ParseState.corrupt || data != null) {
      notices.add(StoreNotice(file: relativePath, recovered: data != null, keptAs: keptAs));
    }
    if (data != null) {
      // La copia buena vuelve a ser el archivo principal.
      try {
        await _writeTextUnqueued(file, jsonEncode(data), keepBackup: false);
      } catch (e) {
        debugPrint('No se pudo restaurar $relativePath: $e');
      }
    }
    return data;
  }

  Future<_Parsed> _parse(File file) async {
    if (!await file.exists()) {
      return const _Parsed(_ParseState.missing, null);
    }
    try {
      final String text = await file.readAsString();
      if (text.trim().isEmpty) {
        return const _Parsed(_ParseState.corrupt, null);
      }
      final dynamic decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return _Parsed(_ParseState.ok, decoded);
      }
      return const _Parsed(_ParseState.corrupt, null);
    } on FormatException {
      return const _Parsed(_ParseState.corrupt, null);
    } on FileSystemException {
      return const _Parsed(_ParseState.corrupt, null);
    }
  }

  Future<void> writeJson(String relativePath, Map<String, dynamic> data) {
    // Se codifica ya: lo que se guarda es el estado de este momento.
    final String text = jsonEncode(data);
    return _enqueue<void>(relativePath, () async {
      final File file = await _file(relativePath);
      await _writeTextUnqueued(file, text, keepBackup: true);
    });
  }

  String _tmpPath(File file) => '${file.path}.$pid-${++_tmpCounter}.tmp';

  Future<void> _writeTextUnqueued(File file, String text, {required bool keepBackup}) async {
    final File tmp = File(_tmpPath(file));
    await tmp.writeAsString(text, flush: true);
    if (keepBackup && await file.exists()) {
      try {
        final File bakTmp = File(_tmpPath(file));
        await file.copy(bakTmp.path);
        await bakTmp.rename('${file.path}.bak');
      } catch (e) {
        // La copia de respaldo es de mejor esfuerzo: el guardado sigue.
        debugPrint('No se pudo copiar el respaldo de ${file.path}: $e');
      }
    }
    await tmp.rename(file.path);
  }

  Future<Uint8List?> readBytes(String relativePath) {
    return _enqueue<Uint8List?>(relativePath, () async {
      final File file = await _file(relativePath);
      if (!await file.exists()) {
        return null;
      }
      return file.readAsBytes();
    });
  }

  Future<File> writeBytes(String relativePath, List<int> bytes) {
    return _enqueue<File>(relativePath, () async {
      final File file = await _file(relativePath);
      final File tmp = File(_tmpPath(file));
      await tmp.writeAsBytes(bytes, flush: true);
      return tmp.rename(file.path);
    });
  }

  Future<void> delete(String relativePath) {
    return _enqueue<void>(relativePath, () async {
      final File file = await _file(relativePath);
      if (await file.exists()) {
        await file.delete();
      }
    });
  }

  Future<bool> exists(String relativePath) async {
    final File file = await _file(relativePath);
    return file.exists();
  }

  Future<int> size(String relativePath) async {
    final File file = await _file(relativePath);
    if (!await file.exists()) {
      return 0;
    }
    return file.length();
  }

  /// Rutas relativas de los archivos de una carpeta, ordenadas por nombre.
  Future<List<String>> list(String relativeDir, {String? extension}) async {
    final Directory dir = await root();
    final String sep = Platform.pathSeparator;
    final Directory sub = Directory('${dir.path}$sep${relativeDir.replaceAll('/', sep)}');
    if (!await sub.exists()) {
      return <String>[];
    }
    final List<String> out = <String>[];
    await for (final FileSystemEntity e in sub.list()) {
      if (e is File) {
        final String name = e.uri.pathSegments.last;
        if (extension == null || name.endsWith(extension)) {
          out.add('$relativeDir/$name');
        }
      }
    }
    out.sort();
    return out;
  }

  /// Borra todos los archivos de una carpeta (por ejemplo, las exportaciones
  /// que ya se compartieron).
  Future<int> clear(String relativeDir) async {
    int n = 0;
    for (final String rel in await list(relativeDir)) {
      try {
        await delete(rel);
        n++;
      } catch (_) {
        // Un archivo en uso se borra la próxima vez.
      }
    }
    return n;
  }

  Future<String> absolutePath(String relativePath) async {
    final File file = await _file(relativePath);
    return file.path;
  }
}

enum _ParseState { ok, missing, corrupt }

class _Parsed {
  const _Parsed(this.state, this.data);

  final _ParseState state;
  final Map<String, dynamic>? data;
}
