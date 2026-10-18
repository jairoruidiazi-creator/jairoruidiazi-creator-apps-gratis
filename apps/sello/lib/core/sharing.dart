import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import 'storage.dart';

/// Hoja de compartir del sistema. Las pruebas la reemplazan para ver qué se
/// comparte y desde dónde.
@visibleForTesting
Future<ShareResult> Function(ShareParams params) shareSheet = (ShareParams params) => SharePlus.instance.share(params);

/// Rectángulo del widget pulsado, en coordenadas de la pantalla, para anclar
/// la hoja de compartir. En iPad es obligatorio y, al compilar con Xcode 26,
/// también en iPhone: sin él la hoja falla. Si el widget ya no está en
/// pantalla se usa un punto en el centro (nunca un rectángulo vacío).
Rect shareOriginOf(BuildContext context) {
  if (context.mounted) {
    final RenderObject? ro = context.findRenderObject();
    if (ro is RenderBox && ro.attached && ro.hasSize && ro.size.width > 0 && ro.size.height > 0) {
      return ro.localToGlobal(Offset.zero) & ro.size;
    }
    final Size? screen = MediaQuery.maybeSizeOf(context);
    if (screen != null && screen.width > 0 && screen.height > 0) {
      return Rect.fromCenter(center: screen.center(Offset.zero), width: 2, height: 2);
    }
  }
  return const Rect.fromLTWH(0, 0, 2, 2);
}

/// Comparte archivos con la hoja del sistema, anclada en [origin].
Future<ShareResult?> shareFiles(List<String> paths, {required Rect origin, String? text, String? subject}) async {
  if (paths.isEmpty) {
    return null;
  }
  final String? body = text == null || text.trim().isEmpty ? null : text;
  return shareSheet(ShareParams(
    files: <XFile>[for (final String p in paths) XFile(p)],
    text: body,
    subject: subject,
    sharePositionOrigin: origin,
  ));
}

/// Guarda [bytes] en la carpeta de exportaciones y lo comparte.
Future<String> shareBytes(JsonStore store, String fileName, Uint8List bytes, {required Rect origin, String? text}) async {
  final String rel = 'exports/$fileName';
  await store.writeBytes(rel, bytes);
  final String path = await store.absolutePath(rel);
  await shareFiles(<String>[path], origin: origin, text: text);
  return path;
}
