import 'dart:io';

import 'package:camera/camera.dart' show CameraException;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device_files.dart';

/// El teléfono (o el destino elegido) se quedó sin espacio, venga de Dart
/// (errno 28) o del canal nativo.
bool isNoSpaceError(Object e) {
  if (e is DocumentNoSpace) {
    return true;
  }
  if (e is FileSystemException && e.osError?.errorCode == 28) {
    return true;
  }
  if (e is PlatformException && e.code == 'nospace') {
    return true;
  }
  final String text = e.toString();
  return text.contains('ENOSPC') || text.contains('No space left');
}

/// Por qué falló algo, en palabras de la app y en su idioma, para
/// completar un mensaje («No se pudo compartir: …»). El texto técnico de la
/// excepción o del complemento nunca va a la pantalla: queda en el registro
/// de depuración.
String errorReason(Object e, {required bool spanish}) {
  debugPrint('Detalle del error: $e');
  String k(String es, String en) => spanish ? es : en;
  if (isNoSpaceError(e)) {
    return k('el teléfono se quedó sin espacio', 'the phone ran out of space');
  }
  if (e is FileSystemException || e is IOException) {
    return k('no se pudo leer o escribir un archivo', 'a file could not be read or written');
  }
  if (e is CameraException) {
    return k('la cámara no respondió', 'the camera did not respond');
  }
  if (e is PlatformException || e is MissingPluginException) {
    return k('el sistema no lo permitió', 'the system did not allow it');
  }
  return k('ocurrió un error inesperado', 'an unexpected error occurred');
}
