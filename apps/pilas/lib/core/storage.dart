import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Resultado de leer un archivo JSON.
enum ReadOutcome {
  /// Se leyó bien.
  ok,

  /// No existe (por ejemplo, un perfil nuevo).
  missing,

  /// El archivo estaba dañado y se recuperó desde la copia .bak.
  recovered,

  /// El archivo y su copia estaban dañados: se apartaron y no hay datos.
  corrupt,
}

class JsonRead {
  const JsonRead(this.data, this.outcome, {this.asidePath});

  final Map<String, dynamic>? data;
  final ReadOutcome outcome;

  /// Ruta donde quedó el archivo dañado (`<archivo>.corrupto-<fecha>`).
  final String? asidePath;
}

/// Guarda y lee archivos JSON y binarios en la carpeta de documentos de la app.
///
/// - Las operaciones sobre un mismo archivo van en cola, una detrás de otra:
///   dos guardados seguidos (por ejemplo al pasar a segundo plano) no se pisan.
/// - Cada escritura usa un temporal con nombre único y lo renombra sobre el
///   original (el renombrado reemplaza de forma atómica; nunca hay un momento
///   sin archivo).
/// - Antes de reemplazar un JSON válido se guarda su copia en `<archivo>.bak`.
/// - Al leer, si el archivo está dañado se usa la copia .bak; si las dos lo
///   están, el dañado se aparta como `<archivo>.corrupto-<fecha>` y la lectura
///   lo informa para que el panel de adultos avise. Nunca se reemplaza en
///   silencio un archivo dañado por uno vacío.
class JsonStore {
  JsonStore({Directory? root}) : _rootOverride = root;

  final Directory? _rootOverride;
  Directory? _root;
  final Map<String, Future<void>> _queues = <String, Future<void>>{};
  int _seq = 0;

  Future<Directory> root() async {
    if (_root != null) {
      return _root!;
    }
    final Directory base = _rootOverride ?? await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}${Platform.pathSeparator}pilas');
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

  /// Ejecuta [task] cuando terminen las operaciones anteriores sobre [key].
  Future<T> _enqueue<T>(String key, Future<T> Function() task) {
    final Future<void> previous = _queues[key] ?? Future<void>.value();
    final Completer<T> done = Completer<T>();
    final Future<void> next = previous.then((_) async {
      try {
        done.complete(await task());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    _queues[key] = next;
    unawaited(next.whenComplete(() {
      if (identical(_queues[key], next)) {
        _queues.remove(key);
      }
    }));
    return done.future;
  }

  String _unique() {
    _seq += 1;
    return '${DateTime.now().microsecondsSinceEpoch}-$_seq';
  }

  static Map<String, dynamic>? _decode(List<int> bytes) {
    try {
      final String text = utf8.decode(bytes);
      if (text.trim().isEmpty) {
        return null;
      }
      final dynamic decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      // Bytes que no son UTF-8, JSON cortado o de otro tipo: dañado.
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _tryRead(File f) async {
    try {
      return _decode(await f.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeNow(File file, List<int> bytes, {required bool backup}) async {
    final File tmp = File('${file.path}.${_unique()}.tmp');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      if (backup && await file.exists()) {
        // Solo se respalda un archivo sano, para no cambiar una buena copia
        // por una dañada.
        if (await _tryRead(file) != null) {
          await file.copy('${file.path}.bak');
        }
      }
      await tmp.rename(file.path);
    } catch (e) {
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Aparta un archivo dañado con un nombre que no se reutiliza.
  Future<String> _aside(File f) async {
    final DateTime n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final String stamp = '${n.year}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}${two(n.second)}';
    String target = '${f.path}.corrupto-$stamp';
    int k = 1;
    while (await File(target).exists()) {
      k += 1;
      target = '${f.path}.corrupto-$stamp-$k';
    }
    await f.rename(target);
    return target;
  }

  /// Lee un JSON con recuperación desde la copia de seguridad.
  Future<JsonRead> readJsonSafe(String relativePath) {
    return _enqueue<JsonRead>(relativePath, () async {
      final File file = await _file(relativePath);
      final File bak = File('${file.path}.bak');
      final bool hasMain = await file.exists();
      if (hasMain) {
        final Map<String, dynamic>? data = await _tryRead(file);
        if (data != null) {
          return JsonRead(data, ReadOutcome.ok);
        }
      }
      final bool hasBak = await bak.exists();
      if (hasBak) {
        final Map<String, dynamic>? data = await _tryRead(bak);
        if (data != null) {
          String? aside;
          if (hasMain) {
            aside = await _aside(file);
          }
          await _writeNow(file, utf8.encode(jsonEncode(data)), backup: false);
          return JsonRead(data, ReadOutcome.recovered, asidePath: aside);
        }
      }
      if (!hasMain) {
        if (hasBak) {
          await _aside(bak);
          return const JsonRead(null, ReadOutcome.corrupt);
        }
        return const JsonRead(null, ReadOutcome.missing);
      }
      final String aside = await _aside(file);
      if (hasBak) {
        await _aside(bak);
      }
      return JsonRead(null, ReadOutcome.corrupt, asidePath: aside);
    });
  }

  /// Lee un JSON (null si no existe o si estaba dañado y no se pudo recuperar).
  Future<Map<String, dynamic>?> readJson(String relativePath) async => (await readJsonSafe(relativePath)).data;

  /// Guarda un JSON de forma atómica. Con [sinRastro] (al borrar datos), la
  /// copia `.bak` también queda con el contenido nuevo: lo borrado no se
  /// queda en el respaldo ni puede volver al recuperarlo.
  Future<void> writeJson(String relativePath, Map<String, dynamic> data, {bool sinRastro = false}) {
    final List<int> bytes = utf8.encode(jsonEncode(data));
    return _enqueue<void>(relativePath, () async {
      final File file = await _file(relativePath);
      await _writeNow(file, bytes, backup: !sinRastro);
      if (sinRastro) {
        await _writeNow(File('${file.path}.bak'), bytes, backup: false);
      }
    });
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
      await _writeNow(file, bytes, backup: false);
      return file;
    });
  }

  /// Borra un archivo y su copia de seguridad.
  Future<void> delete(String relativePath) {
    return _enqueue<void>(relativePath, () async {
      final File file = await _file(relativePath);
      for (final File f in <File>[file, File('${file.path}.bak')]) {
        if (await f.exists()) {
          await f.delete();
        }
      }
    });
  }

  /// Borra una carpeta completa (por ejemplo, los dibujos de un perfil).
  Future<void> deleteDir(String relativeDir) async {
    final Directory dir = await root();
    final String sep = Platform.pathSeparator;
    final Directory sub = Directory('${dir.path}$sep${relativeDir.replaceAll('/', sep)}');
    if (await sub.exists()) {
      await sub.delete(recursive: true);
    }
  }

  /// Rutas relativas de los archivos de una carpeta, ordenadas por nombre.
  /// No incluye copias de seguridad, temporales ni archivos apartados.
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
        if (name.endsWith('.bak') || name.endsWith('.tmp') || name.contains('.corrupto-')) {
          continue;
        }
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
    final Directory dir = await root();
    final String sep = Platform.pathSeparator;
    final Directory sub = Directory('${dir.path}$sep${relativeDir.replaceAll('/', sep)}');
    if (!await sub.exists()) {
      return 0;
    }
    await for (final FileSystemEntity e in sub.list()) {
      try {
        await e.delete(recursive: true);
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
