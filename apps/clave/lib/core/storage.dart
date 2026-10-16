import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Guarda y lee archivos JSON y binarios en la carpeta de documentos de la app.
/// Las escrituras son atómicas: se escribe un archivo temporal y se renombra.
class JsonStore {
  JsonStore({Directory? root}) : _rootOverride = root;

  final Directory? _rootOverride;
  Directory? _root;

  Future<Directory> root() async {
    if (_root != null) {
      return _root!;
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
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
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

  Future<String> absolutePath(String relativePath) async {
    final File file = await _file(relativePath);
    return file.path;
  }
}
