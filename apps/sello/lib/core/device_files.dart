import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'exports.dart';

/// Documento que eligió el usuario, todavía sin copiar: su dirección en el
/// sistema, su nombre y su tamaño (-1 si el proveedor no lo dice).
class PickedDocument {
  const PickedDocument({required this.uri, required this.name, required this.size});

  final String uri;
  final String name;
  final int size;
}

/// La copia del documento se canceló.
class DocumentCopyCancelled implements Exception {
  const DocumentCopyCancelled();
}

/// No hay espacio en el teléfono para copiar el documento.
class DocumentNoSpace implements Exception {
  const DocumentNoSpace();
}

/// Archivos del sistema por el canal propio co.appsgratis.sello/files (ver
/// native/android/MainActivity.kt y native/ios/AppDelegate.swift).
///
/// - Android: la copia completa se guarda donde el usuario elija y se abre
///   desde donde la tenga con el selector de documentos del sistema,
///   copiando el flujo en un hilo aparte: el archivo nunca pasa entero por
///   la memoria (el selector de archivos de Flutter lo leía completo).
/// - Android e iOS: el espacio libre.
class DeviceFiles {
  const DeviceFiles();

  static const MethodChannel _channel = MethodChannel('co.appsgratis.sello/files');

  /// En Android la copia completa usa el selector de documentos propio; en
  /// iOS, la hoja de compartir y el selector de archivos (que ya copian en
  /// disco).
  bool get usesDocumentPicker => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Bytes libres donde la app guarda sus datos, o null si no se sabe.
  Future<int?> freeBytes() async {
    try {
      final Object? v = await _channel.invokeMethod<Object>('freeBytes');
      return v is int ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// Pide al usuario dónde guardar [sourcePath] (con el nombre [name]) y lo
  /// copia allí. Falso si cancela.
  Future<bool> saveDocument(String sourcePath, String name, {String mime = 'application/zip'}) async {
    final Object? ok = await _channel.invokeMethod<Object>('saveDocument', <String, Object>{'source': sourcePath, 'name': name, 'mime': mime});
    return ok == true;
  }

  /// iPhone: el selector de archivos del sistema, que copia el ZIP elegido a
  /// la carpeta temporal de la app (`asCopy`). Devuelve esa copia; null si
  /// cancela.
  Future<String?> pickZipCopy() async {
    const XTypeGroup zip = XTypeGroup(label: 'ZIP', extensions: <String>['zip'], mimeTypes: <String>['application/zip', 'application/x-zip-compressed'], uniformTypeIdentifiers: <String>['public.zip-archive']);
    return (await openFile(acceptedTypeGroups: <XTypeGroup>[zip]))?.path;
  }

  /// Carpetas temporales de la app. En iPhone, la copia del selector queda
  /// en `tmp/<bundle>-Inbox` del contenedor (TMPDIR, [Directory.systemTemp]);
  /// `getTemporaryDirectory()` es `Library/Caches`, otra carpeta.
  Future<List<String>> temporaryDirs() async {
    final List<String> dirs = <String>[Directory.systemTemp.path];
    try {
      dirs.add((await getTemporaryDirectory()).path);
    } catch (_) {}
    return dirs;
  }

  /// Borra la copia que dejó [pickZipCopy], solo si está dentro de una
  /// carpeta temporal de la app (nunca un archivo del usuario), y la
  /// carpeta `…-Inbox` que la contenía si quedó vacía.
  Future<void> deletePickedCopy(String path) async {
    try {
      if (!isPickerCopy(path, await temporaryDirs())) {
        debugPrint('No se borra (no está en una carpeta temporal): $path');
        return;
      }
      final File f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
      final Directory parent = f.parent;
      if (parent.path.endsWith('-Inbox') && await parent.exists() && await parent.list().isEmpty) {
        await parent.delete();
      }
    } catch (e) {
      debugPrint('No se pudo borrar la copia del selector: $e');
    }
  }

  /// Pide al usuario un documento, sin copiarlo todavía. Null si cancela.
  Future<PickedDocument?> pickDocument({List<String> mimes = const <String>['application/zip', 'application/x-zip-compressed', 'application/octet-stream']}) async {
    final Map<Object?, Object?>? r = await _channel.invokeMapMethod<Object?, Object?>('pickDocument', <String, Object>{'mimes': mimes});
    if (r == null) {
      return null;
    }
    final Object? uri = r['uri'];
    final Object? name = r['name'];
    final Object? size = r['size'];
    if (uri is! String) {
      return null;
    }
    return PickedDocument(uri: uri, name: name is String ? name : '', size: size is int ? size : -1);
  }

  static void Function(int done, int total)? _onProgress;

  /// Copia [doc] a [targetPath] en un hilo aparte, de a 1 MB, avisando el
  /// avance a [onProgress]. Lanza [DocumentCopyCancelled] si [cancel] se
  /// activa y [DocumentNoSpace] si el teléfono se queda sin espacio; el
  /// archivo a medias se borra.
  Future<int> copyDocument(PickedDocument doc, String targetPath, {void Function(int done, int total)? onProgress, ExportCancel? cancel}) async {
    _onProgress = onProgress;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'copyProgress') {
        final Object? args = call.arguments;
        if (args is Map) {
          final Object? done = args['done'];
          final Object? total = args['total'];
          _onProgress?.call(done is int ? done : 0, total is int ? total : doc.size);
        }
      }
      return null;
    });
    cancel?.whenCancelled(() => unawaited(_channel.invokeMethod<void>('cancelCopy').catchError((Object _) {})));
    if (cancel?.cancelled ?? false) {
      throw const DocumentCopyCancelled();
    }
    try {
      final Object? n = await _channel.invokeMethod<Object>('copyDocument', <String, Object>{'uri': doc.uri, 'target': targetPath, 'size': doc.size});
      return n is int ? n : 0;
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') {
        throw const DocumentCopyCancelled();
      }
      if (e.code == 'nospace') {
        throw const DocumentNoSpace();
      }
      rethrow;
    } finally {
      cancel?.whenCancelled(null);
      _onProgress = null;
    }
  }
}

/// Verdadero si [path] está dentro de alguna de [tempDirs] (y no es la
/// carpeta misma). Las rutas de iOS llegan a veces con `/private` delante
/// (`/private/var/mobile/…`) y a veces sin él: se comparan sin ese prefijo.
bool isPickerCopy(String path, Iterable<String> tempDirs) {
  String norm(String p) {
    String s = p.replaceAll('\\', '/');
    if (s.startsWith('/private/')) {
      s = s.substring('/private'.length);
    }
    while (s.length > 1 && s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  final String file = norm(path);
  if (file.split('/').contains('..')) {
    return false;
  }
  for (final String d in tempDirs) {
    final String dir = norm(d);
    if (dir.length > 1 && file.startsWith('$dir/')) {
      return true;
    }
  }
  return false;
}
