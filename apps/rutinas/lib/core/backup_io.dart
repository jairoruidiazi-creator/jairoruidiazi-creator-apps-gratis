import 'package:file_selector/file_selector.dart' as picker;
import 'package:share_plus/share_plus.dart' as share;

/// Entrada y salida de las copias: compartir un archivo con la hoja del
/// sistema y elegir uno para restaurar.
abstract class BackupIO {
  Future<void> shareFile(String path, {required String subject, required String text});

  /// Texto del archivo elegido, o null si se canceló.
  Future<String?> pickText();
}

class DeviceBackupIO implements BackupIO {
  @override
  Future<void> shareFile(String path, {required String subject, required String text}) async {
    await share.SharePlus.instance.share(share.ShareParams(files: <share.XFile>[share.XFile(path, mimeType: 'application/json')], subject: subject, text: text));
  }

  @override
  Future<String?> pickText() async {
    const picker.XTypeGroup group = picker.XTypeGroup(
      label: 'Rutinas',
      extensions: <String>['json'],
      mimeTypes: <String>['application/json', 'text/plain', 'application/octet-stream'],
      uniformTypeIdentifiers: <String>['public.json', 'public.plain-text', 'public.data'],
    );
    final picker.XFile? file = await picker.openFile(acceptedTypeGroups: <picker.XTypeGroup>[group]);
    if (file == null) {
      return null;
    }
    return file.readAsString();
  }
}

/// Para pruebas: guarda lo compartido y entrega un texto fijo al elegir.
class FakeBackupIO implements BackupIO {
  final List<String> shared = <String>[];
  String? toPick;

  @override
  Future<void> shareFile(String path, {required String subject, required String text}) async => shared.add(path);

  @override
  Future<String?> pickText() async => toPick;
}
