import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/core/es.dart';
import 'package:pilas/core/parental_gate.dart';
import 'package:pilas/core/rng.dart';
import 'package:pilas/core/strings.dart';
import 'package:pilas/engine/game_def.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/games/choice/choice_game_screen.dart';
import 'package:pilas/games/choice/choice_round.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/model/area.dart';
import 'package:pilas/model/profile.dart';
import 'package:pilas/model/progress.dart';
import 'package:pilas/ui/kid_home_screen.dart';
import 'package:pilas/ui/parent/child_report_screen.dart';
import 'package:pilas/ui/parent/family_guide_screen.dart';
import 'package:pilas/ui/parent/parent_panel.dart';
import 'package:pilas/ui/parent/settings_screen.dart';
import 'package:pilas/ui/parent/teacher_screen.dart';
import 'package:pilas/ui/profile_edit_screen.dart';
import 'package:pilas/ui/profiles_screen.dart';
import 'package:pilas/ui/rest_screen.dart';
import 'package:pilas/ui/stickers_screen.dart';

import 'support/harness.dart';

/// Rondas fijas de dos opciones para llegar rápido al resumen de la carrera.
class _SiNo implements ChoiceGenerator {
  @override
  ChoiceRound next(Rng rng, AgeBand band, int level) => ChoiceRound(
        instruction: '¿Cuánto es uno más uno?',
        options: <ChoiceOption>[
          ChoiceOption(id: 'si', label: 'Dos', build: (BuildContext context, double size) => const Text('Dos', key: ValueKey<String>('op-si'))),
          ChoiceOption(id: 'no', label: 'Tres', build: (BuildContext context, double size) => const Text('Tres', key: ValueKey<String>('op-no'))),
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

/// Una pantalla para revisar: cómo se abre y, si hace falta, qué se toca
/// para llegar a lo que se quiere ver.
class _Caso {
  const _Caso(this.pantalla, {this.antes, this.despues});

  final Widget Function(Harness h, Profile p) pantalla;

  /// Preparación del estado antes de abrir la pantalla.
  final void Function(Harness h, Profile p)? antes;

  /// Toques para llegar a lo que se revisa (la puerta abierta, el resumen).
  final Future<void> Function(WidgetTester tester)? despues;
}

/// M11 (y M10 de la tercera ronda): con la letra al doble (el tope de la
/// app, 200 %), las pantallas fuera de los juegos, la puerta para adultos, el
/// descanso, el informe del niño y el resumen de la carrera caben en un
/// teléfono de 360 dp, de pie y acostado, sin desbordes. (Los juegos los
/// revisa test/games_smoke_test.dart.)
void main() {
  late Harness h;

  setUp(() async {
    h = await Harness.create();
  });

  tearDown(() async {
    await h.dispose();
  });

  final Map<String, _Caso> casos = <String, _Caso>{
    'perfiles': _Caso((Harness h, Profile p) => const ProfilesScreen()),
    'inicio del niño': _Caso((Harness h, Profile p) => const KidHomeScreen()),
    'pegatinas': _Caso((Harness h, Profile p) => const StickersScreen()),
    'editar perfil': _Caso((Harness h, Profile p) => const ProfileEditScreen()),
    'panel de adultos': _Caso((Harness h, Profile p) => const ParentPanel()),
    'ajustes': _Caso((Harness h, Profile p) => const SettingsScreen()),
    'modo docente': _Caso((Harness h, Profile p) => const TeacherScreen()),
    'guía para familias': _Caso((Harness h, Profile p) => const FamilyGuideScreen()),
    'informe del niño': _Caso((Harness h, Profile p) => ChildReportScreen(profile: p)),
    'descanso': _Caso(
      (Harness h, Profile p) => const RestScreen(),
      antes: (Harness h, Profile p) => h.state.progressOf(p.id).restUntil = clock.now().add(const Duration(minutes: 10)),
    ),
    'puerta para adultos': _Caso(
      (Harness h, Profile p) => Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(child: TextButton(onPressed: () => showParentalGate(context, reason: S.panelAdultos), child: const Text('abrir'))),
        ),
      ),
      despues: (WidgetTester tester) async {
        await tester.tap(find.text('abrir'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const ValueKey<String>('puerta-respuesta')), findsOneWidget);
      },
    ),
    'resumen de la carrera': _Caso(
      (Harness h, Profile p) {
        final GameDef carrera = GameRegistry.byId('carrera')!;
        return ChoiceGameScreen(launch: GameLaunch(game: carrera, band: AgeBand.b9a11, profile: p), generator: _SiNo(), race: const RaceConfig(length: 1));
      },
      despues: (WidgetTester tester) async {
        await tester.tap(find.byKey(const ValueKey<String>('op-no')));
        await tester.pump();
        for (int i = 0; i < 3; i++) {
          await _dejarGuardar(tester);
          await tester.pump(const Duration(seconds: 3));
        }
        await _dejarGuardar(tester);
        expect(find.text(S.otraCarrera), findsOneWidget);
      },
    ),
  };

  for (final Size tamano in <Size>[const Size(360, 740), const Size(740, 360)]) {
    casos.forEach((String nombre, _Caso caso) {
      testWidgets('$nombre cabe con la letra al doble en ${tamano.width.toInt()} × ${tamano.height.toInt()}', (WidgetTester tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final List<String> errores = <String>[];
        final FlutterExceptionHandler? antes = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails d) => errores.add(d.toString());
        addTearDown(() => FlutterError.onError = antes);
        late Profile p;
        await tester.runAsync(() async {
          p = await h.state.addProfile(nombre: 'Valentina', avatar: '1f431', birthYear: 2016, birthMonth: 1, bandOverride: AgeBand.b9a11);
        });
        h.state.current = p;
        caso.antes?.call(h, p);
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = Size(tamano.width * 3, tamano.height * 3);
        await tester.pumpWidget(h.app(caso.pantalla(h, p), textScale: 2.0, navigatorKey: GlobalKey<NavigatorState>()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        if (caso.despues != null) {
          await caso.despues!(tester);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => h.state.pauseClock());
        FlutterError.onError = antes;
        expect(errores, isEmpty, reason: errores.join('\n----\n'));
      });
    });
  }

  testWidgets('M3 (cuarta ronda): con letra ×2 el número de pegatinas de una tarjeta no se corta', (WidgetTester tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Profile p;
    await tester.runAsync(() async {
      p = await h.state.addProfile(nombre: 'Leo', avatar: '1f436', birthYear: 2020, birthMonth: 1, bandOverride: AgeBand.b5a6);
    });
    final GameDef juego = GameRegistry.forAreaAndBand(Area.values.first, AgeBand.b5a6).first;
    for (int nivel = 1; nivel <= 3; nivel++) {
      h.state.progressOf(p.id).stickers.add(StickerAward(gameId: juego.id, band: AgeBand.b5a6, level: nivel, emoji: '2b50', date: DateTime(2026, 10, 18)));
    }
    h.state.current = p;
    tester.view.devicePixelRatio = 3;
    for (final Size tamano in <Size>[const Size(360, 740), const Size(740, 360)]) {
      tester.view.physicalSize = Size(tamano.width * 3, tamano.height * 3);
      await tester.pumpWidget(h.app(const KidHomeScreen(), textScale: 2.0, navigatorKey: GlobalKey<NavigatorState>()));
      await tester.pump();
      final Finder numero = find.byKey(ValueKey<String>('pegatinas-${juego.id}'), skipOffstage: false);
      expect(numero, findsOneWidget);
      expect(tester.widget<Text>(numero).data, '3');
      // La caja del texto mide lo que su línea (13 × 2), no los 16 dp de antes.
      expect(tester.getSize(numero).height, greaterThanOrEqualTo(13 * 2 - 0.5), reason: '$tamano');
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => h.state.pauseClock());
  });

  for (final Size tamano in <Size>[const Size(360, 740), const Size(740, 360)]) {
    testWidgets('M4 (cuarta ronda): con el teclado abierto y letra ×2, «Entrar» se alcanza (${tamano.width.toInt()} × ${tamano.height.toInt()})', (WidgetTester tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = Size(tamano.width * 3, tamano.height * 3);
      // Teclado numérico: unos 290 dp de alto de pie y 160 dp acostado.
      final double teclado = tamano.height > tamano.width ? 290 : 160;
      bool? paso;
      await tester.pumpWidget(h.app(
        Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(child: TextButton(onPressed: () async => paso = await showParentalGate(context, reason: S.masTiempoRazon), child: const Text('abrir'))),
          ),
        ),
        textScale: 2.0,
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding(bottom: teclado * 3);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final String q = tester.widget<Text>(find.byKey(const ValueKey<String>('puerta-pregunta'))).data!;
      int? respuesta;
      for (final int a in GateChallenge.factores) {
        for (final int b in GateChallenge.factores) {
          if (q == '¿Cuánto es ${Es.numero(a)} por ${Es.numero(b)}?') {
            respuesta = a * b;
          }
        }
      }
      await tester.enterText(find.byKey(const ValueKey<String>('puerta-respuesta')), '$respuesta');
      await tester.pump();
      // «Entrar» está en la parte que se desplaza: se llega a él sin cerrar
      // el teclado, queda por encima del teclado y recibe el toque.
      final Finder entrar = find.byKey(const ValueKey<String>('puerta-entrar'));
      await tester.ensureVisible(entrar);
      await tester.pumpAndSettle();
      final Rect r = tester.getRect(entrar);
      expect(r.bottom, lessThanOrEqualTo(tamano.height - teclado + 0.5), reason: 'Entrar queda debajo del teclado: $r');
      expect(entrar.hitTestable(), findsOneWidget);
      await tester.tap(entrar);
      await tester.pumpAndSettle();
      expect(paso, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
