import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Cómo se leyó un JSON guardado.
enum ReadOutcome {
  /// El archivo principal estaba bien (o no existía todavía).
  ok,

  /// El principal faltaba o estaba dañado y se usó la copia anterior (.bak).
  fromBackup,

  /// Ni el principal ni la copia se pudieron leer: se empieza vacío y los
  /// archivos dañados quedan aparte (.danado-…) para no perderlos.
  lost,
}

/// Resultado de [JsonStore.readJsonChecked].
class JsonRead {
  const JsonRead(this.data, this.outcome);

  final Map<String, dynamic>? data;
  final ReadOutcome outcome;
}

/// Guarda y lee archivos JSON y binarios en la carpeta de documentos de la app.
///
/// Las escrituras de una misma ruta van en cola (una después de otra) y son
/// atómicas: se escribe un temporal con nombre único, se sincroniza con el
/// disco y se renombra sobre el archivo (en Android e iOS `rename` reemplaza
/// de una vez). Antes de reemplazar un JSON se guarda la versión anterior en
/// `<archivo>.bak`, que es la que se usa si el principal llega dañado.
class JsonStore {
  JsonStore({Directory? root}) : _rootOverride = root;

  final Directory? _rootOverride;
  Directory? _root;

  /// Última tarea en cola por ruta relativa.
  final Map<String, Future<void>> _queues = <String, Future<void>>{};
  int _tmpCounter = 0;

  Future<Directory> root() async {
    if (_root != null) {
      return _root!;
    }
    final Directory base = _rootOverride ?? await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}${Platform.pathSeparator}sello');
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

  /// Ejecuta [task] cuando terminen las tareas anteriores de la misma ruta.
  Future<T> _serialized<T>(String relativePath, Future<T> Function() task) {
    final Future<void> previous = _queues[relativePath] ?? Future<void>.value();
    final Completer<T> done = Completer<T>();
    final Future<void> next = previous.then((_) async {
      try {
        done.complete(await task());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    _queues[relativePath] = next;
    // Cuando la cola queda vacía se olvida la ruta.
    unawaited(next.then((_) {
      if (identical(_queues[relativePath], next)) {
        _queues.remove(relativePath);
      }
    }));
    return done.future;
  }

  String _uniqueSuffix() {
    _tmpCounter += 1;
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$_tmpCounter';
  }

  /// Escribe [bytes] en [file] de forma atómica (temporal único + rename).
  Future<File> _writeAtomic(File file, List<int> bytes, {bool keepBackup = false}) async {
    final File tmp = File('${file.path}.tmp-${_uniqueSuffix()}');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      if (keepBackup && await file.exists()) {
        // La versión anterior pasa a .bak, también de forma atómica.
        final File bakTmp = File('${file.path}.bak.tmp-${_uniqueSuffix()}');
        await file.copy(bakTmp.path);
        await bakTmp.rename('${file.path}.bak');
      }
      return await tmp.rename(file.path);
    } catch (_) {
      try {
        if (await tmp.exists()) {
          await tmp.delete();
        }
      } catch (_) {}
      rethrow;
    }
  }

  static Map<String, dynamic>? _decode(String text) {
    if (text.trim().isEmpty) {
      return null;
    }
    final dynamic decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const FormatException('El JSON no es un objeto');
  }

  /// Lee un JSON. Si el archivo está dañado usa la copia anterior; ver
  /// [readJsonChecked] para saber qué pasó.
  Future<Map<String, dynamic>?> readJson(String relativePath) async => (await readJsonChecked(relativePath)).data;

  /// Lee un JSON e informa si tuvo que recurrir a la copia (.bak) o si no
  /// se pudo recuperar. Los archivos dañados se apartan con otro nombre en
  /// vez de borrarse, para que la siguiente escritura no los pise.
  Future<JsonRead> readJsonChecked(String relativePath) {
    return _serialized<JsonRead>(relativePath, () async {
      final File file = await _file(relativePath);
      final File bak = File('${file.path}.bak');
      bool mainBroken = false;
      if (await file.exists()) {
        try {
          final Map<String, dynamic>? data = _decode(await file.readAsString());
          if (data != null) {
            return JsonRead(data, ReadOutcome.ok);
          }
          mainBroken = true;
        } on FormatException {
          mainBroken = true;
        } on FileSystemException {
          mainBroken = true;
        }
      } else if (!await bak.exists()) {
        // Nunca se guardó: primera vez.
        return const JsonRead(null, ReadOutcome.ok);
      }
      if (mainBroken) {
        await _setAside(file);
      }
      if (await bak.exists()) {
        try {
          final Map<String, dynamic>? data = _decode(await bak.readAsString());
          if (data != null) {
            // La copia vuelve a ser el principal.
            await _writeAtomic(file, utf8.encode(jsonEncode(data)));
            return JsonRead(data, ReadOutcome.fromBackup);
          }
        } on FormatException {
          await _setAside(bak);
        } on FileSystemException {
          await _setAside(bak);
        }
      }
      return const JsonRead(null, ReadOutcome.lost);
    });
  }

  Future<void> _setAside(File f) async {
    try {
      if (await f.exists()) {
        await f.rename('${f.path}.danado-${_uniqueSuffix()}');
      }
    } catch (_) {}
  }

  /// Guarda [data] como JSON: en cola por ruta, atómico y con copia .bak de
  /// la versión anterior.
  Future<void> writeJson(String relativePath, Map<String, dynamic> data) {
    final List<int> bytes = utf8.encode(jsonEncode(data));
    return _serialized<void>(relativePath, () async {
      await _writeAtomic(await _file(relativePath), bytes, keepBackup: true);
    });
  }

  Future<Uint8List?> readBytes(String relativePath) async {
    final File file = await _file(relativePath);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  /// Guarda bytes de forma atómica (en cola por ruta).
  Future<File> writeBytes(String relativePath, List<int> bytes) {
    return _serialized<File>(relativePath, () async => _writeAtomic(await _file(relativePath), bytes));
  }

  Future<void> delete(String relativePath) {
    return _serialized<void>(relativePath, () async {
      final File file = await _file(relativePath);
      if (await file.exists()) {
        await file.delete();
      }
    });
  }

  Future<bool> exists(String relativePath) async => (await _file(relativePath)).exists();

  /// Rutas relativas de los archivos de una carpeta, ordenadas por nombre.
  /// Con [recursive] incluye las subcarpetas.
  Future<List<String>> list(String relativeDir, {String? extension, bool recursive = false}) async {
    final Directory dir = await root();
    final String sep = Platform.pathSeparator;
    final Directory sub = Directory('${dir.path}$sep${relativeDir.replaceAll('/', sep)}');
    if (!await sub.exists()) {
      return <String>[];
    }
    final String prefix = '${dir.path}$sep';
    final List<String> out = <String>[];
    await for (final FileSystemEntity e in sub.list(recursive: recursive)) {
      if (e is File) {
        final String name = e.uri.pathSegments.last;
        if (extension == null || name.toLowerCase().endsWith(extension)) {
          out.add(e.path.startsWith(prefix) ? e.path.substring(prefix.length).replaceAll(sep, '/') : '$relativeDir/$name');
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
    for (final String rel in await list(relativeDir, recursive: true)) {
      try {
        await delete(rel);
        n++;
      } catch (_) {
        // Un archivo en uso se borra la próxima vez.
      }
    }
    return n;
  }

  /// Borra los temporales que dejó una escritura interrumpida.
  Future<void> cleanTemporaries(String relativeDir) async {
    for (final String rel in await list(relativeDir, recursive: true)) {
      if (rel.contains('.tmp-')) {
        try {
          await delete(rel);
        } catch (_) {}
      }
    }
  }

  Future<String> absolutePath(String relativePath) async {
    final File file = await _file(relativePath);
    return file.path;
  }
}
