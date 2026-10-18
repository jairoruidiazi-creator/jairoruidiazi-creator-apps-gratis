import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/sfx.dart';
import '../core/speech.dart';
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

/// Inicio del niño: los juegos agrupados por área, con tarjetas grandes cuyo
/// pictograma nunca se achica (es lo que guía a quien todavía no lee).
class KidHomeScreen extends StatefulWidget {
  const KidHomeScreen({super.key});

  @override
  State<KidHomeScreen> createState() => _KidHomeScreenState();
}

class _KidHomeScreenState extends State<KidHomeScreen> {
  bool _opening = false;

  Future<void> _open(Future<void> Function(NavigatorState nav) action) async {
    if (_opening) {
      return; // un toque doble no abre dos veces
    }
    _opening = true;
    try {
      await action(Navigator.of(context));
    } finally {
      _opening = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _play(GameDef game, Profile profile) => _open((NavigatorState nav) async {
        final Services s = AppScope.read(context);
        await s.voice.stop();
        // Antes de abrir un juego se revisa el tiempo de la sesión: si ya se
        // cumplió, empieza el descanso (la app lo muestra) y no se abre.
        await s.state.checkLimit();
        if (!mounted || s.state.isResting(profile.id)) {
          return;
        }
        await s.sfx.play(SfxId.tap);
        final GameLaunch launch = GameLaunch(game: game, band: profile.band, profile: profile);
        await nav.push(MaterialPageRoute<void>(builder: (BuildContext context) => game.build(context, launch), settings: RouteSettings(name: 'juego/${game.id}')));
      });

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final PilasPalette pal = PilasPalette.of(context);
    final Profile? profile = s.state.current;
    if (profile == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final AgeBand band = profile.band;
    final ProfileProgress progress = s.state.progressOf(profile.id);
    final bool reads = band.readsText;
    final double scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(16) / 16);
    final List<Widget> slivers = <Widget>[];
    for (final Area area in Area.values) {
      final List<GameDef> games = GameRegistry.forAreaAndBand(area, band);
      if (games.isEmpty) {
        continue;
      }
      slivers.add(SliverToBoxAdapter(child: _AreaHeader(area: area, reads: reads)));
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            // El alto de la tarjeta se calcula para que quepan el pictograma
            // de 64 dp y dos líneas de nombre con la letra que haya.
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 116 + 2 * 16 * 1.3 * scale,
            ),
            delegate: SliverChildListDelegate(<Widget>[
              for (final GameDef g in games)
                _GameCard(
                  key: ValueKey<String>('juego-${g.id}'),
                  game: g,
                  band: band,
                  mastery: progress.masteryIfAny(g.id, band),
                  stickers: progress.stickers.where((StickerAward st) => st.gameId == g.id && st.band == band).length,
                  reads: reads,
                  onTap: () => _play(g, profile),
                ),
            ]),
          ),
        ),
      );
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 16)));
    }

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: <Widget>[
                    Semantics(label: Profile.nombresAvatar[profile.avatar], child: EmojiImage(profile.avatar, size: 56)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(S.hola(profile.nombre), style: Theme.of(context).textTheme.headlineSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (reads) Text(S.queQuieresJugar, style: TextStyle(fontSize: 16, color: pal.tintaSuave)),
                        ],
                      ),
                    ),
                    RoundIconButton(
                      icon: Icons.volume_up_rounded,
                      tooltip: S.repetir,
                      color: pal.destacado,
                      onPressed: () => s.voice.sayLater('${S.holaVoz} ${S.queQuieresJugar}'),
                    ),
                    const SizedBox(width: 6),
                    RoundIconButton(
                      key: const ValueKey<String>('cambiar-jugador'),
                      icon: Icons.swap_horiz_rounded,
                      tooltip: S.cambiarJugador,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
            ),
            if (!reads) SliverToBoxAdapter(child: _NoVoiceBanner(voice: s.voice)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _ShortcutTile(
                        emoji: '2b50',
                        label: S.misPegatinas,
                        count: progress.stickers.length,
                        onTap: () => _open((NavigatorState nav) => nav.push(MaterialPageRoute<void>(builder: (_) => const StickersScreen()))),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ShortcutTile(
                        emoji: '1f5bc',
                        label: S.misDibujos,
                        onTap: () => _open((NavigatorState nav) => nav.push(MaterialPageRoute<void>(builder: (_) => const MyDrawingsScreen()))),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ...slivers,
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

/// Aviso para los que todavía no leen: sin voz en español los juegos de 3 a
/// 6 años no se pueden seguir. Aparece cuando la voz terminó de prepararse.
class _NoVoiceBanner extends StatelessWidget {
  const _NoVoiceBanner({required this.voice});

  final Voice voice;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: voice,
      builder: (BuildContext context, Widget? _) {
        if (!voice.ready || voice.available || !voice.settings.voiceEnabled) {
          return const SizedBox.shrink();
        }
        final PilasPalette pal = PilasPalette.of(context);
        return Container(
          key: const ValueKey<String>('aviso-sin-voz'),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: pal.pistaClaro, borderRadius: BorderRadius.circular(16), border: Border.all(color: pal.pista, width: 2)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.volume_off_rounded, color: pal.pista),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(S.sinVozTitulo, style: TextStyle(fontWeight: FontWeight.w700, color: pal.tinta)),
                    const SizedBox(height: 4),
                    Text(S.sinVozTexto, style: TextStyle(color: pal.tinta)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AreaHeader extends StatelessWidget {
  const _AreaHeader({required this.area, required this.reads});

  final Area area;
  final bool reads;

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Semantics(
        header: true,
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: area.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
              child: EmojiImage(area.emoji, size: 28),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(reads ? area.nombre : area.nombreCorto, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: pal.areaTexto(area)))),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({super.key, required this.game, required this.band, required this.mastery, required this.stickers, required this.reads, required this.onTap});

  final GameDef game;
  final AgeBand band;
  final MasteryState? mastery;
  final int stickers;
  final bool reads;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    final int levels = game.levelsFor(band);
    final int level = mastery?.level ?? 1;
    final bool showLevels = game.hasLevels && levels > 1;
    final String estado = showLevels ? ', nivel $level de $levels' : '';
    return OptionTile(
      semanticsLabel: '${game.nombre}$estado${stickers > 0 ? ', $stickers ${stickers == 1 ? 'pegatina' : 'pegatinas'}' : ''}',
      onTap: onTap,
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          EmojiImage(game.emoji, size: 64),
          const SizedBox(height: 6),
          Text(game.nombre, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: pal.tinta, height: 1.25)),
          const SizedBox(height: 6),
          SizedBox(
            height: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (showLevels)
                  for (int i = 1; i <= levels; i++)
                    Container(
                      width: 11,
                      height: 11,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < level ? game.area.color : (i == level ? pal.tarjeta : pal.inactivo),
                        border: i == level ? Border.all(color: game.area.color, width: 2.5) : null,
                      ),
                    ),
                if (stickers > 0) ...<Widget>[
                  const SizedBox(width: 8),
                  Icon(Icons.star_rounded, size: 16, color: pal.pista),
                  Text('$stickers', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: pal.tinta)),
                ],
              ],
            ),
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
    final PilasPalette pal = PilasPalette.of(context);
    return OptionTile(
      semanticsLabel: count == null ? label : '$label: $count',
      onTap: onTap,
      minHeight: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          EmojiImage(emoji, size: 32),
          const SizedBox(width: 8),
          // Dos líneas: en teléfonos angostos "Mis pegatinas" no se corta.
          Flexible(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.1, color: pal.tinta))),
          if (count != null) ...<Widget>[
            const SizedBox(width: 6),
            Text('$count', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: pal.tinta)),
          ],
        ],
      ),
    );
  }
}
