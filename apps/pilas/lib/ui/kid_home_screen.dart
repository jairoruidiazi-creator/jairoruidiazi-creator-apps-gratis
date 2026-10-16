import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/app_state.dart';
import '../core/sfx.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../engine/game_def.dart';
import '../engine/game_registry.dart';
import '../engine/mastery.dart';
import '../games/shell/widgets.dart';
import '../model/age_band.dart';
import '../model/area.dart';
import '../model/profile.dart';
import '../model/progress.dart';
import 'my_drawings_screen.dart';
import 'stickers_screen.dart';

/// Inicio del niño: los juegos agrupados por área, con tarjetas grandes.
class KidHomeScreen extends StatefulWidget {
  const KidHomeScreen({super.key});

  @override
  State<KidHomeScreen> createState() => _KidHomeScreenState();
}

class _KidHomeScreenState extends State<KidHomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final AppState app = AppScope.read(context).state;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      app.flushSession();
    } else if (state == AppLifecycleState.resumed) {
      app.startSession();
    }
  }

  Future<void> _play(GameDef game, Profile profile) async {
    final Services s = AppScope.read(context);
    await s.sfx.play(SfxId.tap);
    await s.voice.stop();
    if (!mounted) {
      return;
    }
    final GameLaunch launch = GameLaunch(game: game, band: profile.band, profile: profile);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (BuildContext context) => game.build(context, launch)));
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final Profile? profile = s.state.current;
    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final AgeBand band = profile.band;
    final ProfileProgress progress = s.state.progressOf(profile.id);
    final bool reads = band.readsText;
    final List<Widget> sections = <Widget>[];
    for (final Area area in Area.values) {
      final List<GameDef> games = GameRegistry.forAreaAndBand(area, band);
      if (games.isEmpty) {
        continue;
      }
      sections.add(_AreaHeader(area: area, reads: reads));
      sections.add(
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final int cols = c.maxWidth > 1000 ? 4 : (c.maxWidth > 640 ? 3 : 2);
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.25,
              children: <Widget>[
                for (final GameDef g in games)
                  _GameCard(
                    game: g,
                    mastery: progress.masteryFor(g.id, band),
                    stickers: progress.stickers.where((StickerAward st) => st.gameId == g.id && st.band == band).length,
                    reads: reads,
                    onTap: () => _play(g, profile),
                  ),
              ],
            );
          },
        ),
      );
      sections.add(const SizedBox(height: 16));
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: <Widget>[
                  EmojiImage(profile.avatar, size: 56),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(S.hola(profile.nombre), style: Theme.of(context).textTheme.headlineSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (reads) const Text(S.queQuieresJugar, style: TextStyle(fontSize: 16, color: PilasColors.tintaSuave)),
                      ],
                    ),
                  ),
                  RoundIconButton(
                    icon: Icons.volume_up_rounded,
                    tooltip: S.repetir,
                    color: PilasColors.amarillo,
                    onPressed: () => s.voice.sayLater('${S.hola(profile.nombre)} ${S.queQuieresJugar}'),
                  ),
                  const SizedBox(width: 6),
                  RoundIconButton(
                    icon: Icons.swap_horiz_rounded,
                    tooltip: S.cambiarJugador,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _ShortcutTile(
                      emoji: '2b50',
                      label: S.misPegatinas,
                      count: progress.stickers.length,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StickersScreen())),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ShortcutTile(
                      emoji: '1f5bc',
                      label: S.misDibujos,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MyDrawingsScreen())),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ...sections,
          ],
        ),
      ),
    );
  }
}

class _AreaHeader extends StatelessWidget {
  const _AreaHeader({required this.area, required this.reads});

  final Area area;
  final bool reads;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: area.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
            child: EmojiImage(area.emoji, size: 28),
          ),
          const SizedBox(width: 10),
          Text(reads ? area.nombre : area.nombreCorto, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: area.color)),
        ],
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game, required this.mastery, required this.stickers, required this.reads, required this.onTap});

  final GameDef game;
  final MasteryState mastery;
  final int stickers;
  final bool reads;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OptionTile(
      semanticsLabel: game.nombre,
      onTap: onTap,
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Expanded(child: Center(child: EmojiImage(game.emoji, size: 64))),
          const SizedBox(height: 6),
          Text(game.nombre, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: reads ? 16 : 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (game.roundBased)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (int i = 1; i <= game.levels; i++)
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < mastery.level ? game.area.color : (i == mastery.level ? game.area.color.withValues(alpha: 0.45) : const Color(0xFFE3DCCB)),
                    ),
                  ),
                if (stickers > 0) ...<Widget>[
                  const SizedBox(width: 8),
                  const Icon(Icons.star_rounded, size: 16, color: PilasColors.naranja),
                  Text('$stickers', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ],
            )
          else if (stickers > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(Icons.star_rounded, size: 16, color: PilasColors.naranja),
                Text('$stickers', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
        ],
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({required this.emoji, required this.label, required this.onTap, this.count});

  final String emoji;
  final String label;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return OptionTile(
      semanticsLabel: label,
      onTap: onTap,
      minHeight: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          EmojiImage(emoji, size: 32),
          const SizedBox(width: 8),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          if (count != null) ...<Widget>[
            const SizedBox(width: 6),
            Text('$count', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: PilasColors.naranja)),
          ],
        ],
      ),
    );
  }
}
