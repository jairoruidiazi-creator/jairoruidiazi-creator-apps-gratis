import 'package:app_settings/app_settings.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart' hide XFile;

/// Tipos que acepta "Importar preajustes": la App Store y Android filtran por
/// el tipo uniforme y el tipo MIME; la extensión sirve en el resto.
const XTypeGroup kJsonTypeGroup = XTypeGroup(
  label: 'JSON',
  extensions: <String>['json'],
  mimeTypes: <String>['application/json'],
  uniformTypeIdentifiers: <String>['public.json'],
);

/// Rectángulo global del widget de [context] (el botón que se tocó): en iPad
/// la hoja de compartir sale de ahí, y en iPhone evita el error de
/// share_plus cuando el origen está vacío.
Rect? shareOriginOf(BuildContext context) {
  final RenderObject? ro = context.findRenderObject();
  if (ro is RenderBox && ro.hasSize && ro.attached) {
    final Offset o = ro.localToGlobal(Offset.zero);
    final Rect r = o & ro.size;
    if (r.width > 0 && r.height > 0) {
      return r;
    }
  }
  return null;
}

/// Acciones del sistema que la app usa: compartir, elegir un archivo y abrir
/// sus ajustes. Separadas para poder probarlas sin plataforma.
abstract class PlatformActions {
  Future<void> share(ShareParams params);

  /// Abre el selector de archivos para un JSON de preajustes.
  Future<XFile?> pickJsonFile();

  /// Abre los ajustes de la app en el sistema (permiso de micrófono).
  Future<void> openAppSettings();
}

class DevicePlatformActions implements PlatformActions {
  const DevicePlatformActions();

  @override
  Future<void> share(ShareParams params) async {
    await SharePlus.instance.share(params);
  }

  @override
  Future<XFile?> pickJsonFile() => openFile(acceptedTypeGroups: const <XTypeGroup>[kJsonTypeGroup]);

  @override
  Future<void> openAppSettings() => AppSettings.openAppSettings();
}
