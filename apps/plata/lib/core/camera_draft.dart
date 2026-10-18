import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../model/models.dart';
import 'ledger.dart';

/// Movimiento a medio escribir mientras la cámara está abierta. Android puede
/// cerrar la app para darle memoria a la cámara: sin esto se perderían la foto
/// del recibo y lo que se había escrito. Se guarda cifrado, como el libro.
class CameraDraft {
  CameraDraft._();

  static const String file = 'drafts/camera.json';

  static Future<void> save(Ledger l, Tx draft, {String? existingId, String? inboxId}) => l.store.writeJson(file, <String, dynamic>{'tx': draft.toJson(), 'existingId': existingId, 'inboxId': inboxId});

  static Future<Map<String, dynamic>?> read(Ledger l) async {
    try {
      return await l.store.readJson(file);
    } catch (e) {
      debugPrint('Borrador de la cámara: $e');
      return null;
    }
  }

  static Future<void> clear(Ledger l) async {
    try {
      await l.store.store.delete(file);
    } catch (e) {
      debugPrint('Borrador de la cámara: $e');
    }
  }
}

/// Lo que se recuperó al abrir la app: el movimiento a medio escribir (con la
/// foto ya adjunta y cifrada) y, si se estaba editando uno guardado, ese.
class RecoveredDraft {
  const RecoveredDraft({required this.draft, this.existing, this.inbox});

  final Tx draft;
  final Tx? existing;

  /// El aviso del banco que se estaba confirmando, si venía de uno: al
  /// guardar queda anotado y no se puede confirmar dos veces.
  final InboxItem? inbox;
}

/// Recupera la foto tomada si Android cerró la app con la cámara abierta
/// ([lost], por defecto `ImagePicker.retrieveLostData`), junto con el
/// borrador del movimiento. Devuelve null si no hay nada que recuperar.
Future<RecoveredDraft?> recoverCameraDraft(Ledger l, {Future<LostDataResponse> Function()? lost}) async {
  final LostDataResponse response = await (lost ?? ImagePicker().retrieveLostData)();
  final Map<String, dynamic>? saved = await CameraDraft.read(l);
  await CameraDraft.clear(l);
  final XFile? photo = response.isEmpty ? null : response.file;
  final Map<String, dynamic>? txJson = saved?['tx'] is Map<String, dynamic> ? saved!['tx'] as Map<String, dynamic> : null;
  // El borrador solo existe si la app se cerró con la cámara abierta (al
  // volver de la cámara se borra): lo escrito se recupera aunque no haya
  // llegado la foto.
  if (photo == null && txJson == null) {
    return null;
  }
  final Tx draft = txJson != null ? Tx.fromJson(txJson) : Tx(id: newId(), kind: TxKind.expense, amountMinor: 0, accountId: '', date: clock.now());
  if (photo != null) {
    final String rel = 'attachments/${newId()}.jpg.enc';
    await l.store.writeBytes(rel, await photo.readAsBytes());
    await deletePickerCopies(photo);
    draft.attachments.add(rel);
  }
  final String? existingId = saved?['existingId'] as String?;
  final String? inboxId = saved?['inboxId'] as String?;
  final InboxItem? inbox = inboxId == null ? null : l.inbox.where((InboxItem i) => i.id == inboxId && i.status == 'pending').firstOrNull;
  return RecoveredDraft(draft: draft, existing: existingId == null ? null : l.tx(existingId), inbox: inbox);
}

/// El selector deja la foto en la caché de la app y, cuando la reduce
/// (`scaled_` delante del nombre), también la original. Solo se borra lo que
/// está dentro de la carpeta privada de la app: nunca la foto de la galería.
Future<void> deletePickerCopies(XFile f) async {
  try {
    final String container = (await getApplicationDocumentsDirectory()).parent.path;
    final String sep = Platform.pathSeparator;
    if (!f.path.startsWith('$container$sep')) {
      return;
    }
    final File picked = File(f.path);
    final String name = picked.uri.pathSegments.last;
    final List<File> copies = <File>[picked];
    if (name.startsWith('scaled_')) {
      final String original = name.substring('scaled_'.length);
      copies.add(File('${picked.parent.path}$sep$original'));
      final List<Directory> dirs = <Directory>[await getTemporaryDirectory(), if (Platform.isIOS) Directory.systemTemp];
      for (final Directory tmp in dirs) {
        if (await tmp.exists()) {
          await for (final FileSystemEntity e in tmp.list(recursive: true)) {
            if (e is File && e.uri.pathSegments.last == original) {
              copies.add(e);
            }
          }
        }
      }
    }
    for (final File c in copies) {
      if (c.path.startsWith('$container$sep') && await c.exists()) {
        await c.delete();
      }
    }
  } catch (e) {
    debugPrint('Copia del selector: $e');
  }
}
