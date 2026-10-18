import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Guarda y lee archivos JSON y binarios en la carpeta privada de la app
/// (Application Support en iOS, `files` en Android): no se ve en la app
/// Archivos y el sistema no la copia a la nube (ver docs/DECISIONES.md).
///
/// Las escrituras son atómicas: se escribe un temporal con nombre único, se
/// fuerza a disco y se renombra encima del archivo final. En Android e iOS el
/// renombrado reemplaza el destino de una vez, así que nunca hay un momento
/// sin archivo: si el proceso muere a mitad, queda el archivo anterior entero
/// (y quizá un temporal que [Ledger.load] sabe recuperar).
class JsonStore {
  JsonStore({Directory? root}) : _rootOverride = root;

  final Directory? _rootOverride;
  Directory? _root;
  static final Random _random = Random();

  /// Mueve los datos de la carpeta vieja [old] a [dir] si la nueva todavía no
  /// tiene libro. En iOS el AppDelegate crea [dir] al arrancar (para sacarla
  /// de la copia de iCloud) antes de que llegue Dart, así que "la carpeta nueva
  /// no existe" no sirve para decidir: lo que cuenta es si ya tiene
  /// `ledger.json`. Se mueve entrada por entrada sin pisar nada de la nueva.
  /// Devuelve si movió algo.
  static Future<bool> migrateLegacy(Directory old, Directory dir) async {
    if (!await old.exists()) {
      return false;
    }
    final String sep = Platform.pathSeparator;
    if (await File('${dir.path}${sep}ledger.json').exists()) {
      return false;
    }
    await dir.create(recursive: true);
    bool moved = false;
    await for (final FileSystemEntity e in old.list()) {
      final String name = e.uri.pathSegments.where((String s) => s.isNotEmpty).last;
      final String target = '${dir.path}$sep$name';
      if (await FileSystemEntity.type(target) != FileSystemEntityType.notFound) {
        continue;
      }
      await e.rename(target);
      moved = true;
    }
    try {
      if (await old.list().isEmpty) {
        await old.delete();
      }
    } catch (_) {
      // Si queda algo en la vieja, se deja.
    }
    return moved;
  }

  /// Sufijo de los temporales: `<archivo>.<azar>.tmp`.
  static const String tmpSuffix = '.tmp';

  Future<Directory> root() async {
    if (_root != null) {
      return _root!;
    }
    final String sep = Platform.pathSeparator;
    final Directory base = _rootOverride ?? await getApplicationSupportDirectory();
    final Directory dir = Directory('${base.path}${sep}plata');
    if (_rootOverride == null) {
      // Las versiones de prueba guardaban en Documentos: se mueve una sola vez.
      try {
        await migrateLegacy(Directory('${(await getApplicationDocumentsDirectory()).path}${sep}plata'), dir);
      } catch (_) {
        // Si no se puede mover, se empieza en la carpeta nueva; la vieja queda intacta.
      }
    }
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

  /// Nombre de un temporal único junto a [file].
  static File _tmpFor(File file) => File('${file.path}.${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_random.nextInt(1 << 32).toRadixString(36)}$tmpSuffix');

  Future<bool> exists(String relativePath) async => (await _file(relativePath)).exists();

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

  Future<void> writeJson(String relativePath, Map<String, dynamic> data) => writeBytes(relativePath, utf8.encode(jsonEncode(data)));

  Future<Uint8List?> readBytes(String relativePath) async {
    final File file = await _file(relativePath);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  Future<File> writeBytes(String relativePath, List<int> bytes) async {
    final File file = await _file(relativePath);
    final File tmp = _tmpFor(file);
    try {
      await tmp.writeAsBytes(bytes, flush: true);
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

  Future<void> delete(String relativePath) async {
    final File file = await _file(relativePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Mueve un archivo dentro de la carpeta de la app (reemplaza el destino).
  Future<void> move(String fromRelative, String toRelative) async {
    final File from = await _file(fromRelative);
    if (!await from.exists()) {
      return;
    }
    final File to = await _file(toRelative);
    await from.rename(to.path);
  }

  /// Rutas relativas de los archivos de una carpeta ('' es la raíz), ordenadas
  /// por nombre.
  Future<List<String>> list(String relativeDir, {String? extension, String? prefix}) async {
    final Directory dir = await root();
    final String sep = Platform.pathSeparator;
    final Directory sub = relativeDir.isEmpty ? dir : Directory('${dir.path}$sep${relativeDir.replaceAll('/', sep)}');
    if (!await sub.exists()) {
      return <String>[];
    }
    final List<String> out = <String>[];
    await for (final FileSystemEntity e in sub.list()) {
      if (e is File) {
        final String name = e.uri.pathSegments.last;
        if ((extension == null || name.endsWith(extension)) && (prefix == null || name.startsWith(prefix))) {
          out.add(relativeDir.isEmpty ? name : '$relativeDir/$name');
        }
      }
    }
    out.sort();
    return out;
  }

  /// Fecha de modificación de un archivo (null si no existe).
  Future<DateTime?> modified(String relativePath) async {
    final File file = await _file(relativePath);
    if (!await file.exists()) {
      return null;
    }
    return file.lastModified();
  }

  /// Borra todos los archivos de una carpeta (por ejemplo, las exportaciones
  /// ya compartidas, que no van cifradas).
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

  /// Borra todo lo que la app guarda en su carpeta (datos, copias, fotos y
  /// exportaciones) y deja la carpeta vacía.
  Future<void> wipe() async {
    final Directory dir = await root();
    if (await dir.exists()) {
      await for (final FileSystemEntity e in dir.list()) {
        try {
          await e.delete(recursive: true);
        } catch (_) {
          // Lo que no se pueda borrar ahora (un archivo abierto) se reintenta
          // en el siguiente borrado; los datos ya no se pueden leer sin la llave.
        }
      }
    } else {
      await dir.create(recursive: true);
    }
  }

  Future<String> absolutePath(String relativePath) async {
    final File file = await _file(relativePath);
    return file.path;
  }
}
