import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';

/// Copia de las fotos selladas en la fototeca del sistema, con el permiso
/// mínimo de cada plataforma.
///
/// - Android: álbum "Sello". Desde Android 11 no pide ningún permiso; hasta
///   Android 10 pide el de almacenamiento (declarado con `maxSdkVersion` 29 y
///   `requestLegacyExternalStorage` para Android 10).
/// - iOS: sin álbum. Buscar o crear un álbum exige acceso completo a la
///   fototeca; agregar una foto solo pide "Agregar a Fotos", y la app nunca lee
///   la fototeca.
class PhotoLibrary {
  const PhotoLibrary._();

  /// Álbum de destino, o null para la fototeca general (iOS).
  static String? get album => defaultTargetPlatform == TargetPlatform.iOS ? null : 'Sello';

  static bool get _toAlbum => album != null;

  /// Pide el permiso solo si hace falta. Devuelve si se puede copiar.
  static Future<bool> ensureAccess() async {
    if (await Gal.hasAccess(toAlbum: _toAlbum)) {
      return true;
    }
    return Gal.requestAccess(toAlbum: _toAlbum);
  }

  /// Copia [path] a la fototeca. Lanza [PhotoLibraryDenied] sin permiso y la
  /// excepción de `gal` si el sistema no guarda la foto.
  static Future<void> put(String path) async {
    if (!await ensureAccess()) {
      throw const PhotoLibraryDenied();
    }
    await Gal.putImage(path, album: album);
  }
}

/// El usuario no dio permiso para guardar en la fototeca.
class PhotoLibraryDenied implements Exception {
  const PhotoLibraryDenied();

  @override
  String toString() => 'PhotoLibraryDenied: sin permiso para la fototeca';
}
