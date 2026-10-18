import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../engine/game_def.dart';
import '../engine/game_registry.dart';
import '../games/shell/widgets.dart';
import '../model/age_band.dart';
import '../model/area.dart';
import '../model/profile.dart';
import '../model/progress.dart';

/// Álbum de pegatinas del niño, agrupado por área.
class StickersScreen extends StatelessWidget {
  const StickersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final PilasPalette pal = PilasPalette.of(context);
    final Profile? p = s.state.current;
    final ProfileProgress? prog = p == null ? null : s.state.progressOf(p.id);
    final List<StickerAward> stickers = prog?.stickers ?? <StickerAward>[];
    final List<Widget> children = <Widget>[];
    for (final Area area in Area.values) {
      final List<StickerAward> deArea = stickers.where((StickerAward st) => GameRegistry.byId(st.gameId)?.area == area).toList();
      if (deArea.isEmpty) {
        continue;
      }
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: <Widget>[
            EmojiImage(area.emoji, size: 28),
            const SizedBox(width: 8),
            Expanded(child: Text(area.nombre, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: pal.areaTexto(area)))),
          ],
        ),
      ));
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            for (final StickerAward st in deArea)
              Semantics(
                label: 'Pegatina de ${GameRegistry.byId(st.gameId)?.nombre ?? st.gameId}, nivel ${st.level}',
                excludeSemantics: true,
                child: Container(
                  width: 104,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: pal.tarjeta, borderRadius: BorderRadius.circular(20), border: Border.all(color: pal.altoContraste ? pal.bordeFuerte : pal.borde, width: 2)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      EmojiImage(st.emoji, size: 56),
                      const SizedBox(height: 4),
                      Text(_nombreCorto(st), textAlign: TextAlign.center, maxLines: 3, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pal.tintaSuave)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ));
    }
    return Scaffold(
      appBar: AppBar(title: Text('${S.misPegatinas} (${stickers.length})')),
      body: stickers.isEmpty
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Mascot(size: 120),
                    const SizedBox(height: 16),
                    Text(
                      p == null || p.band.readsText ? 'Completa un nivel de cualquier juego para ganar tu primera pegatina.' : '¡Juega para ganar pegatinas!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: pal.tinta),
                    ),
                  ],
                ),
              ),
            )
          : ListView(padding: const EdgeInsets.only(bottom: 24), children: children),
    );
  }

  String _nombreCorto(StickerAward st) {
    final GameDef? g = GameRegistry.byId(st.gameId);
    return '${g?.nombre ?? st.gameId} · nivel ${st.level}';
  }
}
