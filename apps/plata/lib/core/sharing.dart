import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'storage.dart';

/// Comparte archivos con la hoja del sistema.
Future<void> shareFiles(List<String> paths, {String? text, String? subject}) async {
  if (paths.isEmpty) {
    return;
  }
  await SharePlus.instance.share(ShareParams(files: paths.map((String p) => XFile(p)).toList(), text: text, subject: subject));
}

/// Guarda [bytes] en la carpeta de exportaciones y lo comparte.
Future<String> shareBytes(JsonStore store, String fileName, Uint8List bytes, {String? text}) async {
  final String rel = 'exports/$fileName';
  await store.writeBytes(rel, bytes);
  final String path = await store.absolutePath(rel);
  await shareFiles(<String>[path], text: text);
  return path;
}

/// En Android, la hoja de compartir copia cada archivo en <caché>/share_plus y
/// solo vacía esa carpeta al compartir otra vez: ahí quedaría el último CSV,
/// Excel o JSON sin cifrar. Se borra al abrir la app y al borrar todo (no al
/// terminar de compartir: la app que lo recibe puede leerlo más tarde).
Future<void> clearShareCache() async {
  try {
    final Directory tmp = await getTemporaryDirectory();
    final Directory share = Directory('${tmp.path}${Platform.pathSeparator}share_plus');
    if (await share.exists()) {
      await share.delete(recursive: true);
    }
  } catch (e) {
    debugPrint('Caché de compartir: $e');
  }
}
