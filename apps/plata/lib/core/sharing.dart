import 'dart:typed_data';

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
