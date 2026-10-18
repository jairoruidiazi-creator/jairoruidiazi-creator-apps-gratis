import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/app_scope.dart';
import '../../core/sfx.dart';

/// Captura el [RepaintBoundary] identificado por [key] y lo guarda como PNG
/// en "Mis dibujos" del perfil. Devuelve true si se guardó. Quien llama se
/// encarga de no guardar dibujos vacíos. Si algo falla, avisa en pantalla.
Future<bool> saveCanvasPng(BuildContext context, GlobalKey key, String profileId, {double pixelRatio = 2.0, bool silencioso = false}) async {
  final RenderObject? ro = key.currentContext?.findRenderObject();
  if (ro is! RenderRepaintBoundary) {
    return false;
  }
  final Services s = AppScope.read(context);
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final ui.Image image = await ro.toImage(pixelRatio: pixelRatio);
    final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) {
      return false;
    }
    final Uint8List bytes = data.buffer.asUint8List();
    await s.store.writeBytes('drawings/$profileId/${clock.now().millisecondsSinceEpoch}.png', bytes);
  } catch (e) {
    debugPrint('No se pudo guardar el dibujo: $e');
    messenger?.showSnackBar(const SnackBar(content: Text('No se pudo guardar el dibujo. Inténtalo de nuevo.')));
    return false;
  }
  if (!silencioso) {
    unawaited(s.sfx.play(SfxId.sticker));
    s.voice.sayLater('Guardado en Mis dibujos.');
    messenger?.showSnackBar(const SnackBar(content: Text('Guardado en Mis dibujos')));
  }
  return true;
}
