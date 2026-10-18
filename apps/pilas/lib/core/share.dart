import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'storage.dart';

/// Función que abre la hoja de compartir del sistema (se puede reemplazar en
/// las pruebas).
typedef ShareFn = Future<ShareResult> Function(ShareParams params);

/// Compartir archivos con la hoja del sistema, siempre con el origen del
/// botón que se tocó (el iPad lo exige para abrir el globo, y el iPhone con
/// iOS 26 también) y con un aviso visible si algo falla.
class Sharer {
  Sharer({ShareFn? share}) : _share = share ?? SharePlus.instance.share;

  final ShareFn _share;

  /// Rectángulo en pantalla del widget de [context] (el botón tocado).
  static Rect originOf(BuildContext context) {
    final RenderObject? ro = context.findRenderObject();
    if (ro is RenderBox && ro.hasSize && ro.attached) {
      return ro.localToGlobal(Offset.zero) & ro.size;
    }
    // Sin caja (no debería pasar): el centro de la pantalla.
    final Size s = MediaQuery.sizeOf(context);
    return Rect.fromCenter(center: Offset(s.width / 2, s.height / 2), width: 1, height: 1);
  }

  /// Comparte [files]. [buttonContext] es el contexto del botón que se tocó.
  /// Devuelve true si la hoja se abrió; si falla, muestra un aviso.
  Future<bool> shareFiles(BuildContext buttonContext, List<XFile> files, {String? text}) async {
    final Rect origin = originOf(buttonContext);
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(buttonContext);
    try {
      await _share(ShareParams(files: files, text: text, sharePositionOrigin: origin));
      return true;
    } catch (e) {
      debugPrint('No se pudo compartir: $e');
      messenger?.showSnackBar(const SnackBar(content: Text('No se pudo abrir la hoja de compartir. Inténtalo de nuevo.')));
      return false;
    }
  }

  /// Guarda [bytes] en la carpeta de exportación (se vacía al abrir la app)
  /// con un nombre seguro y lo comparte. [baseName] no lleva extensión.
  Future<bool> shareBytes(BuildContext buttonContext, JsonStore store, List<int> bytes, {required String baseName, required String extension, required String mimeType, String? text}) async {
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(buttonContext);
    String path;
    try {
      final File f = await store.writeBytes('export/${safeFileName(baseName)}.$extension', bytes);
      path = f.path;
    } catch (e) {
      debugPrint('No se pudo preparar el archivo: $e');
      messenger?.showSnackBar(const SnackBar(content: Text('No se pudo preparar el archivo para compartir.')));
      return false;
    }
    if (!buttonContext.mounted) {
      return false;
    }
    return shareFiles(buttonContext, <XFile>[XFile(path, mimeType: mimeType)], text: text);
  }

  /// Nombre de archivo seguro a partir de un nombre que puso un adulto
  /// (sin barras, tildes ni signos que rompan la ruta).
  static String safeFileName(String base) {
    const Map<String, String> sin = <String, String>{'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
    final StringBuffer b = StringBuffer();
    for (final int r in base.toLowerCase().runes) {
      final String ch = String.fromCharCode(r);
      final String plano = sin[ch] ?? ch;
      if (RegExp('[a-z0-9]').hasMatch(plano)) {
        b.write(plano);
      } else if (b.isNotEmpty && !b.toString().endsWith('-')) {
        b.write('-');
      }
    }
    String out = b.toString();
    while (out.endsWith('-')) {
      out = out.substring(0, out.length - 1);
    }
    return out.isEmpty ? 'pilas' : out;
  }

  /// Borra las copias temporales que deja la hoja de compartir de Android
  /// (carpeta share_plus de la caché de la app). En iOS no existe.
  static Future<void> clearShareCache() async {
    try {
      final Directory tmp = await getTemporaryDirectory();
      final Directory d = Directory('${tmp.path}${Platform.pathSeparator}share_plus');
      if (await d.exists()) {
        await d.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('No se pudo limpiar la caché de compartir: $e');
    }
  }
}
