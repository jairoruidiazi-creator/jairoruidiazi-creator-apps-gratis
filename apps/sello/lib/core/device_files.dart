import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Documento elegido por el usuario y ya copiado a un archivo de la app.
class PickedDocument {
  const PickedDocument({required this.path, required this.name, required this.size});

  final String path;
  final String name;
  final int size;
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

  /// Pide al usuario un documento y lo copia a [targetPath]. Null si cancela.
  Future<PickedDocument?> openDocument(String targetPath, {List<String> mimes = const <String>['application/zip', 'application/x-zip-compressed', 'application/octet-stream']}) async {
    final Map<Object?, Object?>? r = await _channel.invokeMapMethod<Object?, Object?>('openDocument', <String, Object>{'target': targetPath, 'mimes': mimes});
    if (r == null) {
      return null;
    }
    final Object? name = r['name'];
    final Object? size = r['size'];
    return PickedDocument(path: targetPath, name: name is String ? name : '', size: size is int ? size : 0);
  }
}
