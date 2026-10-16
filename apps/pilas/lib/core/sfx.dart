import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'settings.dart';

/// Efectos de sonido cortos. Nunca hay sonidos de derrota: el error suena a
/// pista, no a castigo.
enum SfxId { tap, ok, great, hint, levelUp, sticker, page, pop }

class Sfx {
  Sfx(this.settings);

  final AppSettings settings;
  final List<AudioPlayer> _players = <AudioPlayer>[];
  int _next = 0;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) {
      return;
    }
    _ready = true;
    try {
      for (int i = 0; i < 3; i++) {
        final AudioPlayer p = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setPlayerMode(PlayerMode.lowLatency);
        _players.add(p);
      }
    } catch (e) {
      debugPrint('Sonido no disponible: $e');
    }
  }

  String _file(SfxId id) {
    switch (id) {
      case SfxId.tap:
        return 'tap.wav';
      case SfxId.ok:
        return 'ok.wav';
      case SfxId.great:
        return 'great.wav';
      case SfxId.hint:
        return 'hint.wav';
      case SfxId.levelUp:
        return 'levelup.wav';
      case SfxId.sticker:
        return 'sticker.wav';
      case SfxId.page:
        return 'page.wav';
      case SfxId.pop:
        return 'pop.wav';
    }
  }

  Future<void> play(SfxId id) async {
    if (!settings.sfxEnabled) {
      return;
    }
    await init();
    if (_players.isEmpty) {
      return;
    }
    final AudioPlayer p = _players[_next % _players.length];
    _next += 1;
    try {
      await p.stop();
      await p.play(AssetSource('sounds/${_file(id)}'));
    } catch (e) {
      debugPrint('Error de sonido: $e');
    }
  }

  Future<void> dispose() async {
    for (final AudioPlayer p in _players) {
      await p.dispose();
    }
    _players.clear();
    _ready = false;
  }
}
