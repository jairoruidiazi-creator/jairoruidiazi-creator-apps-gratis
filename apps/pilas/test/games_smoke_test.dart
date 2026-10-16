import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/core/app_scope.dart';
import 'package:pilas/core/app_state.dart';
import 'package:pilas/core/settings.dart';
import 'package:pilas/core/sfx.dart';
import 'package:pilas/core/speech.dart';
import 'package:pilas/core/storage.dart';
import 'package:pilas/core/theme.dart';
import 'package:pilas/engine/game_def.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/games/shell/widgets.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/model/profile.dart';

/// Abre cada juego en cada tramo que soporta, toca una opción si la hay y
/// comprueba que no se lance ninguna excepción (desbordes de layout, nulos,
/// índices fuera de rango).
void main() {
  late Directory tmp;
  late Services services;
  final Map<AgeBand, Profile> profiles = <AgeBand, Profile>{};

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('pilas_smoke');
    final AppSettings settings = AppSettings()
      ..voiceEnabled = false
      ..sfxEnabled = false
      ..sessionLimitMinutes = 0;
    final JsonStore store = JsonStore(root: tmp);
    final AppState state = AppState(store);
    await state.load();
    services = Services(settings: settings, voice: Voice(settings), sfx: Sfx(settings), store: store, state: state);
    for (final AgeBand b in AgeBand.values) {
      profiles[b] = await state.addProfile(nombre: 'Peque ${b.id}', avatar: '1f431', birthYear: 2020, birthMonth: 1, bandOverride: b);
    }
  });

  tearDownAll(() async {
    await tmp.delete(recursive: true);
  });

  Widget host(GameDef game, AgeBand band) {
    return AppScope(
      services: services,
      state: services.state,
      child: MaterialApp(
        theme: PilasTheme.light(),
        home: Builder(builder: (BuildContext context) => game.build(context, GameLaunch(game: game, band: band, profile: profiles[band]!))),
      ),
    );
  }

  for (final GameDef game in GameRegistry.all) {
    for (final AgeBand band in AgeBand.values) {
      if (!game.supports(band)) {
        continue;
      }
      testWidgets('${game.id} abre y responde en ${band.id}', (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 2.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        services.state.current = profiles[band];
        await tester.pumpWidget(host(game, band));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: '${game.id} ${band.id}: excepción al abrir');
        expect(find.text(game.nombre), findsWidgets);

        // Si hay opciones, toca la primera y deja pasar la celebración o la pista.
        final Finder tiles = find.byType(OptionTile);
        if (tiles.evaluate().isNotEmpty) {
          await tester.tap(tiles.first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pump(const Duration(seconds: 3));
          await tester.pump(const Duration(seconds: 3));
          expect(tester.takeException(), isNull, reason: '${game.id} ${band.id}: excepción al responder');
          // Segunda ronda o segunda oportunidad: toca otra vez.
          final Finder again = find.byType(OptionTile);
          if (again.evaluate().isNotEmpty) {
            await tester.tap(again.last, warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 200));
            await tester.pump(const Duration(seconds: 3));
            await tester.pump(const Duration(seconds: 3));
            expect(tester.takeException(), isNull, reason: '${game.id} ${band.id}: excepción en la segunda respuesta');
          }
        }
        // Apaisado: la pantalla se reacomoda sin desbordes.
        tester.view.physicalSize = const Size(1920, 1080);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: '${game.id} ${band.id}: excepción en apaisado');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '${game.id} ${band.id}: excepción al cerrar');
      });
    }
  }
}
