import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/app_state.dart';
import '../core/parental_gate.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../games/shell/widgets.dart';
import '../model/profile.dart';
import 'kid_home_screen.dart';
import 'parent/parent_panel.dart';
import 'profile_edit_screen.dart';

/// Pantalla inicial: ¿quién va a jugar?
class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});

  Future<void> _abrirPerfil(BuildContext context, Profile p) async {
    final Services s = AppScope.read(context);
    await s.state.selectProfile(p);
    await s.settings.setLastProfileId(p.id);
    if (!context.mounted) {
      return;
    }
    s.voice.sayLater(S.hola(p.nombre));
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const KidHomeScreen()));
    if (context.mounted) {
      await AppScope.read(context).state.endSession();
    }
  }

  Future<void> _nuevo(BuildContext context) async {
    final AppState state = AppScope.read(context).state;
    if (state.profiles.isNotEmpty) {
      final bool ok = await showParentalGate(context, reason: S.nuevoPerfil);
      if (!ok || !context.mounted) {
        return;
      }
    }
    if (!context.mounted) {
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProfileEditScreen()));
  }

  Future<void> _adultos(BuildContext context) async {
    final bool ok = await showParentalGate(context, reason: S.panelAdultos);
    if (!ok || !context.mounted) {
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ParentPanel()));
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final List<Profile> profiles = s.state.profiles;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final int cols = c.maxWidth > 900 ? 5 : (c.maxWidth > 600 ? 4 : 3);
            return CustomScrollView(
              slivers: <Widget>[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Column(
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Mascot(size: 64),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(S.appName, style: Theme.of(context).textTheme.headlineMedium),
                                  Text(S.lema, style: const TextStyle(fontSize: 16, color: PilasColors.tintaSuave)),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _adultos(context),
                              icon: const Icon(Icons.lock_outline_rounded),
                              label: const Text(S.soyAdulto),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(S.quienJuega, style: Theme.of(context).textTheme.headlineSmall),
                        if (profiles.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('${S.sinConexion} ${S.privacidad}', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: PilasColors.tintaSuave)),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.85),
                    delegate: SliverChildBuilderDelegate(
                      (BuildContext context, int i) {
                        if (i == profiles.length) {
                          return OptionTile(
                            semanticsLabel: S.nuevoPerfil,
                            onTap: () => _nuevo(context),
                            color: PilasColors.amarillo.withValues(alpha: 0.35),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(Icons.add_circle_rounded, size: 56, color: PilasColors.naranja),
                                SizedBox(height: 8),
                                Text(S.nuevoPerfil, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          );
                        }
                        final Profile p = profiles[i];
                        return OptionTile(
                          semanticsLabel: p.nombre,
                          onTap: () => _abrirPerfil(context, p),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              EmojiImage(p.avatar, size: 72),
                              const SizedBox(height: 8),
                              Text(p.nombre, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        );
                      },
                      childCount: profiles.length + 1,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
