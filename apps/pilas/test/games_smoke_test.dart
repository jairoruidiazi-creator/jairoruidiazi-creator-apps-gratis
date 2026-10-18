import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/core/app_scope.dart';
import 'package:pilas/core/app_state.dart';
import 'package:pilas/core/settings.dart';
import 'package:pilas/core/sfx.dart';
import 'package:pilas/core/speech.dart';
import 'package:pilas/core/storage.dart';
import 'package:pilas/core/strings.dart';
import 'package:pilas/core/theme.dart';
import 'package:pilas/engine/game_def.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/games/shell/widgets.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/model/profile.dart';

/// Comprueba que [finder] se ve y recibe toques: tiene tamaño y un toque en su
/// centro llega a él. Encontrar el widget no basta: un Stack de tamaño cero
/// dejó los juegos invisibles sin que ninguna prueba fallara.
void expectHittable(WidgetTester tester, Finder finder, String reason) {
  final RenderBox box = tester.renderObject<RenderBox>(finder.first);
  expect(box.hasSize && !box.size.isEmpty, isTrue, reason: '$reason: sin tamaño');
  final Offset center = box.localToGlobal(box.size.center(Offset.zero));
  final HitTestResult result = tester.hitTestOnBinding(center);
  final bool hit = result.path.any((HitTestEntry e) => e.target == box);
  if (!hit) {
    final Rect rect = box.localToGlobal(Offset.zero) & box.size;
    final String path = result.path.take(14).map((HitTestEntry e) => e.target.runtimeType.toString()).join(' > ');
    fail('$reason: un toque en el centro no le llega (caja $rect en pantalla ${tester.view.physicalSize / tester.view.devicePixelRatio}; '
        'el toque llega a: $path)');
  }
}

/// Abre cada juego en cada tramo que soporta, comprueba que el marco y las
/// opciones se ven y reciben toques, toca una opción si la hay y comprueba que
/// no se lance ninguna excepción (desbordes de layout, nulos, índices fuera de
/// rango).
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
        // Teléfono pequeño (360 × 740 dp), el caso más estrecho y común.
        tester.view.physicalSize = const Size(1080, 2220);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        // Se guardan los errores completos (con el widget que los causa) en
        // lugar de solo el mensaje que deja takeException.
        final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
        final FlutterExceptionHandler? previous = FlutterError.onError;
        FlutterError.onError = errors.add;
        addTearDown(() => FlutterError.onError = previous);
        void expectNoErrors(String when) {
          if (errors.isNotEmpty) {
            final String text = errors.map((FlutterErrorDetails d) => d.toString()).join('\n----\n');
            errors.clear();
            fail('${game.id} ${band.id}: errores $when:\n$text');
          }
        }

        final Finder exit = find.byWidgetPredicate((Widget w) => w is RoundIconButton && w.tooltip == S.salir);
        services.state.current = profiles[band];
        await tester.pumpWidget(host(game, band));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expectNoErrors('al abrir');
        expect(find.text(game.nombre), findsWidgets);
        expectHittable(tester, exit, '${game.id} ${band.id}: botón de salir');

        // Si hay opciones, toca la primera y deja pasar la celebración o la pista.
        final Finder tiles = find.byType(OptionTile);
        if (tiles.evaluate().isNotEmpty) {
          expectHittable(tester, tiles, '${game.id} ${band.id}: primera opción');
          await tester.tap(tiles.first);
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pump(const Duration(seconds: 3));
          await tester.pump(const Duration(seconds: 3));
          expectNoErrors('al responder');
          // Segunda ronda o segunda oportunidad: toca otra vez.
          final Finder again = find.byType(OptionTile);
          if (again.evaluate().isNotEmpty) {
            await tester.tap(again.last, warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 200));
            await tester.pump(const Duration(seconds: 3));
            await tester.pump(const Duration(seconds: 3));
            expectNoErrors('en la segunda respuesta');
          }
        }
        // Apaisado: la pantalla se reacomoda sin desbordes.
        tester.view.physicalSize = const Size(2220, 1080);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expectNoErrors('en apaisado');
        expectHittable(tester, exit, '${game.id} ${band.id}: botón de salir en apaisado');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expectNoErrors('al cerrar');
      });
    }
  }
}
