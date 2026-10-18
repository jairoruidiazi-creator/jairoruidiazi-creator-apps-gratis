import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Guarda y lee archivos JSON en la carpeta privada de la app (Application
/// Support en iOS, `files` en Android): no se ve en la app Archivos.
/// Las escrituras son atómicas: se escribe un archivo temporal y se renombra,
/// así un corte a mitad de camino deja el archivo anterior intacto.
class JsonStore {
  JsonStore({Directory? root}) : _rootOverride = root;

  final Directory? _rootOverride;
  Directory? _root;

  Future<Directory> root() async {
    if (_root != null) {
      return _root!;
    }
    final String sep = Platform.pathSeparator;
    final Directory base = _rootOverride ?? await getApplicationSupportDirectory();
    final Directory dir = Directory('${base.path}${sep}rutinas');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _root = dir;
    return dir;
  }

  /// Carpeta ya resuelta (con [root] o con la carpeta de las pruebas): las
  /// lecturas y escrituras síncronas la necesitan.
  Directory _rootSync() {
    final Directory? known = _root ?? _rootOverride;
    if (known == null) {
      throw StateError('JsonStore: llama a root() antes de usar las operaciones síncronas');
    }
    final Directory dir = _root ?? Directory('${known.path}${Platform.pathSeparator}rutinas');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _root = dir;
    return dir;
  }

  File _fileSync(String relativePath) {
    final String sep = Platform.pathSeparator;
    final File file = File('${_rootSync().path}$sep${relativePath.replaceAll('/', sep)}');
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    return file;
  }

  bool existsSync(String relativePath) => _fileSync(relativePath).existsSync();

  /// Lectura síncrona: los datos de la app son pequeños y así se cargan sin
  /// esperas (y las pruebas con reloj falso no dependen de E/S asíncrona).
  Map<String, dynamic>? readJsonSync(String relativePath) {
    final File file = _fileSync(relativePath);
    if (!file.existsSync()) {
      return null;
    }
    try {
      final String text = file.readAsStringSync();
      if (text.trim().isEmpty) {
        return null;
      }
      final dynamic decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// Escritura síncrona y atómica (archivo temporal y renombrado).
  void writeJsonSync(String relativePath, Map<String, dynamic> data) {
    final File file = _fileSync(relativePath);
    final File tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(jsonEncode(data), flush: true);
    tmp.renameSync(file.path);
  }

  String? setAsideSync(String relativePath, String suffix) {
    final File file = _fileSync(relativePath);
    if (!file.existsSync()) {
      return null;
    }
    final String target = '${file.path}.$suffix';
    file.renameSync(target);
    return target;
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

  Future<Map<String, dynamic>?> readJson(String relativePath) async {
    final File file = await _file(relativePath);
    if (!await file.exists()) {
      return null;
    }
    try {
      final String text = await file.readAsString();
      if (text.trim().isEmpty) {
        return null;
      }
      final dynamic decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<void> writeJson(String relativePath, Map<String, dynamic> data) async {
    final File file = await _file(relativePath);
    final File tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    // En Android e iOS el renombrado reemplaza el archivo de una sola vez.
    await tmp.rename(file.path);
  }

  Future<bool> exists(String relativePath) async => (await _file(relativePath)).exists();

  /// Aparta un archivo que no se pudo leer (por ejemplo, dañado por un corte)
  /// para no sobrescribirlo con datos vacíos; queda junto al original.
  Future<String?> setAside(String relativePath, String suffix) async {
    final File file = await _file(relativePath);
    if (!await file.exists()) {
      return null;
    }
    final String target = '${file.path}.$suffix';
    await file.rename(target);
    return target;
  }

  Future<Uint8List?> readBytes(String relativePath) async {
    final File file = await _file(relativePath);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  Future<File> writeBytes(String relativePath, List<int> bytes) async {
    final File file = await _file(relativePath);
    final File tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    return tmp.rename(file.path);
  }

  Future<void> delete(String relativePath) async {
    final File file = await _file(relativePath);
    if (await file.exists()) {
      await file.delete();
    }
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

  /// Borra todos los archivos de una carpeta (por ejemplo, las copias de
  /// seguridad que ya se compartieron).
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
