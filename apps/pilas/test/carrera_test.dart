import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/core/rng.dart';
import 'package:pilas/core/strings.dart';
import 'package:pilas/engine/game_def.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/games/choice/choice_game_screen.dart';
import 'package:pilas/games/choice/choice_round.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/model/profile.dart';

import 'support/harness.dart';

/// Rondas fijas de dos opciones: «Sí» es la correcta.
class _SiNo implements ChoiceGenerator {
  @override
  ChoiceRound next(Rng rng, AgeBand band, int level) => ChoiceRound(
        instruction: '¿Cuánto es uno más uno?',
        options: <ChoiceOption>[
          ChoiceOption(id: 'si', label: 'Sí', build: (BuildContext context, double size) => const Text('Sí', key: ValueKey<String>('op-si'))),
          ChoiceOption(id: 'no', label: 'No', build: (BuildContext context, double size) => const Text('No', key: ValueKey<String>('op-no'))),
        ],
        correctId: 'si',
        hint: 'Cuenta con los dedos.',
        explain: 'Uno más uno es dos.',
      );
}

Future<void> _dejarGuardar(WidgetTester tester) async {
  for (int i = 0; i < 15; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

/// Toca una opción y deja pasar la celebración (o la explicación) y la
/// subida de nivel, con el guardado de por medio.
Future<void> _responder(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey<String>('op-$id')));
  await tester.pump();
  for (int i = 0; i < 3; i++) {
    await _dejarGuardar(tester);
    await tester.pump(const Duration(seconds: 3));
  }
  await _dejarGuardar(tester);
}

void main() {
  late Harness h;

  setUp(() async {
    h = await Harness.create();
  });

  tearDown(() async {
    await h.dispose();
  });

  for (final bool ultimaBien in <bool>[false, true]) {
    testWidgets('G1: el resumen de la carrera queda a la vista y «Otra carrera» se puede tocar (última ${ultimaBien ? 'acertada' : 'errada'})', (WidgetTester tester) async {
      late Profile p;
      await tester.runAsync(() async {
        p = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2016, birthMonth: 1, bandOverride: AgeBand.b9a11);
        await h.state.selectProfile(p);
      });
      final GameDef game = GameRegistry.byId('carrera')!;
      expect(game.supports(AgeBand.b9a11), isTrue);
      await tester.pumpWidget(h.app(ChoiceGameScreen(launch: GameLaunch(game: game, band: AgeBand.b9a11, profile: p), generator: _SiNo(), race: const RaceConfig())));
      await tester.pump();

      for (int i = 0; i < 9; i++) {
        expect(find.textContaining(S.preguntaDe(i + 1, 10)), findsOneWidget);
        await _responder(tester, 'si');
      }
      expect(find.textContaining(S.preguntaDe(10, 10)), findsOneWidget);
      await _responder(tester, ultimaBien ? 'si' : 'no');

      // El resumen se ve, sin velo ni tarjeta de la última ronda encima.
      final int aciertos = ultimaBien ? 10 : 9;
      expect(find.text(S.acertasteDe(aciertos, 10)), findsOneWidget);
      expect(find.text(S.asiEs), findsNothing);
      expect(find.text(S.excelente), findsNothing);
      expect(find.text(S.nuevoNivel), findsNothing);
      expect(find.text('Uno más uno es dos.'), findsNothing);
      expect(find.text(S.otraCarrera).hitTestable(), findsOneWidget);
      expect(find.text(S.nuevaMarca), findsOneWidget);
      expect(h.state.recordOf(RaceConfig.recordKey(game, AgeBand.b9a11)), aciertos);
      // Y sigue así aunque pase el tiempo.
      await tester.pump(const Duration(seconds: 5));
      expect(find.text(S.otraCarrera).hitTestable(), findsOneWidget);

      // «Otra carrera» empieza de nuevo, con la marca a la vista.
      await tester.tap(find.text(S.otraCarrera));
      await tester.pump();
      expect(find.text(S.otraCarrera), findsNothing);
      expect(find.textContaining(S.preguntaDe(1, 10)), findsOneWidget);
      expect(find.textContaining('${S.tuMarca}: $aciertos'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('op-si')).hitTestable(), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => h.state.pauseClock());
    });
  }
}
