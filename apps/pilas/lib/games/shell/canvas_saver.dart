import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/app_scope.dart';
import '../../core/sfx.dart';

/// Captura el [RepaintBoundary] identificado por [key] y lo guarda como PNG
/// en "Mis dibujos" del perfil. Devuelve true si se guardó.
Future<bool> saveCanvasPng(BuildContext context, GlobalKey key, String profileId, {double pixelRatio = 2.0, bool silencioso = false}) async {
  final RenderRepaintBoundary? boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) {
    return false;
  }
  final Services s = AppScope.read(context);
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) {
    return false;
  }
  final Uint8List bytes = data.buffer.asUint8List();
  final String name = 'drawings/$profileId/${DateTime.now().millisecondsSinceEpoch}.png';
  await s.store.writeBytes(name, bytes);
  if (!silencioso) {
    unawaited(s.sfx.play(SfxId.sticker));
    s.voice.sayLater('Guardado en mis dibujos.');
    messenger?.showSnackBar(const SnackBar(content: Text('Guardado en Mis dibujos')));
  }
  return true;
}
