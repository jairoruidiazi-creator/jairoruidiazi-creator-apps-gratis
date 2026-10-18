import 'dart:math' as math;

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
import 'rest_screen.dart';

/// Pantalla inicial: ¿quién va a jugar?
///
/// - Crear un perfil (también el primero) pasa por la puerta parental.
/// - Si otro jugador está en su descanso, cambiar de jugador también pide la
///   puerta: así el descanso no se salta eligiendo a un hermano.
/// - Si el jugador elegido está en su descanso, se muestra el descanso.
/// - Un toque doble no abre dos veces.
class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && AppScope.read(context).state.profiles.isNotEmpty) {
        AppScope.read(context).voice.sayLater(S.quienJuega);
      }
    });
  }

  /// Ejecuta [action] una sola vez aunque se toque dos veces seguidas.
  Future<void> _once(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _abrirPerfil(Profile p) async {
    final Services s = AppScope.read(context);
    final AppState state = s.state;
    final NavigatorState nav = Navigator.of(context);
    final Profile? descansando = state.restingProfileOtherThan(p.id);
    if (descansando != null) {
      final bool ok = await showParentalGate(context, reason: S.cambiarConDescanso);
      if (!ok || !mounted) {
        return;
      }
    }
    await state.selectProfile(p);
    await s.settings.setLastProfileId(p.id);
    if (!mounted) {
      return;
    }
    if (state.isResting(p.id)) {
      // Su descanso sigue corriendo: primero termina el descanso.
      await nav.push(RestScreen.route());
      if (!mounted || state.current?.id != p.id || state.isResting(p.id)) {
        return;
      }
    }
    s.voice.sayLater(S.holaVoz);
    await nav.push(MaterialPageRoute<void>(builder: (_) => const KidHomeScreen(), settings: const RouteSettings(name: 'inicio')));
    if (mounted) {
      // La sesión queda en pausa: si vuelve en menos de 10 minutos, sigue la
      // misma sesión (el tiempo no se reinicia saliendo a esta pantalla).
      await AppScope.read(context).state.selectProfile(null);
    }
  }

  Future<void> _nuevo() async {
    final bool ok = await showParentalGate(context, reason: S.nuevoPerfil);
    if (!ok || !mounted) {
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProfileEditScreen()));
  }

  Future<void> _adultos() async {
    final bool ok = await showParentalGate(context, reason: S.panelAdultos);
    if (!ok || !mounted) {
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ParentPanel()));
  }

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final PilasPalette pal = PilasPalette.of(context);
    final List<Profile> profiles = s.state.profiles;
    final double scale = MediaQuery.textScalerOf(context).scale(18) / 18;
    // Teléfono acostado: cabecera compacta (sin lema y con la mascota más
    // pequeña) para que las tarjetas se vean sin desplazar, aun con la letra
    // al doble.
    final bool compacta = MediaQuery.sizeOf(context).height < 500;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  children: <Widget>[
                    LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
                      final Widget titulo = Row(
                        children: <Widget>[
                          Mascot(size: compacta ? 40 : 64),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(S.appName, style: Theme.of(context).textTheme.headlineMedium),
                                if (!compacta) Text(S.lema, style: TextStyle(fontSize: 16, color: pal.tintaSuave)),
                              ],
                            ),
                          ),
                        ],
                      );
                      final Widget adulto = TextButton.icon(
                        key: const ValueKey<String>('soy-adulto'),
                        onPressed: _busy ? null : () => _once(_adultos),
                        icon: const Icon(Icons.lock_outline_rounded),
                        label: const Text(S.soyAdulto),
                      );
                      // En un teléfono, «Soy adulto» va en su propia fila para
                      // no apretar el nombre de la app.
                      if (c.maxWidth < 520) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[Align(alignment: Alignment.centerRight, child: adulto), titulo],
                        );
                      }
                      return Row(children: <Widget>[Expanded(child: titulo), adulto]);
                    }),
                    SizedBox(height: compacta ? 8 : 20),
                    Text(S.quienJuega, textAlign: TextAlign.center, style: compacta ? Theme.of(context).textTheme.titleLarge : Theme.of(context).textTheme.headlineSmall),
                    if (profiles.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${S.sinConexion} ${S.privacidad} Un adulto crea el primer perfil.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 15, color: pal.tintaSuave),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                // Tarjetas de 150 a 190 dp de ancho: en un teléfono de 360 dp
                // caben dos, y el alto crece con el tamaño de letra.
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  mainAxisExtent: 112 + 40 * math.max(1.0, scale),
                ),
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int i) {
                    if (i == profiles.length) {
                      return OptionTile(
                        key: const ValueKey<String>('nuevo-perfil'),
                        semanticsLabel: S.nuevoPerfil,
                        onTap: _busy ? null : () => _once(_nuevo),
                        color: pal.acentoClaro,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(Icons.add_circle_rounded, size: 56, color: pal.acento),
                              const SizedBox(height: 8),
                              Text(S.nuevoPerfil, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: pal.tinta)),
                            ],
                          ),
                        ),
                      );
                    }
                    final Profile p = profiles[i];
                    final bool descansa = s.state.isResting(p.id);
                    return OptionTile(
                      key: ValueKey<String>('perfil-${p.id}'),
                      semanticsLabel: descansa ? '${p.nombre}, en su descanso' : p.nombre,
                      onTap: _busy ? null : () => _once(() => _abrirPerfil(p)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Stack(
                            clipBehavior: Clip.none,
                            children: <Widget>[
                              EmojiImage(p.avatar, size: 72),
                              if (descansa)
                                Positioned(
                                  right: -6,
                                  bottom: -6,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(color: pal.tarjeta, shape: BoxShape.circle, border: Border.all(color: pal.bordeFuerte)),
                                    child: Icon(Icons.bedtime_rounded, size: 22, color: pal.tinta),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(p.nombre, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: pal.tinta)),
                        ],
                      ),
                    );
                  },
                  childCount: profiles.length + 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
