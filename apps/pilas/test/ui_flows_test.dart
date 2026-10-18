import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilas/core/parental_gate.dart';
import 'package:pilas/core/share.dart';
import 'package:pilas/core/strings.dart';
import 'package:pilas/engine/game_def.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/model/age_band.dart';
import 'package:pilas/model/profile.dart';
import 'package:pilas/ui/kid_home_screen.dart';
import 'package:pilas/ui/profile_edit_screen.dart';
import 'package:pilas/ui/profiles_screen.dart';
import 'package:pilas/ui/rest_screen.dart';
import 'package:share_plus/share_plus.dart';

import 'support/harness.dart';

/// Deja avanzar las escrituras a disco (que no corren con el reloj falso de
/// las pruebas de widgets).
Future<void> dejarGuardar(WidgetTester tester) async {
  // Cada escritura encadena varias operaciones de disco (temporal, copia,
  // renombrar): cada vuelta deja avanzar una.
  for (int i = 0; i < 15; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

void main() {
  late Harness h;

  setUp(() async {
    h = await Harness.create();
  });

  tearDown(() async {
    await h.dispose();
  });

  group('G14: puerta para adultos', () {
    test('Pide una multiplicación de dos cifras por dos cifras, en palabras, con un factor amable', () {
      final Set<int> amables = <int>{};
      for (int seed = 0; seed < 2000; seed++) {
        final GateChallenge g = GateChallenge.random(Random(seed));
        expect(g.a, inInclusiveRange(13, 39));
        expect(g.b, inInclusiveRange(13, 39));
        expect(g.a % 10, isNot(0));
        expect(g.b % 10, isNot(0));
        // Exactamente un factor es 15 o 25: se resuelve de cabeza en dos pasos.
        expect(GateChallenge.amables.contains(g.a) != GateChallenge.amables.contains(g.b), isTrue, reason: '${g.a} × ${g.b}');
        amables.add(GateChallenge.amables.contains(g.a) ? g.a : g.b);
        expect(g.answer, inInclusiveRange(100, 999));
        expect(g.question, isNot(matches(RegExp(r'\d'))), reason: 'la pregunta va en palabras');
        expect(g.check('${g.answer}'), isTrue);
        expect(g.check('${g.answer + 1}'), isFalse);
      }
      expect(GateChallenge.random(Random(1)).check('abc'), isFalse);
      expect(amables, GateChallenge.amables.toSet());
    });

    test('M9: el contador de errores vuelve a cero tras 15 minutos sin errores', () {
      final DateTime ahora = DateTime(2026, 10, 18, 12);
      expect(GateLock.vigentes(3, ahora.subtract(const Duration(minutes: 5)), ahora), 3);
      expect(GateLock.vigentes(3, ahora.subtract(const Duration(minutes: 15)), ahora), 0);
      expect(GateLock.vigentes(5, ahora.subtract(const Duration(days: 2)), ahora), 0);
      expect(GateLock.vigentes(2, null, ahora), 0);
      // El bloqueo más largo (15 min) termina cuando el contador ya volvió a cero.
      expect(GateLock.waitAfter(99), lessThanOrEqualTo(GateLock.reinicio));
    });

    test('Dos errores sin espera; desde el tercero, 60 s, luego 120 s, 240 s…', () {
      expect(GateLock.waitAfter(1), Duration.zero);
      expect(GateLock.waitAfter(2), Duration.zero);
      expect(GateLock.waitAfter(3), const Duration(seconds: 60));
      expect(GateLock.waitAfter(4), const Duration(seconds: 120));
      expect(GateLock.waitAfter(5), const Duration(seconds: 240));
      expect(GateLock.waitAfter(20), const Duration(seconds: 900));
    });

    testWidgets('Avisa por voz, no ofrece menú de texto y se bloquea tras varios errores', (WidgetTester tester) async {
      await tester.pumpWidget(h.app(Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(child: TextButton(onPressed: () => showParentalGate(context, reason: 'Prueba'), child: const Text('abrir'))),
        ),
      )));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(h.voice.dicho, contains(S.esParaUnAdulto));
      final TextField campo = tester.widget<TextField>(find.byKey(const ValueKey<String>('puerta-respuesta')));
      expect(campo.contextMenuBuilder, isNull);
      expect(campo.enableInteractiveSelection, isFalse);
      // Pedir otra operación no cuenta como error.
      final String antes = tester.widgetList<Text>(find.byType(Text)).map((Text t) => t.data ?? '').firstWhere((String t) => t.startsWith('¿Cuánto es'));
      await tester.tap(find.byKey(const ValueKey<String>('puerta-otra')));
      await tester.pump();
      expect(h.services.settings.gateFails, 0);
      expect(find.textContaining('¿Cuánto es'), findsOneWidget);
      expect(antes, startsWith('¿Cuánto es'));
      for (int i = 0; i < 3; i++) {
        await tester.enterText(find.byKey(const ValueKey<String>('puerta-respuesta')), '1');
        await tester.tap(find.text(S.entrar));
        await tester.pump();
      }
      expect(find.textContaining('Demasiados intentos'), findsOneWidget);
      expect(h.services.settings.gateFails, 3);
      expect(h.services.settings.gateLastFail, isNotNull);
      // Se cierra el diálogo para no dejar el temporizador corriendo.
      await tester.tap(find.text(S.cancelar));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('G15: el nombre del perfil no ofrece menú de texto', (WidgetTester tester) async {
    await tester.pumpWidget(h.app(const ProfileEditScreen()));
    await tester.pump();
    final TextField campo = tester.widget<TextField>(find.byKey(const ValueKey<String>('perfil-nombre')));
    expect(campo.contextMenuBuilder, isNull);
    expect(campo.enableInteractiveSelection, isFalse);
  });

  group('Pantalla de perfiles', () {
    testWidgets('M1: el primer perfil también pasa por la puerta', (WidgetTester tester) async {
      await tester.pumpWidget(h.app(const ProfilesScreen()));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('nuevo-perfil')));
      await tester.pumpAndSettle();
      expect(find.text(S.paraAdultos), findsOneWidget);
      expect(find.byType(ProfileEditScreen), findsNothing);
    });

    testWidgets('G1: cambiar de jugador mientras otro descansa pide la puerta', (WidgetTester tester) async {
      late Profile ana;
      late Profile beto;
      await tester.runAsync(() async {
        ana = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1);
        beto = await h.state.addProfile(nombre: 'Beto', avatar: '1f436', birthYear: 2019, birthMonth: 1);
      });
      h.state.progressOf(ana.id).restUntil = clock.now().add(const Duration(minutes: 5));
      await tester.pumpWidget(h.app(const ProfilesScreen()));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey<String>('perfil-${beto.id}')));
      await tester.pumpAndSettle();
      expect(find.text(S.cambiarConDescanso), findsOneWidget);
      expect(find.byType(KidHomeScreen), findsNothing);
      await tester.tap(find.text(S.cancelar));
      await tester.pumpAndSettle();
    });

    testWidgets('G1: el jugador que está en su descanso ve el descanso', (WidgetTester tester) async {
      late Profile ana;
      await tester.runAsync(() async {
        ana = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1);
      });
      h.state.progressOf(ana.id).restUntil = clock.now().add(const Duration(minutes: 5));
      await tester.pumpWidget(h.app(const ProfilesScreen()));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey<String>('perfil-${ana.id}')));
      await dejarGuardar(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(RestScreen), findsOneWidget);
      expect(find.byType(KidHomeScreen), findsNothing);
    });

    testWidgets('M5: un toque doble abre el inicio una sola vez', (WidgetTester tester) async {
      late Profile ana;
      await tester.runAsync(() async {
        ana = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1);
      });
      await tester.pumpWidget(h.app(const ProfilesScreen()));
      await tester.pump();
      final Finder tile = find.byKey(ValueKey<String>('perfil-${ana.id}'));
      await tester.tap(tile);
      await tester.tap(tile, warnIfMissed: false);
      await dejarGuardar(tester);
      await tester.pumpAndSettle();
      expect(find.byType(KidHomeScreen), findsOneWidget);
      // Se detiene el reloj de la sesión antes de terminar la prueba.
      await tester.runAsync(() => h.state.pauseClock());
    });
  });

  group('G2: el descanso no se cierra con atrás', () {
    testWidgets('El botón atrás de Android no saca la pantalla de descanso', (WidgetTester tester) async {
      late Profile ana;
      await tester.runAsync(() async {
        ana = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1);
      });
      h.state.current = ana;
      h.state.progressOf(ana.id).restUntil = clock.now().add(const Duration(minutes: 10));
      final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(h.app(const Scaffold(body: Text('juego')), navigatorKey: nav));
      nav.currentState!.push(RestScreen.route());
      await tester.pumpAndSettle();
      expect(find.byType(RestScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(RestScreen), findsOneWidget);
      // El temporizador de la cuenta regresiva se detiene al cerrar la prueba.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('M5: el lector de pantalla oye los minutos, no cada segundo', (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      late Profile ana;
      await tester.runAsync(() async {
        ana = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1);
      });
      h.state.current = ana;
      h.state.progressOf(ana.id).restUntil = clock.now().add(const Duration(minutes: 9, seconds: 30));
      await tester.pumpWidget(h.app(const RestScreen()));
      await tester.pump();
      final SemanticsNode n = tester.getSemantics(find.byKey(const ValueKey<String>('descanso-cuenta')));
      expect(n.label, S.quedanMinutos(10));
      expect(n.label, isNot(contains(':')));
      expect(S.quedanMinutos(10), 'Faltan diez minutos de descanso.');
      expect(S.quedanMinutos(1), 'Falta menos de un minuto de descanso.');
      await tester.pumpWidget(const SizedBox.shrink());
      sem.dispose();
    });

    test('M4: durante el descanso la voz no lee el juego que quedó debajo', () async {
      final Profile ana = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1);
      h.state.current = ana;
      h.state.progressOf(ana.id).restUntil = clock.now().add(const Duration(minutes: 10));
      h.voice.dicho.clear();
      h.voice.sayLater('¿Cuál es el círculo?');
      await h.voice.say('¡Excelente!');
      expect(h.voice.dicho, isEmpty);
      // La pantalla de descanso y la puerta sí hablan.
      h.voice.sayAlways(S.horaDeDescansar);
      expect(h.voice.dicho, <String>[S.horaDeDescansar]);
      // Al volver, se dice lo último que se calló.
      h.state.progressOf(ana.id).restUntil = null;
      h.voice.soltarRetenido();
      expect(h.voice.dicho.last, '¡Excelente!');
      h.voice.sayLater('¿Cuál es el cuadrado?');
      expect(h.voice.dicho.last, '¿Cuál es el cuadrado?');
    });
  });

  testWidgets('M6: salir de un juego con atrás calla la voz', (WidgetTester tester) async {
    late Profile ana;
    await tester.runAsync(() async {
      ana = await h.state.addProfile(nombre: 'Ana', avatar: '1f431', birthYear: 2019, birthMonth: 1, bandOverride: AgeBand.b5a6);
    });
    h.state.current = ana;
    final GameDef g = GameRegistry.byId('patrones')!;
    final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(h.app(const Scaffold(body: Text('inicio')), navigatorKey: nav));
    nav.currentState!.push(MaterialPageRoute<void>(builder: (BuildContext context) => g.build(context, GameLaunch(game: g, band: AgeBand.b5a6, profile: ana))));
    await tester.pumpAndSettle();
    final int antes = h.voice.paradas;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('inicio'), findsOneWidget);
    expect(h.voice.paradas, greaterThan(antes));
  });

  group('B3: compartir', () {
    testWidgets('Pasa siempre el rectángulo del botón tocado como origen', (WidgetTester tester) async {
      ShareParams? recibido;
      final Sharer sharer = Sharer(share: (ShareParams p) async {
        recibido = p;
        return const ShareResult('ok', ShareResultStatus.success);
      });
      await tester.pumpWidget(h.app(Scaffold(
        body: Center(
          child: Builder(
            builder: (BuildContext b) => TextButton(
              key: const ValueKey<String>('compartir'),
              onPressed: () => sharer.shareFiles(b, <XFile>[XFile('dibujo.png')]),
              child: const Text('Compartir'),
            ),
          ),
        ),
      )));
      await tester.tap(find.byKey(const ValueKey<String>('compartir')));
      await tester.pump();
      expect(recibido, isNotNull);
      final Rect boton = tester.getRect(find.byKey(const ValueKey<String>('compartir')));
      expect(recibido!.sharePositionOrigin, boton);
      expect(boton.isEmpty, isFalse);
    });

    testWidgets('Si la hoja de compartir falla, avisa en pantalla', (WidgetTester tester) async {
      final Sharer sharer = Sharer(share: (ShareParams p) async => throw Exception('sin hoja'));
      bool? resultado;
      await tester.pumpWidget(h.app(Scaffold(
        body: Center(
          child: Builder(
            builder: (BuildContext b) => TextButton(onPressed: () async => resultado = await sharer.shareFiles(b, <XFile>[XFile('x.png')]), child: const Text('Compartir')),
          ),
        ),
      )));
      await tester.tap(find.text('Compartir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(resultado, isFalse);
      expect(find.textContaining('No se pudo abrir la hoja de compartir'), findsOneWidget);
    });

    test('Los nombres de archivo quedan seguros', () {
      expect(Sharer.safeFileName('Grupo 2/B: Martín'), 'grupo-2-b-martin');
      expect(Sharer.safeFileName('///'), 'pilas');
    });
  });
}
